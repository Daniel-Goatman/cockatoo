import Foundation

/// Deterministic seedable RNG so shuffle behavior is testable.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    var state: UInt64

    public init(seed: UInt64) {
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Generates fully materialized questions. A mode is only offered if it is
/// generatable for the item (principle P4); the generative mode-coverage
/// test enforces this for whole packs.
public struct QuestionFactory: Sendable {
    public var config: EngineConfig

    public init(config: EngineConfig = .default) {
        self.config = config
    }

    /// Modes the session planner may offer this item, by stage/box — the
    /// Core Five ladder (research/brainstorm-mockups 03). Rebuild joins at
    /// the bottom of the ladder so day-1 sessions aren't recognition-only;
    /// cloze is available from pack examples before any sentence is
    /// captured. selfGrade is never offered here — it is the release beat.
    public func offerableModes(
        progress: ItemProgress,
        hasSentence: Bool,
        hasExample: Bool = false
    ) -> [PracticeMode] {
        switch progress.stage {
        case .locked, .ambient:
            return []
        case .ready:
            return [.recognition]
        case .learning, .known, .mastered:
            let clozeOK = hasSentence || hasExample
            if progress.srsBox <= 1 {
                return [.recognition] + (hasExample ? [.rebuild] : [])
            }
            if progress.srsBox <= 3 {
                var modes: [PracticeMode] = [.recognition, .recall]
                if clozeOK { modes.append(.cloze) }
                if hasExample { modes.append(.rebuild) }
                return modes
            }
            var modes: [PracticeMode] = [.recall]
            if clozeOK { modes.append(.cloze) }
            if hasExample { modes.append(.rebuild) }
            return modes
        }
    }

    /// An example is rebuildable when its target sentence tokenizes to a
    /// buildable puzzle: 3–10 whitespace tokens.
    public static func rebuildableExample(_ item: VocabItem) -> Example? {
        item.examples.first { rebuildTokens($0) != nil }
    }

    static func rebuildTokens(_ example: Example) -> [String]? {
        let tokens = example.target.split(separator: " ").map(String.init)
        return (3...10).contains(tokens.count) ? tokens : nil
    }

    /// Build a question. Returns nil only for impossible inputs (no forms) —
    /// which the pack validator rejects, so in practice never for pack items.
    public func question(
        item: VocabItem,
        mode: PracticeMode,
        distractorPool: [VocabItem],
        sentence: CapturedSentence?,
        rng: inout some RandomNumberGenerator
    ) -> Question? {
        switch mode {
        case .recognition:
            return recognition(item: item, distractorPool: distractorPool, rng: &rng)
        case .recall:
            return recall(item: item)
        case .cloze:
            if let sentence, let q = cloze(item: item, sentence: sentence) { return q }
            // Day-1 cloze source: the pack example's source sentence
            // (captured sentences win when they exist).
            if let example = item.examples.first {
                let synthetic = CapturedSentence(itemId: item.id, text: example.source, capturedAt: .distantPast)
                if let q = cloze(item: item, sentence: synthetic) { return q }
            }
            // Documented fallback: no usable sentence → recall, and the
            // question *is* a recall question (no silent degradation
            // labeled cloze).
            return recall(item: item)
        case .rebuild:
            // Same fallback contract as cloze.
            return rebuild(item: item, rng: &rng) ?? recall(item: item)
        case .selfGrade:
            return selfGrade(item: item)
        }
    }

    func rebuild(item: VocabItem, rng: inout some RandomNumberGenerator) -> Question? {
        guard let example = Self.rebuildableExample(item),
              let order = Self.rebuildTokens(example) else { return nil }
        var shuffled = order
        var attempts = 0
        repeat {
            shuffled.shuffle(using: &rng)
            attempts += 1
        } while shuffled == order && attempts < 8
        guard shuffled != order else { return nil }   // degenerate (repeated tokens)
        return .rebuild(itemId: item.id, sourceText: example.source, tokens: shuffled, expectedOrder: order)
    }

    func selfGrade(item: VocabItem) -> Question? {
        .selfGrade(
            itemId: item.id,
            prompt: displayTarget(item),
            exampleTarget: item.examples.first?.target,
            exampleSource: item.examples.first?.source
        )
    }

    func recognition(
        item: VocabItem,
        distractorPool: [VocabItem],
        rng: inout some RandomNumberGenerator
    ) -> Question? {
        guard let correct = primarySource(item) else { return nil }

        // Distractors: same language, prefer same kind and adjacent band,
        // never sharing the correct answer's text.
        let ranked = distractorPool
            .filter { $0.id != item.id && $0.language == item.language }
            .map { candidate -> (score: Int, text: String, id: String) in
                var score = abs(candidate.frequencyBand - item.frequencyBand)
                if candidate.kind != item.kind { score += 10 }
                return (score, primarySource(candidate) ?? candidate.target, candidate.id)
            }
            .filter { $0.text.lowercased() != correct.lowercased() }
            .sorted { ($0.score, $0.id) < ($1.score, $1.id) }

        var distractors: [String] = []
        for candidate in ranked where !distractors.contains(where: { $0.lowercased() == candidate.text.lowercased() }) {
            distractors.append(candidate.text)
            if distractors.count == 3 { break }
        }
        guard !distractors.isEmpty else { return nil }

        // Shuffle: the test suite asserts the correct index is ~uniform.
        var options = distractors + [correct]
        options.shuffle(using: &rng)
        guard let correctIndex = options.firstIndex(of: correct) else { return nil }

        let prompt = displayTarget(item)
        return .recognition(itemId: item.id, prompt: prompt, options: options, correctIndex: correctIndex)
    }

    func recall(item: VocabItem) -> Question? {
        guard let source = primarySource(item) else { return nil }
        return .recall(itemId: item.id, prompt: source, expected: displayTarget(item))
    }

    func cloze(item: VocabItem, sentence: CapturedSentence) -> Question? {
        // Blank the surface form that appeared in that sentence; expected
        // answer is that form's target.
        let text = sentence.text
        let lowered = text.lowercased()
        // Longest form first so "the houses" wins over "houses".
        let forms = item.sourceForms.sorted { $0.form.count > $1.form.count }
        for form in forms {
            if let range = lowered.range(of: form.form.lowercased()) {
                let blanked = text.replacingCharacters(in: range, with: "_____")
                return .cloze(itemId: item.id, sentenceWithBlank: blanked, expected: form.target)
            }
        }
        return nil
    }

    /// The bare (non-determiner) source form used as the item's "meaning" text.
    func primarySource(_ item: VocabItem) -> String? {
        item.bareSourceForm
    }

    /// Target with citation-form article where authored, e.g. "das Haus".
    func displayTarget(_ item: VocabItem) -> String {
        item.displayTarget
    }
}
