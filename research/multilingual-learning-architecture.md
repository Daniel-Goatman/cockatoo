# Multilingual Learning Architecture

Date: 2026-05-28
Product: Cockatoo
Scope: Spanish, French, German, Italian, and Portuguese

## Summary

Cockatoo should become a five-language ambient learning system, not a
German-only word replacer. The architecture should keep the current Safari
replacement wedge, but replace the single `CurriculumWord` model with a
language-aware curriculum graph that supports words, chunks, patterns, and
sentence frames.

The main engineering principle is:

> The app owns truth. The model proposes, explains, and generates practice.

That means the LLM can create candidate content, examples, cloze cards,
distractors, tutor answers, and future lesson suggestions, but it should not be
allowed to silently mutate the active curriculum or decide that a learner has
mastered something. A deterministic state machine should decide exposure,
review scheduling, progression, and replacement eligibility.

## Product Thesis

The product should support learners who want language exposure during normal
Safari reading and a short review loop that turns exposure into memory. It
should not try to be a full course, a video immersion platform, or a general
chatbot. Its advantage is that it attaches learning to the user's real reading
habit.

For the first paid beta, the product should support:

- Spanish
- French
- German
- Italian
- Portuguese

These are good first languages because they are well supported by current LLMs,
use Latin script, fit Safari inline replacement well, and share enough
curriculum structure that one architecture can serve them without adding
right-to-left layout, non-segmented writing, or major script-learning concerns.

## Research And Competitor Signals

The research direction is consistent:

- Digital reading can support vocabulary acquisition, especially when
  comprehension is preserved and glosses are adaptive.
- Exposure is useful but insufficient. Durable learning needs spaced retrieval,
  production, feedback, and adaptive scaffolding.
- LLM tutors are promising for feedback, writing, speaking, and vocabulary
  practice, but they need constraints because feedback can be inconsistent.
- More advanced learning needs phrases and sentence-level patterns, not just
  single words.

Competitors also point toward a hybrid system:

- Readlang lets learners translate words and phrases, tracks highlights, and
  uses AI for context explanations.
- LingQ stores known/new/learning words and phrases from authentic content and
  uses review workflows.
- Language Reactor distinguishes words, phrases, and saved context.
- Migaku uses interactive text, sentence breakdowns, spaced repetition, and
  known-vocabulary recommendations.

The pattern is clear: serious products maintain structured learner state and
content objects. They use AI as assistance, not as an unbounded curriculum.

Sources:

- https://link.springer.com/article/10.1007/s10639-023-11969-1
- https://www.sciencedirect.com/science/article/pii/S2215039025000086
- https://link.springer.com/article/10.1007/s10791-025-09833-6
- https://platform.openai.com/docs/guides/structured-outputs
- https://readlang.com/features
- https://www.lingq.com/en/learn-english-online/
- https://www.languagereactor.com/help/faq
- https://migaku.com/faq/features

## Core Design Decision

Do not build a flat vocabulary list. Build a curriculum graph.

The current model:

```swift
CurriculumWord(
    source: "and",
    translation: "und",
    explanation: "Connects words or ideas.",
    tier: 1
)
```

This cannot scale because it assumes:

- one source string
- one target string
- one target language
- one item type
- one exposure count
- one tier progression rule

The replacement model should be:

```swift
CurriculumItem(
    id: "de.word.and.und",
    language: .german,
    kind: .word,
    source: SourceExpression(text: "and", matchType: .wordBoundary),
    target: TargetExpression(text: "und", pronunciation: nil),
    level: .a1,
    frequencyBand: 1,
    replacementPolicy: .ambientSafe,
    reviewPolicy: .recognitionFirst,
    dependencies: [],
    explanations: [...]
)
```

Then the same system can represent:

- `word`: `and -> und`
- `chunk`: `of course -> por supuesto`
- `pattern`: `because + subordinate clause`
- `sentenceFrame`: `I would like ... -> Ich moechte ...`

For beta, the extension should automatically replace `word` and exact safe
`chunk` items. `pattern` and `sentenceFrame` items should live in review, tutor,
and guided practice only; automatic pattern/sentence rewriting is a later
capability because it requires grammar transformation, context, and stricter
privacy controls.

## Language Pack Model

Each supported language should be a versioned pack:

```swift
LanguagePack(
    id: "es",
    displayName: "Spanish",
    version: "2026.05.1",
    sourceLanguage: .english,
    targetLanguage: .spanish,
    items: [CurriculumItem],
    rules: LanguageRules,
    reviewTemplates: [ReviewTemplate],
    tutorProfile: TutorProfile
)
```

