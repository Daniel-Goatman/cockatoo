import Foundation

public enum PracticeMode: String, Codable, CaseIterable, Sendable {
    case recognition
    case recall
    case cloze
    /// Reassemble the target sentence from shuffled tokens (tactile
    /// production without typing — Core Five, research/brainstorm 03).
    case rebuild
    /// Release-beat micro-production with honest self-report; the app never
    /// pretends it can grade free production.
    case selfGrade
}

public struct PracticeResult: Codable, Equatable, Sendable {
    public var itemId: String
    public var mode: PracticeMode
    public var correct: Bool
    /// Typed answer within edit distance 1 (Grader.TypedVerdict.nearMiss):
    /// counts as not-correct but is graded gently — the box holds instead of
    /// lapsing (docs/plan/04-learning-engine.md §Recall).
    public var nearMiss: Bool
    public var answeredAt: Date

    public init(itemId: String, mode: PracticeMode, correct: Bool, nearMiss: Bool = false, answeredAt: Date) {
        self.itemId = itemId
        self.mode = mode
        self.correct = correct
        self.nearMiss = nearMiss
        self.answeredAt = answeredAt
    }
}

/// A fully materialized practice question. Only modes that are generatable
/// for the item are ever produced (principle P4).
public enum Question: Equatable, Sendable {
    /// Show target text; pick the source meaning among shuffled options.
    case recognition(itemId: String, prompt: String, options: [String], correctIndex: Int)
    /// Show source text; type the target.
    case recall(itemId: String, prompt: String, expected: String)
    /// A captured sentence with the token blanked; type the surface form
    /// that appeared in that sentence.
    case cloze(itemId: String, sentenceWithBlank: String, expected: String)
    /// Show the source sentence; rebuild the target sentence by ordering
    /// the shuffled `tokens`. `expectedOrder` is the authored sentence.
    case rebuild(itemId: String, sourceText: String, tokens: [String], expectedOrder: [String])
    /// "Say — or think — a small sentence with <prompt>", then self-report
    /// got-it / shaky. The example (when authored) is shown afterwards.
    case selfGrade(itemId: String, prompt: String, exampleTarget: String?, exampleSource: String?)

    public var itemId: String {
        switch self {
        case .recognition(let id, _, _, _): return id
        case .recall(let id, _, _): return id
        case .cloze(let id, _, _): return id
        case .rebuild(let id, _, _, _): return id
        case .selfGrade(let id, _, _, _): return id
        }
    }

    public var mode: PracticeMode {
        switch self {
        case .recognition: return .recognition
        case .recall: return .recall
        case .cloze: return .cloze
        case .rebuild: return .rebuild
        case .selfGrade: return .selfGrade
        }
    }
}

/// Language-specific grading knobs shipped in the pack header so the Grader
/// stays language-agnostic (docs/plan/07-content-pipeline.md).
public struct GradingConfig: Codable, Equatable, Sendable {
    /// Articles a typed answer may omit or include ("das Haus" == "Haus").
    public var articles: [String]

    public init(articles: [String]) {
        self.articles = articles
    }

    public static let german = GradingConfig(articles: ["der", "die", "das", "ein", "eine"])
}
