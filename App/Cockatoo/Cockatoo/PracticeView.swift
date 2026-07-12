import SwiftUI
import LearnerCore

/// The one review engine's UI: recognition, recall, cloze — plus
/// introduction cards for new words (cold start) and the in-session repair
/// lane. Session state lives in PracticeSessionModel so leaving the tab
/// mid-session doesn't discard it.
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
        VStack(spacing: 20) {
            if let planned = session.currentQuestion {
                HStack(spacing: 12) {
                    progressStrip
                    Spacer()
                    Button("End session") { session.finishEarly() }
                        .buttonStyle(.pill)
                        .help("Finish now and see the session ledger")
                }
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
            } else if !session.ledger.isEmpty {
                summaryView
            } else {
                emptyState
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(cardAnimation, value: session.index)
        .animation(cardAnimation, value: session.showingIntro)
        .animation(.easeOut(duration: 0.18), value: session.feedback)
        .onAppear { session.ensureSession() }
        .navigationTitle("Practice")
    }

    // MARK: - Motion (slide/stack base, flip-ish reveal; calm under
    // Reduce Motion — the living-deck language from the design mockups)

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

    // MARK: - Session progress strip (answers collapse into chips)

    var progressStrip: some View {
        HStack(spacing: 4) {
            ForEach(Array(session.answerTrail.enumerated()), id: \.offset) { _, outcome in
                Capsule()
                    .fill(outcomeColor(outcome))
                    .frame(width: 14, height: 6)
            }
            Capsule()
                .fill(Theme.gold)
                .frame(width: 22, height: 6)
            let remaining = max(0, session.queue.count - session.index - 1)
            ForEach(0..<remaining, id: \.self) { _ in
                Capsule()
                    .fill(Theme.line)
                    .frame(width: 14, height: 6)
            }
        }
        .accessibilityLabel("question \(min(session.index + 1, session.queue.count)) of \(session.queue.count)")
    }

    func outcomeColor(_ outcome: PracticeSessionModel.LedgerEntry.Outcome) -> Color {
        switch outcome {
        case .introduced: return Theme.outcomeIntroduced
        case .strengthened: return Theme.outcomeStrengthened
        case .repaired: return Theme.outcomeRepaired
        case .almost: return Theme.outcomeAlmost
        case .missed: return Theme.outcomeMissed
        }
    }

    // MARK: - Introduction card (cold-start path c')

    @ViewBuilder
    func introCard(_ item: VocabItem) -> some View {
        VStack(spacing: 10) {
            Text("New word")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Theme.stageOnPages.opacity(0.15), in: Capsule())
                .foregroundStyle(Theme.stageOnPages)
            Text(item.displayTarget)
                .font(Theme.serif(38, weight: .semibold))
            if let source = item.bareSourceForm {
                Text(source).font(.title3).foregroundStyle(.secondary)
            }
            if let example = item.examples.first {
                VStack(spacing: 2) {
                    Text(example.target).font(.callout.italic())
                    Text(example.source).font(.callout).foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }
            Text("You'll see it swapped into pages you read — the first real test comes back in about an hour.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            if planned.beat == .tierCheck, !planned.isRepair {
                tierCheckBanner
            }
            // Honest progress: current position / current total (repairs grow it).
            Text(progressLabel(planned))
                .font(.caption).foregroundStyle(.secondary)
            questionView(planned.question)
        }
        if let feedback = session.feedback {
            feedbackView(feedback)
            if let unlocked = session.unlockedTier {
                Label("Tier \(unlocked) unlocked", systemImage: "sparkles")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.gold)
            } else if let chip = reviewChip {
                Text(chip).font(.caption).foregroundStyle(.secondary)
            }
            Button(session.index + 1 >= session.queue.count ? "Finish" : "Next") { session.advance() }
                .buttonStyle(.pillProminent)
                .keyboardShortcut(.return, modifiers: [])
        }
    }

    /// The per-answer micro chip: what just changed for this word.
    var reviewChip: String? {
        guard let p = session.lastGraded, let dueAt = p.dueAt else { return nil }
        let when = RelativeDateTimeFormatter().localizedString(for: dueAt, relativeTo: Date())
        return "next review \(when)"
    }

    var tierCheckBanner: some View {
        let next = (model.overview?.tierProgress?.nextTier).map(String.init) ?? "next"
        return Label("Tier \(next) check — all correct unlocks it", systemImage: "flag.checkered")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(Theme.gold.opacity(0.16), in: Capsule())
            .foregroundStyle(Theme.goldDeep)
    }

    func progressLabel(_ planned: SessionPlanner.PlannedQuestion) -> String {
        var label = "\(min(session.index + 1, session.queue.count)) of \(session.queue.count)"
        if planned.isRepair { label += " · repair" }
        switch planned.beat {
        case .warmup: label += " · warm-up"
        case .newWords: label += " · new word"
        case .tierCheck: label += " · tier check"
        case .mix: break
        }
        return label
    }

    @ViewBuilder
    func questionView(_ question: Question) -> some View {
        switch question {
        case .recognition(_, let prompt, let options, _):
            Text(prompt).font(Theme.serif(34, weight: .semibold))
            Text("What does this mean?").foregroundStyle(.secondary)
            VStack(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                    Button {
                        session.answerChoice(i)
                    } label: {
                        Text(option).frame(maxWidth: 320).padding(.vertical, 6)
                    }
                    .disabled(session.feedback != nil)
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
                }
            }
            Text("Press 1–\(options.count) to answer")
                .font(.caption2).foregroundStyle(.tertiary)
        case .recall(_, let prompt, _):
            Text(prompt).font(Theme.serif(34, weight: .semibold))
            Text("Type the German").foregroundStyle(.secondary)
            answerField
        case .cloze(_, let sentence, _):
            Text(sentence).font(Theme.serif(22, weight: .regular)).multilineTextAlignment(.center)
            Text("Fill in the blank (German)").foregroundStyle(.secondary)
            answerField
        }
    }

    var answerField: some View {
        TextField("answer", text: $session.typed)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 320)
            .onSubmit { session.answerTyped() }
            .disabled(session.feedback != nil)
    }

    @ViewBuilder
    func feedbackView(_ feedback: PracticeSessionModel.Feedback) -> some View {
        switch feedback {
        // Gold family for good, terracotta for misses — green stays
        // reserved for connectivity (Theme).
        case .correct:
            Label("Correct", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.goldDeep)
        case .nearMiss(let expected):
            Label("Almost — \(expected) · held, not dropped", systemImage: "circle.bottomhalf.filled")
                .foregroundStyle(Theme.outcomeAlmost)
        case .wrong(let expected):
            Label("It's \(expected) — comes back in a moment", systemImage: "xmark.circle.fill")
                .foregroundStyle(Theme.outcomeMissed)
        }
    }

    // MARK: - Session summary (what actually changed)

    var summaryView: some View {
        VStack(spacing: 14) {
            if let unlocked = session.unlockedTier {
                VStack(spacing: 4) {
                    Label("Tier \(unlocked) unlocked", systemImage: "sparkles")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.goldDeep)
                    Text("New words are entering rotation — they'll start appearing in Safari and in practice.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(14)
                .frame(maxWidth: 420)
                .background(Theme.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }
            Text("Session complete").font(.title2.bold())
            Text("\(session.correctCount) of \(session.answeredCount) correct")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(session.ledger) { entry in
                    HStack(spacing: 8) {
                        ledgerIcon(entry.outcome)
                        Text(entry.display).font(.callout.weight(.medium))
                        Text(ledgerText(entry))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .themeCard(padding: 14)
            Button("Start another") { session.startSession() }
                .buttonStyle(.pillProminent)
                .keyboardShortcut(.return, modifiers: [])
        }
    }

    @ViewBuilder
    func ledgerIcon(_ outcome: PracticeSessionModel.LedgerEntry.Outcome) -> some View {
        switch outcome {
        case .introduced: Image(systemName: "plus.circle.fill").foregroundStyle(Theme.outcomeIntroduced)
        case .strengthened: Image(systemName: "arrow.up.circle.fill").foregroundStyle(Theme.outcomeStrengthened)
        case .repaired: Image(systemName: "arrow.uturn.up.circle.fill").foregroundStyle(Theme.outcomeRepaired)
        case .almost: Image(systemName: "circle.bottomhalf.filled").foregroundStyle(Theme.outcomeAlmost)
        case .missed: Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.outcomeMissed)
        }
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

    var emptyState: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "All caught up",
                systemImage: "checkmark.circle",
                description: Text(emptyReason)
            )
            if let almost = model.overview?.almostReady, !almost.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Almost ready").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(almost, id: \.itemId) { need in
                        Text("\(need.target) — \(ExposureHint.text(for: need))")
                            .font(.callout)
                    }
                }
                .themeCard(padding: 12)
            }
            Button("Check again") { session.startSession() }
                .buttonStyle(.pill)
        }
    }

    var emptyReason: String {
        guard let o = model.overview else {
            return "Browse with the Safari extension to meet new words, then come back."
        }
        if let nextDue = o.nextDueAt {
            let when = RelativeDateTimeFormatter().localizedString(for: nextDue, relativeTo: Date())
            return "Nothing is due right now — your next review is \(when)."
        }
        return "Nothing is due right now. Keep reading with the Safari extension to meet new words."
    }
}

