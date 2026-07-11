import XCTest
@testable import LearnerCore

/// The tier-check gate: tiers unlock through an explicit in-session check,
/// never by a silent background flip (docs/plan/04 §ActivationEngine).
final class TierCheckTests: XCTestCase {
    var engine: LearnerEngine!
    let t0 = Fixtures.t0

    override func setUpWithError() throws {
        engine = try Fixtures.makeEngine()
    }

    /// Push the given fraction of band-1 items to known, backdating the
    /// tier-1 unlock timestamp so the 7-day interval is satisfied.
    func makeTierOneReady(knownFraction: Double = 0.8, now: Date) throws {
        let items = try engine.store.items(language: "de").filter { $0.frequencyBand == 1 }
        let knownCount = Int((Double(items.count) * knownFraction).rounded())
        for item in items.prefix(knownCount) {
            var p = try Fixtures.progress(engine, item.id)
            p.stage = .known
            p.srsBox = 4
            p.dueAt = now.addingTimeInterval(72 * 3600)
            p.recognitionCorrect = 2
            p.recallCorrect = 2
            try engine.store.saveProgress(p)
        }
        try engine.store.setSetting(
            SettingsKey.tierUnlockedAt(1),
            ISO8601DateFormatter().string(from: now.addingTimeInterval(-8 * 24 * 3600))
        )
    }

    func testExposureIngestionNeverUnlocksTiers() throws {
        let now = t0.addingTimeInterval(10 * 24 * 3600)
        try makeTierOneReady(now: now)
        // Heavy ingestion with the unlock condition fully met…
        let events = (0..<10).map { i in
            ExposureEvent(id: "tc\(i)", itemId: "de.word.und", type: .seen,
                          occurredAt: now.addingTimeInterval(Double(i) * 3600))
        }
        try engine.postEvents(events, now: now.addingTimeInterval(11 * 3600))
        // …must not flip the tier: unlocking is quiz-gated.
        XCTAssertEqual(try engine.overview(now: now).unlockedTier, 1)
        XCTAssertTrue(try engine.overview(now: now).tierCheckReady)
    }

    func testSessionIncludesTierCheckBurstWhenReady() throws {
        let now = t0.addingTimeInterval(10 * 24 * 3600)
        try makeTierOneReady(now: now)
        let session = try engine.planSession(now: now, seed: 7)
        let check = session.queue.filter { $0.beat == .tierCheck }
        XCTAssertEqual(check.count, EngineConfig.default.tierCheckQuestionCount)
        // The check draws from current-tier practiced items and rides on top
        // of the session target.
        let items = try engine.store.items(language: "de")
        for planned in check {
            let item = items.first { $0.id == planned.question.itemId }!
            XCTAssertEqual(item.frequencyBand, 1)
        }
        // No tier check when the condition doesn't hold (fresh engine).
        let fresh = try Fixtures.makeEngine()
        let freshSession = try fresh.planSession(now: t0, seed: 7)
        XCTAssertTrue(freshSession.queue.allSatisfy { $0.beat != .tierCheck })
    }

    func testUnlockNextTierValidatesCondition() throws {
        // Condition not met: unlock refuses.
        XCTAssertNil(try engine.unlockNextTier(now: t0))
        XCTAssertEqual(try engine.overview(now: t0).unlockedTier, 1)

        // Condition met: unlock fires once and admits tier-2 items.
        let now = t0.addingTimeInterval(10 * 24 * 3600)
        try makeTierOneReady(now: now)
        XCTAssertEqual(try engine.unlockNextTier(now: now), 2)
        let overview = try engine.overview(now: now)
        XCTAssertEqual(overview.unlockedTier, 2)
        XCTAssertGreaterThan(overview.countsByStage[.ambient] ?? 0, 0, "tier-2 items enter rotation")

        // Tier 3 immediately after: blocked by the min interval.
        XCTAssertNil(try engine.unlockNextTier(now: now.addingTimeInterval(60)))
    }

    func testTierCheckPassRule() {
        XCTAssertFalse(SessionPlanner.tierCheckPassed(firstResults: []))
        XCTAssertFalse(SessionPlanner.tierCheckPassed(firstResults: [true, false, true]))
        XCTAssertTrue(SessionPlanner.tierCheckPassed(firstResults: [true, true, true]))
    }

    func testWarmupOpensSessionWithEasiestDueItems() throws {
        let items = try engine.store.items(language: "de").filter { $0.frequencyBand == 1 }
        for (i, item) in items.prefix(4).enumerated() {
            var p = try Fixtures.progress(engine, item.id)
            p.stage = .learning
            p.srsBox = i + 1   // boxes 1...4
            p.dueAt = t0.addingTimeInterval(-60)
            try engine.store.saveProgress(p)
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
