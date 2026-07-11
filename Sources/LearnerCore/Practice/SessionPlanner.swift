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
        /// True if this question introduces an ambient item the learner has
        /// never practiced (cold-start path c'). The UI shows the word first.
        public var isIntro: Bool

        public init(question: Question, isRepair: Bool, isIntro: Bool = false) {
            self.question = question
            self.isRepair = isRepair
            self.isIntro = isIntro
        }
    }

    /// Selection mix (docs/plan/04-learning-engine.md):
    /// 1. due learning/known items (≤ sessionDueLimit)
    /// 2. ready items awaiting first question (≤ sessionReadyLimit)
    /// 3. ambient introductions filling leftover room (≤ sessionIntroLimit)
    /// 4. ≤ sessionMasteredLimit sampled mastered item
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

        // Introductions: ambient items in admission order (band, then id),
        // only when due + ready leave room — reviews always come first.
        let introRoom = min(
            config.sessionIntroLimit,
            max(0, config.sessionQuestionTarget - due.count - ready.count)
        )
        let intro = items
            .filter { progress[$0.id]?.stage == .ambient }
            .sorted { ($0.frequencyBand, $0.id) < ($1.frequencyBand, $1.id) }
            .map(\.id)
            .prefix(introRoom)

        let mastered = sortedByDue(progress.values
            .filter { $0.stage == .mastered && scheduler.isDue($0, now: now) }
            .map(\.itemId))
            .prefix(config.sessionMasteredLimit)

        return (Array(due) + Array(ready) + Array(intro) + Array(mastered))
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
            // Ambient items are introductions: always recognition, marked so
            // the UI presents the word before asking (exposure rules stay
            // untouched — the first graded answer is what advances anything).
            let isIntro = p.stage == .ambient
            let modes = isIntro
                ? [PracticeMode.recognition]
                : factory.offerableModes(progress: p, hasSentence: !itemSentences.isEmpty)
            guard let mode = modes.randomElement(using: &rng) else { continue }
            if let q = factory.question(
                item: item,
                mode: mode,
                distractorPool: allItems,
                sentence: itemSentences.first,
                rng: &rng
            ) {
                planned.append(PlannedQuestion(question: q, isRepair: false, isIntro: isIntro))
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
