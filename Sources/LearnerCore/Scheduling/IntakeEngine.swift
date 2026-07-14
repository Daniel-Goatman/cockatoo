import Foundation

/// Decides which words are introduced next and how many fit today's budget
/// (practice-first intake, docs/plan/10-learning-redesign.md D-R1/D-R3).
/// Pure logic over in-memory inputs; the session planner consumes it.
public struct IntakeEngine: Sendable {
    public var config: EngineConfig

    public init(config: EngineConfig = .default) {
        self.config = config
    }

    /// Un-introduced items eligible for introduction, in intake order:
    /// ascending band, then id (stable) — with anchor items boosted two
    /// bands so a fun word arrives alongside the base words its phrases
    /// are built from. Dependency-gated at ≥ learning: a chunk becomes
    /// introducible as soon as every component word is in the library.
    public func candidates(items: [VocabItem], progress: [String: ItemProgress]) -> [VocabItem] {
        items
            .filter { item in
                progress[item.id] == nil && dependenciesMet(item, progress: progress)
            }
            .sorted { (intakeRank($0), $0.id) < (intakeRank($1), $1.id) }
    }

    /// Today's remaining introduction budget: newPerDay minus what was
    /// already introduced today — and zero while review debt is high, so
    /// intake never drowns reviews.
    public func budget(progress: [String: ItemProgress], dueNow: Int, now: Date) -> Int {
        guard dueNow < config.introDuePauseThreshold else { return 0 }
        let dayStart = LearningCalendar.dayStart(of: now)
        let introducedToday = progress.values.filter {
            ($0.activatedAt ?? .distantPast) >= dayStart
        }.count
        return max(0, config.newPerDay - introducedToday)
    }

    /// Fraction of a band's items that are ≥ known, for milestone checks
    /// (non-gating, D-R3).
    public struct BandProgress: Equatable, Sendable {
        public var band: Int
        public var known: Int
        public var needed: Int
        public var total: Int

        public var reached: Bool { total > 0 && known >= needed }
    }

    public func bandProgress(items: [VocabItem], progress: [String: ItemProgress]) -> [BandProgress] {
        let byBand = Dictionary(grouping: items, by: \.frequencyBand)
        return byBand.keys.sorted().map { band in
            let bandItems = byBand[band] ?? []
            let known = bandItems.filter { (progress[$0.id]?.stage ?? nil).map { $0 >= .known } ?? false }.count
            return BandProgress(
                band: band,
                known: known,
                needed: Int((Double(bandItems.count) * config.milestoneFraction).rounded(.up)),
                total: bandItems.count
            )
        }
    }

    func intakeRank(_ item: VocabItem) -> Int {
        item.isAnchor ? max(1, item.frequencyBand - 2) : item.frequencyBand
    }

    func dependenciesMet(_ item: VocabItem, progress: [String: ItemProgress]) -> Bool {
        // In the library at all means ≥ .learning (rows start there).
        item.dependencies.allSatisfy { progress[$0] != nil }
    }
}
