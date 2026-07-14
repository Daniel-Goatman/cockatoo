import Foundation

/// Scheduling behind a protocol so FSRS can drop in later (decision D3)
/// without touching callers.
public protocol ReviewScheduler: Sendable {
    /// New (box, dueAt) after a graded answer. Rules:
    /// correct while due → box+1, at most once per calendar day (D-R2 —
    /// the first-ever answer, box 0, is the introduction and exempt);
    /// correct while not due or already advanced today → unchanged;
    /// wrong → lapse drop.
    func next(after correct: Bool, progress: ItemProgress, now: Date) -> (box: Int, dueAt: Date)
    /// Near-miss: hold the current box (no advance, no lapse) and reschedule
    /// its interval from now.
    func hold(progress: ItemProgress, now: Date) -> (box: Int, dueAt: Date)
    func isDue(_ progress: ItemProgress, now: Date) -> Bool
}

/// The proven Leitner 6-box cooldown ladder: 1h → 6h → 24h → 72h → 168h → 720h,
/// with ±10% deterministic jitter to avoid review pile-ups. The distinct-day
/// advance gate stacks on top: intervals are the *minimum* spacing, the
/// calendar day is the unit of evidence.
public struct LeitnerScheduler: ReviewScheduler {
    public var config: EngineConfig

    /// Hours for boxes 1...6. Box 0 (never answered) is due immediately.
    static let intervalHours: [Double] = [1, 6, 24, 72, 168, 720]

    public init(config: EngineConfig = .default) {
        self.config = config
    }

    public func isDue(_ progress: ItemProgress, now: Date) -> Bool {
        guard let dueAt = progress.dueAt else { return progress.srsBox == 0 }
        return dueAt <= now
    }

    public func next(after correct: Bool, progress: ItemProgress, now: Date) -> (box: Int, dueAt: Date) {
        if correct {
            let due = isDue(progress, now: now)
            // Box 0 → 1 is the introduction, not retention evidence, so the
            // day gate starts counting from box 1 upward.
            let advancedToday = LearningCalendar.sameDay(progress.lastAdvancedAt, now)
            if due, progress.srsBox == 0 || !advancedToday {
                let box = min(6, progress.srsBox + 1)
                return (box, dueDate(box: box, itemId: progress.itemId, from: now))
            }
            if due {
                // Day-gated: answered while due, box held; its interval
                // restarts so it comes due again (and advances tomorrow).
                return (progress.srsBox, dueDate(box: progress.srsBox, itemId: progress.itemId, from: now))
            }
            // Extra rep on a non-due item: leave the schedule untouched —
            // reinforcement must never DELAY the next real review.
            return (progress.srsBox, progress.dueAt ?? dueDate(box: progress.srsBox, itemId: progress.itemId, from: now))
        }
        let box = max(config.lapseBoxFloor, progress.srsBox - config.lapseBoxDrop)
        return (box, dueDate(box: box, itemId: progress.itemId, from: now))
    }

    public func hold(progress: ItemProgress, now: Date) -> (box: Int, dueAt: Date) {
        // Same non-due rule as next(): a near-miss on a not-yet-due rep
        // must not push the real review out.
        if !isDue(progress, now: now), let dueAt = progress.dueAt {
            return (progress.srsBox, dueAt)
        }
        return (progress.srsBox, dueDate(box: progress.srsBox, itemId: progress.itemId, from: now))
    }

    func dueDate(box: Int, itemId: String, from now: Date) -> Date {
        let hours = Self.intervalHours[max(0, min(box, 6) - 1)]
        // Deterministic jitter in [-10%, +10%] derived from the item id, so
        // tests are stable and items don't pile up on shared boundaries.
        let jitter = (Double(stableHash(itemId) % 2001) / 1000.0 - 1.0) * 0.10
        return now.addingTimeInterval(hours * 3600 * (1 + jitter))
    }
}

/// FNV-1a; Swift's Hashable is per-process seeded, unusable for stable jitter.
func stableHash(_ s: String) -> UInt64 {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in s.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001b3
    }
    return hash
}
