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
            for stage in Stage.allCases {
                for box in 0...6 {
                    for hasSentence in [false, true] {
                        var p = ItemProgress(itemId: item.id, now: now)
                        p.stage = stage
                        p.srsBox = box

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
              case .cloze(_, let blanked, let hint, let expected) = q else {
            return XCTFail("cloze not generated")
        }
        XCTAssertEqual(expected, "die Häuser", "expected the surface form that appeared ('the houses'), not the citation form")
        XCTAssertTrue(blanked.contains("_____"))
        XCTAssertFalse(blanked.lowercased().contains("the houses"))
        XCTAssertNil(hint, "captured-context cloze carries no hint — context is the point")
    }

    /// The Glamorgan bug: a form must never be blanked mid-word, a
    /// paragraph-sized capture is not a card, and a blank that removes all
    /// identifying context is not a question.
    func testCapturedClozeRejectsUnanswerableSentences() {
        let oder = Fixtures.invariant("or", "oder")

        // "or" inside "Glamorgan" — word boundaries required.
        let midWord = CapturedSentence(itemId: oder.id, text: "Glywysing is now called Glamorgan today.", capturedAt: now)
        XCTAssertNil(factory.cloze(item: oder, sentence: midWord), "must not blank inside a word")

        // Boundary-clean occurrence still works.
        let clean = CapturedSentence(itemId: oder.id, text: "Is the kingdom large or small today?", capturedAt: now)
        guard case .cloze(_, let blanked, _, _)? = factory.cloze(item: oder, sentence: clean) else {
            return XCTFail("boundary-clean cloze should generate")
        }
        XCTAssertTrue(blanked.contains("large _____ small"))

        // Longer than the card cap → rejected.
        let essay = CapturedSentence(
            itemId: oder.id,
            text: "In the seventh century it was one kingdom or two, covering the south-east, "
                + "but in the ninth century it was divided between two smaller realms of higher "
                + "status whose borders shifted many times over the following decades.",
            capturedAt: now
        )
        XCTAssertNil(factory.cloze(item: oder, sentence: essay), "paragraph captures are not cards")

        // Blanking away nearly everything → rejected (no context survives).
        let haus = pack.items.first { $0.id == "de.word.haus" }!
        let tiny = CapturedSentence(itemId: haus.id, text: "The house is old.", capturedAt: now)
        XCTAssertNil(factory.cloze(item: haus, sentence: tiny), "'_____ is old.' identifies nothing")
    }

    /// Without a captured sentence, cloze blanks the GERMAN word in the
    /// authored example and carries the English sentence as the hint —
    /// always answerable. With no example either, it degrades to recall
    /// and IS a recall question (no silent degradation labeled cloze — P4).
    func testExampleClozeBlanksGermanWithEnglishHint() {
        let item = pack.items.first { $0.id == "de.word.haus" }!
        var rng = SplitMix64(seed: 1)

        guard case .cloze(_, let blanked, let hint, let expected)? =
            factory.question(item: item, mode: .cloze, distractorPool: pack.items, sentence: nil, rng: &rng) else {
            return XCTFail("example cloze should generate")
        }
        XCTAssertTrue(blanked.contains("_____"))
        XCTAssertFalse(blanked.contains("Haus"), "the German word is the blank")
        XCTAssertEqual(expected, "Haus")
        XCTAssertEqual(hint, item.examples[0].source, "English sentence rides along as the hint")

        var bare = item
        bare.examples = []
        let fallback = factory.question(item: bare, mode: .cloze, distractorPool: pack.items, sentence: nil, rng: &rng)
        XCTAssertEqual(fallback?.mode, .recall)
    }

    /// Rebuild tokenizes the example's target sentence and never presents
    /// the tokens in already-solved order; without a usable example it
    /// degrades to recall, labeled as such.
    func testRebuildShufflesExampleTokensAndFallsBack() {
        let item = pack.items.first { $0.id == "de.word.haus" }!
        var rng = SplitMix64(seed: 1)

        let q = factory.question(item: item, mode: .rebuild, distractorPool: pack.items, sentence: nil, rng: &rng)
        guard case .rebuild(_, _, let tokens, let expectedOrder)? = q else {
            return XCTFail("expected a rebuild question, got \(String(describing: q))")
        }
        XCTAssertEqual(tokens.sorted(), expectedOrder.sorted())
        XCTAssertNotEqual(tokens, expectedOrder)
        XCTAssertEqual(expectedOrder, ["ich", "sehe", "das", "Haus"])

        var bare = item
        bare.examples = []
        let fallback = factory.question(item: bare, mode: .rebuild, distractorPool: pack.items, sentence: nil, rng: &rng)
        XCTAssertEqual(fallback?.mode, .recall)
    }

    func testRebuildRemovesOrderingCluesButPreservesWordCapitalization() {
        var item = Fixtures.invariant("now", "jetzt")
        item.examples = [
            Example(source: "We are going now.", target: "Wir gehen jetzt."),
            Example(source: "Today, we see the house!", target: "Heute, sehen wir das Haus!"),
        ]

        XCTAssertEqual(
            QuestionFactory.rebuildTokens(item.examples[0]),
            ["wir", "gehen", "jetzt"],
            "sentence case and terminal punctuation must not identify the endpoints"
        )
        XCTAssertEqual(
            QuestionFactory.rebuildTokens(item.examples[1]),
            ["heute", "sehen", "wir", "das", "Haus"],
            "outer punctuation is removed while an inherently capitalized noun stays capitalized"
        )
    }

    /// Rich examples (D-R4): cloze and rebuild rotate across an item's
    /// examples instead of recycling the first forever.
    func testClozeAndRebuildRotateAcrossExamples() {
        var item = pack.items.first { $0.id == "de.word.haus" }!
        item.examples = [
            Example(source: "I see the house.", target: "Ich sehe das Haus."),
            Example(source: "The house is very old.", target: "Das Haus ist sehr alt."),
            Example(source: "We are buying a house.", target: "Wir kaufen ein Haus."),
        ]
        var clozeSentences = Set<String>(), rebuildSources = Set<String>()
        for seed in 0..<60 {
            var rng = SplitMix64(seed: UInt64(seed))
            if case .cloze(_, let blanked, _, _)? = factory.question(item: item, mode: .cloze, distractorPool: pack.items, sentence: nil, rng: &rng) {
                clozeSentences.insert(blanked)
            }
            var rng2 = SplitMix64(seed: UInt64(seed) &+ 999)
            if case .rebuild(_, let source, _, _)? = factory.question(item: item, mode: .rebuild, distractorPool: pack.items, sentence: nil, rng: &rng2) {
                rebuildSources.insert(source)
            }
        }
        XCTAssertGreaterThan(clozeSentences.count, 1, "cloze stuck on one example")
        XCTAssertGreaterThan(rebuildSources.count, 1, "rebuild stuck on one example")
    }

    /// Self-grade carries the word and its example for the reveal.
    func testSelfGradeCarriesPromptAndExample() {
        let item = pack.items.first { $0.id == "de.word.haus" }!
        var rng = SplitMix64(seed: 1)
        let q = factory.question(item: item, mode: .selfGrade, distractorPool: pack.items, sentence: nil, rng: &rng)
        guard case .selfGrade(_, let prompt, let exampleTarget, _)? = q else {
            return XCTFail("expected a selfGrade question, got \(String(describing: q))")
        }
        XCTAssertEqual(prompt, item.displayTarget)
        XCTAssertEqual(exampleTarget, item.examples.first?.target)
    }

    /// The ladder offers rebuild from the first box when an example exists,
    /// so day-1 sessions aren't recognition-only (Core Five).
    func testOfferableModesIncludeRebuildAndExampleClozeWhenAvailable() {
        var p = ItemProgress(itemId: "de.word.haus", now: now)
        p.stage = .learning
        p.srsBox = 0
        XCTAssertEqual(
            factory.offerableModes(progress: p, hasSentence: false, hasExample: true),
            [.recognition, .rebuild]
        )
        p.srsBox = 2
        XCTAssertEqual(
            factory.offerableModes(progress: p, hasSentence: false, hasExample: true),
            [.recognition, .recall, .cloze, .rebuild]
        )
        p.srsBox = 5
        XCTAssertEqual(
            factory.offerableModes(progress: p, hasSentence: false, hasExample: true),
            [.recall, .cloze, .rebuild]
        )
    }

    func testOfferableModesByBox() {
        var p = ItemProgress(itemId: "de.word.haus", now: now)

        p.stage = .learning
        p.srsBox = 1
        XCTAssertEqual(factory.offerableModes(progress: p, hasSentence: true), [.recognition])

        p.srsBox = 2
        XCTAssertEqual(factory.offerableModes(progress: p, hasSentence: false), [.recognition, .recall])

        p.srsBox = 5
        XCTAssertEqual(factory.offerableModes(progress: p, hasSentence: true), [.recall, .cloze])
        XCTAssertEqual(factory.offerableModes(progress: p, hasSentence: false), [.recall])
    }

    /// D-R4: once sentence material exists, cloze/rebuild dominate the draw —
    /// most reps happen inside a phrase.
    func testWeightedModesBiasSentenceContexts() {
        var p = ItemProgress(itemId: "de.word.haus", now: now)
        p.stage = .learning
        p.srsBox = 3
        let weighted = factory.weightedModes(progress: p, hasSentence: true, hasExample: true)
        let sentenceSlots = weighted.filter { $0 == .cloze || $0 == .rebuild }.count
        let bareSlots = weighted.filter { $0 == .recognition || $0 == .recall }.count
        XCTAssertEqual(sentenceSlots, 4, "cloze + rebuild, each ×sentenceModeBias(2)")
        XCTAssertEqual(bareSlots, 2)
        XCTAssertGreaterThan(sentenceSlots, bareSlots)

        // No material → no phantom sentence slots.
        let bare = factory.weightedModes(progress: p, hasSentence: false, hasExample: false)
        XCTAssertEqual(bare, [.recognition, .recall])
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
