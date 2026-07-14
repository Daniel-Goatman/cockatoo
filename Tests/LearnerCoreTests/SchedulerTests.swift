import XCTest
@testable import LearnerCore

final class SchedulerTests: XCTestCase {
    let scheduler = LeitnerScheduler()
    let now = Fixtures.t0

    func progress(box: Int, dueAt: Date?) -> ItemProgress {
        var p = ItemProgress(itemId: "de.word.haus", now: now)
        p.stage = .learning
        p.srsBox = box
        p.dueAt = dueAt
        return p
    }

    func testBoxStaysInRangeUnderRandomSequences() {
        var rng = SplitMix64(seed: 7)
        var p = progress(box: 0, dueAt: nil)
        var clock = now
        for _ in 0..<500 {
            let correct = rng.next() % 100 < 70
            let (box, dueAt) = scheduler.next(after: correct, progress: p, now: clock)
            XCTAssertTrue((0...6).contains(box), "box \(box) out of range")
            p.srsBox = box
            p.dueAt = dueAt
            clock = clock.addingTimeInterval(Double(rng.next() % (48 * 3600)))
        }
    }

    func testCorrectWhileDueAdvancesOneBox() {
        let p = progress(box: 2, dueAt: now.addingTimeInterval(-60))
        let (box, dueAt) = scheduler.next(after: true, progress: p, now: now)
        XCTAssertEqual(box, 3)
        XCTAssertGreaterThan(dueAt, now)
    }

    func testEarlyCorrectNeverAdvances() {
        let p = progress(box: 3, dueAt: now.addingTimeInterval(3600))
        let (box, _) = scheduler.next(after: true, progress: p, now: now)
        XCTAssertEqual(box, 3)
    }

    // MARK: - Distinct-day advance gate (D-R2)

    func testSameDayCorrectAfterAdvanceHoldsBox() {
        // Advanced 2 hours ago (same calendar day), due again now: correct
        // holds the box — one advance per word per day.
        var p = progress(box: 1, dueAt: now.addingTimeInterval(-60))
        p.lastAdvancedAt = now.addingTimeInterval(-2 * 3600)
        let (box, dueAt) = scheduler.next(after: true, progress: p, now: now)
        XCTAssertEqual(box, 1, "same-day rep must not climb the ladder")
        XCTAssertGreaterThan(dueAt, now, "but it still reschedules")
    }

    func testNextDayCorrectAdvances() {
        var p = progress(box: 1, dueAt: now.addingTimeInterval(-60))
        p.lastAdvancedAt = now.addingTimeInterval(-25 * 3600)
        let (box, _) = scheduler.next(after: true, progress: p, now: now)
        XCTAssertEqual(box, 2)
    }

    func testIntroductionAdvanceExemptFromDayGate() {
        // Box 0 → 1 is the introduction, not retention evidence — it is
        // allowed even if some advance already happened today (fresh rows
        // have lastAdvancedAt nil anyway; this guards the definition).
        var p = progress(box: 0, dueAt: nil)
        p.lastAdvancedAt = now.addingTimeInterval(-3600)
        let (box, _) = scheduler.next(after: true, progress: p, now: now)
        XCTAssertEqual(box, 1)
    }

    func testWrongAlwaysLapsesRegardlessOfDayGate() {
        var p = progress(box: 4, dueAt: now.addingTimeInterval(3600))
        p.lastAdvancedAt = now.addingTimeInterval(-60)
        let (box, _) = scheduler.next(after: false, progress: p, now: now)
        XCTAssertEqual(box, 2, "evidence of not-knowing is valid anytime")
    }

    func testWrongDropsTwoBoxesWithFloor() {
        let high = progress(box: 5, dueAt: now.addingTimeInterval(-60))
        XCTAssertEqual(scheduler.next(after: false, progress: high, now: now).box, 3)
        let low = progress(box: 2, dueAt: now.addingTimeInterval(-60))
        XCTAssertEqual(scheduler.next(after: false, progress: low, now: now).box, 1)
        let floor = progress(box: 1, dueAt: now.addingTimeInterval(-60))
        XCTAssertEqual(scheduler.next(after: false, progress: floor, now: now).box, 1)
    }

    func testIntervalsMonotonicInBox() {
        var previous: TimeInterval = 0
        for box in 1...6 {
            let due = scheduler.dueDate(box: box, itemId: "de.word.haus", from: now)
            let interval = due.timeIntervalSince(now)
            XCTAssertGreaterThan(interval, previous, "box \(box) interval not larger than box \(box - 1)")
            previous = interval
        }
    }

    func testJitterIsDeterministicAndBounded() {
        let a = scheduler.dueDate(box: 3, itemId: "de.word.haus", from: now)
        let b = scheduler.dueDate(box: 3, itemId: "de.word.haus", from: now)
        XCTAssertEqual(a, b, "jitter must be deterministic per item")

        let base: TimeInterval = 24 * 3600
        for id in ["de.word.hund", "de.word.stadt", "de.word.kind", "de.word.welt"] {
            let interval = scheduler.dueDate(box: 3, itemId: id, from: now).timeIntervalSince(now)
            XCTAssertGreaterThanOrEqual(interval, base * 0.9 - 1)
            XCTAssertLessThanOrEqual(interval, base * 1.1 + 1)
        }
    }

    func testBoxZeroIsDueImmediately() {
        XCTAssertTrue(scheduler.isDue(progress(box: 0, dueAt: nil), now: now))
    }
}
