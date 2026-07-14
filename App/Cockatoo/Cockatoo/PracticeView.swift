import SwiftUI
import LearnerCore

/// The one review engine's UI: recognition, recall, cloze, rebuild — plus
/// introduction cards for new words and the in-session repair lane. Session
/// state lives in PracticeSessionModel so leaving the tab mid-session
/// doesn't discard it.
///
/// Layout follows research/prototype-v2/practice-session.html: a flush arc
/// row (phase · outcome strip · count · End session), a centered question
/// card, the collapsible inspector (milestone ring + done-stack), the
/// ring-draw milestone celebration, and the ledger.
struct PracticeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        PracticeSessionView(session: model.practice)
    }
}

struct PracticeSessionView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: PracticeSessionModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let planned = session.currentQuestion {
                HStack(spacing: 0) {
                    mainColumn(planned)
                    if model.practiceInspectorOpen {
                        PracticeInspector(session: session)
                            .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(cardAnimation, value: model.practiceInspectorOpen)
            } else if !session.ledger.isEmpty {
                if let band = session.milestoneBand, !session.celebrationSeen {
                    CelebrationView(band: band) { session.acknowledgeMilestone() }
                } else {
                    summaryColumn
                }
            } else {
                emptyColumn
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(cardAnimation, value: session.index)
        .animation(cardAnimation, value: session.showingIntro)
        .animation(.easeOut(duration: 0.18), value: session.feedback)
        .onAppear { session.ensureSession() }
        .navigationTitle("Practice")
    }

    // MARK: - Motion (slide/stack base per motion-spec.md; calm under RM)

    var cardAnimation: Animation? {
        reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.85)
    }

