import Foundation

/// Well-known locations. The database lives in the App Group container when
/// available (packaged app), else in Application Support (dev builds, CLIs).
public enum CockatooPaths {
    public static var appGroupId: String {
        configuredValue("CockatooAppGroupIdentifier", fallback: "group.dev.cockatoo.shared")
    }
    /// CFMessagePort name for app-extension IPC. The App-Group prefix is what
    /// the sandbox permits the appex to look up (decision D9).
    public static var ipcServiceName: String {
        configuredValue("CockatooIPCServiceName", fallback: "\(appGroupId).api")
    }

    public static func databaseURL() -> URL {
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) {
            return container.appendingPathComponent("cockatoo.sqlite")
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("Cockatoo/cockatoo.sqlite")
    }

    private static func configuredValue(_ key: String, fallback: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.contains("$(") else { return fallback }
        return value
    }
}
