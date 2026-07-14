import Foundation

/// The unified learning stage. An item with no progress row is not in the
/// library yet (practice-first intake, docs/plan/10-learning-redesign.md);
/// the row is created by the first graded answer, already at `.learning`.
/// Transitions are monotonic except the lapse edges (mastered → known,
/// known → learning).
public enum Stage: String, Codable, CaseIterable, Comparable, Sendable {
    case learning
    case known
    case mastered

    public var order: Int {
        switch self {
        case .learning: return 0
        case .known: return 1
        case .mastered: return 2
        }
    }

    public static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.order < rhs.order }
}

/// THE one progress record per item (principle P2). Existence of the row
/// means the item is in the learner's library.
public struct ItemProgress: Codable, Equatable, Identifiable, Sendable {
    public var itemId: String
    public var stage: Stage
    /// Leitner box 0...6. Only the Grader may change this.
    public var srsBox: Int
    /// Always non-nil once persisted — every library item is scheduled.
    public var dueAt: Date?
    /// Page sightings since introduction — display-only ("seen in the
    /// wild"), never scheduling input (D-R1).
    public var seenCount: Int
    public var engagedCount: Int
    public var correctStreak: Int
    public var lapses: Int
    /// Correct answers per mode, used for stage promotion requirements.
    public var recognitionCorrect: Int
    public var recallCorrect: Int
    public var clozeCorrect: Int
    /// Number of distinct calendar days with ≥1 correct answer — the
    /// multi-day evidence that gates learning → known (D-R2).
    public var distinctCorrectDays: Int
    /// When the last correct answer landed (drives distinct-day counting).
    public var lastCorrectAt: Date?
    /// When the box last advanced — at most one advance per calendar day
    /// (D-R2), so binge practice cannot climb the ladder.
    public var lastAdvancedAt: Date?
    /// When the item was introduced (entered the library).
    public var activatedAt: Date?
    public var lastResultAt: Date?
    public var updatedAt: Date

    public var id: String { itemId }

    public init(itemId: String, now: Date) {
        self.itemId = itemId
        self.stage = .learning
        self.srsBox = 0
        self.dueAt = now
        self.seenCount = 0
        self.engagedCount = 0
        self.correctStreak = 0
        self.lapses = 0
        self.recognitionCorrect = 0
        self.recallCorrect = 0
        self.clozeCorrect = 0
        self.distinctCorrectDays = 0
        self.lastCorrectAt = nil
        self.lastAdvancedAt = nil
        self.activatedAt = now
        self.lastResultAt = nil
        self.updatedAt = now
    }

    /// Invariants from docs/plan/03-data-model-and-storage.md. Checked in tests
    /// after every mutation sequence.
    public func validateInvariants() -> [String] {
        var violations: [String] = []
        if !(0...6).contains(srsBox) { violations.append("srsBox \(srsBox) out of range") }
        if dueAt == nil { violations.append("library item requires dueAt") }
        if seenCount < 0 || engagedCount < 0 || lapses < 0 || correctStreak < 0 {
            violations.append("negative counter")
        }
        if distinctCorrectDays < 0 { violations.append("negative distinctCorrectDays") }
        if distinctCorrectDays > 0, lastCorrectAt == nil {
            violations.append("distinctCorrectDays without lastCorrectAt")
        }
        return violations
    }
}

/// Calendar-day comparison used by the distinct-day gates. The learner's
/// local day is the honest unit — "tomorrow" means after you slept, not
/// 24 hours on a stopwatch.
public enum LearningCalendar {
    public static let calendar = Calendar(identifier: .gregorian)

    public static func dayStart(of date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    public static func sameDay(_ a: Date?, _ b: Date) -> Bool {
        guard let a else { return false }
        return calendar.isDate(a, inSameDayAs: b)
    }
}
