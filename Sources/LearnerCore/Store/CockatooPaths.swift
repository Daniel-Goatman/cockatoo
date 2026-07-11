import Foundation

/// Well-known locations. The database lives in the App Group container when
/// available (packaged app), else in Application Support (dev builds, CLIs).
public enum CockatooPaths {
    public static let appGroupId = "group.dev.cockatoo.shared"
    /// Mach service name for the app's XPC listener. The App-Group prefix is
    /// what the sandbox permits the appex to look up (decision D9).
    public static let xpcServiceName = "group.dev.cockatoo.shared.api"

    public static func databaseURL() -> URL {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) {
            return container.appendingPathComponent("cockatoo.sqlite")
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Cockatoo/cockatoo.sqlite")
    }
}
