import Foundation

/// Plans a review session (~10 questions) with a visible arc:
/// warm-up → new words → mix → release. Sessions are never empty while the
/// library has items (docs/plan/10-learning-redesign.md): due reviews come
/// first, then new introductions within the daily budget, then
/// reinforcement reps of non-due items — which the scheduler guarantees
/// cannot advance a box, so "practice as much as you want" is safe by
/// construction. Also manages the in-session repair queue: a missed item
/// re-enters once, repairOffset positions later.
public struct SessionPlanner: Sendable {
    public var config: EngineConfig
    public var factory: QuestionFactory
    public var scheduler: any ReviewScheduler
    public var intake: IntakeEngine

    public init(config: EngineConfig = .default, scheduler: (any ReviewScheduler)? = nil) {
        self.config = config
        self.factory = QuestionFactory(config: config)
        self.scheduler = scheduler ?? LeitnerScheduler(config: config)
        self.intake = IntakeEngine(config: config)
    }

    /// The session arc position of a question. Repairs keep their original
    /// beat and carry `isRepair` instead.
    public enum Beat: String, Equatable, Sendable {
        case warmup
        case newWords
        case mix
        /// One light self-grade production card to close the session
        /// (research/brainstorm 03: "release — self-grade or quick win").
        case release
    }

    public struct PlannedQuestion: Equatable, Sendable {
        public var question: Question
        /// True if this entry is a repair re-ask of a missed question.
        public var isRepair: Bool
        /// True if this question introduces a word into the library — the
        /// UI shows the word first, marked as new.
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
        public var release: [VocabItem] = []

        public var isEmpty: Bool {
            // Release never carries a session on its own — it's a closing
            // beat, so it doesn't count toward "is there anything to do".
            warmup.isEmpty && newWords.isEmpty && mix.isEmpty
        }
    }

    /// Selection (docs/plan/10-learning-redesign.md), in priority order:
    /// 1. due learning/known items (≤ sessionDueLimit) — the easiest 1–2
    ///    open as the warm-up beat, the rest land in the mix
    /// 2. new introductions: intake candidates within today's remaining
    ///    budget (≤ sessionIntroLimit per session)
    /// 3. ≤ sessionMasteredLimit due mastered item
    /// 4. reinforcement reps of non-due library items fill the session to
    ///    its target — weakest and least-recently-practiced first
    public func select(
        items: [VocabItem],
        progress: [String: ItemProgress],
        now: Date
    ) -> Selection {
        let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        func sortedByDue(_ ids: [String]) -> [String] {
            ids.sorted { a, b in
                let da = progress[a]?.dueAt ?? .distantPast
                let db = progress[b]?.dueAt ?? .distantPast
                return da == db ? a < b : da < db
            }
        }

        let dueAll = progress.values
            .filter { ($0.stage == .learning || $0.stage == .known) && scheduler.isDue($0, now: now) }
            .map(\.itemId)
        let due = Array(sortedByDue(dueAll).prefix(config.sessionDueLimit))

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

        // Introductions: intake order, bounded by the per-session cap,
        // today's remaining daily budget (which pauses under review debt),
        // and the room due reviews leave — reviews always come first.
        let introRoom = min(
            config.sessionIntroLimit,
            intake.budget(progress: progress, dueNow: dueAll.count, now: now),
            max(0, config.sessionQuestionTarget - due.count)
        )
        let intro = intake.candidates(items: items, progress: progress)
            .prefix(introRoom)
            .map(\.id)

        let mastered = sortedByDue(progress.values
            .filter { $0.stage == .mastered && scheduler.isDue($0, now: now) }
            .map(\.itemId))
            .prefix(config.sessionMasteredLimit)

        var core: [String] = due.filter { !warmupSet.contains($0) } + Array(mastered)
        let coreRoom = max(0, config.sessionQuestionTarget - warmupSet.count - intro.count)
        core = Array(core.prefix(coreRoom))

        // Reinforcement fill: non-due library items round the session out to
        // the target. The scheduler holds their boxes (not due), so these
        // reps add practice volume without inflating mastery — wrong
        // answers still lapse, as they should.
        let taken = warmupSet.union(intro).union(core)
        let fillRoom = max(0, config.sessionQuestionTarget - warmupSet.count - intro.count - core.count)
        let reinforcement = progress.values
            .filter { p in
                (p.stage == .learning || p.stage == .known) && !taken.contains(p.itemId)
            }
            .sorted { a, b in
                if a.srsBox != b.srsBox { return a.srsBox < b.srsBox }
                let ra = a.lastResultAt ?? .distantPast
                let rb = b.lastResultAt ?? .distantPast
                return ra == rb ? a.itemId < b.itemId : ra < rb
            }
            .prefix(fillRoom)
            .map(\.itemId)

        var selection = Selection()
        selection.warmup = warmupIds.compactMap { byId[$0] }
        selection.newWords = intro.compactMap { byId[$0] }
        selection.mix = (core + reinforcement).compactMap { byId[$0] }

        // Release: one light production card (self-grade) on the strongest
        // word NOT already in this session — a quick win, and no double SRS
        // credit for a word answered minutes earlier. Skipped when the
        // session is otherwise empty or nothing qualifies (never padded).
        if !selection.isEmpty {
            let allTaken = taken.union(reinforcement)
            // srsBox ≥ 2: a word with some standing — never a box-0/1 item
            // that was introduced minutes ago and isn't due yet.
            selection.release = progress.values
                .filter { p in
                    (p.stage == .learning || p.stage == .known)
                        && p.srsBox >= 2
                        && !allTaken.contains(p.itemId)
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
    /// warm-up → new words → mix → release.
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
                let itemSentences = try sentences(item.id)
                let isIntro = beat == .newWords
                let modes: [PracticeMode]
                if isIntro {
                    // Introductions have no progress row yet and are always
                    // recognition — the gentlest generatable mode.
                    modes = [.recognition]
                } else {
                    guard let p = progress[item.id] else { continue }
                    modes = factory.weightedModes(
                        progress: p,
                        hasSentence: !itemSentences.isEmpty,
                        hasExample: QuestionFactory.rebuildableExample(item) != nil
                    )
                }
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
