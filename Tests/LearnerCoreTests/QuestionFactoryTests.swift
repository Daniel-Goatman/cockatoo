import XCTest
@testable import LearnerCore

final class QuestionFactoryTests: XCTestCase {
    let factory = QuestionFactory()
    let pack = Fixtures.simPack()
    let now = Fixtures.t0

    /// The test that would have caught the prototype's correct-answer-always-
    /// first bug: over many generations the correct index must be ~uniform.
    func testRecognitionShuffleDistribution() throws {
        let item = pack.items.first { $0.id == "de.word.haus" }!
        var positionCounts = [Int: Int]()
        let generations = 400

        for seed in 0..<generations {
            var rng = SplitMix64(seed: UInt64(seed))
            guard case .recognition(_, _, let options, let correctIndex)? =
                factory.recognition(item: item, distractorPool: pack.items, rng: &rng) else {
                return XCTFail("recognition not generatable")
            }
            XCTAssertEqual(options.count, 4)
            positionCounts[correctIndex, default: 0] += 1
        }

        XCTAssertEqual(positionCounts.keys.sorted(), [0, 1, 2, 3], "all four positions must occur")
        for (position, count) in positionCounts {
            // Uniform p=0.25, n=400 → expect 100; allow generous 55...165.
            XCTAssertTrue((55...165).contains(count), "position \(position) hit \(count)/400 — not plausibly uniform")
        }
    }

    func testDistractorsNeverContainCorrectAnswer() {
        for item in pack.items {
            var rng = SplitMix64(seed: stableHash(item.id))
            guard case .recognition(_, _, let options, let correctIndex)? =
                factory.recognition(item: item, distractorPool: pack.items, rng: &rng) else {
                return XCTFail("recognition not generatable for \(item.id)")
            }
            let correct = options[correctIndex]
            let duplicates = options.filter { $0.lowercased() == correct.lowercased() }
            XCTAssertEqual(duplicates.count, 1, "\(item.id): correct answer duplicated in options")
        }
    }

    /// The generative mode-coverage test (kills the prototype's "4 of 6 modes
    /// never generated / mastery unreachable" bug class): every item in every
    /// reachable (stage, box) state can produce every mode the planner offers.
    func testEveryOfferedModeIsGeneratableForEveryItem() throws {
        for item in pack.items {
            for stage in [Stage.ready, .learning, .known, .mastered] {
                for box in 0...6 {
                    for hasSentence in [false, true] {
                        var p = ItemProgress(itemId: item.id, now: now)
                        p.stage = stage
                        p.srsBox = box
                        p.dueAt = stage >= .learning ? now : nil

                        let sentence = hasSentence
                            ? CapturedSentence(itemId: item.id, text: "Yesterday I saw the \(item.sourceForms.last!.form) again.", capturedAt: now)
                            : nil

                        for mode in factory.offerableModes(progress: p, hasSentence: hasSentence) {
                            var rng = SplitMix64(seed: stableHash(item.id) ^ UInt64(box))
                            let q = factory.question(
                                item: item, mode: mode,
                                distractorPool: pack.items,
                                sentence: sentence, rng: &rng
                            )
                            XCTAssertNotNil(q, "\(item.id) stage=\(stage) box=\(box): offered \(mode) but not generatable")
                            if mode == .cloze, hasSentence {
                                XCTAssertEqual(q?.mode, .cloze, "\(item.id): cloze with sentence must be a real cloze")
                            }
                        }
                    }
                }
            }
        }
    }

    func testClozeBlanksLongestFormAndExpectsItsTarget() {
        let item = pack.items.first { $0.id == "de.word.haus" }!
        let sentence = CapturedSentence(itemId: item.id, text: "We walked past the houses at dusk.", capturedAt: now)
        guard let q = factory.cloze(item: item, sentence: sentence),
              case .cloze(_, let blanked, let expected) = q else {
            return XCTFail("cloze not generated")
        }
        XCTAssertEqual(expected, "die Häuser", "expected the surface form that appeared ('the houses'), not the citation form")
        XCTAssertTrue(blanked.contains("_____"))
        XCTAssertFalse(blanked.lowercased().contains("the houses"))
    }

    /// Documented fallback: cloze without a sentence degrades to recall and
    /// IS a recall question (no silent degradation labeled cloze — P4).
    func testClozeWithoutSentenceFallsBackToLabeledRecall() {
        let item = pack.items.first { $0.id == "de.word.haus" }!
        var rng = SplitMix64(seed: 1)
        let q = factory.question(item: item, mode: .cloze, distractorPool: pack.items, sentence: nil, rng: &rng)
        XCTAssertEqual(q?.mode, .recall)
    }

    func testOfferableModesByStageAndBox() {
        var p = ItemProgress(itemId: "de.word.haus", now: now)

        p.stage = .ambient
        XCTAssertTrue(factory.offerableModes(progress: p, hasSentence: true).isEmpty)

        p.stage = .ready
        XCTAssertEqual(factory.offerableModes(progress: p, hasSentence: true), [.recognition])

        p.stage = .learning
        p.srsBox = 2
        XCTAssertEqual(factory.offerableModes(progress: p, hasSentence: false), [.recognition, .recall])

        p.srsBox = 5
        XCTAssertEqual(factory.offerableModes(progress: p, hasSentence: true), [.recall, .cloze])
        XCTAssertEqual(factory.offerableModes(progress: p, hasSentence: false), [.recall])
    }

    func testSessionRepairRequeuesOnce() {
        let planner = SessionPlanner()
        let missed = Question.recall(itemId: "de.word.haus", prompt: "house", expected: "das Haus")
        var queue: [SessionPlanner.PlannedQuestion] = (0..<8).map { i in
            .init(question: .recall(itemId: "item\(i)", prompt: "p\(i)", expected: "e\(i)"), isRepair: false)
        }
        planner.requeueMissed(missed, into: &queue, afterIndex: 1)
        XCTAssertEqual(queue.count, 9)
        XCTAssertEqual(queue[5].question.itemId, "de.word.haus", "re-inserted repairOffset(3) + 1 positions after index 1")
        XCTAssertTrue(queue[5].isRepair)

        // Second miss of the same item does not re-queue again.
        planner.requeueMissed(missed, into: &queue, afterIndex: 5)
        XCTAssertEqual(queue.count, 9)
    }
}
