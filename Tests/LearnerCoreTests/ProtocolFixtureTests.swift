import XCTest
@testable import LearnerCore

/// Decodes the SAME fixture files the TypeScript tests decode
/// (protocol-fixtures/ at the repo root) — one spec, two encodings,
/// drift caught at test time on either side.
final class ProtocolFixtureTests: XCTestCase {
    var fixturesURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // LearnerCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("protocol-fixtures")
    }

    func load(_ name: String) throws -> Data {
        try Data(contentsOf: fixturesURL.appendingPathComponent(name))
    }

    func testSnapshotFixtureDecodes() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(Snapshot.self, from: load("snapshot.json"))
        XCTAssertEqual(snapshot.version, 412)
        XCTAssertEqual(snapshot.items.count, 2)
        let haus = snapshot.items[0]
        XCTAssertEqual(haus.tier, .formMatched)
        XCTAssertEqual(haus.forms.first?.match, "the house")
        XCTAssertEqual(haus.forms.first?.display, "das Haus")
        XCTAssertEqual(snapshot.items[1].tier, .exact)
        XCTAssertEqual(snapshot.settings.blockedHosts, ["bank.example"])
    }

    /// The regression test for the bug where a Data-typed payload made
    /// every extension request fail as internalError: the envelope payload
    /// is JSON TEXT, and a fixture envelope must round-trip through a real
    /// SyncService without an error response.
    func testEnvelopeFixtureRoundTripsThroughSyncService() throws {
        let fixtures = try JSONSerialization.jsonObject(with: load("envelope.json")) as! [String: Any]

        let withPayload = try JSONSerialization.data(withJSONObject: fixtures["withPayload"]!)
        let envelope = try JSONDecoder().decode(MessageEnvelope.self, from: withPayload)
        XCTAssertEqual(envelope.method, "getSnapshot")
        let request = try JSONDecoder().decode(GetSnapshotRequest.self, from: Data(envelope.payload!.utf8))
        XCTAssertEqual(request.sinceVersion, 412)

        let withoutPayload = try JSONSerialization.data(withJSONObject: fixtures["withoutPayload"]!)
        let bare = try JSONDecoder().decode(MessageEnvelope.self, from: withoutPayload)
        XCTAssertNil(bare.payload)

        // End-to-end: a real service must answer, not error.
        let engine = try Fixtures.makeEngine()
        let service = SyncService(engine: engine)
        let response = service.handle(withPayload, now: Fixtures.t0)
        XCTAssertNil(try? JSONDecoder().decode(SyncErrorResponse.self, from: response),
                     "fixture envelope produced an error response: \(String(data: response, encoding: .utf8) ?? "?")")
        let snapshot = try JSONDecoder().decode(GetSnapshotResponse.self, from: response)
        if case .unchanged = snapshot { XCTFail("sinceVersion 412 cannot match a fresh engine") }
    }

    func testPostEventsFixtureDecodes() throws {
        struct Fixture: Decodable {
            var request: PostEventsRequest
            var response: PostEventsResponse
            var errorResponse: SyncErrorResponse
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let fixture = try decoder.decode(Fixture.self, from: load("postEvents.json"))
        XCTAssertEqual(fixture.request.events.count, 2)
        XCTAssertEqual(fixture.request.events[0].type, .seen)
        XCTAssertEqual(fixture.request.events[1].sentence, "We walked past the houses at dusk.")
        XCTAssertEqual(fixture.response.latestVersion, 413)
        XCTAssertEqual(fixture.errorResponse.error, .appUnavailable)
    }
}
