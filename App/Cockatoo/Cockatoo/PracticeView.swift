import SwiftUI
import LearnerCore

/// The one review engine's UI: recognition, recall, cloze — with the real
/// in-session repair lane (a missed question re-enters repairOffset later).
struct PracticeView: View {
    @EnvironmentObject var model: AppModel

    @State private var queue: [SessionPlanner.PlannedQuestion] = []
    @State private var index = 0
    @State private var answered = 0
    @State private var correct = 0
    @State private var typed = ""
    @State private var feedback: Feedback?
    @State private var sessionDone = false

    enum Feedback: Equatable {
        case correct
        case nearMiss(String)
        case wrong(String)
    }

    var body: some View {
        VStack(spacing: 20) {
            if queue.isEmpty && !sessionDone {
                ContentUnavailableView(
                    "Nothing due right now",
                    systemImage: "checkmark.circle",
                    description: Text("Browse with the Safari extension to meet new words, then come back.")
                )
                Button("Check again") { startSession() }
            } else if sessionDone {
                VStack(spacing: 8) {
                    Text("Session complete").font(.title2.bold())
                    Text("\(correct) of \(answered) correct")
                    Button("Start another") { startSession() }
                        .buttonStyle(.borderedProminent)
                }
            } else if index < queue.count {
                let planned = queue[index]
                VStack(spacing: 6) {
                    // Honest progress: answered / current total (repairs grow it).
                    Text("\(min(index + 1, queue.count)) of \(queue.count)\(planned.isRepair ? " · repair" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                    questionView(planned.question)
                }
                if let feedback {
                    feedbackView(feedback)
                    Button(index + 1 >= queue.count ? "Finish" : "Next") { advance() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: [])
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { startSession() }
        .navigationTitle("Practice")
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
                        answerChoice(i)
                    } label: {
                        Text(option).frame(maxWidth: 320).padding(.vertical, 6)
                    }
                    .disabled(feedback != nil)
                }
            }
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
        TextField("answer", text: $typed)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 320)
            .onSubmit { answerTyped() }
            .disabled(feedback != nil)
    }

    @ViewBuilder
    func feedbackView(_ feedback: Feedback) -> some View {
        switch feedback {
        case .correct:
            Label("Correct", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .nearMiss(let expected):
            Label("Almost — \(expected)", systemImage: "circle.bottomhalf.filled").foregroundStyle(.orange)
        case .wrong(let expected):
            Label("It's \(expected) — comes back in a moment", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    func startSession() {
        let session = try? model.engine.planSession(now: Date(), seed: UInt64.random(in: 0..<UInt64.max))
        queue = session?.queue ?? []
        index = 0
        answered = 0
        correct = 0
        typed = ""
        feedback = nil
        sessionDone = false
    }

    func answerChoice(_ selected: Int) {
        guard case .recognition(_, _, _, let correctIndex) = queue[index].question else { return }
        finishAnswer(isCorrect: selected == correctIndex, expected: nil)
    }

    func answerTyped() {
        guard feedback == nil else { return }
        let grading = (try? model.engine.importer.gradingConfig(language: "de", store: model.engine.store)) ?? GradingConfig(articles: [])
        let grader = Grader(grading: grading)
        switch grader.checkTyped(question: queue[index].question, answer: typed) {
        case .correct:
            finishAnswer(isCorrect: true, expected: nil)
        case .nearMiss(let expected):
            feedback = .nearMiss(expected)
            record(correct: false)
        case .wrong(let expected):
            finishAnswer(isCorrect: false, expected: expected)
        }
    }

    func finishAnswer(isCorrect: Bool, expected: String?) {
        feedback = isCorrect ? .correct : .wrong(expected ?? expectedText(queue[index].question))
        record(correct: isCorrect)
    }

    func record(correct isCorrect: Bool) {
        let planned = queue[index]
        answered += 1
        if isCorrect { correct += 1 }
        _ = try? model.engine.grade(result: PracticeResult(
            itemId: planned.question.itemId,
            mode: planned.question.mode,
            correct: isCorrect,
            answeredAt: Date()
        ), now: Date())
        if !isCorrect {
            model.engine.planner.requeueMissed(planned.question, into: &queue, afterIndex: index)
        }
    }

    func advance() {
        typed = ""
        feedback = nil
        if index + 1 >= queue.count {
            sessionDone = true
        } else {
            index += 1
        }
    }

    func expectedText(_ question: Question) -> String {
        switch question {
        case .recognition(_, _, let options, let i): return options[i]
        case .recall(_, _, let expected): return expected
        case .cloze(_, _, let expected): return expected
        }
    }
}
