import XCTest
@testable import LearnerCore

/// The redesign's core promise (D-R2): practice as much as you want in one
/// day — none of it can fake multi-day understanding. Box height climbs at
/// most one step per calendar day, `known` needs correct answers on ≥3
/// distinct days, and wrong answers still count against you at any volume.
///
/// All timestamps anchor to the LOCAL calendar day (LearningCalendar), so
/// "same day" in a test means the same day the engine sees, regardless of
/// the machine's timezone.
final class BingePracticeTests: XCTestCase {
    /// Hour `hour` of the `day`-th local calendar day at/after t0.
    func at(day: Int, hour: Double) -> Date {
        LearningCalendar.dayStart(of: Fixtures.t0)
            .addingTimeInterval(Double(day) * 86_400 + hour * 3600)
    }

    func testDayLongBingeCannotClimbPastBoxOne() throws {
        let engine = try Fixtures.makeEngine()
        let itemId = "de.word.und"

        // Introduce at 08:00, then answer correctly every 30 minutes until
        // 19:30 — far past the box-1 (1h) and box-2 (6h) cooldowns, all
        // within one local calendar day.
        for rep in 0..<24 {
            let clock = at(day: 1, hour: 8 + Double(rep) * 0.5)
            let updated = try engine.grade(result: PracticeResult(
                itemId: itemId, mode: .recognition, correct: true, answeredAt: clock
            ), now: clock)
            XCTAssertEqual(updated.validateInvariants(), [])
        }

        let p = try Fixtures.progress(engine, itemId)
        XCTAssertEqual(p.srsBox, 1, "24 same-day correct answers = exactly the introduction advance")
        XCTAssertEqual(p.stage, .learning)
        XCTAssertEqual(p.distinctCorrectDays, 1, "a binge is one day of evidence")
    }

    func testKnownTakesAtLeastFourCalendarDaysNoMatterTheVolume() throws {
        let engine = try Fixtures.makeEngine()
        let itemId = "de.word.und"
        var reachedKnownOnDay: Int?

        // Ten days; each day the learner binges 10 correct answers in
        // mixed modes between 08:00 and 15:30.
        for day in 1...10 {
            for rep in 0..<10 {
                let clock = at(day: day, hour: 8 + Double(rep) * 0.75)
                let mode: PracticeMode = rep % 2 == 0 ? .recognition : .recall
                let updated = try engine.grade(result: PracticeResult(
                    itemId: itemId, mode: mode, correct: true, answeredAt: clock
                ), now: clock)
                XCTAssertEqual(updated.validateInvariants(), [])
                if updated.stage >= .known, reachedKnownOnDay == nil {
                    reachedKnownOnDay = day
                }
            }
        }

        let day = try XCTUnwrap(reachedKnownOnDay, "the word must eventually become known")
        // Boxes: intro day (0→1), then one advance per day → box 4 (known
        // threshold) on the 4th day at the earliest.
        XCTAssertGreaterThanOrEqual(day, 4, "known on day \(day) — cramming compressed the calendar")
        let p = try Fixtures.progress(engine, itemId)
        XCTAssertGreaterThanOrEqual(p.distinctCorrectDays, 3)
    }

    func testWrongAnswersCountAtAnyVolume() throws {
        let engine = try Fixtures.makeEngine()
        let itemId = "de.word.und"

        // Three good days to box 3.
        for day in 1...3 {
            let clock = at(day: day, hour: 9)
            try engine.grade(result: PracticeResult(
                itemId: itemId, mode: .recognition, correct: true, answeredAt: clock
            ), now: clock)
        }
        XCTAssertEqual(try Fixtures.progress(engine, itemId).srsBox, 3)

        // A same-day extra rep that misses: the lapse lands even though the
        // item isn't due — evidence of not-knowing is valid anytime.
        let clock = at(day: 3, hour: 9.5)
        let updated = try engine.grade(result: PracticeResult(
            itemId: itemId, mode: .recall, correct: false, answeredAt: clock
        ), now: clock)
        XCTAssertEqual(updated.srsBox, 1, "lapse drop applies on non-due reps too")
        XCTAssertEqual(updated.lapses, 1)
    }

    func testExtraRepsNeverDelayTheNextRealReview() throws {
        let engine = try Fixtures.makeEngine()
        let itemId = "de.word.und"

        // Two days to box 2 (6h interval), advancing at 09:00.
        for day in 1...2 {
            let clock = at(day: day, hour: 9)
            try engine.grade(result: PracticeResult(
                itemId: itemId, mode: .recognition, correct: true, answeredAt: clock
            ), now: clock)
        }
        let scheduled = try Fixtures.progress(engine, itemId).dueAt

        // An enthusiastic non-due rep an hour later must leave dueAt alone.
        let clock = at(day: 2, hour: 10)
        let updated = try engine.grade(result: PracticeResult(
            itemId: itemId, mode: .recognition, correct: true, answeredAt: clock
        ), now: clock)
        XCTAssertEqual(updated.dueAt, scheduled, "reinforcement must not push the review out")
    }

    func testUnlimitedSessionsStayHonestOverAWeek() throws {
        // A maniac learner: 8 full sessions every day for 7 days, all
        // correct. The library grows only by the drip, and nothing reaches
        // known before the third day.
        let engine = try Fixtures.makeEngine()
        var rng = SplitMix64(seed: 99)

        for day in 1...7 {
            for bout in 0..<8 {
                var clock = at(day: day, hour: 8 + Double(bout) * 1.5)
                let session = try engine.planSession(now: clock, seed: rng.next())
                for planned in session.queue {
                    let updated = try engine.grade(result: PracticeResult(
                        itemId: planned.question.itemId,
                        mode: planned.question.mode,
                        correct: true,
                        answeredAt: clock
                    ), now: clock)
                    XCTAssertEqual(updated.validateInvariants(), [])
                    if day < 3 {
                        XCTAssertLessThan(updated.stage, .known,
                                          "known on day \(day) despite distinct-day gates")
                    }
                    clock = clock.addingTimeInterval(30)
                }
            }
        }

        let progress = try engine.store.allProgress()
        let items = try engine.store.items(language: "de")
        XCTAssertEqual(progress.count, min(7 * EngineConfig.default.newPerDay, items.count),
                       "the drip, not the volume, sets library growth")
        // Honesty both ways: anything promoted carries real multi-day
        // evidence — and real progress DID happen; this is unlimited
        // practice, not a treadmill.
        for p in progress.values where p.stage >= .known {
            XCTAssertGreaterThanOrEqual(p.distinctCorrectDays, EngineConfig.default.knownDistinctDays)
        }
        for p in progress.values where p.stage == .mastered {
            XCTAssertGreaterThanOrEqual(p.distinctCorrectDays, 5, "mastered needs box 5 = five daily advances")
        }
        XCTAssertGreaterThanOrEqual(
            progress.values.filter { $0.stage >= .known }.count, 3,
            "honest multi-day evidence still promotes words"
        )
    }
}
