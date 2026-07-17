import AppKit
import Foundation
import SafariServices

// The appex: a STATELESS FORWARDER (decision D9). Native message in →
// CFMessagePort request to the app → response out. No database access, no
// learning logic, no state between invocations. The port name carries the
// App-Group prefix, which is what authorizes both the app's registration
// and this lookup under the sandbox. This file is compiled into the Xcode
// appex target (see App/README.md for the packaging steps).

private func configuredValue(_ key: String, fallback: String) -> String {
    guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
          !value.isEmpty,
          !value.contains("$(") else { return fallback }
    return value
}

let appServiceName = configuredValue(
    "CockatooIPCServiceName",
    fallback: "group.dev.cockatoo.shared.api"
)
let containingAppBundleIdentifier = configuredValue(
    "CockatooAppBundleIdentifier",
    fallback: "dev.cockatoo.app"
)

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = item?.userInfo?[SFExtensionMessageKey]

        guard let envelope = try? JSONSerialization.data(withJSONObject: message ?? [:]) else {
            Self.respond(context, ["error": "badPayload"])
            return
        }

        // Launch/activation is allowed ONLY for explicit user intent
        // (openDashboard). Background sync must respect an explicit quit: it
        // degrades to cached state instead of resurrecting the app.
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
        DispatchQueue.global(qos: .userInitiated).async {
            if attemptLaunch {
                // Even when IPC is already reachable, route the user's click
                // through Launch Services. That user-intent-bearing activation
                // is more reliable than asking a background app to front
                // itself, and it also starts a quit app before delivery.
                launchApp {
                    DispatchQueue.global(qos: .userInitiated).async {
                        if let response = sendToApp(envelope, timeout: 2.0) {
                            completion(response)
                            return
                        }
                        // Launch completion can precede the app registering
                        // its CFMessagePort. One short, bounded retry covers
                        // that cold-start window.
                        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.6) {
                            completion(sendToApp(envelope, timeout: 3.0))
                        }
                    }
                }
                return
            }

            if let response = sendToApp(envelope) {
                completion(response)
                return
            }
            completion(nil)
        }
    }

    private static func sendToApp(_ envelope: Data, timeout: TimeInterval = 5.0) -> Data? {
        guard let port = CFMessagePortCreateRemote(nil, appServiceName as CFString) else {
            return nil
        }
        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(
            port, 0, envelope as CFData, timeout, timeout,
            CFRunLoopMode.defaultMode.rawValue, &reply
        )
        CFMessagePortInvalidate(port)
        guard status == kCFMessagePortSuccess, let data = reply?.takeRetainedValue() else {
            return nil
        }
        return data as Data
    }

    private static func launchApp(then continuation: @escaping @Sendable () -> Void) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: containingAppBundleIdentifier) else {
            continuation()
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        // This path is reserved for openDashboard — an explicit click — so
        // bringing an existing app forward is also the requested behavior.
        config.activates = true
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

/// Boxes NSExtensionContext (thread-safe for completeRequest) across the
/// @Sendable completion boundary.
private struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
}
