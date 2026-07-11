import Foundation

public struct ChatMessage: Codable, Equatable, Sendable {
    public var role: String // "system" | "user" | "assistant"
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }

    public static func system(_ content: String) -> ChatMessage { .init(role: "system", content: content) }
    public static func user(_ content: String) -> ChatMessage { .init(role: "user", content: content) }
    public static func assistant(_ content: String) -> ChatMessage { .init(role: "assistant", content: content) }
}

public struct CompletionOptions: Sendable {
    public var maxTokens: Int
    public var temperature: Double
    /// JSON schema for structured output where the provider supports
    /// response_format: json_schema; nil for free text.
    public var responseSchemaJSON: String?
    public var timeout: TimeInterval

    public init(maxTokens: Int = 1024, temperature: Double = 0.3, responseSchemaJSON: String? = nil, timeout: TimeInterval = 60) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.responseSchemaJSON = responseSchemaJSON
        self.timeout = timeout
    }
}

public struct Completion: Equatable, Sendable {
    public var text: String
    public var model: String

    public init(text: String, model: String) {
        self.text = text
        self.model = model
    }
}

public enum LLMError: Error, Equatable, Sendable {
    case notConfigured
    case transport(String)
    case httpStatus(Int, String)
    /// Output failed to parse even after the one retry-with-error pass.
    /// Features never regex-patch model text — they degrade (R8).
    case malformedOutput(String)
    /// A sendsPageText call while pageContextOptIn is off.
    case pageContextNotOptedIn
}

/// One provider protocol; one OpenAI-compatible implementation covers
/// OpenRouter, OpenAI, llama.cpp server, and Ollama (P6/D6).
public protocol ChatProvider: Sendable {
    func complete(_ messages: [ChatMessage], options: CompletionOptions) async throws -> Completion
}

/// Decode structured output with the retry ladder from
/// docs/plan/06-llm-integration.md: parse → on failure retry ONCE with the
/// parse error appended → typed failure. No regex patching, ever.
public func completeDecoding<T: Decodable>(
    _ type: T.Type,
    provider: any ChatProvider,
    messages: [ChatMessage],
    options: CompletionOptions
) async throws -> T {
    let first = try await provider.complete(messages, options: options)
    do {
        return try decodeLenient(type, from: first.text)
    } catch {
        var retryMessages = messages
        retryMessages.append(.assistant(first.text))
        retryMessages.append(.user(
            "Your reply failed to parse as the required JSON (\(error)). Reply again with ONLY valid JSON matching the schema — no prose, no code fences."
        ))
        let second = try await provider.complete(retryMessages, options: options)
        do {
            return try decodeLenient(type, from: second.text)
        } catch {
            throw LLMError.malformedOutput(String(second.text.prefix(300)))
        }
    }
}

/// Tolerates code fences and surrounding prose, nothing else.
func decodeLenient<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
    var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if candidate.hasPrefix("```") {
        candidate = candidate
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    if let data = candidate.data(using: .utf8), let value = try? JSONCoding.decoder.decode(T.self, from: data) {
        return value
    }
    // Last resort: the outermost {...} span.
    if let start = candidate.firstIndex(of: "{"), let end = candidate.lastIndex(of: "}"), start < end {
        let span = String(candidate[start...end])
        if let data = span.data(using: .utf8) {
            return try JSONCoding.decoder.decode(T.self, from: data)
        }
    }
    throw LLMError.malformedOutput(String(candidate.prefix(300)))
}