The app ships with bundled language packs. Later, packs can update through app
updates or a signed remote content manifest. For beta, keep packs bundled so
the app works offline except for tutor/generation calls.

### Language Rules

Each language needs rules that the core app can understand without hard-coding
language-specific behavior throughout the codebase:

- display name and locale
- punctuation spacing rules
- capitalization behavior
- whether target terms can be safely lowercased
- allowed ambient item kinds
- maximum replacement density
- preferred review modes
- ambiguous source terms to avoid
- false-friend warnings
- grammar notes by pattern family

For the initial five languages, most rules can be similar. German needs more
care around word order and capitalization. French, Italian, Spanish, and
Portuguese need gender, number, and pronoun/clitic caution. All five need
high-confidence phrase matching before live chunk replacement.

## Item Types

### Word

A single lexical item or short fixed expression with a stable mapping.

Examples:

- `and -> y / et / und / e / e`
- `but -> pero / mais / aber / ma / mas`
- `today -> hoy / aujourd'hui / heute / oggi / hoje`

Ambient replacement is usually safe for high-frequency function words and
adverbs, but not always for prepositions, pronouns, or polysemous words.

### Chunk

A multi-word phrase with stable meaning.

Examples:

- `of course -> por supuesto`
- `I think -> je pense`
- `there is -> es gibt`
- `a little -> un poco`

Chunks should be part of the Safari experience in beta. Ambient replacement is
allowed when the source phrase is exact, low ambiguity, marked `ambientSafe`,
and not inside an excluded DOM area. A phrase exposure is tracked against the
chunk item itself, not only against the component words.

### Pattern

A grammar construction or sentence structure.

Examples:

- German subordinate clause word order after `weil`
- Spanish `tener que + infinitive`
- French partitive article
- Italian `stare + gerund`
- Portuguese personal infinitive caution

Patterns should not be replaced inline as raw text. They should power cloze
cards, sentence recomposition, contrast choices, and tutor explanations.

### Sentence Frame

A reusable sentence skeleton for production.

Examples:

- `I would like ...`
- `I am going to ...`
- `I have to ...`
- `Can you ...?`

Sentence frames are useful for practice and tutor roleplay. They are dangerous
as automatic webpage replacement because they usually require grammar changes.

## Data Model

The core app should separate curriculum truth from learner state.

### Curriculum

```swift
enum SupportedLanguage: String, Codable, CaseIterable {
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case portuguese = "pt"
}

enum CurriculumItemKind: String, Codable {
    case word
    case chunk
    case pattern
    case sentenceFrame
}

enum ReplacementPolicy: String, Codable {
    case never
    case reviewOnly
    case ambientSafe
    case ambientAfterReview
}

struct CurriculumItem: Identifiable, Codable, Hashable {
    var id: String
    var language: SupportedLanguage
    var kind: CurriculumItemKind
    var source: SourceExpression
    var target: TargetExpression
    var level: LearningLevel
    var frequencyBand: Int
    var replacementPolicy: ReplacementPolicy
    var dependencies: [String]
    var ambiguityNotes: [String]
    var explanations: [LocalizedExplanation]
    var examples: [ExampleSentence]
    var reviewTemplates: [ReviewTemplateID]
}
```

### Learner State

```swift
struct LearnerProfile: Codable {
    var activeLanguage: SupportedLanguage
    var languageStates: [SupportedLanguage: LanguageLearningState]
}

struct LanguageLearningState: Codable {
    var isEnabled: Bool
    var replacementDensity: ReplacementDensity
    var blockedHosts: Set<String>
    var itemStates: [CurriculumItem.ID: ItemLearningState]
    var generatedArtifacts: [GeneratedArtifact.ID: GeneratedArtifact]
}

struct ItemLearningState: Codable {
    var status: ItemStatus
    var firstSeenAt: Date?
    var lastSeenAt: Date?
    var exposureCount: Int
    var recognition: ReviewStats
    var recall: ReviewStats
    var cloze: ReviewStats
    var production: ProductionStats
    var nextReviewAt: Date?
    var difficulty: Double
    var blockedContexts: [BlockedContext]
}
```

The important change is that exposure no longer means progress. Exposure unlocks
review eligibility. Review performance drives mastery and future replacement
priority.

## Closed Learning Loop

Every feature should feed the same loop:

1. `Select`
   The scheduler chooses eligible items for the current language based on level,
   dependencies, review due status, recent failures, site policy, and density.

2. `Encounter`
   Safari replaces a small number of safe words/chunks in eligible text blocks.
   The content script records exposure events by item ID only.

