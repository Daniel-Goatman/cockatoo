import Foundation

/// Decides which items enter the ambient set (transition a) and when tiers
/// unlock. Pure logic over in-memory inputs; the engine facade persists
/// its decisions. docs/plan/04-learning-engine.md §ActivationEngine.
public struct ActivationEngine: Sendable {
    public var config: EngineConfig

    public init(config: EngineConfig = .default) {
        self.config = config
    }

    public struct TierState: Equatable, Sendable {
        public var unlockedTier: Int
        public var unlockedAt: Date?

        public init(unlockedTier: Int, unlockedAt: Date?) {
            self.unlockedTier = unlockedTier
            self.unlockedAt = unlockedAt
        }
    }

    /// Tier N+1 unlocks when ≥ tierUnlockFraction of tier N items are ≥ known
    /// AND tierUnlockMinInterval has elapsed since tier N unlocked.
    public func shouldUnlockNextTier(
        items: [VocabItem],
        progress: [String: ItemProgress],
        tier: TierState,
        now: Date
    ) -> Bool {
        let currentTierItems = items.filter { $0.frequencyBand == tier.unlockedTier }
        guard !currentTierItems.isEmpty else { return false }
        guard items.contains(where: { $0.frequencyBand == tier.unlockedTier + 1 }) else { return false }

        if let unlockedAt = tier.unlockedAt,
           now.timeIntervalSince(unlockedAt) < config.tierUnlockMinInterval {
            return false
        }

        let knownCount = currentTierItems.filter { (progress[$0.id]?.stage ?? .locked) >= .known }.count
        return Double(knownCount) / Double(currentTierItems.count) >= config.tierUnlockFraction
    }

    /// Item IDs to promote locked → ambient right now. Admission order within
    /// the unlocked tiers: ascending band, then id (stable). Dependency-gated.
    public func admissions(
        items: [VocabItem],
        progress: [String: ItemProgress],
        unlockedTier: Int
    ) -> [String] {
        let ambientCount = items.filter { item in
            let stage = progress[item.id]?.stage ?? .locked
            return stage == .ambient || stage == .ready
        }.count

        var room = config.ambientSetMax - ambientCount
        guard room > 0 else { return [] }

        var admitted: [String] = []
        let candidates = items
            .filter { item in
                (progress[item.id]?.stage ?? .locked) == .locked
                    && item.frequencyBand <= unlockedTier
                    && item.replacementPolicy == .ambientSafe
                    && dependenciesMet(item, progress: progress)
            }
            .sorted { ($0.frequencyBand, $0.id) < ($1.frequencyBand, $1.id) }

        for item in candidates {
            guard room > 0 else { break }
            admitted.append(item.id)
            room -= 1
        }
        return admitted
    }

    func dependenciesMet(_ item: VocabItem, progress: [String: ItemProgress]) -> Bool {
        item.dependencies.allSatisfy { (progress[$0]?.stage ?? .locked) >= .known }
    }
}
