import XCTest
@testable import LearnerCore

final class SyncServiceTests: XCTestCase {
    let t0 = Fixtures.t0

    func makeService(optIn: Bool = false, resolver: (@Sendable (GetContextualFormRequest) throws -> String)? = nil) throws -> SyncService {
        let engine = try Fixtures.makeEngine()
        try engine.store.setSetting(SettingsKey.pageContextOptIn, optIn ? "true" : "false")
        return SyncService(engine: engine, contextualForm: resolver)
    }

    func envelope(_ method: String, payload: Data? = nil, version: Int = SyncProtocol.version) throws -> Data {
        try JSONEncoder().encode(MessageEnvelope(protocolVersion: version, method: method, payload: payload))
    }

    func decodeError(_ data: Data) -> SyncError? {
        (try? JSONDecoder().decode(SyncErrorResponse.self, from: data))?.error
    }

    func testProtocolMismatchRejected() throws {
        let service = try makeService()
        let response = service.handle(try envelope("getSettings", version: 99), now: t0)
        XCTAssertEqual(decodeError(response), .protocolMismatch)
    }

    func testUnknownMethodRejected() throws {
        let service = try makeService()
        let response = service.handle(try envelope("stealAllVocab"), now: t0)
        XCTAssertEqual(decodeError(response), .unknownMethod)
    }

    /// The server-side page-context gate: a compromised or stale extension
    /// cannot bypass the opt-in (docs/plan/06-llm-integration.md).
    func testContextualFormGatedServerSide() throws {
        let request = GetContextualFormRequest(itemId: "de.word.haus", sentence: "The houses were old.", sentenceHash: "abc")
        let payload = try JSONEncoder().encode(request)

        // Opt-in off → refused even though a resolver exists.
        let gated = try makeService(optIn: false, resolver: { _ in "Häuser" })
        var response = gated.handle(try envelope("getContextualForm", payload: payload), now: t0)
        XCTAssertEqual(decodeError(response), .pageContextNotOptedIn)

        // Opt-in on → resolved.
        let open = try makeService(optIn: true, resolver: { _ in "Häuser" })
        response = open.handle(try envelope("getContextualForm", payload: payload), now: t0)
        let form = try JSONDecoder().decode(GetContextualFormResponse.self, from: response)
        XCTAssertEqual(form.form, "Häuser")

        // Opt-in on but no provider configured → appUnavailable degradation.
        let unconfigured = try makeService(optIn: true, resolver: nil)
        response = unconfigured.handle(try envelope("getContextualForm", payload: payload), now: t0)
        XCTAssertEqual(decodeError(response), .appUnavailable)
    }

    func testPostEventsRoundTripThroughEnvelope() throws {
        let engine = try Fixtures.makeEngine()
        let service = SyncService(engine: engine)
        let itemId = try engine.store.allProgress().values.first { $0.stage == .ambient }!.itemId

        let request = PostEventsRequest(events: [
            ExposureEvent(id: "env-e1", itemId: itemId, type: .seen, occurredAt: t0),
        ])
        let payload = try JSONCoding.encoder.encode(request)
        let response = service.handle(try envelope("postEvents", payload: payload), now: t0)
        let decoded = try JSONDecoder().decode(PostEventsResponse.self, from: response)
        XCTAssertEqual(decoded.accepted, 1)
        XCTAssertGreaterThan(decoded.latestVersion, 0)

        // getSnapshot(sinceVersion: latest) piggyback contract → unchanged.
        let snapReq = try JSONCoding.encoder.encode(GetSnapshotRequest(sinceVersion: decoded.latestVersion))
        let snapResponse = service.handle(try envelope("getSnapshot", payload: snapReq), now: t0)
        let snap = try JSONCoding.decoder.decode(GetSnapshotResponse.self, from: snapResponse)
        XCTAssertEqual(snap, .unchanged(version: decoded.latestVersion))
    }
}

// MARK: - LLM

/// Scripted provider for testing the retry ladder and the gateway gate.
final class MockProvider: ChatProvider, @unchecked Sendable {
    var responses: [String]
    private(set) var calls: [[ChatMessage]] = []