3. `Notice`
   Hover/focus cards show source, target, explanation, and optional quick action.
   No raw page text leaves the page.

4. `Review`
   The dashboard creates short retrieval tasks from due items. Review results
   update recognition, recall, cloze, and production stats.

5. `Generate`
   The LLM generates examples, cloze cards, distractors, or tutor feedback from
   bounded item context and learner state.

6. `Validate`
   Generated content is parsed through structured output, checked against
   language/item rules, cached, and either used as a review artifact or rejected.

7. `Promote`
   Items move from exposure to recognition, recall, cloze, production, and
   eventually strong. Future Safari replacement preference changes accordingly.

8. `Adapt`
   The next page replacement batch prioritizes items that are useful, due, and
   safe, while avoiding items that caused confusion or bad contexts.

No subsystem should be a dead end. Tutor chats, hover cards, reviews, and page
exposures should all write back to the same `ItemLearningState`.

## Word And Curriculum Production Pipeline

There should be two content pipelines: offline pack production and runtime
personalization.

### Offline Pack Production

This creates the bundled trusted curriculum.

1. Seed candidate list
   Start from frequency lists, CEFR/A1-A2 curriculum targets, competitor-style
   starter concepts, and manually chosen high-safety source expressions.

2. Generate target candidates
   Use OpenAI with structured outputs to create target translations,
   explanations, examples, ambiguity warnings, and suggested review modes for
   each language.

3. Validate mechanically
   Reject items that fail schema validation, duplicate IDs, empty examples,
   unsupported item types, overlong source strings, or banned replacement
   policies.

4. Validate linguistically
   Run a second model pass that critiques the candidate in the target language:
   "Is this natural? Is it too ambiguous? Is it safe for ambient replacement?"
   Treat this as a review signal, not proof.

5. Validate for matching
   Test every source expression against a corpus of English sample sentences to
   estimate false positives. Flag prepositions, pronouns, and short ambiguous
   words.

6. Human spot-check
   For beta, manually inspect the first 300-500 items across five languages.
   This is cheaper than debugging broken learning trust after launch.

7. Freeze pack
   Commit the generated JSON fixtures and Swift/JS generated bundles. The app
   should not need the model to know the base curriculum.

### Runtime Personalization

This adapts content per learner without mutating the canonical pack.

1. Detect need
   The scheduler sees due items, repeated failures, or a learner asking the
   tutor about a concept.

2. Request artifact
   The app asks the model for a specific artifact: cloze card, distractors,
   micro-dialogue, example sentence, explanation, or production prompt.

3. Validate artifact
   The app validates schema, item IDs, target language, source language,
   difficulty, length, banned characters, and required answer.

4. Cache artifact
   Store the artifact under `generatedArtifacts` with model, prompt version,
   source item IDs, and validation status.

5. Use in review
   Present the artifact. Record learner outcome against the underlying item,
   not just the generated card.

6. Retire bad artifacts
   If the learner reports confusion, fails repeatedly, or the answer is
   disputed, retire the artifact and reduce confidence for that item/context.

Runtime generation should produce practice, not curriculum truth.

## LLM Integration Points

### 1. Pack Builder

Purpose: generate candidate curriculum items offline.

Runtime: developer/admin tool, not app UI.

Output: strict structured JSON.

Risk: bad translations become product truth.

Mitigation: validation, second-pass critique, manual spot-check, versioned packs.

### 2. Exercise Generator

Purpose: create review cards from trusted items.

Runtime: app background task or on-demand when the Learn screen opens.

Output examples:

- cloze card
- multiple-choice distractors
- sentence recomposition item
- contrast card
- short production prompt

Risk: generated exercise has wrong answer or introduces unseen grammar.

Mitigation: require source item IDs, known answer, allowed vocabulary level, and
short output. Cache only validated artifacts.

### 3. Tutor

Purpose: answer learner questions and give bounded feedback.

Runtime: live OpenAI call.

Context:

- active language
- selected item
- known related items
- learner question
- optional selected page snippet only when the user explicitly opts in

Risk: overexplaining, wrong correction, accidental page-data upload.

Mitigation: bounded prompt, no automatic page text, short responses, cite the
specific item, offer one correction at a time.

### 4. Production Feedback

Purpose: evaluate learner-written sentences.

Runtime: live or delayed OpenAI call.

Output:

- accepted/retry
- one corrected sentence
- one explanation
- one next prompt

Risk: inconsistent grading.

Mitigation: rubric-based structured output. Do not let this alone mark an item
as mastered; combine with repeated successful attempts.

### 5. Candidate Expansion

Purpose: suggest what the learner should see next.

Runtime: background, after enough learner history exists.

