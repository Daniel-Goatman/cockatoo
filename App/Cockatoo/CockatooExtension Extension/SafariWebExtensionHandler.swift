import AppKit
import Foundation
import SafariServices

// The appex: a STATELESS FORWARDER (decision D9). Native message in →
// XPC call to the app → response out. No database access, no learning
// logic, no state between invocations. This file is compiled into the
// Xcode appex target (see App/README.md for the packaging steps).

let xpcServiceName = "group.dev.cockatoo.shared.api"

@objc public protocol CockatooXPCProtocol {
    func handle(_ envelope: Data, reply: @escaping @Sendable (Data) -> Void)
}

/// Boxes framework objects that are documented thread-safe for the calls we
/// make (NSExtensionContext.completeRequest, NSXPCConnection.invalidate) but
/// predate Sendable annotations.
private struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
}

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey]

        guard let envelope = try? JSONSerialization.data(withJSONObject: message ?? [:]) else {
            Self.respond(context, ["error": "badPayload"])
            return
        }

        // Launch-on-miss ONLY for explicit user intent (openDashboard).
        // Background sync must respect an explicit quit: it degrades to the
        // cached snapshot + queued events instead of resurrecting the app.
        let method = (message as? [String: Any])?["method"] as? String
        let boxedContext = UncheckedSendable(value: context)
        Self.forward(envelope, attemptLaunch: method == "openDashboard") { responseData in
            if let responseData,
               let json = try? JSONSerialization.jsonObject(with: responseData) {
                Self.respond(boxedContext.value, json)
            } else {
                // Structured degradation: the extension keeps its cached
                // snapshot and queued events (docs/plan/05-extension.md).
                Self.respond(boxedContext.value, ["error": "appUnavailable"])
            }
        }
    }

    private static func forward(_ envelope: Data, attemptLaunch: Bool, completion: @escaping @Sendable (Data?) -> Void) {
        let connection = NSXPCConnection(machServiceName: xpcServiceName)
        connection.remoteObjectInterface = NSXPCInterface(with: CockatooXPCProtocol.self)
        connection.resume()
        let boxedConnection = UncheckedSendable(value: connection)

        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
            boxedConnection.value.invalidate()
            if attemptLaunch {
                launchApp {
                    // One retry after a launch attempt.
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                        forward(envelope, attemptLaunch: false, completion: completion)
                    }
                }
            } else {
                completion(nil)
            }
        } as? CockatooXPCProtocol

        guard let proxy else {
            connection.invalidate()
            completion(nil)
            return
        }
        proxy.handle(envelope) { response in
            boxedConnection.value.invalidate()
            completion(response)
        }
    }

    private static func launchApp(then continuation: @escaping @Sendable () -> Void) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "dev.cockatoo.app") else {
            continuation()
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            continuation()
        }
    }

    private static func respond(_ context: NSExtensionContext, _ payload: Any) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: payload]
        context.completeRequest(returningItems: [response])
    }
}
