# 00 — Current State Assessment

> Why the rebuild exists. This document records what the first-pass codebase ("Cockatoo", branch `feature/safari-inline-learning-mvp`) does today, what is worth carrying forward conceptually, and what is broken badly enough that a from-scratch rebuild beats incremental repair. File references point into the **old** repo at `/Users/daniel/Documents/Mac Language Learner`.

## What exists today

Two runtime halves:

1. **A SwiftUI dashboard app** (`Sources/MacLanguageLearner/`) with Overview, Learn, Practice, Vocabulary, Tutor, Sites, and Settings screens, backed by a shared Swift library (`Sources/LanguageLearnerCore/`).
2. **A Safari Web Extension** (`SafariExtension/Resources/`, bundled with esbuild, shipped via the generated Xcode project in `SafariApp/`) whose content script replaces a budgeted number of English words on web pages with target-language vocabulary, with a hover card showing the translation.

State is a JSON-encoded `LearningState` blob in App Group `UserDefaults` (`group.com.daniel.MacLanguageLearner.shared`), guarded by a `flock`-based file lock so the app and the extension's native handler can both mutate it (`Sources/LanguageLearnerCore/LearningStore.swift`). The extension talks to the native side via Safari native messaging (`SafariExtension/Native/SafariWebExtensionHandler.swift`, wire schema in `Sources/LanguageLearnerCore/ExtensionMessage.swift`). A local Ollama-served Qwen2.5-1.5B powers a tutor chat.

## What works — carry these forward conceptually

These are design wins. The rebuild keeps the *rules*, not necessarily the code.

### 1. The DOM transformer (`SafariExtension/Resources/lib/transformer.js`)
- **Budgeted replacement**: ~1 token per 40 words of page text, minimum 3, capped at 20 per page; per-block budget of ~1 per 25 words. Sparse enough to be non-interruptive.
- **Even distribution**: tokens are spread across blocks (`fillDistributedPage` / `evenlySpacedSubset`) rather than clumped in the first paragraph.
- **Strong exclusion rules**: never touches inputs, `contenteditable`, `code/pre/kbd/samp`, nav/header/footer/buttons, or anything inside a form whose attributes look sensitive (password/checkout/billing). Sensitive-host blocking lives in `lib/policy.js`.
- **Honest token contract**: the replaced word is a `<span>` with data attributes carrying the item ID and original text, `tabindex=0`, and an `aria-label` — accessible and restorable.

### 2. The SRS core (`Sources/LanguageLearnerCore/WordStats.swift`, `SafariExtension/Resources/lib/srs.js`)
- Leitner-style 6-box cooldown ladder: **1h → 6h → 24h → 72h → 168h → 720h**. Strength only advances when an item is *due*, so repeated glances can't power-level a word.
- **Two credit channels**: passive *seen* (viewport dwell via `IntersectionObserver`) and active *engaged* (hover/focus/click), with engagement credit capped below quiz-ready strength so hovering can never substitute for retrieval practice. This is the single most thoughtful mechanic in the codebase and survives verbatim as a rule in [04-learning-engine.md](04-learning-engine.md).

### 3. The privacy boundary
Only word IDs, exposure increments, host policy, and user commands cross from the page to the app. Raw page text never leaves the content script (captured sentences stay local). The rebuild keeps this as the *default* posture, with an explicit opt-in tier for page context ([06-llm-integration.md](06-llm-integration.md)).

### 4. The curriculum item schema (`Sources/LanguageLearnerCore/CurriculumItem.swift`)
`id / language / kind (word|chunk|pattern|sentenceFrame) / source / target / level / frequencyBand / replacementPolicy / dependencies / explanation / examples / metadata` — expressive and forward-looking. It evolves into `VocabItem` in [03-data-model-and-storage.md](03-data-model-and-storage.md).

### 5. The overall app ↔ extension shape
App Group shared storage + native messaging + a graceful `storage.local` fallback is the right architecture for a Safari-first product. The rebuild keeps the shape and replaces the storage engine and the sync protocol.

## What is broken — the rebuild's anti-goals

### 1. Two disconnected practice engines (the "totally broken" puzzles)
- **`QuizView`** (Practice tab) grades against `WordStats` via `LearningState.applyQuizResult`. **`LearnView`** grades against a *separate* `ItemLearningState` store via `ReviewScheduler.recordReview`. **Neither reads the other.** Quizzing in Practice leaves the Vocabulary table (which reads `ItemLearningState`) showing "available / —" forever; `QuizView`'s own "Due now" counter reads the store its quiz never updates (`QuizView.swift:435`).
- **Concrete bug: the correct answer is always the first button.** `ReviewCard.recognition`/`reverseRecall` build `options = [correct] + distractors` and never shuffle (`ReviewCard.swift:31,49`); `LearnView` renders in order.
- **Mastery is mathematically unreachable.** `ReviewScheduler` only ever generates 2 of 6 review modes (`ReviewScheduler.swift:60-66`), but reaching `.strong` requires cloze passes that no generator can produce (`ReviewScheduler.swift:95`).
- **Decorative fake UI**: the "repair lane" displays missed questions but never re-asks them (`QuizView.swift:355`); the "tutor checkpoint" panel is static text with no input, no grading, no model call (`QuizView.swift:372`); the hover card renders three buttons ("Examples", "Quiz me", "Ask Tutor") with no handlers (`hoverCard.js:144`). A "15-card session" is really 3–4 cards because only the current tier's items are eligible.

