import Foundation

/// Privacy tier of an LLM feature (P3). Enforcement happens HERE — the
/// single choke point through which all feature clients call the provider.
public enum PrivacyTier: String, Codable, Sendable {
    /// No LLM call at all.
    case localOnly
    /// Curriculum items, learner-state summaries, user-typed chat text.
    case sendsWordIds
    /// Captured sentences / page-derived text. Hard-gated on explicit opt-in.
    case sendsPageText
}

/// All feature clients call through the gateway; a sendsPageText call with
/// the opt-in off throws before any network I/O.
public struct LLMGateway: Sendable {
    public var provider: (any ChatProvider)?
    public var pageContextOptIn: @Sendable () -> Bool

    public init(provider: (any ChatProvider)?, pageContextOptIn: @escaping @Sendable () -> Bool) {
        self.provider = provider
        self.pageContextOptIn = pageContextOptIn
    }

    public func complete(
        tier: PrivacyTier,
        messages: [ChatMessage],
        options: CompletionOptions
    ) async throws -> Completion {
        guard tier != .localOnly else {
            throw LLMError.notConfigured // localOnly features never call the model
        }
        if tier == .sendsPageText, !pageContextOptIn() {
            throw LLMError.pageContextNotOptedIn
        }
        guard let provider else {
            throw LLMError.notConfigured
        }
        return try await provider.complete(messages, options: options)
    }

    public func completeDecoding<T: Decodable>(
        _ type: T.Type,
        tier: PrivacyTier,
        messages: [ChatMessage],
        options: CompletionOptions
    ) async throws -> T {
        if tier == .sendsPageText, !pageContextOptIn() {
            throw LLMError.pageContextNotOptedIn
        }
        guard let provider else {
            throw LLMError.notConfigured
        }
        return try await LearnerCore.completeDecoding(type, provider: provider, messages: messages, options: options)
    }
}
