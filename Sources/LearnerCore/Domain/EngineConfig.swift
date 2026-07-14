import Foundation

/// All pedagogical tunables in one place. Values from
/// docs/plan/04-learning-engine.md + docs/plan/10-learning-redesign.md;
/// tests use the defaults.
public struct EngineConfig: Sendable {
    // Intake drip (D-R1/D-R3): new words enter via practice sessions.
    /// New introductions allowed per calendar day.
    public var newPerDay: Int = 5
    /// Introductions pause while this many reviews are due — reviews never
    /// drown under intake.
    public var introDuePauseThreshold: Int = 12

    // learning → known (transition d)
    public var knownMinBox: Int = 4
    /// Correct answers on at least this many distinct calendar days before
    /// a word can be `known` (D-R2 — multi-day evidence).
    public var knownDistinctDays: Int = 3
    // known → mastered (transition e)
    public var masteredClozeCorrect: Int = 2
    public var masteredMinBox: Int = 5

    // Milestones (non-gating, D-R3): a band "completes" at this fraction
    // ≥ known — a celebration, never a gate on intake.
    public var milestoneFraction: Double = 0.7

    // Lapse (edge f)
    public var lapseBoxDrop: Int = 2
    public var lapseBoxFloor: Int = 1

    // Sessions
    public var sessionQuestionTarget: Int = 10
    public var sessionDueLimit: Int = 7
    /// New introductions per session (bounded further by the daily budget).
    public var sessionIntroLimit: Int = 3
    public var sessionMasteredLimit: Int = 1
    /// Warm-up questions at the session start: easiest due items (ordering
    /// only; modes untouched).
    public var sessionWarmupLimit: Int = 2
    /// A missed question re-enters the same session this many positions later.
    public var repairOffset: Int = 3
    /// Sentence-context modes (cloze, rebuild) are offered this many times
    /// for every one slot a bare-word mode gets, once material exists
    /// (D-R4 — most reps happen inside a phrase).
    public var sentenceModeBias: Int = 2

    // Retention
    public var sentencesPerItemCap: Int = 5
    public var sentenceStoreCap: Int = 2000
    /// Captured sentences longer than this are useless as practice cards
    /// (a Wikipedia paragraph is not a cloze) — skipped at ingest and at
    /// question time.
    public var capturedSentenceMaxLength: Int = 160
    public var eventRetentionDays: Int = 30

    // Snapshot (R3)
    public var snapshotMaxEncodedBytes: Int = 100_000

    public init() {}

    public static let `default` = EngineConfig()
}
