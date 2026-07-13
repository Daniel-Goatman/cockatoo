import XCTest
@testable import LearnerCore

/// The day-1 regression suite: a fresh import must offer practice
/// immediately through introduction questions (transition c'), without
/// weakening the exposure rules for everything else.
final class ColdStartTests: XCTestCase {
    var engine: LearnerEngine!
    let t0 = Fixtures.t0

    override func setUpWithError() throws {
        engine = try Fixtures.makeEngine()
    }

    func testFreshImportOffersIntroductionSession() throws {
        let session = try engine.planSession(now: t0, seed: 1)
        XCTAssertEqual(
            session.queue.count, EngineConfig.default.sessionIntroLimit,
            "a fresh install must offer intro questions, capped per session"
        )
        for planned in session.queue {
            XCTAssertTrue(planned.isIntro)
            XCTAssertEqual(planned.question.mode, .recognition, "introductions are recognition only")
        }
    }

    func testIntroductionsFollowAdmissionOrder() throws {
        let session = try engine.planSession(now: t0, seed: 1)
        let items = try engine.store.items(language: "de")
        let expected = items
            .filter { $0.frequencyBand == 1 }
            .sorted { ($0.frequencyBand, $0.id) < ($1.frequencyBand, $1.id) }
            .prefix(EngineConfig.default.sessionIntroLimit)
            .map(\.id)
        XCTAssertEqual(session.queue.map(\.question.itemId), Array(expected))
    }

    func testGradedIntroductionEntersLearning() throws {
        let session = try engine.planSession(now: t0, seed: 1)
        let question = session.queue[0].question
        let updated = try engine.grade(result: PracticeResult(
            itemId: question.itemId, mode: .recognition, correct: true, answeredAt: t0
        ), now: t0)
        XCTAssertEqual(updated.stage, .learning, "transition c' — ambient enters learning on first answer")
        XCTAssertEqual(updated.srsBox, 1)
        XCTAssertNotNil(updated.dueAt)
        XCTAssertEqual(updated.validateInvariants(), [])
    }

    /// The release beat closes a session with ONE self-grade card on a
    /// settled (box ≥ 2) word that isn't already in the session — and never
    /// pads an otherwise-empty session into existence.
    func testReleaseBeatPicksSettledOutOfSessionWord() throws {
        let items = try engine.store.items(language: "de").filter { $0.frequencyBand == 1 }

        // One due word (carries the session) and one settled, not-due word
        // (the release candidate).
        var due = try Fixtures.progress(engine, items[0].id)
        due.stage = .learning
        due.srsBox = 1
        due.dueAt = t0.addingTimeInterval(-60)
        try engine.store.saveProgress(due)

        var settled = try Fixtures.progress(engine, items[1].id)
        settled.stage = .known
        settled.srsBox = 4
        settled.dueAt = t0.addingTimeInterval(86_400)
        try engine.store.saveProgress(settled)

        let session = try engine.planSession(now: t0, seed: 1)
        let release = session.queue.filter { $0.beat == .release }
        XCTAssertEqual(release.count, 1)
        XCTAssertEqual(release[0].question.itemId, items[1].id)
        XCTAssertEqual(release[0].question.mode, .selfGrade)
        XCTAssertEqual(session.queue.last?.beat, .release, "release closes the session")
    }

    func testIntroducedItemLeavesNextSessionUntilDue() throws {
        let first = try engine.planSession(now: t0, seed: 1)
        let introducedId = first.queue[0].question.itemId
        try engine.grade(result: PracticeResult(
            itemId: introducedId, mode: .recognition, correct: true, answeredAt: t0
        ), now: t0)

        // Immediately after: the item is in learning, box 1, due in ~1h —
        // the next session must not re-offer it as an intro or a review.
        let second = try engine.planSession(now: t0.addingTimeInterval(60), seed: 2)
        XCTAssertFalse(second.queue.contains { $0.question.itemId == introducedId })
    }

    func testReviewsAndReadyTakePriorityOverIntroductions() throws {
        // Make three items due-for-review and two ready; intros should only
        // fill the room the target leaves.
        var config = EngineConfig.default
        config.sessionQuestionTarget = 6
        let engine = try Fixtures.makeEngine(config: config)
        let items = try engine.store.items(language: "de").filter { $0.frequencyBand == 1 }

        for item in items.prefix(3) {
            var p = try Fixtures.progress(engine, item.id)
            p.stage = .learning
            p.srsBox = 1
            p.dueAt = t0.addingTimeInterval(-60)
            try engine.store.saveProgress(p)
        }
        for item in items.dropFirst(3).prefix(2) {
            var p = try Fixtures.progress(engine, item.id)
            p.stage = .ready
            try engine.store.saveProgress(p)
        }

        let session = try engine.planSession(now: t0, seed: 3)
        let intros = session.queue.filter(\.isIntro)
        let reviews = session.queue.filter { !$0.isIntro }
        XCTAssertEqual(reviews.count, 5, "due + ready come first")
        XCTAssertEqual(intros.count, 1, "intros only fill the remaining room")
    }

    func testFullSessionLeavesNoRoomForIntroductions() throws {
        var config = EngineConfig.default
        config.sessionQuestionTarget = 4
        let engine = try Fixtures.makeEngine(config: config)
        let items = try engine.store.items(language: "de").filter { $0.frequencyBand == 1 }
        for item in items.prefix(4) {
            var p = try Fixtures.progress(engine, item.id)
            p.stage = .learning
            p.srsBox = 1
            p.dueAt = t0.addingTimeInterval(-60)
            try engine.store.saveProgress(p)
        }
        let session = try engine.planSession(now: t0, seed: 4)
        XCTAssertTrue(session.queue.allSatisfy { !$0.isIntro })
    }

    func testOverviewReportsPracticeAvailabilityAndTierProgress() throws {
        let overview = try engine.overview(now: t0)
        XCTAssertTrue(overview.practiceAvailable, "day 1 must have something to do")
        XCTAssertEqual(overview.introAvailable, EngineConfig.default.sessionIntroLimit)
        XCTAssertEqual(overview.readyCount, 0)
        XCTAssertEqual(overview.almostReady.count, 3)

        let tier = try XCTUnwrap(overview.tierProgress)
        XCTAssertEqual(tier.currentTier, 1)
        XCTAssertEqual(tier.nextTier, 2)
        XCTAssertEqual(tier.knownInCurrentTier, 0)
        XCTAssertEqual(tier.currentTierTotal, 8)
        XCTAssertEqual(tier.neededInCurrentTier, 6, "ceil(0.7 × 8)")
    }
}
