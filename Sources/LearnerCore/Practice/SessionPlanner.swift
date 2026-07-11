import Foundation

/// Plans a short review session (~10 questions, never padded, never
/// advertised longer than it is — principle P4) and manages the in-session
/// repair queue: a missed item re-enters once, repairOffset positions later.
public struct SessionPlanner: Sendable {
    public var config: EngineConfig
    public var factory: QuestionFactory
    public var scheduler: any ReviewScheduler

    public init(config: EngineConfig = .default, scheduler: (any ReviewScheduler)? = nil) {
        self.config = config
        self.factory = QuestionFactory(config: config)
        self.scheduler = scheduler ?? LeitnerScheduler(config: config)
    }

    public struct PlannedQuestion: Equatable, Sendable {
        public var question: Question
        /// True if this entry is a repair re-ask of a missed question.
        public var isRepair: Bool
    }

    /// Selection mix (docs/plan/04-learning-engine.md):
    /// 1. due learning/known items (≤ sessionDueLimit)
    /// 2. ready items awaiting first question (≤ sessionReadyLimit)
    /// 3. ≤ sessionMasteredLimit sampled mastered item
    public func selectItems(
        items: [VocabItem],
        progress: [String: ItemProgress],
        now: Date
    ) -> [VocabItem] {
        let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        func sortedByDue(_ ids: [String]) -> [String] {
            ids.sorted { a, b in
                let da = progress[a]?.dueAt ?? .distantPast
                let db = progress[b]?.dueAt ?? .distantPast
                return da == db ? a < b : da < db
            }
        }

        let due = sortedByDue(progress.values
            .filter { ($0.stage == .learning || $0.stage == .known) && scheduler.isDue($0, now: now) }
            .map(\.itemId))
            .prefix(config.sessionDueLimit)

        let ready = progress.values
            .filter { $0.stage == .ready }
            .map(\.itemId)
            .sorted()
            .prefix(config.sessionReadyLimit)

        let mastered = sortedByDue(progress.values
            .filter { $0.stage == .mastered && scheduler.isDue($0, now: now) }
            .map(\.itemId))
            .prefix(config.sessionMasteredLimit)

        return (Array(due) + Array(ready) + Array(mastered))
            .prefix(config.sessionQuestionTarget)
            .compactMap { byId[$0] }
    }

    /// Materialize questions for the selected items.
    public func plan(
        items selected: [VocabItem],
        allItems: [VocabItem],
        progress: [String: ItemProgress],
        sentences: (String) throws -> [CapturedSentence],
        seed: UInt64
    ) rethrows -> [PlannedQuestion] {
        var rng = SplitMix64(seed: seed)
        var planned: [PlannedQuestion] = []
        for item in selected {
            guard let p = progress[item.id] else { continue }
            let itemSentences = try sentences(item.id)
            let modes = factory.offerableModes(progress: p, hasSentence: !itemSentences.isEmpty)
            guard let mode = modes.randomElement(using: &rng) else { continue }
            if let q = factory.question(
                item: item,
                mode: mode,
                distractorPool: allItems,
                sentence: itemSentences.first,
                rng: &rng
            ) {
                planned.append(PlannedQuestion(question: q, isRepair: false))
            }
        }
        return planned
    }

    /// Called after a wrong answer: re-insert the same question once,
    /// repairOffset positions after the current one. Implements the real
    /// repair lane (anti-goal: the prototype's decorative one).
    public func requeueMissed(
        _ missed: Question,
        into queue: inout [PlannedQuestion],
        afterIndex index: Int
    ) {
        guard !queue.contains(where: { $0.isRepair && $0.question.itemId == missed.itemId }) else { return }
        let insertAt = min(queue.count, index + 1 + config.repairOffset)
        queue.insert(PlannedQuestion(question: missed, isRepair: true), at: insertAt)
    }
}
