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

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey]

        guard let envelope = try? JSONSerialization.data(withJSONObject: message ?? [:]) else {
            respond(context, ["error": "badPayload"])
            return
        }

        forward(envelope, attemptLaunch: true) { [weak self] responseData in
            guard let self else { return }
            if let responseData,
               let json = try? JSONSerialization.jsonObject(with: responseData) {
                self.respond(context, json)
            } else {
                // Structured degradation: the extension keeps its cached
                // snapshot and queued events (docs/plan/05-extension.md).
                self.respond(context, ["error": "appUnavailable"])
            }
        }
    }

    private func forward(_ envelope: Data, attemptLaunch: Bool, completion: @escaping @Sendable (Data?) -> Void) {
        let connection = NSXPCConnection(machServiceName: xpcServiceName)
        connection.remoteObjectInterface = NSXPCInterface(with: CockatooXPCProtocol.self)
        connection.resume()

        let proxy = connection.remoteObjectProxyWithErrorHandler { [self] _ in
            connection.invalidate()
            if attemptLaunch {
                launchApp {
                    // One retry after a launch attempt.
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                        self.forward(envelope, attemptLaunch: false, completion: completion)
                    }
                }
            } else {
                completion(nil)
            }
        } as? CockatooXPCProtocol

        guard let proxy else {
            completion(nil)
            return
        }
        proxy.handle(envelope) { response in
            connection.invalidate()
            completion(response)
        }
    }

    private func launchApp(then continuation: @escaping @Sendable () -> Void) {
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

    private func respond(_ context: NSExtensionContext, _ payload: Any) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: payload]
        context.completeRequest(returningItems: [response])
    }
}
