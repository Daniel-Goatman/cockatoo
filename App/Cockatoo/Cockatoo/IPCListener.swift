import Foundation
import AppKit
import LearnerCore

/// The app-side IPC endpoint the appex forwards native messages to (D9).
/// Mechanism: a CFMessagePort named with the App-Group prefix — the one
/// dynamic registration the sandbox grants to group members regardless of
/// how the app was launched. (NSXPCListener(machServiceName:) only worked
/// when Xcode launched the app — launchd never owned the name otherwise;
/// verified live, see docs/plan/03-data-model-and-storage.md §R2.)
/// The protocol is unchanged: opaque JSON envelope in, JSON response out —
/// all typing happens in LearnerCore.SyncService.
final class CockatooIPCListener {
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
            // the window and optionally select an explicit destination
            // (LearnerCore validates the payload, then just acks it).
            if let object = try? JSONSerialization.jsonObject(with: request) as? [String: Any],
               object["method"] as? String == "openDashboard" {
                let openRequest: OpenDashboardRequest? = (object["payload"] as? String)
                    .flatMap { $0.data(using: .utf8) }
                    .flatMap { try? JSONDecoder().decode(OpenDashboardRequest.self, from: $0) }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .cockatooOpenDashboard, object: openRequest)

                    // Front an existing dashboard directly as well as asking
                    // SwiftUI to recreate one through the notification. The
                    // menu-bar scene can otherwise be lazy when Safari sends
                    // the first request of a launch.
                    NSApp.setActivationPolicy(.regular)
                    NSApp.unhide(nil)
                    for window in NSApp.windows where
                        window.identifier?.rawValue.hasPrefix("main") == true || window.title == "Cockatoo" {
                        window.deminiaturize(nil)
                        window.makeKeyAndOrderFront(nil)
                    }
                    NSApp.activate(ignoringOtherApps: true)
                }
            }

            // Any message proves the extension ⇄ app path is alive; the UI
            // shows this as honest connectivity status.
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .cockatooExtensionContact, object: nil)
            }

            let response = box.service.handle(request, now: Date())
            return Unmanaged.passRetained(response as CFData)
        }

        guard let port = CFMessagePortCreateLocal(
            nil,
            CockatooPaths.ipcServiceName as CFString,
            callback,
            &context,
            nil
        ) else {
            NSLog("Cockatoo: CFMessagePort registration failed for \(CockatooPaths.ipcServiceName)")
            return
        }
        self.port = port
        let source = CFMessagePortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.source = source
        NSLog("Cockatoo: service listening on \(CockatooPaths.ipcServiceName)")
    }
}

extension Notification.Name {
    /// Posted by the IPC callback when the extension asks to open the app.
    static let cockatooOpenDashboard = Notification.Name("dev.cockatoo.openDashboard")
    /// Posted on every IPC message — drives the extension-status UI.
    static let cockatooExtensionContact = Notification.Name("dev.cockatoo.extensionContact")
}