    var cardTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
    }

    var revealTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity)
    }

    // MARK: - Main column

    func mainColumn(_ planned: SessionPlanner.PlannedQuestion) -> some View {
        VStack(spacing: 0) {
            arcRow(planned)
            Spacer(minLength: 12)
            Group {
                if session.showingIntro, let item = session.introItem {
                    introCard(item)
                        .transition(revealTransition)
                } else {
                    questionCard(planned)
                        .transition(cardTransition)
                }
            }
            .id("card-\(session.index)-\(session.showingIntro)")
            .frame(maxWidth: 560)
            Spacer(minLength: 24)
        }
        .padding(.horizontal, 34)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Arc row (phase · strip · count · End session)

    func arcRow(_ planned: SessionPlanner.PlannedQuestion) -> some View {
        HStack(spacing: 12) {
            Text(phaseName(planned.beat).uppercased())
                .font(Theme.monoLabel())
                .kerning(0.6)
                .foregroundStyle(Theme.inkFaint)
            progressStrip
            Text("\(min(session.index + 1, session.queue.count)) / \(session.queue.count)")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Theme.inkFaint)
            Button("End session") { session.finishEarly() }
                .buttonStyle(.pill)
                .help("Finish now and see the session ledger")
            SidebarChevron(edge: .trailing, collapsed: !model.practiceInspectorOpen) {
                model.togglePracticeInspector()
            }
            .help(model.practiceInspectorOpen ? "Hide session panel" : "Show session panel")
        }
        .frame(height: Theme.chromeTop)
    }

    func phaseName(_ beat: SessionPlanner.Beat) -> String {
        switch beat {
        case .warmup: return "Warm-up"
        case .newWords: return "New words"
        case .mix: return "Mix"
        case .release: return "Release"
        }
    }

    /// Answers collapse into outcome-coloured chips; the queue visibly grows
    /// when a miss requeues a repair.
    var progressStrip: some View {
        HStack(spacing: 5) {
            ForEach(Array(session.answerTrail.enumerated()), id: \.offset) { _, outcome in
                Capsule()
                    .fill(outcome.color)
                    .frame(height: 5)
                    .frame(minWidth: 8, maxWidth: 30)
            }
            Capsule()
                .strokeBorder(Theme.gold.opacity(0.72), lineWidth: 1.5)
                .frame(height: 5)
                .frame(minWidth: 8, maxWidth: 30)
            let remaining = max(0, session.queue.count - session.index - 1)
            ForEach(0..<remaining, id: \.self) { _ in
                Capsule()
                    .fill(Theme.line)
                    .frame(height: 5)
                    .frame(minWidth: 8, maxWidth: 30)
            }
            Spacer(minLength: 0)
        }
        .accessibilityLabel("question \(min(session.index + 1, session.queue.count)) of \(session.queue.count)")
    }

    // MARK: - Introduction card (cold-start path)

    @ViewBuilder
    func introCard(_ item: VocabItem) -> some View {
        VStack(spacing: 10) {
            Text("NEW WORD")
                .font(Theme.monoLabel())
                .kerning(0.8)
                .foregroundStyle(Theme.inkFaint)
                .padding(.bottom, 6)
            Text(item.displayTarget)
                .font(Theme.serif(38, weight: .semibold))
            if let source = item.bareSourceForm {
                Text(source).font(.title3).foregroundStyle(Theme.inkMuted)
            }
            if let example = item.examples.first {
                VStack(spacing: 3) {
                    Text(example.target).font(Theme.serif(15, weight: .regular)).italic()
                    Text(example.source).font(.system(size: 12.5)).foregroundStyle(Theme.inkMuted)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: 420)
                .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line))
                .padding(.top, 8)
            }
            Text("You'll see it swapped into pages you read — the first real test comes back in about an hour.")
                .font(.caption)
                .foregroundStyle(Theme.inkFaint)
                .frame(maxWidth: 380)
                .multilineTextAlignment(.center)
            Button("Got it — quiz me") { session.revealIntroQuestion() }
                .buttonStyle(.pillProminent)
                .keyboardShortcut(.return, modifiers: [])
                .padding(.top, 4)
        }
    }

    // MARK: - Question card

    @ViewBuilder
    func questionCard(_ planned: SessionPlanner.PlannedQuestion) -> some View {
        VStack(spacing: 6) {
            Text(beatCaption(planned))
                .font(Theme.monoLabel())
                .kerning(0.8)
                .foregroundStyle(Theme.inkFaint)
                .padding(.bottom, 12)
            questionView(planned.question)
            if let feedback = session.feedback {
                feedbackPanel(feedback, planned: planned)
                    .padding(.top, 14)
                Button(session.index + 1 >= session.queue.count ? "Finish" : "Continue") { session.advance() }
                    .buttonStyle(.pillProminent)
                    .keyboardShortcut(.return, modifiers: [])
                    .padding(.top, 8)
            }
        }
    }

    func beatCaption(_ planned: SessionPlanner.PlannedQuestion) -> String {
        if planned.isRepair { return "REPAIR · ONE MORE LOOK" }
        switch planned.beat {
        case .warmup: return "WARM-UP"
        case .newWords: return "NEW WORD"
        case .mix: return "MIX"
        case .release: return "RELEASE · LAST ONE, NO GRADING"
        }
    }

    @ViewBuilder
    func questionView(_ question: Question) -> some View {
        switch question {
        case .recognition(_, let prompt, let options, let correctIndex):
            Text(prompt).font(Theme.serif(34, weight: .semibold))
            Text("What does this mean?")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted)
                .padding(.bottom, 10)
            VStack(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                    choiceButton(i, option, correct: correctIndex)
                }
            }
            .frame(maxWidth: 360)
            if session.feedback == nil {
                Text("Press 1–\(options.count) to answer")
                    .font(.caption2).foregroundStyle(Theme.inkFaint)
                    .padding(.top, 6)
            }
        case .recall(_, let prompt, _):
            Text(prompt).font(Theme.serif(34, weight: .semibold))
            Text("Type the German")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted)
                .padding(.bottom, 10)
            answerField
        case .cloze(_, let sentence, _):
            Text(sentence)
                .font(Theme.serif(22, weight: .regular))
                .multilineTextAlignment(.center)
            Text("Fill in the blank (German)")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted)
                .padding(.bottom, 10)
            answerField
        case .rebuild(_, let sourceText, let tokens, _):
            Text("Build the German for")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted)
            Text(sourceText)
                .font(Theme.serif(19, weight: .regular))
                .italic()
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)
            RebuildAnswerView(tokens: tokens, locked: session.feedback != nil) { order in
                session.answerRebuild(order: order)
            }
        case .selfGrade(_, let prompt, _, _):
            Text("Say — or just think — a small sentence with")
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted)
            Text(prompt)
                .font(Theme.serif(34, weight: .semibold))
                .padding(.bottom, 10)
            if session.feedback == nil {
                HStack(spacing: 12) {
                    Button("Shaky") { session.answerSelfGrade(gotIt: false) }
                        .buttonStyle(.pill)
                    Button("Got it") { session.answerSelfGrade(gotIt: true) }
                        .buttonStyle(.pillProminent)
                        .keyboardShortcut(.return, modifiers: [])
                }
                Text("Honesty beats streaks — shaky just holds the word where it is.")
                    .font(.caption2)
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.top, 6)
            }
        }
    }

    func choiceButton(_ i: Int, _ option: String, correct: Int) -> some View {
        let visual: ChoiceVisual
        if session.feedback == nil {
            visual = .idle
        } else if i == correct {
            visual = .right
        } else if i == session.lastChoice {
            visual = .wrongPick
        } else {
            visual = .dimmed
        }
        return Button {
            session.answerChoice(i)
        } label: {
            HStack(spacing: 12) {
                Text("\(i + 1)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.line2))
                Text(option).font(Theme.serif(16, weight: .regular))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(ChoiceButtonStyle(visual: visual))
        .disabled(session.feedback != nil)
        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
    }

    var answerField: some View {
        TextField("auf Deutsch…", text: $session.typed)
            .textFieldStyle(.plain)
            .font(Theme.serif(19, weight: .regular))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 300)
            .background(Theme.cardBg, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.line2))
            .onSubmit { session.answerTyped() }
            .disabled(session.feedback != nil)
    }

    // MARK: - Feedback (title · why · micro chip, colour-coded left bar)

    func feedbackPanel(_ feedback: PracticeSessionModel.Feedback, planned: SessionPlanner.PlannedQuestion) -> some View {
        let color = feedbackColor(feedback)
        return HStack(spacing: 0) {
            Rectangle().fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(feedbackTitle(feedback, planned: planned))
                    .font(.system(size: 13, weight: .semibold))
                if let detail = feedbackDetail(feedback, planned: planned) {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkMuted)
                }
                if let chip = reviewChip {
                    HStack(spacing: 7) {
                        Circle().fill(color).frame(width: 7, height: 7)
                        Text(chip)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Theme.inkMuted)
                    }
                    .padding(.top, 5)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 420)
        // Hug the text — without this the colour bar's unbounded ideal
        // height inflates the panel to fill the column.
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.line))
    }

    func feedbackColor(_ feedback: PracticeSessionModel.Feedback) -> Color {
        switch feedback {
        case .correct: return Theme.gold
        case .nearMiss: return Theme.outcomeAlmost
        case .wrong: return Theme.outcomeMissed
        }
    }

    func feedbackTitle(_ feedback: PracticeSessionModel.Feedback, planned: SessionPlanner.PlannedQuestion) -> String {
        if case .selfGrade = planned.question {
            if case .correct = feedback { return "Noted — got it" }
            return "Noted — shaky"
        }
        switch feedback {
        case .correct:
            return "Correct"
        case .nearMiss(let expected):
            return "Almost — \(expected)"
        case .wrong(let expected):
            return "Not quite — it's \(expected)"
        }
    }

    func feedbackDetail(_ feedback: PracticeSessionModel.Feedback, planned: SessionPlanner.PlannedQuestion) -> String? {
        if case .selfGrade(_, _, let exampleTarget, let exampleSource) = planned.question {
            var lines: [String] = []
            if let exampleTarget, let exampleSource {
                lines.append("One way: \(exampleTarget) — \(exampleSource)")
            }
            if case .nearMiss = feedback {
                lines.append("Held where it is — it comes around again soon.")
            }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        }
        switch feedback {
        case .correct:
            return nil
        case .nearMiss:
            return "Held, not dropped — it won't re-queue."
        case .wrong:
            return "It comes back for a repair in a moment."
        }
    }

    /// The per-answer micro chip: what just changed for this word.
    var reviewChip: String? {
        guard let p = session.lastGraded, let dueAt = p.dueAt else { return nil }
        let when = RelativeDateTimeFormatter().localizedString(for: dueAt, relativeTo: Date())
        return "next review \(when)"
    }

    // MARK: - Session ledger (what actually changed)

    var summaryColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: Theme.chromeTop)
            Text("Session ledger")
                .font(Theme.serif(24, weight: .medium))
            HStack(spacing: 6) {
                if let band = session.milestoneBand {
                    Text("Band \(band) milestone ·")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.goldDeep)
                }
                Text("\(session.correctCount) of \(session.answeredCount) correct")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.inkMuted)
            }
            .padding(.top, 3)
            .padding(.bottom, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(session.ledger) { entry in
                        HStack(spacing: 10) {
                            Circle().fill(entry.outcome.color).frame(width: 8, height: 8)
                            Text(entry.display)
                                .font(Theme.serif(15.5, weight: .semibold))
                                .frame(width: 140, alignment: .leading)
                            Text(ledgerText(entry))
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.inkMuted)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                    }
                }
            }
            HStack(spacing: 12) {
                Button("Keep going") { session.startSession() }
                    .buttonStyle(.pillProminent)
                    .keyboardShortcut(.return, modifiers: [])
                Text(keepGoingSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkFaint)
            }
            .padding(.top, 16)
            Spacer(minLength: 24)
        }
        .frame(maxWidth: 560, alignment: .leading)
        .padding(.horizontal, 34)
        .frame(maxWidth: .infinity)
    }

    /// Honest about what another round contains — and that extra reps are
    /// safe: strength climbs across days, not within one.
    var keepGoingSubtitle: String {
        guard let o = model.overview else { return "" }
        var parts: [String] = []
        if o.dueNow > 0 { parts.append("\(o.dueNow) due") }
        let newAvailable = min(o.newRemainingToday, o.introAvailable)
        if newAvailable > 0 { parts.append("\(newAvailable) new available") }
        if parts.isEmpty { return "extra reps — they sharpen, without rushing the schedule" }
        return parts.joined(separator: " · ")
    }

    func ledgerText(_ entry: PracticeSessionModel.LedgerEntry) -> String {
        let when = entry.dueAt.map {
            RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date())
        }
        switch entry.outcome {
        case .introduced: return "new word started" + reviewSuffix(when)
        case .strengthened: return "strengthened" + reviewSuffix(when)
        case .repaired: return "repaired" + reviewSuffix(when)
        case .almost: return "almost — spelling corrected" + reviewSuffix(when)
        case .missed: return "missed" + reviewSuffix(when)
        }
    }

    func reviewSuffix(_ when: String?) -> String {
        when.map { " · review \($0)" } ?? ""
    }

    // MARK: - Empty state (always says why, and what would change it)

    var emptyColumn: some View {
        VStack(spacing: 14) {
            CockatooMark(bodyColor: Theme.inkFaint, crestColor: Theme.gold, eyeColor: Theme.bg)
                .frame(width: 44, height: 44)
                .padding(.bottom, 4)
            Text("All caught up")
                .font(Theme.serif(24, weight: .medium))
            Text(emptyReason)
                .font(.system(size: 13))
                .foregroundStyle(Theme.inkMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Check again") { session.startSession() }
                .buttonStyle(.pill)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// With never-empty sessions this only shows before a pack is imported
    /// (or with a truly empty library and spent intake) — say which.
    var emptyReason: String {
        guard let o = model.overview, o.totalItems > 0 else {
            return "Import a language pack to start — your first words arrive in the very first session."
        }
        if o.libraryCount == 0, o.newRemainingToday == 0 {
            return "Today's \(o.newPerDay) new words are done and nothing is in the library yet — more arrive tomorrow."
        }
        if let nextDue = o.nextDueAt {
            let when = RelativeDateTimeFormatter().localizedString(for: nextDue, relativeTo: Date())
            return "Nothing to practice right now — your next review is \(when)."
        }
        return "Nothing to practice right now."
    }
}

// MARK: - Rebuild (token reorder)

/// Tap tokens into order; tap a placed token to take it back. Tokens are
/// addressed by index so duplicates stay distinct.
struct RebuildAnswerView: View {
    let tokens: [String]
    let locked: Bool
    let submit: ([String]) -> Void
    @State private var placed: [Int] = []

    var body: some View {
        VStack(spacing: 14) {
            // The answer line being assembled.
            FlowLayout(spacing: 6) {
                ForEach(placed, id: \.self) { i in
                    TokenChip(text: tokens[i], placed: true) {
                        guard !locked, let at = placed.firstIndex(of: i) else { return }
                        placed.remove(at: at)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(8)
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Theme.line2, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            // The pool of remaining tokens.
            FlowLayout(spacing: 6) {
                ForEach(tokens.indices.filter { !placed.contains($0) }, id: \.self) { i in
                    TokenChip(text: tokens[i], placed: false) {
                        guard !locked else { return }
                        placed.append(i)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !locked {
                Button("Check") { submit(placed.map { tokens[$0] }) }
                    .buttonStyle(.pillProminent)
                    .disabled(placed.count != tokens.count)
                    .keyboardShortcut(.return, modifiers: [])
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: 420)
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: placed)
    }
}

struct TokenChip: View {
    let text: String
    let placed: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(Theme.serif(15, weight: .regular))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(hovering ? Theme.surface2 : Theme.surface, in: RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(placed ? Theme.gold.opacity(0.45) : Theme.line2)
                )
        }
        .buttonStyle(.plain)
        .offset(y: hovering ? -1 : 0)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Minimal wrapping layout for token chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 420
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Choice styling

enum ChoiceVisual { case idle, right, wrongPick, dimmed }

struct ChoiceButtonStyle: ButtonStyle {
    var visual: ChoiceVisual

    func makeBody(configuration: Configuration) -> some View {
        ChoiceBody(configuration: configuration, visual: visual)
    }

    private struct ChoiceBody: View {
        let configuration: Configuration
        let visual: ChoiceVisual
        @State private var hovering = false

        var border: Color {
            switch visual {
            case .right: return Theme.gold
            case .wrongPick: return Theme.outcomeMissed
            case .idle: return hovering ? Theme.line2 : Theme.line
            case .dimmed: return Theme.line
            }
        }

        var body: some View {
            configuration.label
                .foregroundStyle(Theme.ink)
                .background(hovering && visual == .idle ? Theme.surface : Theme.cardBg,
                            in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(border, lineWidth: visual == .right ? 1.5 : 1))
                .opacity(visual == .dimmed ? 0.55 : 1)
                .offset(y: hovering && visual == .idle ? -1 : 0)
                .scaleEffect(configuration.isPressed ? 0.99 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.14), value: hovering)
        }
    }
}

// MARK: - Outcome presentation

extension PracticeSessionModel.LedgerEntry.Outcome {
    var color: Color {
        switch self {
        case .introduced: return Theme.outcomeIntroduced
        case .strengthened: return Theme.outcomeStrengthened
        case .repaired: return Theme.outcomeRepaired
        case .almost: return Theme.outcomeAlmost
        case .missed: return Theme.outcomeMissed
        }
    }

    var label: String {
        switch self {
        case .introduced: return "introduced"
        case .strengthened: return "strengthened"
        case .repaired: return "repaired"
        case .almost: return "almost"
        case .missed: return "missed"
        }
    }
}

// MARK: - Inspector (tier ring + done-stack; tucks during the tier check)

struct PracticeInspector: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: PracticeSessionModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let m = model.overview?.nextMilestone {
                VStack(alignment: .leading, spacing: 12) {
                    Text("BAND \(m.band) · MILESTONE")
                        .font(Theme.monoLabel())
                        .kerning(0.5)
                        .foregroundStyle(Theme.inkFaint)
                    ProgressRing(known: m.known, needed: m.needed)
                        .frame(maxWidth: .infinity)
                    Text(ringCaption(m))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            HStack {
                Text("DONE THIS SESSION")
                    .font(Theme.monoLabel())
                    .kerning(0.5)
                    .foregroundStyle(Theme.inkFaint)
                Spacer()
                Text("\(session.ledger.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.inkFaint)
            }
            doneStack
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, Theme.chromeTop)
        .padding(.bottom, 16)
        .frame(width: 268)
        .frame(maxHeight: .infinity)
        .background(Theme.inspBg)
    }

    func ringCaption(_ m: LearnerEngine.MilestoneProgress) -> String {
        let togo = max(0, m.needed - m.known)
        return "\(togo) to go — a milestone, not a gate; new words keep flowing."
    }

    var doneStack: some View {
        let entries = Array(session.ledger.suffix(6))
        return ZStack(alignment: .top) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                DoneCard(entry: entry, index: i)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: entries.isEmpty ? 0 : CGFloat(entries.count - 1) * 32 + 62, alignment: .top)
        .animation(.spring(response: 0.34, dampingFraction: 0.85), value: session.ledger.count)
    }
}

/// One fanned "done this session" card. Hover brings it to the front,
/// straightens and lifts it so the whole card is readable.
struct DoneCard: View {
    let entry: PracticeSessionModel.LedgerEntry
    let index: Int
    @State private var hovering = false

    private static let messy: [Double] = [0, -1.4, 1.8, -2.2, 1.4]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(entry.display)
                    .font(Theme.serif(15, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 6)
                Circle().fill(entry.outcome.color).frame(width: 7, height: 7)
                Text(entry.outcome.label)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.inkMuted)
            }
            HStack {
                Text(entry.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkMuted)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let dueAt = entry.dueAt {
                    Text(RelativeDateTimeFormatter().localizedString(for: dueAt, relativeTo: Date()))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Theme.inkFaint)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: 204)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(hovering ? Theme.gold.opacity(0.5) : Theme.line2)
        )
        .shadow(color: .black.opacity(hovering ? 0.5 : 0.3), radius: hovering ? 12 : 6, y: hovering ? 8 : 4)
        .scaleEffect(hovering ? 1.05 : 1)
        .rotationEffect(.degrees(hovering ? 0 : Self.messy[index % Self.messy.count]))
        .offset(y: CGFloat(index) * 32 + (hovering ? -6 : 0))
        .zIndex(hovering ? 100 : Double(index))
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: hovering)
    }
}

/// The milestone ring: fills toward the band-completion threshold (needed,
/// not band size).
struct ProgressRing: View {
    let known: Int
    let needed: Int
    var diameter: CGFloat = 132
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var fraction: CGFloat {
        needed > 0 ? min(CGFloat(known) / CGFloat(needed), 1) : 0
    }

    var body: some View {
        let stroke = diameter * 9 / 132
        ZStack {
            Circle().stroke(Theme.line, lineWidth: stroke)
            Circle()
                .trim(from: 0, to: shown ? fraction : 0)
                .stroke(Theme.gold, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(known)")
                    .font(.system(size: diameter * 0.2, weight: .semibold))
                    .monospacedDigit()
                Text("of \(needed) needed")
                    .font(.system(size: max(9, diameter * 0.075), design: .monospaced))
                    .foregroundStyle(Theme.inkFaint)
            }
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            if reduceMotion {
                shown = true
            } else {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.9)) { shown = true }
            }
        }
        .accessibilityLabel("\(known) of \(needed) words needed for the band milestone")
    }
}

