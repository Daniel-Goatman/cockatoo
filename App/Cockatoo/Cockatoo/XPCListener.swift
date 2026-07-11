import Foundation
import LearnerCore

/// The app-side IPC endpoint the appex forwards native messages to (D9).
/// Mechanism: a CFMessagePort named with the App-Group prefix — the one
/// dynamic registration the sandbox grants to group members regardless of
/// how the app was launched. (NSXPCListener(machServiceName:) only worked
/// when Xcode launched the app — launchd never owned the name otherwise;
/// verified live, see docs/plan/03-data-model-and-storage.md §R2.)
/// The protocol is unchanged: opaque JSON envelope in, JSON response out —
/// all typing happens in LearnerCore.SyncService.
final class CockatooXPCListener {
    private final class ServiceBox {
        let service: SyncService
        init(_ service: SyncService) { self.service = service }
    }

    private let box: ServiceBox
    private var port: CFMessagePort?
    private var source: CFRunLoopSource?

    init(service: SyncService) {
        self.box = ServiceBox(service)
    }

    func start() {
        var context = CFMessagePortContext(
            version: 0,
            info: Unmanaged.passRetained(box).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // The callback is a C function pointer: no captures, state rides in.
        let callback: CFMessagePortCallBack = { _, _, data, info in
            guard let info else { return nil }
            let box = Unmanaged<ServiceBox>.fromOpaque(info).takeUnretainedValue()
            let request = (data as Data?) ?? Data()

            // openDashboard is the one method with a UI side effect: front
            // the window (LearnerCore just acks it — it has no UI).
            if let object = try? JSONSerialization.jsonObject(with: request) as? [String: Any],
               object["method"] as? String == "openDashboard" {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .cockatooOpenDashboard, object: nil)
                }
            }

            let response = box.service.handle(request, now: Date())
            return Unmanaged.passRetained(response as CFData)
        }

        guard let port = CFMessagePortCreateLocal(
            nil,
            CockatooPaths.xpcServiceName as CFString,
            callback,
            &context,
            nil
        ) else {
            NSLog("Cockatoo: CFMessagePort registration failed for \(CockatooPaths.xpcServiceName)")
            return
        }
        self.port = port
        let source = CFMessagePortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = source
        NSLog("Cockatoo: service listening on \(CockatooPaths.xpcServiceName)")
    }
}

extension Notification.Name {
    /// Posted by the IPC callback when the extension asks to open the app.
    static let cockatooOpenDashboard = Notification.Name("dev.cockatoo.openDashboard")
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
