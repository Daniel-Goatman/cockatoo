import SwiftUI
import Combine
import LearnerCore

/// Session state lives here, not in view @State, so switching sidebar
/// sections mid-session and coming back resumes exactly where you were.
@MainActor
final class PracticeSessionModel: ObservableObject {
    private let engine: LearnerEngine

    @Published var queue: [SessionPlanner.PlannedQuestion] = []
    @Published var index = 0
    @Published var typed = ""
    @Published var feedback: Feedback?
    @Published var sessionDone = false
    /// True while an introduction card shows the word before its question.
    @Published var showingIntro = false
    @Published var introItem: VocabItem?
    @Published var ledger: [LedgerEntry] = []
    /// Outcome of every answer in order (repairs included) — drives the
    /// session progress strip.
    @Published var answerTrail: [LedgerEntry.Outcome] = []
    /// The just-graded item's progress, for the post-answer micro chip.
    @Published var lastGraded: ItemProgress?
    /// Set when a band crossed its milestone during this session.
    @Published var milestoneBand: Int?
    /// The recognition option the user picked (drives right/wrong outlines).
    @Published var lastChoice: Int?
    /// True once the milestone celebration has been acknowledged — the
    /// ledger shows after, not instead of, the celebration.
    @Published var celebrationSeen = false
    /// Sessions completed in a row this sitting (drives "keep going" copy).
    @Published var sessionsThisSitting = 0

    enum Feedback: Equatable {
        case correct
        case nearMiss(String)
        case wrong(String)
    }

    /// One row of the session-end ledger: what changed for each item.
    struct LedgerEntry: Identifiable, Equatable {
        enum Outcome: Equatable {
            case introduced        // new word met and answered
            case strengthened      // correct answer
            case almost            // near-miss (box held)
            case repaired          // missed, then correct on the repair re-ask
            case missed            // wrong (repair pending or also missed)
        }

        let id: String             // itemId — one row per item
        var display: String        // target-language text, e.g. "das Haus"
        var subtitle: String       // source text, e.g. "house"
        var outcome: Outcome
        var stage: Stage
        var dueAt: Date?
    }

    init(engine: LearnerEngine) {
        self.engine = engine
    }

    var currentQuestion: SessionPlanner.PlannedQuestion? {
        index < queue.count ? queue[index] : nil
    }

    var answeredCount: Int { ledger.count }
    var correctCount: Int {
        ledger.filter { $0.outcome == .strengthened || $0.outcome == .introduced || $0.outcome == .repaired }.count
    }

    /// Start a session only when none is active — entering the Practice tab
    /// resumes an in-flight session instead of discarding it.
    func ensureSession() {
        guard queue.isEmpty, !sessionDone else { return }
        startSession()
    }

    func startSession() {
        let session = try? engine.planSession(now: Date(), seed: UInt64.random(in: 0..<UInt64.max))
        queue = session?.queue ?? []
        index = 0
        typed = ""
        feedback = nil
        sessionDone = queue.isEmpty
        ledger = []
        answerTrail = []
        lastGraded = nil
        milestoneBand = nil
        lastChoice = nil
        celebrationSeen = false
        prepareCurrent()
    }

    /// A queued session belongs to the language that planned it. Switching
    /// packs discards that transient queue; progress remains untouched.
    func resetForLanguageChange() {
        queue = []
        index = 0
        typed = ""
        feedback = nil
        sessionDone = false
        showingIntro = false
        introItem = nil
        ledger = []
        answerTrail = []
        lastGraded = nil
        milestoneBand = nil
        lastChoice = nil
        celebrationSeen = false
        sessionsThisSitting = 0
    }

    private func prepareCurrent() {
        guard let planned = currentQuestion, planned.isIntro, !planned.isRepair else {
            showingIntro = false
            introItem = nil
            return
        }
        introItem = try? engine.store.item(id: planned.question.itemId)
        showingIntro = introItem != nil
    }

    func revealIntroQuestion() {
        showingIntro = false
    }

    // MARK: - Answering

    func answerChoice(_ selected: Int) {
        guard feedback == nil,
              case .recognition(_, _, _, let correctIndex) = currentQuestion?.question else { return }
        lastChoice = selected
        let isCorrect = selected == correctIndex
        feedback = isCorrect ? .correct : .wrong(expectedText())
        record(correct: isCorrect, nearMiss: false)
    }

    func answerTyped() {
        guard feedback == nil, let planned = currentQuestion else { return }
        let grading = (try? engine.importer.gradingConfig(
            language: (try? engine.store.setting(SettingsKey.activeLanguage)) ?? "und",
            store: engine.store
        )) ?? GradingConfig(articles: [])
        let grader = Grader(grading: grading)
        switch grader.checkTyped(question: planned.question, answer: typed) {
        case .correct:
            feedback = .correct
            record(correct: true, nearMiss: false)
        case .nearMiss(let expected):
            feedback = .nearMiss(expected)
            record(correct: false, nearMiss: true)
        case .wrong(let expected):
            feedback = .wrong(expected)
            record(correct: false, nearMiss: false)
        }
    }

