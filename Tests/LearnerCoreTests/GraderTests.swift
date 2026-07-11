import XCTest
@testable import LearnerCore

final class GraderTests: XCTestCase {
    let grader = Grader(grading: .german)
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

    // MARK: - Stage transitions (c/d/e/f of docs/plan/04)

    func learningProgress(box: Int, stage: Stage, recog: Int = 0, recall: Int = 0, cloze: Int = 0) -> ItemProgress {
        var p = ItemProgress(itemId: "de.word.haus", now: now)
        p.stage = stage
        p.srsBox = box
        p.dueAt = stage >= .learning ? now.addingTimeInterval(-60) : nil
        p.recognitionCorrect = recog
        p.recallCorrect = recall
        p.clozeCorrect = cloze
        return p
    }

    func testFirstAnswerEntersLearning() {
        var p = ItemProgress(itemId: "de.word.haus", now: now)
        p.stage = .ready
        let result = PracticeResult(itemId: p.itemId, mode: .recognition, correct: false, answeredAt: now)
        let updated = grader.apply(result: result, progress: p, now: now)
        XCTAssertEqual(updated.stage, .learning, "transition c fires on wrong answers too")
        XCTAssertEqual(updated.validateInvariants(), [])
    }

    func testKnownRequiresBoxAndBothModes() {
        // Box 3→4 while due, has recall but no recognition: stays learning.
        var p = learningProgress(box: 3, stage: .learning, recog: 0, recall: 2)
        var updated = grader.apply(result: .init(itemId: p.itemId, mode: .recall, correct: true, answeredAt: now), progress: p, now: now)
        XCTAssertEqual(updated.srsBox, 4)
        XCTAssertEqual(updated.stage, .learning)

        // Same but with recognition history: promotes to known.
        p = learningProgress(box: 3, stage: .learning, recog: 1, recall: 1)
        updated = grader.apply(result: .init(itemId: p.itemId, mode: .recall, correct: true, answeredAt: now), progress: p, now: now)
        XCTAssertEqual(updated.stage, .known)
        XCTAssertEqual(updated.validateInvariants(), [])
    }

    func testMasteredRequiresClozePassesAtHighBox() {
        // Second cloze correct at box 5 while known → mastered.
        let p = learningProgress(box: 4, stage: .known, recog: 2, recall: 2, cloze: 1)
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

    func testInvariantsHoldUnderRandomResultSequences() {
        var rng = SplitMix64(seed: 42)
        var p = learningProgress(box: 0, stage: .ready)
        p.dueAt = nil
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
