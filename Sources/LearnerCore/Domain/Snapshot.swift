import Foundation

/// The extension's entire knowledge of the curriculum: the versioned,
/// precomputed active slice (stages ambient...known). Must stay < 100 KB
/// encoded (risk R3; test-enforced).
public struct Snapshot: Codable, Equatable, Sendable {
    public var version: Int
    public var language: String
    public var settings: SnapshotSettings
    public var items: [SnapshotItem]

    public init(version: Int, language: String, settings: SnapshotSettings, items: [SnapshotItem]) {
        self.version = version
        self.language = language
        self.settings = settings
        self.items = items
    }
}

public struct SnapshotSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var blockedHosts: [String]

    public init(enabled: Bool, blockedHosts: [String]) {
        self.enabled = enabled
        self.blockedHosts = blockedHosts
    }
}

public struct SnapshotItem: Codable, Equatable, Sendable {
    public var id: String
    public var kind: ItemKind
    public var tier: FidelityTier
    public var forms: [SnapshotForm]
    public var hover: HoverContent

    public init(id: String, kind: ItemKind, tier: FidelityTier, forms: [SnapshotForm], hover: HoverContent) {
        self.id = id
        self.kind = kind
        self.tier = tier
        self.forms = forms
        self.hover = hover
    }
}

public struct SnapshotForm: Codable, Equatable, Sendable {
    /// Lowercased source-language surface form to match.
    public var match: String
    /// Target-language display text.
    public var display: String

    public init(match: String, display: String) {
        self.match = match
        self.display = display
    }
}

public struct HoverContent: Codable, Equatable, Sendable {
    /// Canonical target, including a citation-form article when applicable.
    public var target: String
    public var pos: String?
    public var example: Example?
    public var seenCount: Int

    public init(target: String, pos: String?, example: Example?, seenCount: Int) {
        self.target = target
        self.pos = pos
        self.example = example
        self.seenCount = seenCount
    }
}
