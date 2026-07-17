import XCTest
@testable import LearnerCore

final class SyncServiceTests: XCTestCase {
    let t0 = Fixtures.t0

    func makeService() throws -> SyncService {
        let engine = try Fixtures.makeEngine()
        return SyncService(engine: engine)
    }

    func envelope(_ method: String, payload: Data? = nil, version: Int = SyncProtocol.version) throws -> Data {
        // Payload rides as JSON text, exactly like the TypeScript transport.
        let text = payload.map { String(data: $0, encoding: .utf8)! }
        return try JSONEncoder().encode(MessageEnvelope(protocolVersion: version, method: method, payload: text))
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

    func testPostEventsRoundTripThroughEnvelope() throws {
        let engine = try Fixtures.makeEngine()
        let service = SyncService(engine: engine)
        let itemId = try Fixtures.introduce(engine, "de.word.und", at: t0).itemId

        let request = PostEventsRequest(events: [
            ExposureEvent(id: "env-e1", itemId: itemId, type: .seen, occurredAt: t0),
        ])
        let payload = try JSONCoding.encoder.encode(request)
        let response = service.handle(try envelope("postEvents", payload: payload), now: t0)
        let decoded = try JSONDecoder().decode(PostEventsResponse.self, from: response)
        XCTAssertEqual(decoded.accepted, 1)
        XCTAssertGreaterThan(decoded.latestVersion, 0)

        let snapReq = try JSONCoding.encoder.encode(GetSnapshotRequest(sinceVersion: decoded.latestVersion))
        let snapResponse = service.handle(try envelope("getSnapshot", payload: snapReq), now: t0)
        let snap = try JSONCoding.decoder.decode(GetSnapshotResponse.self, from: snapResponse)
        XCTAssertEqual(snap, .unchanged(version: decoded.latestVersion))
    }

    func testOverviewIsComputedBySwiftForTheExtension() throws {
        let engine = try Fixtures.makeEngine()
        let service = SyncService(engine: engine)
        let response = service.handle(try envelope("getOverview"), now: t0)
        let overview = try JSONCoding.decoder.decode(GetOverviewResponse.self, from: response)

        XCTAssertEqual(overview.activeLanguage, "de")
        XCTAssertEqual(overview.libraryCount, 0)
        XCTAssertGreaterThan(overview.newAvailable, 0)
        XCTAssertEqual(overview.availablePracticeItems, overview.dueNow + overview.newAvailable)
    }

    func testOpenPracticePayloadDecodesAndAcknowledges() throws {
        let service = try makeService()
        let payload = try JSONCoding.encoder.encode(OpenDashboardRequest(destination: .practice))
        let response = service.handle(try envelope("openDashboard", payload: payload), now: t0)
        XCTAssertEqual(String(data: response, encoding: .utf8), "{}")
    }
}
