import Foundation

/// The extension ⇄ app protocol. TypeScript mirrors these types; shared
/// JSON fixtures keep the two sides from drifting
/// (docs/plan/05-extension.md §Messaging protocol).
public enum SyncProtocol {
    public static let version = 1
}

public struct MessageEnvelope: Codable, Equatable, Sendable {
    public var protocolVersion: Int
    public var method: String
    /// JSON TEXT of the request payload — a plain string, never base64.
    /// Must match the TypeScript transport byte-for-byte; the envelope
    /// fixture test enforces this on both sides (a Data-typed payload here
    /// once silently broke every extension request as internalError).
    public var payload: String?

    public init(protocolVersion: Int = SyncProtocol.version, method: String, payload: String? = nil) {
        self.protocolVersion = protocolVersion
        self.method = method
        self.payload = payload
    }
}

public enum SyncMethod: String, Codable, CaseIterable, Sendable {
    case getSnapshot
    case postEvents
    case getSettings
    case getOverview
    case openDashboard
}

public struct GetSnapshotRequest: Codable, Equatable, Sendable {
    public var sinceVersion: Int?

    public init(sinceVersion: Int? = nil) {
        self.sinceVersion = sinceVersion
    }
}

public enum GetSnapshotResponse: Codable, Equatable, Sendable {
    case unchanged(version: Int)
    case snapshot(Snapshot)

    enum CodingKeys: String, CodingKey { case version, unchanged, snapshot }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if (try c.decodeIfPresent(Bool.self, forKey: .unchanged)) == true {
            self = .unchanged(version: try c.decode(Int.self, forKey: .version))
        } else {
            self = .snapshot(try c.decode(Snapshot.self, forKey: .snapshot))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .unchanged(let version):
            try c.encode(true, forKey: .unchanged)
            try c.encode(version, forKey: .version)
        case .snapshot(let snapshot):
            try c.encode(snapshot.version, forKey: .version)
            try c.encode(snapshot, forKey: .snapshot)
        }
    }
}

public struct PostEventsRequest: Codable, Equatable, Sendable {
    public var events: [ExposureEvent]

    public init(events: [ExposureEvent]) {
        self.events = events
    }
}

public struct PostEventsResponse: Codable, Equatable, Sendable {
    public var accepted: Int
    public var latestVersion: Int

    public init(accepted: Int, latestVersion: Int) {
        self.accepted = accepted
        self.latestVersion = latestVersion
    }
}

public struct GetSettingsResponse: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var blockedHosts: [String]
    public var activeLanguage: String

    public init(enabled: Bool, blockedHosts: [String], activeLanguage: String) {
        self.enabled = enabled
        self.blockedHosts = blockedHosts
        self.activeLanguage = activeLanguage
    }
}

/// A compact, precomputed summary for the browser-extension popup. Swift
/// decides what is actionable; the extension only renders these values (P1).
public struct GetOverviewResponse: Codable, Equatable, Sendable {
    public var activeLanguage: String
    public var libraryCount: Int
    public var dueNow: Int
    public var newAvailable: Int
    public var knownCount: Int
    public var availablePracticeItems: Int

    public init(
        activeLanguage: String,
        libraryCount: Int,
        dueNow: Int,
        newAvailable: Int,
        knownCount: Int,
        availablePracticeItems: Int
    ) {
        self.activeLanguage = activeLanguage
        self.libraryCount = libraryCount
        self.dueNow = dueNow
        self.newAvailable = newAvailable
        self.knownCount = knownCount
        self.availablePracticeItems = availablePracticeItems
    }
}

public enum OpenDestination: String, Codable, Equatable, Sendable {
    case practice
    case library
}

public struct OpenDashboardRequest: Codable, Equatable, Sendable {
    public var itemId: String?
    public var destination: OpenDestination?

    public init(itemId: String? = nil, destination: OpenDestination? = nil) {
        self.itemId = itemId
        self.destination = destination
    }
}

/// Structured errors the extension can act on.
public enum SyncError: String, Codable, Sendable, Error {
    /// App process unreachable after launch-and-retry — extension degrades
    /// to cached snapshot + queued events.
    case appUnavailable
    /// protocolVersion mismatch — popup shows "Update Cockatoo".
    case protocolMismatch
    case unknownMethod
    case badPayload
    case internalError
}

public struct SyncErrorResponse: Codable, Equatable, Sendable {
    public var error: SyncError
    /// Debug context (e.g. the decode failure); never parsed, only shown.
    public var detail: String?

    public init(error: SyncError, detail: String? = nil) {
        self.error = error
        self.detail = detail
    }
}
