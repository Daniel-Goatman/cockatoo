import Foundation

/// Plans a short review session (~10 questions, never padded, never
/// advertised longer than it is — principle P4) with a visible arc:
/// warm-up → new words → mix → tier check (docs/plan/04-learning-engine.md
/// §Session planner). Also manages the in-session repair queue: a missed
/// item re-enters once, repairOffset positions later.
public struct SessionPlanner: Sendable {
    public var config: EngineConfig
    public var factory: QuestionFactory
    public var scheduler: any ReviewScheduler

    public init(config: EngineConfig = .default, scheduler: (any ReviewScheduler)? = nil) {
        self.config = config
        self.factory = QuestionFactory(config: config)
        self.scheduler = scheduler ?? LeitnerScheduler(config: config)
    }

    /// The session arc position of a question. Repairs keep their original
    /// beat and carry `isRepair` instead.
    public enum Beat: String, Equatable, Sendable {
        case warmup
        case newWords
        case mix
        case tierCheck
        /// One light self-grade production card to close the session
        /// (research/brainstorm 03: "release — self-grade or quick win").
        case release
    }

    public struct PlannedQuestion: Equatable, Sendable {
        public var question: Question
        /// True if this entry is a repair re-ask of a missed question.
        public var isRepair: Bool
        /// True if this question introduces an ambient item the learner has
        /// never practiced (cold-start path c'). The UI shows the word first.
        public var isIntro: Bool
        public var beat: Beat

        public init(question: Question, isRepair: Bool, isIntro: Bool = false, beat: Beat = .mix) {
            self.question = question
            self.isRepair = isRepair
            self.isIntro = isIntro
            self.beat = beat
        }
    }

    /// Items chosen for one session, grouped by beat.
    public struct Selection: Equatable, Sendable {
        public var warmup: [VocabItem] = []
        public var newWords: [VocabItem] = []
        public var mix: [VocabItem] = []
        public var tierCheck: [VocabItem] = []
        public var release: [VocabItem] = []

        public var isEmpty: Bool {
            // Release never carries a session on its own — it's a closing
            // beat, so it doesn't count toward "is there anything to do".
            warmup.isEmpty && newWords.isEmpty && mix.isEmpty && tierCheck.isEmpty
        }
    }

    /// Selection (docs/plan/04-learning-engine.md), in priority order:
    /// 1. due learning/known items (≤ sessionDueLimit) — the easiest 1–2
    ///    open as the warm-up beat, the rest land in the mix
    /// 2. ready items awaiting their first question (≤ sessionReadyLimit)
    /// 3. ambient introductions filling leftover room (≤ sessionIntroLimit)
    /// 4. ≤ sessionMasteredLimit sampled mastered item
    /// 5. when the tier-unlock condition holds, a tier-check burst of the
    ///    weakest current-tier items rides on top of the session target
    public func select(
        items: [VocabItem],
        progress: [String: ItemProgress],
        now: Date,
        currentTier: Int,
        tierCheckReady: Bool
    ) -> Selection {
        let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        func sortedByDue(_ ids: [String]) -> [String] {
            ids.sorted { a, b in
                let da = progress[a]?.dueAt ?? .distantPast
                let db = progress[b]?.dueAt ?? .distantPast
                return da == db ? a < b : da < db
            }
        }

        let due = Array(sortedByDue(progress.values
            .filter { ($0.stage == .learning || $0.stage == .known) && scheduler.isDue($0, now: now) }
            .map(\.itemId))
            .prefix(config.sessionDueLimit))

        // Warm-up: the easiest (lowest-box) due items open the session —
        // an ordering/framing beat; question modes are untouched.
        let warmupIds = due
            .sorted { a, b in
                let ba = progress[a]?.srsBox ?? 0
                let bb = progress[b]?.srsBox ?? 0
                return ba == bb ? a < b : ba < bb
            }
            .prefix(config.sessionWarmupLimit)
        let warmupSet = Set(warmupIds)

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

        // Cap the core session at the target; the tier check rides on top.
        var core: [String] = due.filter { !warmupSet.contains($0) } + Array(ready) + Array(mastered)
        let coreRoom = max(0, config.sessionQuestionTarget - warmupSet.count - intro.count)
        core = Array(core.prefix(coreRoom))

        var selection = Selection()
        selection.warmup = warmupIds.compactMap { byId[$0] }
        selection.newWords = intro.compactMap { byId[$0] }
        selection.mix = core.compactMap { byId[$0] }

        if tierCheckReady {
            let taken = warmupSet.union(intro).union(core)
            selection.tierCheck = items
                .filter { item in
                    item.frequencyBand == currentTier
                        && !taken.contains(item.id)
                        && (progress[item.id]?.stage ?? .locked) >= .learning
                }
                .sorted { a, b in
                    let ba = progress[a.id]?.srsBox ?? 0
                    let bb = progress[b.id]?.srsBox ?? 0
                    return ba == bb ? a.id < b.id : ba < bb   // weakest first
                }
                .prefix(config.tierCheckQuestionCount)
                .map { $0 }
        }

        // Release: one light production card (self-grade) on the strongest
        // word NOT already in this session — a quick win, and no double SRS
        // credit for a word answered minutes earlier. Skipped when the
        // session is otherwise empty or nothing qualifies (never padded).
        if !selection.isEmpty {
            let taken = warmupSet
                .union(intro)
                .union(core)
                .union(selection.tierCheck.map(\.id))
            // srsBox ≥ 2: a word with some standing — never a box-0/1 item
            // that was introduced minutes ago and isn't due yet.
            selection.release = progress.values
                .filter { p in
                    (p.stage == .learning || p.stage == .known)
                        && p.srsBox >= 2
                        && !taken.contains(p.itemId)
                }
                .sorted { a, b in
                    a.srsBox == b.srsBox ? a.itemId < b.itemId : a.srsBox > b.srsBox
                }
                .prefix(1)
                .compactMap { byId[$0.itemId] }
        }
        return selection
    }