/// Turns an ExposureNeed into the one-line human hint used by Practice and
/// the dashboard: what would make this word practicable. Cap-aware — the
/// hint never suggests an action that won't credit today (P4: a hint on
/// screen must be true).
enum ExposureHint {
    static func text(for need: LearnerEngine.ExposureNeed) -> String {
        let seenRemaining = max(0, need.seenForReady - need.seenCount)
        let fastRemaining = max(0, need.seenForFastReady - need.seenCount)
        let hasEngagement = need.engagedCount >= need.engagedForFastReady
        // A hover helps only if it completes the fast path and can still
        // credit today.
        let hoverHelpsNow = !hasEngagement && !need.engagedCappedToday && fastRemaining == 0

        if need.seenCappedToday {
            if hoverHelpsNow {
                return "hover it once on a page — sightings are done for today"
            }
            return "done for today — sightings count again tomorrow"
        }
        if hasEngagement, fastRemaining > 0 {
            return "\(fastRemaining) more sighting\(fastRemaining == 1 ? "" : "s") on pages"
        }
        if hoverHelpsNow {
            return "hover it once on a page — or \(seenRemaining) more sighting\(seenRemaining == 1 ? "" : "s")"
        }
        if fastRemaining == 0 {
            // Fast path blocked (hover capped today, none banked yet).
            return "\(seenRemaining) more sighting\(seenRemaining == 1 ? "" : "s") — hovers count again tomorrow"
        }
        let hoverNote = need.engagedCappedToday ? "" : " — hovering speeds this up"
        return "\(seenRemaining) more sighting\(seenRemaining == 1 ? "" : "s")\(hoverNote)"
    }
}
