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
        case .cloze(_, _, _, let e): expected = e
        case .recognition, .rebuild, .selfGrade: return .wrong(expected: "")
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

    /// Pack-configured case/diacritic folding, substitutions, and whitespace.
    func normalize(_ s: String) -> String {
        var options: String.CompareOptions = [.caseInsensitive]
        if grading.diacriticInsensitive { options.insert(.diacriticInsensitive) }
        var normalized = s.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: options, locale: Locale(identifier: grading.localeIdentifier))
        for key in grading.substitutions.keys.sorted() {
            normalized = normalized.replacingOccurrences(of: key, with: grading.substitutions[key] ?? "")
        }
        return normalized.split(separator: " ").joined(separator: " ")
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
        let nearMiss = result.nearMiss && !result.correct
        let previousBox = p.srsBox
        let (box, dueAt) = nearMiss
            ? scheduler.hold(progress: p, now: now)
            : scheduler.next(after: result.correct, progress: p, now: now)
        p.srsBox = box
        p.dueAt = dueAt
        if box > previousBox { p.lastAdvancedAt = now }
        p.lastResultAt = now
        p.updatedAt = now

        if result.correct {
            p.correctStreak += 1
            // Distinct-day evidence (D-R2): the first correct answer of a
            // calendar day counts, every further same-day rep doesn't.
            if !LearningCalendar.sameDay(p.lastCorrectAt, now) {
                p.distinctCorrectDays += 1
            }
            p.lastCorrectAt = now
            switch result.mode {
            case .recognition: p.recognitionCorrect += 1
            case .recall: p.recallCorrect += 1
            case .cloze: p.clozeCorrect += 1
            // Rebuild/self-grade don't feed the per-mode counters (the v1
            // schema tracks the original three); box and streak above are
            // the load-bearing state and count normally.
            case .rebuild, .selfGrade: break
            }
        } else {
            p.correctStreak = 0
            // Near-miss is wrong-but-gentle: no lapse count, no box drop.
            if !nearMiss { p.lapses += 1 }
        }

        if result.correct {
            // Transition d: learning → known — box height AND mode breadth
            // AND multi-day evidence (D-R2).
            if p.stage == .learning,
               p.srsBox >= config.knownMinBox,
               p.recognitionCorrect >= 1, p.recallCorrect >= 1,
               p.distinctCorrectDays >= config.knownDistinctDays {
                p.stage = .known
            }
            // Transition e: known → mastered (cloze passes at high box).
            if p.stage == .known,
               result.mode == .cloze,
               p.clozeCorrect >= config.masteredClozeCorrect,
               p.srsBox >= config.masteredMinBox {
                p.stage = .mastered
            }
        } else if !nearMiss {
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
