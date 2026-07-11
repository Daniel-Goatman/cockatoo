import Foundation

/// The only v1 ChatProvider: any /v1/chat/completions endpoint —
/// OpenRouter (https://openrouter.ai/api/v1), OpenAI, llama.cpp server
/// (http://127.0.0.1:8080/v1), Ollama (http://127.0.0.1:11434/v1).
/// No provider-specific branches (D6).
public struct OpenAICompatClient: ChatProvider {
    public struct Config: Sendable {
        public var baseURL: URL
        /// Loaded from Keychain by the caller; never persisted in the DB.
        public var apiKey: String?
        public var model: String

        public init(baseURL: URL, apiKey: String?, model: String) {
            self.baseURL = baseURL
            self.apiKey = apiKey
            self.model = model
        }
    }

    public var config: Config
    let session: URLSession

    public init(config: Config, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    struct RequestBody: Encodable {
        var model: String
        var messages: [ChatMessage]
        var max_tokens: Int
        var temperature: Double
        var response_format: ResponseFormat?

        struct ResponseFormat: Encodable {
            var type: String
            var json_schema: RawJSON?
        }
    }

    /// Pass-through raw JSON for the schema blob.
    struct RawJSON: Encodable {
        var json: String
        func encode(to encoder: Encoder) throws {
            let value = try JSONSerialization.jsonObject(with: Data(json.utf8))
            var container = encoder.singleValueContainer()
            try container.encode(AnyEncodable(value))
        }
    }

    struct AnyEncodable: Encodable {
        let value: Any
        init(_ value: Any) { self.value = value }
        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch value {
            case let v as String: try c.encode(v)
            case let v as Int: try c.encode(v)
            case let v as Double: try c.encode(v)
            case let v as Bool: try c.encode(v)
            case let v as [Any]: try c.encode(v.map(AnyEncodable.init))
            case let v as [String: Any]: try c.encode(v.mapValues(AnyEncodable.init))
            case is NSNull: try c.encodeNil()
            default: throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "unsupported"))
            }
        }
    }

    struct ResponseBody: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { var content: String? }
            var message: Message
        }
        var choices: [Choice]
        var model: String?
    }

    public func complete(_ messages: [ChatMessage], options: CompletionOptions) async throws -> Completion {
        var request = URLRequest(url: config.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = options.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let key = config.apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let body = RequestBody(
            model: config.model,
            messages: messages,
            max_tokens: options.maxTokens,
            temperature: options.temperature,
            response_format: options.responseSchemaJSON.map {
                RequestBody.ResponseFormat(type: "json_schema", json_schema: RawJSON(json: $0))
            }
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LLMError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw LLMError.transport("non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.httpStatus(http.statusCode, String(data: data.prefix(300), encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        guard let text = decoded.choices.first?.message.content else {
            throw LLMError.malformedOutput("empty choices")
        }
        return Completion(text: text, model: decoded.model ?? config.model)
    }

    /// Settings "Test connection": 1-token completion, reports latency.
    public func testConnection() async -> Result<TimeInterval, LLMError> {
        let start = Date()
        do {
            _ = try await complete(
                [.user("Reply with the single word: ok")],
                options: CompletionOptions(maxTokens: 4, temperature: 0, timeout: 15)
            )
            return .success(Date().timeIntervalSince(start))
        } catch let error as LLMError {
            return .failure(error)
        } catch {
            return .failure(.transport(error.localizedDescription))
        }
    }
}