### 2. Vocabulary defined in three places, with no basis
- ~**13 real German items** (12 words + 1 chunk); es/fr/it/pt packs are 2-item stubs.
- The same vocabulary is defined in **three overlapping places**: hardcoded Swift (`Curriculum.swift` `StarterCurriculum` + inline pack builders in `LanguagePackRepository.swift`), JSON packs (`Resources/LanguagePacks/*.json`), and generated JS (`build-extension-curriculum.mjs` → `lib/curriculum.js`, written to two locations). Manual sync, guaranteed drift.
- `frequencyBand` is a hand-assigned integer. No frequency corpus, no CEFR grounding (everything is `a1`).
- "On-device generation" is a declared-but-unimplemented stub (`TranslationProvider.swift:113` advertises capabilities no implementation has; the only provider is a 12-word en→de dictionary lookup).

### 3. Learning logic duplicated wholesale Swift ↔ JS
SRS boxes, tier unlock, quiz readiness, and even the v2→v3 state migration exist in *both* `WordStats.swift`/`LearningState.swift` *and* `lib/srs.js`/`lib/state.js` (e.g. the `count / 5` strength migration at `state.js:57` and `LearningState.swift:104`). Two implementations of the same rules that must be kept in lockstep by hand. Several JS exports (`applyQuizResult`, `quizReadiness`, `activationCandidates`, …) have no callers; the Swift `CurriculumActivationScheduler` is called only by tests. The rebuild's fix is structural: **Swift owns all learning logic; JS is a renderer and event emitter** ([01-vision-and-principles.md](01-vision-and-principles.md), principle P1).

### 4. Extension performance
- The transformer re-runs its **entire pipeline on every non-managed DOM mutation** — full-page word count (reads `textContent` of the whole body), full `querySelectorAll` sweeps, per-word `TreeWalker`s — with **no debounce** (`transformer.js` `start`, line 105). Chatty/infinite-scroll pages re-trigger it continuously.
- The content script **polls native messaging every 2 seconds on every tab** (`runtime.js:89`), JSON-diffing state and fully restoring + re-applying the page on change. The interval is never cleared.
- The extension runs on literally every http(s) page even when nothing is eligible.

### 5. The LLM integration
- Hard dependency on a locally running Ollama with a hand-built model tag; every tutor turn fails otherwise.
- The tutor system prompt is **hardcoded German** while the app claims five languages; topic selection is wired to the 12-word starter deck.
- Output quality is patched with a **regex sanitizer** that fixes one specific grammar error the 1.5B model makes (`TutorProvider.swift:260`) — a smell, not a solution.
- The model is used *only* for tutor chat: nothing for content authoring, enrichment, or contextual inflection, which is where a model actually earns its keep in this product.

### 6. Storage and state
- One JSON blob in `UserDefaults` re-encoded wholesale on every write. Workable at 13 words; wrong at 1,000+ items with per-item SRS state, append-only exposure events, and cross-process writers.
- Legacy cruft already: dual ID systems (canonical + legacy starter IDs) with resolver shims, and a v2→v3 migration mirrored in JS. For a 13-word corpus.

### 7. Smaller correctness gaps (recorded so the redesign closes the class)
- Fire-and-forget exposure writes with silent `catch` — progress diverges quietly until the next poll.
- Naive sentence extraction mangles cloze sentences on markup-heavy blocks (`exposureTracker.js:109`).
- `isVisible` misses `opacity:0`/zero-rect elements, so tokens can be injected into invisible content and still earn "seen" credit.
- Progress denominator bug in quiz UI (`QuizView.swift:730`).
- Dead attributes/exports (`data-mll-tooltip`, `tierWords`, legacy `recordExposure` path).

## Verdict

The product concept is validated by the prototype: sparse in-page replacement with hover translation feels right, the exposure/SRS mechanics are sound, and the privacy stance is a real differentiator. But the implementation has three structural faults that incremental repair can't cheaply fix — duplicated learning logic across languages, fragmented progress state across two schemas, and vocabulary with no data foundation. Combined with a storage layer that won't scale past toy content and an LLM integration pointed at the wrong problem, **rebuild is cheaper than repair**. What we rebuild toward is defined in [01-vision-and-principles.md](01-vision-and-principles.md) through [08-roadmap.md](08-roadmap.md).