// MARK: - Milestone celebration (one ring-draw + one bloom — no confetti)

struct CelebrationView: View {
    let band: Int
    let onContinue: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false
    @State private var bloomed = false
    @State private var textIn = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().stroke(Theme.line, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: drawn ? 1 : 0)
                    .stroke(Theme.gold, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                CockatooMark(eyeColor: Theme.bg)
                    .frame(width: 64, height: 64)
                Circle()
                    .stroke(Theme.gold.opacity(bloomed ? 0 : 0.4), lineWidth: 2)
                    .scaleEffect(bloomed ? 1.55 : 1)
            }
            .frame(width: 172, height: 172)
            .padding(.bottom, 26)
            Group {
                Text("Band \(band) complete")
                    .font(Theme.serif(30, weight: .medium))
                Text("Most of this band is now known — a milestone, earned by remembering across days. New words keep flowing like always.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.inkMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
                    .padding(.top, 9)
                Button("Continue", action: onContinue)
                    .buttonStyle(.pillProminent)
                    .keyboardShortcut(.return, modifiers: [])
                    .padding(.top, 26)
            }
            .opacity(textIn ? 1 : 0)
            .offset(y: textIn ? 0 : 10)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else {
                drawn = true; bloomed = true; textIn = true
                return
            }
            withAnimation(.easeInOut(duration: 0.9)) { drawn = true }
            withAnimation(.easeOut(duration: 0.9).delay(0.75)) { bloomed = true }
            withAnimation(.easeOut(duration: 0.5).delay(0.55)) { textIn = true }
        }
    }
}

