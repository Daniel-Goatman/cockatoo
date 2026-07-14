import XCTest
@testable import LearnerCore

/// The whole-system soak: a 30-day simulated learner — two sessions a day at
/// 85% accuracy, browsing generating display-only sightings — must pull the
/// whole pack into the library through the drip, push band 1 past its
/// milestone, leave no stuck items, and keep invariants + the snapshot
/// bound holding throughout.
final class SimulatedLearnerTests: XCTestCase {
    func testThirtyDaySimulationLearnsHonestly() throws {
        let engine = try Fixtures.makeEngine()
        var rng = SplitMix64(seed: 20260701)
        var clock = Fixtures.t0
        var eventCounter = 0
        var questionsAnswered = 0

        for day in 0..<30 {
            for bout in 0..<4 {
                clock = clock.addingTimeInterval(4 * 3600)

                // --- Browsing: library items get sighted (display-only).
                let progress = try engine.store.allProgress()
                var events: [ExposureEvent] = []
                for p in progress.values where p.stage < .mastered {
                    guard rng.next() % 100 < 40 else { continue }
                    eventCounter += 1
                    events.append(ExposureEvent(
                        id: "sim-\(eventCounter)", itemId: p.itemId, type: .seen,
                        occurredAt: clock, host: "example.org"
                    ))
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
                        if !correct {
                            engine.planner.requeueMissed(planned.question, into: &queue, afterIndex: index)
                        }
                        questionsAnswered += 1
                        index += 1
                        clock = clock.addingTimeInterval(20)
                    }
                }
            }
        }

        // --- Exit criteria ---
        let overview = try engine.overview(now: clock)
        XCTAssertGreaterThan(questionsAnswered, 300, "sessions must actually run")

        let progress = try engine.store.allProgress()
        let items = try engine.store.items(language: "de")

        // The drip pulled the whole (24-item) pack in within the month.
        XCTAssertEqual(progress.count, items.count, "the library should hold the whole pack by day 30")

        // No stuck items: anything due in the past must have an offerable mode.
        let factory = QuestionFactory()
        for p in progress.values {
            if let dueAt = p.dueAt, dueAt < clock {
                let sentences = try engine.store.sentences(itemId: p.itemId)
                let modes = factory.offerableModes(progress: p, hasSentence: !sentences.isEmpty)
                XCTAssertFalse(modes.isEmpty, "stuck item \(p.itemId): due with no offerable mode")
            }
            XCTAssertEqual(p.validateInvariants(), [])
        }

        // Learning actually happened: at least half of band 1 is known and
        // some band crossed its milestone. (Exact per-band counts vary with
        // the machine's timezone via local-day boundaries, so the bar is
        // deliberately conservative.)
        let band1 = items.filter { $0.frequencyBand == 1 }
        let band1Known = band1.filter { (progress[$0.id]?.stage).map { $0 >= .known } ?? false }.count
        XCTAssertGreaterThanOrEqual(
            Double(band1Known) / Double(band1.count), 0.5,
            "only \(band1Known)/\(band1.count) band-1 items reached known"
        )
        let knownTotal = progress.values.filter { $0.stage >= .known }.count
        XCTAssertGreaterThanOrEqual(knownTotal, 12, "half the pack should be known after a month")
        XCTAssertNotNil(try engine.pendingMilestone(now: clock), "some band milestone should be waiting to celebrate")

        // Honesty: nothing is known without multi-day evidence.
        for p in progress.values where p.stage >= .known {
            XCTAssertGreaterThanOrEqual(p.distinctCorrectDays, EngineConfig.default.knownDistinctDays,
                                        "\(p.itemId) is known on \(p.distinctCorrectDays) distinct days")
        }

        // Some items should have real mastery motion (cloze happened).
        let anyCloze = progress.values.contains { $0.clozeCorrect > 0 }
        XCTAssertTrue(anyCloze, "cloze questions never ran — sentence capture → cloze pipeline is dead")

        // Milestone state is visible on the overview.
        XCTAssertNotNil(overview.pendingMilestoneBand)

        // Snapshot still healthy and within the size bound after 30 days.
        let snapshot = try engine.snapshotBuilder.build(store: engine.store)
        XCTAssertFalse(snapshot.items.isEmpty)
        XCTAssertLessThan(try engine.snapshotBuilder.encodedSize(snapshot), EngineConfig.default.snapshotMaxEncodedBytes)
    }
}
