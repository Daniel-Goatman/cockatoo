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

    var body: some View {
        VStack(spacing: 20) {
            if let planned = session.currentQuestion {
                if session.showingIntro, let item = session.introItem {
                    introCard(item)
                } else {
                    questionCard(planned)
                }
            } else if !session.ledger.isEmpty {
                summaryView
            } else {
                emptyState
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { session.ensureSession() }
        .navigationTitle("Practice")
    }

    // MARK: - Introduction card (cold-start path c')

    @ViewBuilder
    func introCard(_ item: VocabItem) -> some View {
        VStack(spacing: 10) {
            Text("New word")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.blue.opacity(0.14), in: Capsule())
                .foregroundStyle(.blue)
            Text(item.displayTarget)
                .font(.system(size: 38, weight: .semibold, design: .serif))
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
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
                .padding(.top, 4)
        }
    }

    // MARK: - Question card

    @ViewBuilder
    func questionCard(_ planned: SessionPlanner.PlannedQuestion) -> some View {
        VStack(spacing: 6) {
            // Honest progress: current position / current total (repairs grow it).
            Text(progressLabel(planned))
                .font(.caption).foregroundStyle(.secondary)
            questionView(planned.question)
        }
        if let feedback = session.feedback {
            feedbackView(feedback)
            Button(session.index + 1 >= session.queue.count ? "Finish" : "Next") { session.advance() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
        }
    }

    func progressLabel(_ planned: SessionPlanner.PlannedQuestion) -> String {
        var label = "\(min(session.index + 1, session.queue.count)) of \(session.queue.count)"
        if planned.isRepair { label += " · repair" }
        if planned.isIntro { label += " · new word" }
        return label
    }

    @ViewBuilder
    func questionView(_ question: Question) -> some View {
        switch question {
        case .recognition(_, let prompt, let options, _):
            Text(prompt).font(.system(size: 34, weight: .semibold, design: .serif))
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
            Text(prompt).font(.system(size: 34, weight: .semibold, design: .serif))
            Text("Type the German").foregroundStyle(.secondary)
            answerField
        case .cloze(_, let sentence, _):
            Text(sentence).font(.system(size: 22, design: .serif)).multilineTextAlignment(.center)
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
        case .correct:
            Label("Correct", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .nearMiss(let expected):
            Label("Almost — \(expected)", systemImage: "circle.bottomhalf.filled").foregroundStyle(.orange)
        case .wrong(let expected):
            Label("It's \(expected) — comes back in a moment", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    // MARK: - Session summary (what actually changed)

    var summaryView: some View {
        VStack(spacing: 14) {
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
            .padding(14)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            Button("Start another") { session.startSession() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
        }
    }

    @ViewBuilder
    func ledgerIcon(_ outcome: PracticeSessionModel.LedgerEntry.Outcome) -> some View {
        switch outcome {
        case .introduced: Image(systemName: "plus.circle.fill").foregroundStyle(.blue)
        case .strengthened: Image(systemName: "arrow.up.circle.fill").foregroundStyle(.green)
        case .repaired: Image(systemName: "arrow.uturn.up.circle.fill").foregroundStyle(.green)
        case .almost: Image(systemName: "circle.bottomhalf.filled").foregroundStyle(.orange)
        case .missed: Image(systemName: "arrow.down.circle.fill").foregroundStyle(.red)
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
                .padding(12)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }
            Button("Check again") { session.startSession() }
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
/// the dashboard: what would make this word practicable.
enum ExposureHint {
    static func text(for need: LearnerEngine.ExposureNeed) -> String {
        let seenRemaining = max(0, need.seenForReady - need.seenCount)
        let fastRemaining = max(0, need.seenForFastReady - need.seenCount)
        let hasEngagement = need.engagedCount >= need.engagedForFastReady
        if hasEngagement, fastRemaining > 0 {
            return "\(fastRemaining) more sighting\(fastRemaining == 1 ? "" : "s") on pages"
        }
        if fastRemaining == 0 {
            return "hover it once on a page — or \(seenRemaining) more sighting\(seenRemaining == 1 ? "" : "s")"
        }
        return "\(seenRemaining) more sighting\(seenRemaining == 1 ? "" : "s") — hovering speeds this up"
    }
}