    init(responses: [String]) {
        self.responses = responses
    }

    func complete(_ messages: [ChatMessage], options: CompletionOptions) async throws -> Completion {
        calls.append(messages)
        guard !responses.isEmpty else { throw LLMError.transport("script exhausted") }
        return Completion(text: responses.removeFirst(), model: "mock")
    }
}

struct TestReply: Codable, Equatable { var form: String }

final class LLMTests: XCTestCase {
    func testStructuredOutputRetryLadder() async throws {
        // First reply malformed → one retry with the parse error → success.
        let provider = MockProvider(responses: [
            "Sure! The form would probably be Häuser.",
            #"{"form": "Häuser"}"#,
        ])
        let reply = try await completeDecoding(TestReply.self, provider: provider, messages: [.user("x")], options: .init())
        XCTAssertEqual(reply, TestReply(form: "Häuser"))
        XCTAssertEqual(provider.calls.count, 2)
        XCTAssertTrue(provider.calls[1].last!.content.contains("failed to parse"), "retry must carry the parse feedback")
    }

    func testStructuredOutputFailsTypedAfterSecondMiss() async {
        let provider = MockProvider(responses: ["nonsense", "more nonsense"])
        do {
            _ = try await completeDecoding(TestReply.self, provider: provider, messages: [.user("x")], options: .init())
            XCTFail("expected malformedOutput")
        } catch let error as LLMError {
            guard case .malformedOutput = error else { return XCTFail("wrong error \(error)") }
        } catch {
            XCTFail("wrong error type \(error)")
        }
    }

    func testDecodeLenientHandlesCodeFencesAndProse() throws {
        let fenced = "```json\n{\"form\": \"das Haus\"}\n```"
        XCTAssertEqual(try decodeLenient(TestReply.self, from: fenced), TestReply(form: "das Haus"))
        let prose = "Here you go: {\"form\": \"die Häuser\"} — hope that helps!"
        XCTAssertEqual(try decodeLenient(TestReply.self, from: prose), TestReply(form: "die Häuser"))
    }

    /// P3 enforcement: a sendsPageText call with opt-in off throws BEFORE any
    /// provider I/O.
    func testGatewayBlocksPageTextWithoutOptIn() async {
        let provider = MockProvider(responses: [#"{"form": "x"}"#])
        let gateway = LLMGateway(provider: provider, pageContextOptIn: { false })
        do {
            _ = try await gateway.complete(tier: .sendsPageText, messages: [.user("page text here")], options: .init())
            XCTFail("expected pageContextNotOptedIn")
        } catch let error as LLMError {
            XCTAssertEqual(error, .pageContextNotOptedIn)
        } catch {
            XCTFail("wrong error type")
        }
        XCTAssertEqual(provider.calls.count, 0, "gate must trip before any network call")
    }

    func testGatewayDegradesWhenUnconfigured() async {
        let gateway = LLMGateway(provider: nil, pageContextOptIn: { true })
        do {
            _ = try await gateway.complete(tier: .sendsWordIds, messages: [.user("x")], options: .init())
            XCTFail("expected notConfigured")
        } catch let error as LLMError {
            XCTAssertEqual(error, .notConfigured)
        } catch {
            XCTFail("wrong error type")
        }
    }

    func testContextualFormCachesBySentence() async throws {
        let engine = try Fixtures.makeEngine()
        let provider = MockProvider(responses: [#"{"form": "Häuser"}"#])
        let gateway = LLMGateway(provider: provider, pageContextOptIn: { true })
        let feature = ContextualFormFeature(gateway: gateway, store: engine.store)
        let item = try engine.store.item(id: "de.word.haus")!

        let first = try await feature.resolve(item: item, sentence: "The houses were old.", languageName: "German", now: Fixtures.t0)
        XCTAssertEqual(first, "Häuser")
        // Second call for the same sentence must hit the cache (script is
        // exhausted — a second provider call would throw).
        let second = try await feature.resolve(item: item, sentence: "The houses were old.", languageName: "German", now: Fixtures.t0)
        XCTAssertEqual(second, "Häuser")
        XCTAssertEqual(provider.calls.count, 1)
    }
}
