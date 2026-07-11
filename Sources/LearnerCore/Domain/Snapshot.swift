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
    public var pageContextOptIn: Bool

    public init(enabled: Bool, blockedHosts: [String], pageContextOptIn: Bool) {
        self.enabled = enabled
        self.blockedHosts = blockedHosts
        self.pageContextOptIn = pageContextOptIn
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
    /// Lowercased English surface form to match, e.g. "the house".
    public var match: String
    /// Target-language display text, e.g. "das Haus".
    public var display: String

    public init(match: String, display: String) {
        self.match = match
        self.display = display
    }
}

public struct HoverContent: Codable, Equatable, Sendable {
    /// Canonical target with citation-form article, e.g. "das Haus".
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
