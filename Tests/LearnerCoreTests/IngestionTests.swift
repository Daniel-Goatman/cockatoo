import XCTest
@testable import LearnerCore

/// Exposure ingestion under practice-first intake: idempotent event storage,
/// display-only sighting counters, sentence capture — and never any effect
/// on stage, box, or scheduling (D-R1).
final class IngestionTests: XCTestCase {
    var engine: LearnerEngine!
    let t0 = Fixtures.t0

    override func setUpWithError() throws {
        engine = try Fixtures.makeEngine()
    }

    /// A library item to sight (rows only exist once introduced).
    func libraryItemId() throws -> String {
        try Fixtures.introduce(engine, "de.word.und", at: t0).itemId
    }

    func seenEvent(_ itemId: String, at date: Date, id: String = UUID().uuidString) -> ExposureEvent {
        ExposureEvent(id: id, itemId: itemId, type: .seen, occurredAt: date, host: "example.org")
    }

    func testFreshImportCreatesNoProgressRows() throws {
        XCTAssertTrue(try engine.store.allProgress().isEmpty,
                      "library membership comes from practice, not import")
    }

    /// R5: replaying a batch changes nothing.
    func testIdempotentIngestion() throws {
        let itemId = try libraryItemId()
        let batch = [
            seenEvent(itemId, at: t0, id: "e1"),
            ExposureEvent(id: "e2", itemId: itemId, type: .engaged, occurredAt: t0),
        ]
        let first = try engine.postEvents(batch, now: t0)
        XCTAssertEqual(first.accepted, 2)
        let before = try Fixtures.progress(engine, itemId)

        let replay = try engine.postEvents(batch, now: t0.addingTimeInterval(60))
        XCTAssertEqual(replay.accepted, 0)
        XCTAssertEqual(replay.latestVersion, first.latestVersion, "no-op replay must not bump the snapshot version")
        let after = try Fixtures.progress(engine, itemId)
        XCTAssertEqual(before, after)
    }

    func testSightingsCountWithoutCaps() throws {
        let itemId = try libraryItemId()
        let events = (0..<5).map { i in seenEvent(itemId, at: t0.addingTimeInterval(Double(i) * 600), id: "seen\(i)") }
            + [ExposureEvent(id: "g1", itemId: itemId, type: .engaged, occurredAt: t0),
               ExposureEvent(id: "g2", itemId: itemId, type: .pinned, occurredAt: t0.addingTimeInterval(60))]
        try engine.postEvents(events, now: t0.addingTimeInterval(3600))
        let p = try Fixtures.progress(engine, itemId)
        XCTAssertEqual(p.seenCount, 5, "display-only counters have no daily cap")
        XCTAssertEqual(p.engagedCount, 2, "pinned counts as engagement")
    }

    func testSightingsForUnintroducedItemsAreInert() throws {
        try engine.postEvents([seenEvent("de.word.haus", at: t0, id: "u1")], now: t0)
        XCTAssertNil(try engine.store.progress(itemId: "de.word.haus"),
                     "exposure never creates library rows — practice does")
    }

    func testExposureNeverTouchesScheduling() throws {
        let itemId = try libraryItemId()
        let before = try Fixtures.progress(engine, itemId)
        let events = (0..<20).map { i in seenEvent(itemId, at: t0.addingTimeInterval(Double(i) * 7200), id: "s\(i)") }
        try engine.postEvents(events, now: t0.addingTimeInterval(50 * 3600))
        let p = try Fixtures.progress(engine, itemId)
        XCTAssertEqual(p.srsBox, before.srsBox, "only the Grader moves srsBox")
        XCTAssertEqual(p.dueAt, before.dueAt)
        XCTAssertEqual(p.stage, before.stage)
        XCTAssertEqual(p.distinctCorrectDays, before.distinctCorrectDays)
        XCTAssertEqual(p.validateInvariants(), [])
    }

    func testSentenceCaptureStoredWithoutProgressCredit() throws {
        let itemId = try libraryItemId()
        let before = try Fixtures.progress(engine, itemId)
        try engine.postEvents([
            ExposureEvent(id: "sc1", itemId: itemId, type: .sentenceCaptured, occurredAt: t0, host: "example.org", sentence: "I saw the house."),
        ], now: t0)
        let sentences = try engine.store.sentences(itemId: itemId)
        XCTAssertEqual(sentences.map(\.text), ["I saw the house."])
        let after = try Fixtures.progress(engine, itemId)
        XCTAssertEqual(before.seenCount, after.seenCount)
        XCTAssertEqual(before.engagedCount, after.engagedCount)
    }

    func testSentencePruneKeepsNewestFive() throws {
        let itemId = try libraryItemId()
        let events = (0..<8).map { i in
            ExposureEvent(id: "sc\(i)", itemId: itemId, type: .sentenceCaptured,
                          occurredAt: t0.addingTimeInterval(Double(i) * 60), sentence: "Sentence number \(i) with house.")
        }
        try engine.postEvents(events, now: t0.addingTimeInterval(600))
        try engine.store.prune(now: t0.addingTimeInterval(700))
        let sentences = try engine.store.sentences(itemId: itemId)
        XCTAssertEqual(sentences.count, 5)
        XCTAssertEqual(sentences.first?.text, "Sentence number 7 with house.", "newest kept")
    }

    func testEventsForUnknownItemsAreAcceptedButInert() throws {
        let outcome = try engine.postEvents([seenEvent("de.word.nonexistent", at: t0, id: "x1")], now: t0)
        XCTAssertEqual(outcome.accepted, 1, "stored for idempotency, applied to nothing")
    }
}
