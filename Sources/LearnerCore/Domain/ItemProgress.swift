import Foundation

/// The unified learning stage. Transitions are monotonic except the lapse
/// edge (known → learning). See docs/plan/04-learning-engine.md.
public enum Stage: String, Codable, CaseIterable, Comparable, Sendable {
    case locked
    case ambient
    case ready
    case learning
    case known
    case mastered

    public var order: Int {
        switch self {
        case .locked: return 0
        case .ambient: return 1
        case .ready: return 2
        case .learning: return 3
        case .known: return 4
        case .mastered: return 5
        }
    }

    public static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.order < rhs.order }
}

/// THE one progress record per item (principle P2).
public struct ItemProgress: Codable, Equatable, Identifiable, Sendable {
    public var itemId: String
    public var stage: Stage
    /// Leitner box 0...6. Only the Grader may change this.
    public var srsBox: Int
    /// Non-nil iff stage ∈ {learning, known, mastered}.
    public var dueAt: Date?
    public var seenCount: Int
    public var engagedCount: Int
    public var correctStreak: Int
    public var lapses: Int
    /// Correct answers per mode, used for stage promotion requirements.
    public var recognitionCorrect: Int
    public var recallCorrect: Int
    public var clozeCorrect: Int
    public var activatedAt: Date?
    public var lastResultAt: Date?
    public var updatedAt: Date

    public var id: String { itemId }

    public init(itemId: String, now: Date) {
        self.itemId = itemId
        self.stage = .locked
        self.srsBox = 0
        self.dueAt = nil
        self.seenCount = 0
        self.engagedCount = 0
        self.correctStreak = 0
        self.lapses = 0
        self.recognitionCorrect = 0
        self.recallCorrect = 0
        self.clozeCorrect = 0
        self.activatedAt = nil
        self.lastResultAt = nil
        self.updatedAt = now
    }

    /// Invariants from docs/plan/03-data-model-and-storage.md. Checked in tests
    /// after every mutation sequence.
    public func validateInvariants() -> [String] {
        var violations: [String] = []
        if !(0...6).contains(srsBox) { violations.append("srsBox \(srsBox) out of range") }
        let scheduled: Set<Stage> = [.learning, .known, .mastered]
        if scheduled.contains(stage), dueAt == nil {
            violations.append("stage \(stage.rawValue) requires dueAt")
        }
        if !scheduled.contains(stage), dueAt != nil {
            violations.append("stage \(stage.rawValue) must not have dueAt")
        }
        if seenCount < 0 || engagedCount < 0 || lapses < 0 || correctStreak < 0 {
            violations.append("negative counter")
        }
        return violations
    }
}
