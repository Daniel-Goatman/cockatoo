import XCTest
@testable import LearnerCore

/// The day-1 suite for practice-first intake (docs/plan/10-learning-redesign):
/// a fresh import must offer practice immediately through introduction
/// questions, and sessions must never run dry while the library has items.
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

    func testIntroductionsFollowIntakeOrder() throws {
        let session = try engine.planSession(now: t0, seed: 1)
        let items = try engine.store.items(language: "de")
        let expected = items
            .sorted { ($0.frequencyBand, $0.id) < ($1.frequencyBand, $1.id) }
            .prefix(EngineConfig.default.sessionIntroLimit)
            .map(\.id)
        XCTAssertEqual(session.queue.map(\.question.itemId), Array(expected))
    }

    func testGradedIntroductionCreatesLibraryRow() throws {
        let session = try engine.planSession(now: t0, seed: 1)
        let question = session.queue[0].question
        XCTAssertNil(try engine.store.progress(itemId: question.itemId), "no row before the first answer")
        let updated = try engine.grade(result: PracticeResult(
            itemId: question.itemId, mode: .recognition, correct: true, answeredAt: t0
        ), now: t0)
        XCTAssertEqual(updated.stage, .learning, "first answer enters the library at learning")
        XCTAssertEqual(updated.srsBox, 1)
        XCTAssertEqual(updated.distinctCorrectDays, 1)
        XCTAssertNotNil(updated.dueAt)
        XCTAssertEqual(updated.activatedAt, t0)
        XCTAssertEqual(updated.validateInvariants(), [])
    }

    func testDailyIntakeBudgetCapsIntroductionsAcrossSessions() throws {
        // Sessions 1 and 2 introduce 3 + 2 = newPerDay(5); session 3 the
        // same day gets none.
        var clock = t0
        for expected in [3, 2, 0] {
            let session = try engine.planSession(now: clock, seed: 1)
            let intros = session.queue.filter(\.isIntro)
            XCTAssertEqual(intros.count, expected, "at \(clock)")
            for planned in intros {
                try engine.grade(result: PracticeResult(
                    itemId: planned.question.itemId, mode: .recognition, correct: true, answeredAt: clock
                ), now: clock)
            }
            clock = clock.addingTimeInterval(600)
        }

        // Tomorrow the budget refills.
        let tomorrow = t0.addingTimeInterval(24 * 3600)
        let fresh = try engine.planSession(now: tomorrow, seed: 2)
        XCTAssertEqual(fresh.queue.filter(\.isIntro).count, EngineConfig.default.sessionIntroLimit)
    }

    func testSessionsNeverRunDryWhileLibraryHasItems() throws {
        // Introduce 5 words (the daily budget), then immediately ask for
        // another session: nothing is due, the budget is spent — the session
        // must still fill with reinforcement reps.
        var clock = t0
        for _ in 0..<2 {
            let session = try engine.planSession(now: clock, seed: 1)
            for planned in session.queue where planned.isIntro {
                try engine.grade(result: PracticeResult(
                    itemId: planned.question.itemId, mode: .recognition, correct: true, answeredAt: clock
                ), now: clock)
            }
            clock = clock.addingTimeInterval(60)
        }

        let extra = try engine.planSession(now: clock, seed: 3)
        XCTAssertFalse(extra.queue.isEmpty, "practice must always be available (D-R1)")
        XCTAssertEqual(extra.queue.filter(\.isIntro).count, 0, "daily budget spent")
        XCTAssertEqual(
            Set(extra.queue.filter { $0.beat != .release }.map(\.question.itemId)).count, 5,
            "all five library words return as reinforcement"
        )
    }

    /// The release beat closes a session with ONE self-grade card on a
    /// settled (box ≥ 2) word that isn't already in the session — and never
    /// pads an otherwise-empty session into existence.
    func testReleaseBeatPicksSettledOutOfSessionWord() throws {
        let items = try engine.store.items(language: "de").filter { $0.frequencyBand == 1 }

        // Enough due words to fill the session target (7 due + 3 intros),
        // plus one settled, not-due word (the release candidate) — with no
        // reinforcement room left to swallow it.
        for item in items.prefix(7) {
            try Fixtures.seed(engine, item.id) { p in
                p.srsBox = 1
                p.dueAt = self.t0.addingTimeInterval(-60)
            }
        }
        let releaseCandidate = items[7].id
        try Fixtures.seed(engine, releaseCandidate) { p in
            p.stage = .known
            p.srsBox = 4
            p.dueAt = self.t0.addingTimeInterval(86_400)
        }

        let session = try engine.planSession(now: t0, seed: 1)
        let release = session.queue.filter { $0.beat == .release }
        XCTAssertEqual(release.count, 1)
        XCTAssertEqual(release.first?.question.itemId, releaseCandidate)
        XCTAssertEqual(release.first?.question.mode, .selfGrade)
        XCTAssertEqual(session.queue.last?.beat, .release, "release closes the session")
    }

    func testReviewsTakePriorityOverIntroductions() throws {
        var config = EngineConfig.default
        config.sessionQuestionTarget = 6
        let engine = try Fixtures.makeEngine(config: config)
        let items = try engine.store.items(language: "de").filter { $0.frequencyBand == 1 }

        for item in items.prefix(5) {
            try Fixtures.seed(engine, item.id) { p in
                p.srsBox = 1
                p.dueAt = self.t0.addingTimeInterval(-60)
            }
        }

        let session = try engine.planSession(now: t0, seed: 3)
        let intros = session.queue.filter(\.isIntro)
        let dueIds = Set(items.prefix(5).map(\.id))
        let reviews = session.queue.filter { dueIds.contains($0.question.itemId) }
        XCTAssertEqual(reviews.count, 5, "due reviews all present")
        XCTAssertEqual(intros.count, 1, "intros only fill the room reviews leave")
    }

    func testFullSessionLeavesNoRoomForIntroductions() throws {
        var config = EngineConfig.default
        config.sessionQuestionTarget = 4
        let engine = try Fixtures.makeEngine(config: config)
        let items = try engine.store.items(language: "de").filter { $0.frequencyBand == 1 }
        for item in items.prefix(4) {
            try Fixtures.seed(engine, item.id) { p in
                p.srsBox = 1
                p.dueAt = self.t0.addingTimeInterval(-60)
            }
        }
        let session = try engine.planSession(now: t0, seed: 4)
        XCTAssertTrue(session.queue.allSatisfy { !$0.isIntro })
    }

    func testIntakePausesUnderReviewDebt() throws {
        let items = try engine.store.items(language: "de")
        for item in items.prefix(EngineConfig.default.introDuePauseThreshold) {
            try Fixtures.seed(engine, item.id) { p in
                p.srsBox = 1
                p.dueAt = self.t0.addingTimeInterval(-60)
            }
        }
        let session = try engine.planSession(now: t0, seed: 5)
        XCTAssertTrue(session.queue.allSatisfy { !$0.isIntro }, "introductions pause while review debt is high")
    }

    /// The "aber forever" bug: the release beat must not pin one word —
    /// a word that already got its release today is excluded, and ties
    /// rotate by least-recently-practiced.
    func testReleaseBeatRotatesInsteadOfPinningOneWord() throws {
        let items = try engine.store.items(language: "de").filter { $0.frequencyBand == 1 }
        // Fill the session with due words so release candidates stay out.
        for item in items.prefix(7) {
            try Fixtures.seed(engine, item.id) { p in
                p.srsBox = 1
                p.dueAt = self.t0.addingTimeInterval(-60)
                p.lastResultAt = self.t0.addingTimeInterval(-3600)
            }
        }
        // Two settled candidates: "aber" is strongest but was practiced
        // TODAY (its release already happened); the weaker one wasn't.
        try Fixtures.seed(engine, items[7].id) { p in   // de.word.und (sorted last)
            p.stage = .known
            p.srsBox = 5
            p.dueAt = self.t0.addingTimeInterval(86_400)
            p.lastResultAt = self.t0.addingTimeInterval(-600)   // today
        }
        let fresh = try engine.store.items(language: "de").first { $0.frequencyBand == 2 }!
        try Fixtures.seed(engine, fresh.id) { p in
            p.stage = .known
            p.srsBox = 4
            p.dueAt = self.t0.addingTimeInterval(86_400)
            p.lastResultAt = self.t0.addingTimeInterval(-30 * 3600)   // yesterday
        }

        let session = try engine.planSession(now: t0, seed: 9)
        let release = session.queue.filter { $0.beat == .release }
        XCTAssertEqual(release.map(\.question.itemId), [fresh.id],
                       "practiced-today words sit release out; the rest rotate")
    }

    func testOverviewReportsPracticeAvailabilityAndMilestone() throws {
        let overview = try engine.overview(now: t0)
        XCTAssertTrue(overview.practiceAvailable, "day 1 must have something to do")
        XCTAssertEqual(overview.libraryCount, 0)
        XCTAssertEqual(overview.introAvailable, 24, "every pack item is an intake candidate")
        XCTAssertEqual(overview.newRemainingToday, EngineConfig.default.newPerDay)

        let milestone = try XCTUnwrap(overview.nextMilestone)
        XCTAssertEqual(milestone.band, 1)
        XCTAssertEqual(milestone.known, 0)
        XCTAssertEqual(milestone.total, 8)
        XCTAssertEqual(milestone.needed, 6, "ceil(0.7 × 8)")
        XCTAssertNil(overview.pendingMilestoneBand)
    }
}
