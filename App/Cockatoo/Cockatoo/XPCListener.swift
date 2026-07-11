import Foundation
import LearnerCore

/// The app-side XPC API the appex forwards native messages to (decision D9).
/// One method: opaque JSON envelope in, JSON response out — all typing
/// happens in LearnerCore.SyncService on this side of the boundary.
@objc public protocol CockatooXPCProtocol {
    func handle(_ envelope: Data, reply: @escaping @Sendable (Data) -> Void)
}

final class CockatooXPCListener: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let service: SyncService
    private var listener: NSXPCListener?

    init(service: SyncService) {
        self.service = service
    }

    /// Registers the App-Group-prefixed mach service. This only succeeds in
    /// the packaged, entitled app bundle — in dev (swift run) registration
    /// fails harmlessly and the extension falls back to its cache
    /// (docs/plan/08-roadmap.md P0 spike verifies the packaged path).
    func start() {
        let listener = NSXPCListener(machServiceName: CockatooPaths.xpcServiceName)
        listener.delegate = self
        listener.resume()
        self.listener = listener
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: CockatooXPCProtocol.self)
        connection.exportedObject = XPCHandler(service: service)
        connection.resume()
        return true
    }
}

final class XPCHandler: NSObject, CockatooXPCProtocol, @unchecked Sendable {
    private let service: SyncService

    init(service: SyncService) {
        self.service = service
    }

    func handle(_ envelope: Data, reply: @escaping @Sendable (Data) -> Void) {
        // SyncService is synchronous over the database; hop to a utility
        // queue so the XPC thread never blocks on SQLite.
        let service = self.service
        DispatchQueue.global(qos: .userInitiated).async {
            reply(service.handle(envelope, now: Date()))
        }
    }
}

// MARK: - Keychain (API keys never touch the DB or UserDefaults — D7)

enum KeychainStore {
    static let service = "dev.cockatoo.llm"

    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(key: String, value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
