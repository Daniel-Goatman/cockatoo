import XCTest
@testable import LearnerCore

/// Milestones are celebrations, never gates (D-R3): band completion is
/// detected and celebrated once, and intake never waits for it.
final class MilestoneAndIntakeTests: XCTestCase {
    var engine: LearnerEngine!
    let t0 = Fixtures.t0

    override func setUpWithError() throws {
        engine = try Fixtures.makeEngine()
    }

    /// Push the given fraction of band-1 items to known.
    func makeBandOneKnown(fraction: Double = 0.8, now: Date) throws {
        let items = try engine.store.items(language: "de").filter { $0.frequencyBand == 1 }
        let knownCount = Int((Double(items.count) * fraction).rounded())
        for item in items.prefix(knownCount) {
            try Fixtures.seed(engine, item.id, at: now) { p in
                p.stage = .known
                p.srsBox = 4
                p.dueAt = now.addingTimeInterval(72 * 3600)
                p.recognitionCorrect = 2
                p.recallCorrect = 2
                p.distinctCorrectDays = 4
                p.lastCorrectAt = now.addingTimeInterval(-3600)
            }
        }
    }

    func testMilestoneFiresOnceAndIsNeverAGate() throws {
        XCTAssertNil(try engine.pendingMilestone(now: t0))

        try makeBandOneKnown(now: t0)
        XCTAssertEqual(try engine.pendingMilestone(now: t0), 1)
        XCTAssertEqual(try engine.overview(now: t0).pendingMilestoneBand, 1)

        // Celebrating marks it done; it never fires again.
        try engine.markMilestoneCelebrated(band: 1, now: t0)
        XCTAssertNil(try engine.pendingMilestone(now: t0))
        XCTAssertNil(try engine.overview(now: t0).pendingMilestoneBand)

        // Never a gate: intake candidates span all bands regardless of
        // milestone state, in band order.
        let progress = try engine.store.allProgress()
        let items = try engine.store.items(language: "de")
        let candidates = engine.planner.intake.candidates(items: items, progress: progress)
        XCTAssertEqual(candidates.count, items.count - progress.count)
        XCTAssertTrue(candidates.contains { $0.frequencyBand == 3 }, "higher bands are reachable from day 1")
    }

    func testOverviewNextMilestoneMovesToLowestIncompleteBand() throws {
        try makeBandOneKnown(now: t0)
        let overview = try engine.overview(now: t0)
        XCTAssertEqual(overview.nextMilestone?.band, 2, "band 1 done → band 2 is the next milestone")
    }

    func testAnchorItemsJumpTheIntakeQueue() throws {
        var pack = Fixtures.simPack()
        // Flag a band-3 word as an anchor: it should sort ahead of band-2.
        let anchorIndex = pack.items.firstIndex { $0.frequencyBand == 3 }!
        pack.items[anchorIndex].anchor = true
        let anchorId = pack.items[anchorIndex].id

        let engine = try Fixtures.makeEngine(pack: pack)
        let items = try engine.store.items(language: "de")
        let candidates = engine.planner.intake.candidates(items: items, progress: [:])

        let anchorPosition = candidates.firstIndex { $0.id == anchorId }!
        let firstBand2 = candidates.firstIndex { $0.frequencyBand == 2 && !$0.isAnchor }!
        XCTAssertLessThan(anchorPosition, firstBand2, "anchor (band 3) boosts ahead of plain band-2 items")
    }

    func testChunkIntroducibleOnceDependenciesAreInLibrary() throws {
        var pack = Fixtures.simPack()
        var chunk = Fixtures.invariant("there is", "es gibt", band: 1)
        chunk.id = "de.chunk.es-gibt"
        chunk.kind = .chunk
        chunk.dependencies = ["de.word.und"]
        pack.items.append(chunk)
        let engine = try Fixtures.makeEngine(pack: pack)
        let items = try engine.store.items(language: "de")

        // Dependency not in the library: chunk is not a candidate.
        var candidates = engine.planner.intake.candidates(items: items, progress: [:])
        XCTAssertFalse(candidates.contains { $0.id == chunk.id })

        // Dependency introduced (merely learning): chunk becomes eligible.
        try Fixtures.introduce(engine, "de.word.und", at: t0)
        let progress = try engine.store.allProgress()
        candidates = engine.planner.intake.candidates(items: items, progress: progress)
        XCTAssertTrue(candidates.contains { $0.id == chunk.id },
                      "deps gate at ≥ learning, not ≥ known (D-R4)")
    }

    func testReviewOnlyItemsAreIntroducibleButNeverInSnapshot() throws {
        var pack = Fixtures.simPack()
        var verb = Fixtures.invariant("to run", "laufen", band: 1)
        verb.id = "de.word.laufen"
        verb.targetMeta = TargetMeta(pos: "verb")
        verb.replacementPolicy = .reviewOnly
        pack.items.append(verb)
        let engine = try Fixtures.makeEngine(pack: pack)
        let items = try engine.store.items(language: "de")

        let candidates = engine.planner.intake.candidates(items: items, progress: [:])
        XCTAssertTrue(candidates.contains { $0.id == verb.id },
                      "reviewOnly items enter the library via practice (the old activation gap)")

        try Fixtures.introduce(engine, verb.id, at: t0)
        guard case .snapshot(let snap) = try engine.snapshot() else { return XCTFail() }
        XCTAssertFalse(snap.items.contains { $0.id == verb.id },
                       "…but are never swapped in-page")
    }

    func testWarmupOpensSessionWithEasiestDueItems() throws {
        let items = try engine.store.items(language: "de").filter { $0.frequencyBand == 1 }
        for (i, item) in items.prefix(4).enumerated() {
            try Fixtures.seed(engine, item.id) { p in
                p.srsBox = i + 1   // boxes 1...4
                p.dueAt = self.t0.addingTimeInterval(-60)
            }
        }
        let session = try engine.planSession(now: t0, seed: 11)
        let warmup = session.queue.prefix(EngineConfig.default.sessionWarmupLimit)
        XCTAssertTrue(warmup.allSatisfy { $0.beat == .warmup })
        // Easiest first: the two lowest boxes open the session. Modes follow
        // the normal ladder — warm-up is ordering, not a distorted mode.
        let warmupIds = Set(warmup.map(\.question.itemId))
        XCTAssertEqual(warmupIds, Set(items.prefix(2).map(\.id)))
    }
}