    /// Rebuild: exact token order or nothing — the tokens were given, so
    /// there is no "almost".
    func answerRebuild(order: [String]) {
        guard feedback == nil,
              case .rebuild(_, _, _, let expected) = currentQuestion?.question else { return }
        let isCorrect = order == expected
        feedback = isCorrect ? .correct : .wrong(expected.joined(separator: " "))
        record(correct: isCorrect, nearMiss: false)
    }

    /// Self-grade: "shaky" is graded like a near-miss — the box holds, no
    /// repair re-queue. Honest: the app doesn't pretend to grade production.
    func answerSelfGrade(gotIt: Bool) {
        guard feedback == nil, case .selfGrade = currentQuestion?.question else { return }
        feedback = gotIt ? .correct : .nearMiss(expectedText())
        record(correct: gotIt, nearMiss: !gotIt)
    }

    private func record(correct isCorrect: Bool, nearMiss: Bool) {
        guard let planned = currentQuestion else { return }
        let updated = try? engine.grade(result: PracticeResult(
            itemId: planned.question.itemId,
            mode: planned.question.mode,
            correct: isCorrect,
            nearMiss: nearMiss,
            answeredAt: Date()
        ), now: Date())
        lastGraded = updated

        updateLedger(planned: planned, correct: isCorrect, nearMiss: nearMiss, progress: updated)

        if !isCorrect {
            engine.planner.requeueMissed(planned.question, into: &queue, afterIndex: index)
        }

        // Milestone check (non-gating, D-R3): a correct answer may tip a
        // band over its completion fraction — celebrate at session end.
        if isCorrect, milestoneBand == nil {
            milestoneBand = try? engine.pendingMilestone(now: Date())
        }
    }

    /// Called from the celebration's Continue: record it so the same band
    /// never celebrates twice.
    func acknowledgeMilestone() {
        if let band = milestoneBand {
            try? engine.markMilestoneCelebrated(band: band, now: Date())
        }
        celebrationSeen = true
    }

    private func updateLedger(
        planned: SessionPlanner.PlannedQuestion,
        correct: Bool,
        nearMiss: Bool,
        progress: ItemProgress?
    ) {
        let outcome: LedgerEntry.Outcome
        if correct {
            outcome = planned.isRepair ? .repaired : (planned.isIntro ? .introduced : .strengthened)
        } else if nearMiss {
            outcome = .almost
        } else {
            outcome = .missed
        }

        answerTrail.append(outcome)

        let display = ledgerDisplay(planned.question)
        if let i = ledger.firstIndex(where: { $0.id == planned.question.itemId }) {
            ledger[i].outcome = outcome
            ledger[i].stage = progress?.stage ?? ledger[i].stage
            ledger[i].dueAt = progress?.dueAt
        } else {
            let item = try? engine.store.item(id: planned.question.itemId)
            ledger.append(LedgerEntry(
                id: planned.question.itemId,
                display: display,
                subtitle: item?.bareSourceForm ?? "",
                outcome: outcome,
                stage: progress?.stage ?? .learning,
                dueAt: progress?.dueAt
            ))
        }
    }

    private func ledgerDisplay(_ question: Question) -> String {
        switch question {
        case .recognition(_, let prompt, _, _): return prompt
        case .recall(_, _, let expected): return expected
        case .cloze(_, _, _, let expected): return expected
        case .rebuild(let id, _, _, _):
            return (try? engine.store.item(id: id))?.displayTarget ?? id
        case .selfGrade(_, let prompt, _, _): return prompt
        }
    }

    func expectedText() -> String {
        switch currentQuestion?.question {
        case .recognition(_, _, let options, let i): return options[i]
        case .recall(_, _, let expected): return expected
        case .cloze(_, _, _, let expected): return expected
        case .rebuild(_, _, _, let order): return order.joined(separator: " ")
        case .selfGrade(_, let prompt, _, _): return prompt
        case nil: return ""
        }
    }

    /// End the session now (the floating "End session" control): drop the
    /// remaining queue and land on the ledger for what was answered.
    /// Distinct from pause — leaving the tab already resumes implicitly.
    func finishEarly() {
        guard !queue.isEmpty else { return }
        queue = []
        index = 0
        typed = ""
        feedback = nil
        showingIntro = false
        introItem = nil
        sessionDone = true
    }

    func advance() {
        typed = ""
        feedback = nil
        lastChoice = nil
        if index + 1 >= queue.count {
            sessionDone = true
            sessionsThisSitting += 1
            queue = []
            index = 0
        } else {
            index += 1
            prepareCurrent()
        }
    }
}
