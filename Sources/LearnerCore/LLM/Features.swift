import Foundation
import CryptoKit

/// LLM feature clients. Prompts are parameterized by language — no
/// hardcoded German anywhere (anti-goal from the prototype's tutor).
/// Every feature degrades to fully-functional local behavior (R8).

// MARK: - Word deep-dive (sendsWordIds, cached in enrichment)

public struct DeepDive: Codable, Equatable, Sendable {
    public var forms: [String: String]
    public var examples: [Example]
    public var usageNotes: String
    public var mnemonic: String
}

public struct DeepDiveFeature: Sendable {
    public static let enrichmentKind = "deepDive"
    public var gateway: LLMGateway
    public var store: LearnerStore

    public init(gateway: LLMGateway, store: LearnerStore) {
        self.gateway = gateway
        self.store = store
    }

    /// Cached-by-design: generated once, free forever after.
    public func deepDive(for item: VocabItem, languageName: String, now: Date) async throws -> DeepDive {
        if let cached = try store.enrichment(itemId: item.id, kind: Self.enrichmentKind, cacheKey: "v1"),
           let dive = try? JSONCoding.decoder.decode(DeepDive.self, from: Data(cached.contentJSON.utf8)) {
            return dive
        }

        let messages: [ChatMessage] = [
            .system("""
                You are a \(languageName) language reference. Reply with ONLY a JSON object:
                {"forms": {<grammatical form name>: <form>}, "examples": [{"source": <English>, "target": <\(languageName)>}],
                 "usageNotes": <string>, "mnemonic": <string>}
                Include the full form table appropriate to the word class (gender, plural, cases for nouns).
                Give exactly 3 short graded example sentences using common vocabulary.
                """),
            .user("Word: \(item.target) (English: \(item.sourceForms.first?.form ?? item.id)). Explanation on file: \(item.explanation)"),
        ]
        let dive = try await gateway.completeDecoding(
            DeepDive.self,
            tier: .sendsWordIds,
            messages: messages,
            options: CompletionOptions(maxTokens: 700, temperature: 0.2)
        )
        let json = String(data: try JSONCoding.encoder.encode(dive), encoding: .utf8)!
        try store.saveEnrichment(EnrichmentRecord(
            itemId: item.id, kind: Self.enrichmentKind, cacheKey: "v1",
            contentJSON: json, model: "gateway", createdAt: now
        ))
        return dive
    }
}

// MARK: - Tutor (sendsWordIds, streaming handled UI-side; core builds prompts)

public struct TutorPromptBuilder: Sendable {
    public init() {}

    /// System prompt parameterized by (targetLanguage, learnerSummary,
    /// focusItems) — never hardcoded to one language.
    public func systemPrompt(languageName: String, overview: LearnerEngine.Overview, weakItems: [VocabItem]) -> String {
        let stageLine = Stage.allCases
            .compactMap { stage in (overview.countsByStage[stage] ?? 0) > 0 ? "\(stage.rawValue): \(overview.countsByStage[stage]!)" : nil }
            .joined(separator: ", ")
        let weak = weakItems.prefix(5).map { "\($0.sourceForms.first?.form ?? $0.id) → \($0.target)" }.joined(separator: "; ")
        return """
        You are a friendly, precise \(languageName) tutor inside Cockatoo, an ambient \
        language-learning app. The learner encounters \(languageName) words swapped into \
        English pages they read. Meet them where they are.
        Learner state — \(overview.libraryCount) of \(overview.totalItems) words in their library; items by stage: \(stageLine.isEmpty ? "none yet" : stageLine).
        Weakest items: \(weak.isEmpty ? "none yet" : weak).
        Keep answers short and concrete. Use examples built from high-frequency vocabulary.
        """
    }
}

// MARK: - Contextual form resolver (sendsPageText, opt-in — R1c)

public struct ContextualFormFeature: Sendable {
    public static let enrichmentKind = "contextualForm"
    public var gateway: LLMGateway
    public var store: LearnerStore

    public init(gateway: LLMGateway, store: LearnerStore) {
        self.gateway = gateway
        self.store = store
    }

    struct FormReply: Codable { var form: String }

    /// Correctly inflected target form for the item in this sentence.
    /// Cached by (itemId, sentenceHash) so repeats are free and offline-safe.
    /// Bad output is never cached. Caller keeps the authored form on failure.
    public func resolve(item: VocabItem, sentence: String, languageName: String, now: Date) async throws -> String {
        let hash = SHA256.hash(data: Data(sentence.lowercased().utf8))
            .map { String(format: "%02x", $0) }.joined().prefix(16)
        let cacheKey = String(hash)

        if let cached = try store.enrichment(itemId: item.id, kind: Self.enrichmentKind, cacheKey: cacheKey),
           let reply = try? JSONCoding.decoder.decode(FormReply.self, from: Data(cached.contentJSON.utf8)) {
            return reply.form
        }

        let messages: [ChatMessage] = [
            .system("""
                You inflect \(languageName) vocabulary to fit an English sentence context.
                Given a \(languageName) word (citation form) and the English sentence where it
                will visually replace the English original, reply ONLY with JSON: {"form": <the
                best \(languageName) form for that slot, including article if natural>}.
                """),
            .user("Word: \(item.target). Sentence: \(sentence)"),
        ]
        let reply = try await gateway.completeDecoding(
            FormReply.self,
            tier: .sendsPageText,
            messages: messages,
            options: CompletionOptions(maxTokens: 60, temperature: 0, timeout: 10)
        )
        guard !reply.form.isEmpty else { throw LLMError.malformedOutput("empty form") }
        let json = String(data: try JSONCoding.encoder.encode(reply), encoding: .utf8)!
        try store.saveEnrichment(EnrichmentRecord(
            itemId: item.id, kind: Self.enrichmentKind, cacheKey: cacheKey,
            contentJSON: json, model: "gateway", createdAt: now
        ))
        return reply.form
    }
}
