import XCTest
@testable import LearnerCore

final class IngestionTests: XCTestCase {
    var engine: LearnerEngine!
    let t0 = Fixtures.t0

    override func setUpWithError() throws {
        engine = try Fixtures.makeEngine()
    }

    func ambientItemId() throws -> String {
        let progress = try engine.store.allProgress()
        return progress.values.first { $0.stage == .ambient }!.itemId
    }

    func seenEvent(_ itemId: String, at date: Date, id: String = UUID().uuidString) -> ExposureEvent {
        ExposureEvent(id: id, itemId: itemId, type: .seen, occurredAt: date, host: "example.org")
    }

    func testImportBootstrapsAmbientSet() throws {
        let progress = try engine.store.allProgress()
        let ambient = progress.values.filter { $0.stage == .ambient }
        // Only tier 1 is unlocked at import; all 8 band-1 items activate
        // (below the 15-item ambient cap).
        XCTAssertEqual(ambient.count, 8)
        let items = try engine.store.items(language: "de")
        for p in ambient {
            let band = items.first { $0.id == p.itemId }!.frequencyBand
            XCTAssertEqual(band, 1, "locked tiers must not activate")
        }
    }

    /// R5: replaying a batch changes nothing.
    func testIdempotentIngestion() throws {
        let itemId = try ambientItemId()
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

    func testDailySeenCapIsThree() throws {
        let itemId = try ambientItemId()
        let events = (0..<5).map { i in seenEvent(itemId, at: t0.addingTimeInterval(Double(i) * 600), id: "seen\(i)") }
        try engine.postEvents(events, now: t0.addingTimeInterval(3600))
        XCTAssertEqual(try Fixtures.progress(engine, itemId).seenCount, 3)

        // Next day the cap resets.
        let nextDay = t0.addingTimeInterval(24 * 3600)
        try engine.postEvents([seenEvent(itemId, at: nextDay, id: "seen-d2")], now: nextDay)
        XCTAssertEqual(try Fixtures.progress(engine, itemId).seenCount, 4)
    }

    func testEngagedCapIsTwoAndPinnedCounts() throws {
        let itemId = try ambientItemId()
        let events: [ExposureEvent] = [
            ExposureEvent(id: "g1", itemId: itemId, type: .engaged, occurredAt: t0),
            ExposureEvent(id: "g2", itemId: itemId, type: .pinned, occurredAt: t0.addingTimeInterval(60)),
            ExposureEvent(id: "g3", itemId: itemId, type: .engaged, occurredAt: t0.addingTimeInterval(120)),
        ]
        try engine.postEvents(events, now: t0.addingTimeInterval(3600))
        XCTAssertEqual(try Fixtures.progress(engine, itemId).engagedCount, 2)
    }

    func testAmbientBecomesReadyAtThresholds() throws {
        let itemId = try ambientItemId()
        var clock = t0
        // 2 days × 3 seen + 1 engaged.
        for day in 0..<2 {
            let events = (0..<3).map { i in
                seenEvent(itemId, at: clock.addingTimeInterval(Double(i) * 600), id: "d\(day)s\(i)")
            } + [ExposureEvent(id: "d\(day)g", itemId: itemId, type: .engaged, occurredAt: clock.addingTimeInterval(1800))]
            try engine.postEvents(events, now: clock.addingTimeInterval(3600))
            clock = clock.addingTimeInterval(24 * 3600)
        }
        let p = try Fixtures.progress(engine, itemId)
        XCTAssertEqual(p.seenCount, 6)
        XCTAssertEqual(p.engagedCount, 2)
        XCTAssertEqual(p.stage, .ready, "transition b well past both thresholds")
        XCTAssertEqual(p.validateInvariants(), [])
    }

    /// Transition b, seen-only path: a reader who never hovers still gets
    /// practice once seenCount reaches readySeenThreshold.
    func testSeenAloneReachesReadyWithoutEngagement() throws {
        let itemId = try ambientItemId()
        var clock = t0
        for day in 0..<2 {
            let events = (0..<3).map { i in
                seenEvent(itemId, at: clock.addingTimeInterval(Double(i) * 600), id: "d\(day)s\(i)")
            }
            try engine.postEvents(events, now: clock.addingTimeInterval(3600))
            clock = clock.addingTimeInterval(24 * 3600)
        }
        let p = try Fixtures.progress(engine, itemId)
        XCTAssertEqual(p.seenCount, 6)
        XCTAssertEqual(p.engagedCount, 0)
        XCTAssertEqual(p.stage, .ready, "engagement must be an accelerant, not a gate")
    }

    /// Transition b, fast path: engagement halves the seen requirement.
    func testEngagementFastPathToReady() throws {
        let itemId = try ambientItemId()
        let events = (0..<3).map { i in
            seenEvent(itemId, at: t0.addingTimeInterval(Double(i) * 600), id: "f\(i)")
        } + [ExposureEvent(id: "fg", itemId: itemId, type: .engaged, occurredAt: t0.addingTimeInterval(1800))]
        try engine.postEvents(events, now: t0.addingTimeInterval(3600))
        let p = try Fixtures.progress(engine, itemId)
        XCTAssertEqual(p.seenCount, 3)
        XCTAssertEqual(p.engagedCount, 1)
        XCTAssertEqual(p.stage, .ready, "seen≥3 && engaged≥1 is the fast path")
    }

    func testSeenBelowFastThresholdStaysAmbientDespiteEngagement() throws {
        let itemId = try ambientItemId()
        try engine.postEvents([
            seenEvent(itemId, at: t0, id: "u1"),
            ExposureEvent(id: "u2", itemId: itemId, type: .engaged, occurredAt: t0.addingTimeInterval(60)),
        ], now: t0.addingTimeInterval(120))
        XCTAssertEqual(try Fixtures.progress(engine, itemId).stage, .ambient)
    }

    func testExposureNeverTouchesSrsBox() throws {
        let itemId = try ambientItemId()
        let events = (0..<20).map { i in seenEvent(itemId, at: t0.addingTimeInterval(Double(i) * 7200), id: "s\(i)") }
        try engine.postEvents(events, now: t0.addingTimeInterval(50 * 3600))
        let p = try Fixtures.progress(engine, itemId)
        XCTAssertEqual(p.srsBox, 0, "only the Grader moves srsBox")
        XCTAssertNil(p.dueAt)
    }

    func testSentenceCaptureStoredWithoutProgressCredit() throws {
        let itemId = try ambientItemId()
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
        let itemId = try ambientItemId()
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

    /// The daily-cap UI ("done today") reads raw today counts; they must
    /// track events even past the crediting cap and reset with the day.
    func testExposureCountsTodayTrackRawEventsAndDayBoundary() throws {
        let progress = try engine.store.allProgress()
        let ambient = progress.values.filter { $0.stage == .ambient }.map(\.itemId).sorted()
        let itemId = ambient[0]
        let otherId = ambient[1]
        // 5 raw sightings (credits cap at 3, stays ambient — no engagement),
        // plus a pin on a different item to check engagement counting.
        let events = (0..<5).map { i in seenEvent(itemId, at: t0.addingTimeInterval(Double(i) * 600), id: "raw\(i)") }
            + [ExposureEvent(id: "rawg", itemId: otherId, type: .pinned, occurredAt: t0)]
        try engine.postEvents(events, now: t0.addingTimeInterval(3600))

        let counts = try engine.store.exposureCountsToday(now: t0.addingTimeInterval(3600))
        XCTAssertEqual(counts[itemId]?.seen, 5, "raw events counted past the credit cap of 3")
        XCTAssertEqual(counts[otherId]?.engaged, 1, "pinned counts as engagement")

        let overview = try engine.overview(now: t0.addingTimeInterval(3600))
        let need = try XCTUnwrap(overview.almostReady.first { $0.itemId == itemId })
        XCTAssertTrue(need.seenCappedToday)
        XCTAssertFalse(need.engagedCappedToday)

        // Next day the counters reset.
        let tomorrow = t0.addingTimeInterval(25 * 3600)
        XCTAssertNil(try engine.store.exposureCountsToday(now: tomorrow)[itemId])
    }

    func testEventsForUnknownItemsAreAcceptedButInert() throws {
        let outcome = try engine.postEvents([seenEvent("de.word.nonexistent", at: t0, id: "x1")], now: t0)
        XCTAssertEqual(outcome.accepted, 1, "stored for idempotency, applied to nothing")
    }
}
