import XCTest
@testable import LearnerCore

final class GraderTests: XCTestCase {
    let grader = Grader(grading: .germanFixture)
    let now = Fixtures.t0

    // MARK: - Typed answer checking

    func check(_ answer: String, expected: String) -> Grader.TypedVerdict {
        grader.checkTyped(question: .recall(itemId: "x", prompt: "p", expected: expected), answer: answer)
    }

    func testExactMatch() {
        XCTAssertEqual(check("das Haus", expected: "das Haus"), .correct)
    }

    func testCaseAndAccentInsensitive() {
        XCTAssertEqual(check("hauser", expected: "Häuser"), .correct)
        XCTAssertEqual(check("STADT", expected: "Stadt"), .correct)
        XCTAssertEqual(check("strasse", expected: "Straße"), .correct)
    }

    func testArticleOptionalBothDirections() {
        XCTAssertEqual(check("Haus", expected: "das Haus"), .correct)
        XCTAssertEqual(check("das Haus", expected: "Haus"), .correct)
        XCTAssertEqual(check("die Haus", expected: "das Haus"), .correct, "wrong article is forgiven when the noun matches (v1 stance)")
    }

    func testNearMissOnLongWords() {
        XCTAssertEqual(check("Hauserr", expected: "Häuser"), .nearMiss(expected: "Häuser"))
        // Short words get no near-miss forgiveness.
        XCTAssertEqual(check("unt", expected: "und"), .wrong(expected: "und"))
    }

    func testPlainWrong() {
        XCTAssertEqual(check("Hund", expected: "das Haus"), .wrong(expected: "das Haus"))
    }

    // MARK: - Stage transitions (d/e/f of docs/plan/04 + D-R2 distinct days)

    /// Yesterday relative to t0, so today's correct answer counts as a new
    /// distinct day.
    var yesterday: Date { now.addingTimeInterval(-24 * 3600) }

    func learningProgress(
        box: Int, stage: Stage,
        recog: Int = 0, recall: Int = 0, cloze: Int = 0,
        distinctDays: Int = 0, lastCorrect: Date? = nil
    ) -> ItemProgress {
        var p = ItemProgress(itemId: "de.word.haus", now: now)
        p.stage = stage
        p.srsBox = box
        p.dueAt = now.addingTimeInterval(-60)
        p.recognitionCorrect = recog
        p.recallCorrect = recall
        p.clozeCorrect = cloze
        p.distinctCorrectDays = distinctDays
        p.lastCorrectAt = lastCorrect
        return p
    }

    func testFirstAnswerCreatesLearningRowEvenWhenWrong() {
        let p = ItemProgress(itemId: "de.word.haus", now: now)
        let result = PracticeResult(itemId: p.itemId, mode: .recognition, correct: false, answeredAt: now)
        let updated = grader.apply(result: result, progress: p, now: now)
        XCTAssertEqual(updated.stage, .learning, "library entry survives a wrong first answer")
        XCTAssertEqual(updated.validateInvariants(), [])
    }

    func testKnownRequiresBoxBothModesAndDistinctDays() {
        // Box 3→4 while due, distinct days satisfied, but no recognition
        // history: stays learning.
        var p = learningProgress(box: 3, stage: .learning, recog: 0, recall: 2, distinctDays: 3, lastCorrect: yesterday)
        var updated = grader.apply(result: .init(itemId: p.itemId, mode: .recall, correct: true, answeredAt: now), progress: p, now: now)
        XCTAssertEqual(updated.srsBox, 4)
        XCTAssertEqual(updated.stage, .learning)

        // Box + both modes but only 2 distinct days, both counted earlier
        // today: stays learning (D-R2 — cramming can't finish the job).
        p = learningProgress(box: 3, stage: .learning, recog: 1, recall: 1, distinctDays: 2, lastCorrect: now.addingTimeInterval(-1800))
        updated = grader.apply(result: .init(itemId: p.itemId, mode: .recall, correct: true, answeredAt: now), progress: p, now: now)
        XCTAssertEqual(updated.srsBox, 4)
        XCTAssertEqual(updated.distinctCorrectDays, 2, "same-day correct adds no distinct day")
        XCTAssertEqual(updated.stage, .learning)

        // All three requirements met (third distinct day lands now): known.
        p = learningProgress(box: 3, stage: .learning, recog: 1, recall: 1, distinctDays: 2, lastCorrect: yesterday)
        updated = grader.apply(result: .init(itemId: p.itemId, mode: .recall, correct: true, answeredAt: now), progress: p, now: now)
        XCTAssertEqual(updated.distinctCorrectDays, 3)
        XCTAssertEqual(updated.stage, .known)
        XCTAssertEqual(updated.validateInvariants(), [])
    }