Output:

- candidate item IDs from existing pack
- proposed new chunks for later review
- pattern recommendations

Risk: curriculum drift.

Mitigation: existing pack IDs are allowed immediately; new generated items are
quarantined until validated.

## Structured Output Contract

Use OpenAI structured outputs for all generation that writes to app state.
OpenAI documents structured outputs as schema-constrained responses, which is
the right primitive for pack building and generated review artifacts. Still,
schema-valid is not the same as semantically correct, so every output needs app
validators after model parsing.

Required validators:

- schema parse
- enum/domain validation
- language ID validation
- item ID existence
- max length
- source expression safety
- target expression non-empty
- answer consistency
- no raw page text unless explicitly requested
- prompt version recorded
- model version recorded

The app should treat model output as untrusted input.

## Review System

Flashcards should be one review format, not the review system. The review
engine should choose formats based on item type and learner state.

### Review Modes

`recognition`

- Prompt: "What does `pero` mean here?"
- Best for first retrieval after exposure.
- Fast, low friction, good for beta.

`reverseRecall`

- Prompt: "How do you say `but` in Spanish?"
- Harder than recognition.
- Useful before marking a word as stable.

`cloze`

- Prompt: `Quiero cafe ___ te.`
- Best for chunks, prepositions, conjunctions, and grammar patterns.

`contrast`

- Prompt: choose between two nearby forms.
- Good for false friends, gender, prepositions, verb constructions.

`recomposition`

- Prompt: reorder short chunks into a target sentence.
- Good bridge from recognition to production.

`microProduction`

- Prompt: "Write one tiny sentence using `porque`."
- Model gives one correction and one rule.
- Best after a learner has already recognized the item multiple times.

### Scheduling

Start with a simple deterministic scheduler before adopting a complex SRS
algorithm.

Recommended beta intervals:

- New exposure: review after 10-60 minutes or next app open.
- Correct recognition: review tomorrow.
- Incorrect recognition: review later today.
- Correct recall/cloze: review in 3 days.
- Correct production: review in 7 days.
- Strong item: review in 14-30 days and reduce ambient priority.

Inputs:

- item status
- last exposure
- review accuracy
- item difficulty
- current replacement density
- number of due reviews
- recent learner fatigue

Outputs:

- due item queue
- suggested review mode
- next review time
- replacement priority modifier

### Progression

Progression should be per item, not per tier only:

```text
locked -> available -> seen -> recognition -> recall -> cloze -> production -> strong
```

Not every item needs every stage. A function word might only need recognition
and cloze. A sentence frame should require guided production before it becomes
strong.

## Safari Extension Strategy

The current extension should remain conservative.

For beta:

- Replace words and exact `ambientSafe` chunks automatically.
- Keep one replacement per block by default.
- Keep sensitive exclusions.
- Keep page text inside the content script.
- Report only item ID, host policy, and exposure increment.
- Run phrase matching before word matching so larger chunks win over component
  words.

Add later:

- language-specific replacement density
- item-kind awareness
- max replacement length
- context denylist by source expression
- user "bad replacement" report action

Do not do:

- model calls from content script
- automatic sentence rewriting
- live grammar transformation
- hidden upload of page context

### Matching Order

The transformer should eventually match in this order:

1. exact safe chunks
2. high-priority due words and chunks
3. low-exposure new words and chunks
4. reinforcement items due for review

It should never match substrings inside existing managed tokens, editable text,
code, controls, or sensitive forms.

## UI And UX Shape

### Onboarding

First-run flow:

1. choose target language
2. choose comfort level: gentle, normal, active
3. enable Safari extension
4. enter or connect OpenAI access
5. open test page

The language choice should be easy to change, but the app should strongly
encourage one active language at a time. Supporting simultaneous languages will
complicate scheduling, vocabulary, replacement density, and page readability.

### Overview

Show the loop, not just stats:

- active language
- reviews due
- words/chunks seen today
- current focus items
- Safari status
- tutor status

### Learn

This should be the main review surface.

Structure:

- due now
- quick review session
- item detail after answer
- ask tutor
- finish summary

The Learn screen should feel like a 3-5 minute task, not a course dashboard.

### Vocabulary

Vocabulary should become "Library" or "Words & Phrases" once chunks and
patterns exist.

Filters:

- all
- words
- chunks
- patterns
- due
- weak
- strong
- blocked

Columns:

- source
- target
- kind
- status
- seen
- next review
- accuracy

Detail:

- examples
- explanation
- review history
- generated artifacts
- report bad item
- ask tutor

### Tutor

Tutor should not be a blank chat first. It should be contextual:

- selected item
- "explain"
- "give examples"
- "quiz me"
- "check my sentence"
- optional selected-text mode

The blank input can exist, but the default should route through known learning
objects.

### Settings

Settings must expose product-risk controls:

- active language
- replacement density
- pause
- site blocklist
- OpenAI connection
- privacy: page text sending off by default
- reset language progress
- export diagnostics

## Engineering Migration Path

### Step 1: Introduce Generic Curriculum Types

Add `SupportedLanguage`, `CurriculumItemKind`, `CurriculumItem`,
`LanguagePack`, and `ItemLearningState` alongside the existing German
`CurriculumWord`. Do not remove old types immediately.

### Step 2: Generate German Pack From Existing Data

Map the current 12 words into the new model. Tests should prove old behavior is
unchanged.

### Step 3: Update Learning State

Move from `exposureCounts: [String: Int]` to
`itemStates: [CurriculumItem.ID: ItemLearningState]`, with migration from old
storage.

### Step 4: Update Extension Payload

Send unlocked/eligible `CurriculumItem` records to the extension instead of
hard-coded starter words. Keep JS matching deterministic.

### Step 5: Add Review Scheduler

Create due queues and record review attempts. Vocabulary stops deriving recall
from exposure count.

### Step 6: Add Five Language Packs

Ship small but consistent starter packs:

- 80-120 words per language
- 20-40 chunks per language
- 10-20 patterns per language for review only

### Step 7: Add OpenAI Exercise Generation

Generate cloze and contrast review cards from trusted items. Cache outputs with
prompt and model metadata.

### Step 8: Add Production Feedback

Add short writing checks after recognition/cloze are stable.

## Edge Cases And Failure Modes

### Bad Translation

Mitigation:

- canonical packs are versioned
- generated artifacts are separate from canonical items
- users can report bad item
- item can be remotely disabled in future manifest

### Ambiguous Source Word

Mitigation:

- `replacementPolicy` can be `reviewOnly`
- source expressions can have blocklisted contexts
- phrase matching can disambiguate before word matching

### Too Many Languages

Mitigation:

- one active language at a time
- language state is isolated
- app UI always scopes stats and reviews to active language

### Generated Exercise Is Wrong

Mitigation:

- structured output
- answer consistency validation
- short artifacts
- user report action
- retire bad artifact without changing item truth

### Page Text Privacy

Mitigation:

- no page text in default extension messages
- selected-text tutor mode must show what will be sent
- generated review uses curriculum items, not arbitrary page content

### Review Overload

Mitigation:

- daily cap
- short sessions
- scheduler throttles new exposure when reviews are overdue

### Replacement Annoyance

Mitigation:

- density controls
- per-site block
- per-item block
- hover original
- quick pause

### State Migration

Mitigation:

- versioned learning state
- one-way migration from old exposure counts
- tests for reset, persistence, and extension message compatibility

## Beta Scope

The realistic paid beta should include:

- five active languages
- one active language at a time
- bundled starter packs
- deterministic inline replacement for safe words
- automatic exact phrase/chunk replacement where safe
- Learn screen with recognition and cloze
- Vocabulary/Library with item kinds and real review state
- OpenAI tutor for selected item questions
- OpenAI-generated review artifacts after validation
- no live sentence rewriting
- no model-generated curriculum promotion without validation

The beta should not include:

- all-language parity at high depth
- freeform model-generated active curriculum
- automatic page-context upload
- full grammar course
- speech
- native-app text replacement outside Safari
- multi-language simultaneous learning

## Recommended First Starter Pack Sizes

For each of the five languages:

- 80 high-frequency ambient-safe words
- 30 review-first words that are too ambiguous for ambient use
- 30 safe chunks
- 15 review-only patterns
- 20 sentence frames

Total per language: about 175 items.

Total across five languages: about 875 canonical items.

This sounds large, but it is manageable if generated offline, validated with
schema and scripts, and spot-checked in batches. It is also enough for a beta to
feel materially larger than the current 12-word German deck.

## Architectural North Star

Cockatoo should become a small adaptive learning system with four explicit
domains:

1. `Curriculum`
   Trusted language packs and item graph.

2. `Learner State`
   Per-language progress, review outcomes, and scheduler state.

3. `Generation`
   LLM-generated artifacts with strict validation and caching.

4. `Surfaces`
   Safari encounter, Learn review, Library inspection, Tutor explanation.

The current app already has the right broad split between Safari and the native
dashboard. The next architecture change should make the core data model worthy
of the product: multilingual, item-kind aware, review-driven, and model-assisted
without being model-owned.
