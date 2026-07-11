import Foundation

/// Grades typed answers and applies results to progress. Language-agnostic:
/// article handling comes from the pack's GradingConfig.
public struct Grader: Sendable {
    public var config: EngineConfig
    public var scheduler: any ReviewScheduler
    public var grading: GradingConfig

    public init(config: EngineConfig = .default, scheduler: (any ReviewScheduler)? = nil, grading: GradingConfig) {
        self.config = config
        self.scheduler = scheduler ?? LeitnerScheduler(config: config)
        self.grading = grading
    }

    public enum TypedVerdict: Equatable, Sendable {
        case correct
        /// Edit distance 1 on words ≥ 5 chars: shown the correction, counted
        /// wrong but without the double lapse penalty.
        case nearMiss(expected: String)
        case wrong(expected: String)
    }

    // MARK: - Answer checking

    public func checkChoice(question: Question, selectedIndex: Int) -> Bool {
        guard case .recognition(_, _, _, let correctIndex) = question else { return false }
        return selectedIndex == correctIndex
    }

    public func checkTyped(question: Question, answer: String) -> TypedVerdict {
        let expected: String
        switch question {
        case .recall(_, _, let e): expected = e
        case .cloze(_, _, let e): expected = e
        case .recognition: return .wrong(expected: "")
        }
        let normAnswer = normalize(answer)
        let normExpected = normalize(expected)
        if normAnswer == normExpected { return .correct }
        // Article-optional in both directions: "das Haus" == "Haus".
        if stripArticle(normAnswer) == stripArticle(normExpected) { return .correct }
        let a = stripArticle(normAnswer), b = stripArticle(normExpected)
        if b.count >= 5, editDistance(a, b) == 1 { return .nearMiss(expected: expected) }
        return .wrong(expected: expected)
    }

    /// Case-insensitive, accent-insensitive, whitespace-trimmed.
    func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "ß", with: "ss")
            .split(separator: " ").joined(separator: " ")
    }

    func stripArticle(_ s: String) -> String {
        let parts = s.split(separator: " ", maxSplits: 1)
        guard parts.count == 2 else { return s }
        let foldedArticles = grading.articles.map { normalize($0) }
        return foldedArticles.contains(String(parts[0])) ? String(parts[1]) : s
    }

    func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var curr = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            curr[0] = i
            for j in 1...b.count {
                curr[j] = a[i - 1] == b[j - 1]
                    ? prev[j - 1]
                    : 1 + min(prev[j - 1], prev[j], curr[j - 1])
            }
            swap(&prev, &curr)
        }
        return prev[b.count]
    }

    // MARK: - Applying results (the ONLY thing that moves srsBox)

    /// Returns updated progress. Stage transitions c/d/e/f from
    /// docs/plan/04-learning-engine.md.
    public func apply(result: PracticeResult, progress: ItemProgress, now: Date) -> ItemProgress {
        var p = progress
        let (box, dueAt) = scheduler.next(after: result.correct, progress: p, now: now)
        p.srsBox = box
        p.dueAt = dueAt
        p.lastResultAt = now
        p.updatedAt = now

        if result.correct {
            p.correctStreak += 1
            switch result.mode {
            case .recognition: p.recognitionCorrect += 1
            case .recall: p.recallCorrect += 1
            case .cloze: p.clozeCorrect += 1
            }
        } else {
            p.correctStreak = 0
            p.lapses += 1
        }

        // Transition c: first answer (right or wrong) enters learning.
        if p.stage == .ready {
            p.stage = .learning
        }

        if result.correct {
            // Transition d: learning → known.
            if p.stage == .learning,
               p.srsBox >= config.knownMinBox,
               p.recognitionCorrect >= 1, p.recallCorrect >= 1 {
                p.stage = .known
            }
            // Transition e: known → mastered (cloze passes at high box).
            if p.stage == .known,
               result.mode == .cloze,
               p.clozeCorrect >= config.masteredClozeCorrect,
               p.srsBox >= config.masteredMinBox {
                p.stage = .mastered
            }
        } else {
            // Edge f: lapse. mastered falls to known; known falls to learning.
            if p.stage == .mastered {
                p.stage = .known
            } else if p.stage == .known {
                p.stage = .learning
            }
        }
        return p
    }
}