    func testMasteredRequiresClozePassesAtHighBox() {
        // Second cloze correct at box 5 while known → mastered.
        let p = learningProgress(box: 4, stage: .known, recog: 2, recall: 2, cloze: 1, distinctDays: 4, lastCorrect: yesterday)
        let updated = grader.apply(result: .init(itemId: p.itemId, mode: .cloze, correct: true, answeredAt: now), progress: p, now: now)
        XCTAssertEqual(updated.srsBox, 5)
        XCTAssertEqual(updated.clozeCorrect, 2)
        XCTAssertEqual(updated.stage, .mastered)
    }

    func testLapseLadder() {
        // known lapses to learning, box drops 2 with floor 1, streak resets.
        var p = learningProgress(box: 4, stage: .known, recog: 3, recall: 3)
        p.correctStreak = 5
        var updated = grader.apply(result: .init(itemId: p.itemId, mode: .recall, correct: false, answeredAt: now), progress: p, now: now)
        XCTAssertEqual(updated.stage, .learning)
        XCTAssertEqual(updated.srsBox, 2)
        XCTAssertEqual(updated.correctStreak, 0)
        XCTAssertEqual(updated.lapses, 1)

        // mastered lapses to known.
        p = learningProgress(box: 6, stage: .mastered, recog: 3, recall: 3, cloze: 3)
        updated = grader.apply(result: .init(itemId: p.itemId, mode: .cloze, correct: false, answeredAt: now), progress: p, now: now)
        XCTAssertEqual(updated.stage, .known)
        XCTAssertEqual(updated.srsBox, 4)
    }

    // MARK: - Near-miss grading (wrong-but-gentle, docs/plan/04 §Recall)

    func testNearMissHoldsBoxWithoutLapse() {
        var p = learningProgress(box: 4, stage: .known, recog: 3, recall: 3)
        p.correctStreak = 5
        let result = PracticeResult(itemId: p.itemId, mode: .recall, correct: false, nearMiss: true, answeredAt: now)
        let updated = grader.apply(result: result, progress: p, now: now)
        XCTAssertEqual(updated.srsBox, 4, "near-miss holds the box")
        XCTAssertEqual(updated.lapses, 0, "near-miss is not a lapse")
        XCTAssertEqual(updated.stage, .known, "no stage fall on a near-miss")
        XCTAssertEqual(updated.correctStreak, 0, "but the streak still resets")
        XCTAssertEqual(updated.recallCorrect, 3, "and it never counts as correct")
        XCTAssertNotNil(updated.dueAt)
        XCTAssertEqual(updated.validateInvariants(), [])
    }

    func testNearMissOnFirstAnswerStillEntersLibrary() {
        let p = ItemProgress(itemId: "de.word.haus", now: now)
        let result = PracticeResult(itemId: p.itemId, mode: .recall, correct: false, nearMiss: true, answeredAt: now)
        let updated = grader.apply(result: result, progress: p, now: now)
        XCTAssertEqual(updated.stage, .learning)
        XCTAssertEqual(updated.lapses, 0)
        XCTAssertEqual(updated.validateInvariants(), [])
    }

    func testNearMissFlagIgnoredWhenCorrect() {
        let p = learningProgress(box: 2, stage: .learning, recog: 1, recall: 1)
        let result = PracticeResult(itemId: p.itemId, mode: .recall, correct: true, nearMiss: true, answeredAt: now)
        let updated = grader.apply(result: result, progress: p, now: now)
        XCTAssertEqual(updated.srsBox, 3)
        XCTAssertEqual(updated.recallCorrect, 2)
    }

    func testInvariantsHoldUnderRandomResultSequences() {
        var rng = SplitMix64(seed: 42)
        var p = learningProgress(box: 0, stage: .learning)
        var clock = now
        for i in 0..<300 {
            let mode = PracticeMode.allCases[Int(rng.next() % 3)]
            let correct = rng.next() % 100 < 80
            p = grader.apply(result: .init(itemId: p.itemId, mode: mode, correct: correct, answeredAt: clock), progress: p, now: clock)
            XCTAssertEqual(p.validateInvariants(), [], "violation at step \(i)")
            clock = clock.addingTimeInterval(Double(rng.next() % (24 * 3600)))
        }
    }
}
