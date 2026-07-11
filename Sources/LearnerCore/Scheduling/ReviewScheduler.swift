import Foundation

/// Scheduling behind a protocol so FSRS can drop in later (decision D3)
/// without touching callers.
public protocol ReviewScheduler: Sendable {
    /// New (box, dueAt) after a graded answer. Rules:
    /// correct while due → box+1; correct while not due → unchanged
    /// (early review doesn't advance); wrong → lapse drop.
    func next(after correct: Bool, progress: ItemProgress, now: Date) -> (box: Int, dueAt: Date)
    /// Near-miss: hold the current box (no advance, no lapse) and reschedule
    /// its interval from now.
    func hold(progress: ItemProgress, now: Date) -> (box: Int, dueAt: Date)
    func isDue(_ progress: ItemProgress, now: Date) -> Bool
}

/// The proven Leitner 6-box cooldown ladder: 1h → 6h → 24h → 72h → 168h → 720h,
/// with ±10% deterministic jitter to avoid review pile-ups.
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
        let box: Int
        if correct {
            if isDue(progress, now: now) {
                box = min(6, progress.srsBox + 1)
            } else {
                box = progress.srsBox // early review never advances
            }
        } else {
            box = max(config.lapseBoxFloor, progress.srsBox - config.lapseBoxDrop)
        }
        return (box, dueDate(box: box, itemId: progress.itemId, from: now))
    }

    public func hold(progress: ItemProgress, now: Date) -> (box: Int, dueAt: Date) {
        (progress.srsBox, dueDate(box: progress.srsBox, itemId: progress.itemId, from: now))
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
