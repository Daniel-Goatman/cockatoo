import Foundation

public enum ItemKind: String, Codable, CaseIterable, Sendable {
    case word
    case chunk
    case pattern
}

public enum ReplacementPolicy: String, Codable, CaseIterable, Sendable {
    case ambientSafe
    case reviewOnly
    case never
}

/// What an ambient swap of this item guarantees grammatically.
/// See docs/plan/01-vision-and-principles.md §Fidelity tiers.
public enum FidelityTier: String, Codable, CaseIterable, Sendable {
    case exact
    case formMatched
    case approximate
}

/// One English surface form and the target-language text that replaces it.
/// Determiner-extended variants ("the house" → "das Haus") are authored
/// at pack-build time (decision D10).
public struct SourceForm: Codable, Equatable, Sendable {
    public var form: String
    public var target: String

    public init(form: String, target: String) {
        self.form = form
        self.target = target
    }
}

public struct Example: Codable, Equatable, Sendable {
    public var source: String
    public var target: String

    public init(source: String, target: String) {
        self.source = source
        self.target = target
    }
}

public struct TargetMeta: Codable, Equatable, Sendable {
    public var gender: String?
    public var plural: String?
    public var pos: String?
    public var pronunciation: String?

    public init(gender: String? = nil, plural: String? = nil, pos: String? = nil, pronunciation: String? = nil) {
        self.gender = gender
        self.plural = plural
        self.pos = pos
        self.pronunciation = pronunciation
    }
}

public struct VocabItem: Codable, Equatable, Identifiable, Sendable {
    /// Stable content-addressed slug, e.g. "de.word.haus". Progress joins on this.
    public var id: String
    public var language: String
    public var kind: ItemKind
    public var sourceForms: [SourceForm]
    /// Canonical target text, e.g. "Haus".
    public var target: String
    public var targetMeta: TargetMeta?
    /// CEFR level: "a1" | "a2" | "b1"
    public var level: String
    /// 1...10, corpus-derived difficulty stratum. Band 1 unlocks first.
    public var frequencyBand: Int
    public var replacementPolicy: ReplacementPolicy
    public var fidelityTier: FidelityTier
    /// Item IDs that must be ≥ .known before this item can activate.
    public var dependencies: [String]
    public var explanation: String
    public var examples: [Example]

    public init(
        id: String,
        language: String,
        kind: ItemKind,
        sourceForms: [SourceForm],
        target: String,
        targetMeta: TargetMeta? = nil,
        level: String,
        frequencyBand: Int,
        replacementPolicy: ReplacementPolicy,
        fidelityTier: FidelityTier,
        dependencies: [String] = [],
        explanation: String,
        examples: [Example] = []
    ) {
        self.id = id
        self.language = language
        self.kind = kind
        self.sourceForms = sourceForms
        self.target = target
        self.targetMeta = targetMeta
        self.level = level
        self.frequencyBand = frequencyBand
        self.replacementPolicy = replacementPolicy
        self.fidelityTier = fidelityTier
        self.dependencies = dependencies
        self.explanation = explanation
        self.examples = examples
    }
}