    /// Materialize the selection into the session queue, arc-ordered:
    /// warm-up → new words → mix → tier check.
    public func plan(
        selection: Selection,
        allItems: [VocabItem],
        progress: [String: ItemProgress],
        sentences: (String) throws -> [CapturedSentence],
        seed: UInt64
    ) rethrows -> [PlannedQuestion] {
        var rng = SplitMix64(seed: seed)
        var planned: [PlannedQuestion] = []

        func append(_ items: [VocabItem], beat: Beat) throws {
            for item in items {
                guard let p = progress[item.id] else { continue }
                let itemSentences = try sentences(item.id)
                // Introductions (ambient, c') are recognition — the
                // gentlest generatable mode. Every other beat follows the
                // stage/box mode ladder: the warm-up is "easiest items
                // first" (ordering), never a distorted mode — forcing
                // recognition would starve recall and stall learning→known.
                let isIntro = beat == .newWords
                let modes = isIntro
                    ? [PracticeMode.recognition]
                    : factory.offerableModes(
                        progress: p,
                        hasSentence: !itemSentences.isEmpty,
                        hasExample: QuestionFactory.rebuildableExample(item) != nil
                    )
                guard let mode = modes.randomElement(using: &rng) else { continue }
                if let q = factory.question(
                    item: item,
                    mode: mode,
                    distractorPool: allItems,
                    sentence: itemSentences.first,
                    rng: &rng
                ) {
                    planned.append(PlannedQuestion(question: q, isRepair: false, isIntro: isIntro, beat: beat))
                }
            }
        }

        try append(selection.warmup, beat: .warmup)
        try append(selection.newWords, beat: .newWords)
        try append(selection.mix, beat: .mix)
        try append(selection.tierCheck, beat: .tierCheck)
        // Release is always self-grade — the one fixed-mode beat.
        for item in selection.release {
            if let q = factory.question(
                item: item,
                mode: .selfGrade,
                distractorPool: allItems,
                sentence: nil,
                rng: &rng
            ) {
                planned.append(PlannedQuestion(question: q, isRepair: false, isIntro: false, beat: .release))
            }
        }
        return planned
    }

    /// The tier check passes only when every check question was answered
    /// correctly on its first ask (repairs don't count — P1: the rule lives
    /// here, not in the UI).
    public static func tierCheckPassed(firstResults: [Bool]) -> Bool {
        !firstResults.isEmpty && firstResults.allSatisfy { $0 }
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
        let original = queue[index]
        queue.insert(
            PlannedQuestion(question: missed, isRepair: true, isIntro: false, beat: original.beat),
            at: insertAt
        )
    }
}
