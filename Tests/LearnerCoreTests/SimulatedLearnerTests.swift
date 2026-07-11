import XCTest
@testable import LearnerCore

/// Phase 1 exit criterion (docs/plan/08-roadmap.md): a 30-day simulated
/// learner — browsing generates events, sessions run at 85% accuracy —
/// must unlock tier 2, produce no stuck items, and keep the ambient set
/// within bounds, with invariants holding throughout.
final class SimulatedLearnerTests: XCTestCase {
    func testThirtyDaySimulationReachesTierTwo() throws {
        let engine = try Fixtures.makeEngine()
        let grader = Grader(grading: .german)
        var rng = SplitMix64(seed: 20260701)
        var clock = Fixtures.t0
        var eventCounter = 0
        var questionsAnswered = 0

        for day in 0..<30 {
            // Four browsing bouts + sessions per day, 4 hours apart.
            for bout in 0..<4 {
                clock = clock.addingTimeInterval(4 * 3600)

                // --- Browsing: ambient/ready items get seen; some engaged.
                let progress = try engine.store.allProgress()
                var events: [ExposureEvent] = []
                for p in progress.values where p.stage == .ambient || p.stage == .ready {
                    eventCounter += 1
                    events.append(ExposureEvent(
                        id: "sim-\(eventCounter)", itemId: p.itemId, type: .seen,
                        occurredAt: clock, host: "example.org"
                    ))
                    if rng.next() % 100 < 40 {
                        eventCounter += 1
                        events.append(ExposureEvent(
                            id: "sim-\(eventCounter)", itemId: p.itemId, type: .engaged,
                            occurredAt: clock.addingTimeInterval(30)
                        ))
                    }
                    if rng.next() % 100 < 20, let item = try engine.store.item(id: p.itemId) {
                        eventCounter += 1
                        events.append(ExposureEvent(
                            id: "sim-\(eventCounter)", itemId: p.itemId, type: .sentenceCaptured,
                            occurredAt: clock.addingTimeInterval(31),
                            sentence: "Yesterday we talked about the \(item.sourceForms.last!.form) for a while."
                        ))
                    }
                }
                try engine.postEvents(events, now: clock)

                // --- Session: answer the planned queue at 85% accuracy,
                // exercising the real repair lane.
                if bout % 2 == 0 {
                    let session = try engine.planSession(now: clock, seed: rng.next())
                    var queue = session.queue
                    var index = 0
                    var tierCheckFirsts: [Bool] = []
                    while index < queue.count {
                        let planned = queue[index]
                        let correct = rng.next() % 100 < 85
                        let result = PracticeResult(
                            itemId: planned.question.itemId,
                            mode: planned.question.mode,
                            correct: correct,
                            answeredAt: clock
                        )
                        let updated = try engine.grade(result: result, now: clock)
                        XCTAssertEqual(updated.validateInvariants(), [], "invariant violation day \(day) item \(updated.itemId)")
                        if planned.beat == .tierCheck, !planned.isRepair {
                            tierCheckFirsts.append(correct)
                        }
                        if !correct {
                            engine.planner.requeueMissed(planned.question, into: &queue, afterIndex: index)
                        }
                        questionsAnswered += 1
                        index += 1
                        clock = clock.addingTimeInterval(20)
                    }
                    // Tier unlocking is quiz-gated: a clean tier-check burst
                    // fires the unlock, exactly as the practice UI does.
                    if SessionPlanner.tierCheckPassed(firstResults: tierCheckFirsts) {
                        try engine.unlockNextTier(now: clock)
                    }
                }
            }
        }

        // --- Exit criteria ---
        let overview = try engine.overview(now: clock)
        XCTAssertGreaterThanOrEqual(overview.unlockedTier, 2, "30 days at 85% accuracy must unlock tier 2")
        XCTAssertGreaterThan(questionsAnswered, 100, "sessions must actually run")

        let progress = try engine.store.allProgress()
        let items = try engine.store.items(language: "de")
        let factory = QuestionFactory()

        // No stuck items: anything due in the past must have an offerable mode.
        for p in progress.values where p.stage >= .learning {
            if let dueAt = p.dueAt, dueAt < clock {
                let sentences = try engine.store.sentences(itemId: p.itemId)
                let modes = factory.offerableModes(progress: p, hasSentence: !sentences.isEmpty)
                XCTAssertFalse(modes.isEmpty, "stuck item \(p.itemId): due with no offerable mode")
            }
            XCTAssertEqual(p.validateInvariants(), [])
        }

        // Ambient set within bounds.
        let ambientCount = progress.values.filter { $0.stage == .ambient || $0.stage == .ready }.count
        XCTAssertLessThanOrEqual(ambientCount, EngineConfig.default.ambientSetMax)

        // Learning actually happened: a healthy majority of band-1 items are known+.
        let band1 = items.filter { $0.frequencyBand == 1 }
        let band1Known = band1.filter { (progress[$0.id]?.stage ?? .locked) >= .known }.count
        XCTAssertGreaterThanOrEqual(
            Double(band1Known) / Double(band1.count), 0.7,
            "only \(band1Known)/\(band1.count) band-1 items reached known"
        )

        // Some items should have real mastery motion (cloze happened).
        let anyCloze = progress.values.contains { $0.clozeCorrect > 0 }
        XCTAssertTrue(anyCloze, "cloze questions never ran — sentence capture → cloze pipeline is dead")

        // Snapshot still healthy and within the size bound after 30 days.
        let snapshot = try engine.snapshotBuilder.build(store: engine.store)
        XCTAssertFalse(snapshot.items.isEmpty)
        XCTAssertLessThan(try engine.snapshotBuilder.encodedSize(snapshot), EngineConfig.default.snapshotMaxEncodedBytes)
    }
}
