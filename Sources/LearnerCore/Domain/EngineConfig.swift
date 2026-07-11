import Foundation

/// All pedagogical tunables in one place. Values from
/// docs/plan/04-learning-engine.md; tests use the defaults.
public struct EngineConfig: Sendable {
    // Exposure crediting
    public var seenCreditDailyCap: Int = 3
    public var engagedCreditDailyCap: Int = 2
    // ambient → ready (transition b): seen alone is enough; engagement is an
    // accelerant, never a gate — a reader who never hovers still progresses.
    public var readySeenThreshold: Int = 6
    /// Fast path: this many seen credits suffice when the learner has also
    /// engaged (hover/pin) at least readyEngagedThreshold times.
    public var readySeenWithEngagementThreshold: Int = 3
    public var readyEngagedThreshold: Int = 1

    // ActivationEngine
    public var ambientSetMin: Int = 8
    public var ambientSetMax: Int = 15
    /// Tier N+1 unlocks when this fraction of tier N items are ≥ known...
    public var tierUnlockFraction: Double = 0.7
    /// ...and at least this long has passed since tier N unlocked.
    public var tierUnlockMinInterval: TimeInterval = 7 * 24 * 3600

    // learning → known (transition d)
    public var knownMinBox: Int = 4
    // known → mastered (transition e)
    public var masteredClozeCorrect: Int = 2
    public var masteredMinBox: Int = 5

    // Lapse (edge f)
    public var lapseBoxDrop: Int = 2
    public var lapseBoxFloor: Int = 1

    // Sessions
    public var sessionQuestionTarget: Int = 10
    public var sessionDueLimit: Int = 7
    public var sessionReadyLimit: Int = 3
    /// Ambient items introduced per session when due+ready leave room, so a
    /// fresh install can practice immediately (cold start, transition c').
    public var sessionIntroLimit: Int = 3
    public var sessionMasteredLimit: Int = 1
    /// A missed question re-enters the same session this many positions later.
    public var repairOffset: Int = 3

    // Retention
    public var sentencesPerItemCap: Int = 5
    public var sentenceStoreCap: Int = 2000
    public var eventRetentionDays: Int = 30

    // Snapshot (R3)
    public var snapshotMaxEncodedBytes: Int = 100_000

    public init() {}

    public static let `default` = EngineConfig()
}
