# 07 — Content Pipeline

> `packtool`: frequency list → curated, validated, versioned language pack. Replaces the prototype's 13 hand-authored items defined in three places. The pipeline is language-agnostic; German is v1's only instantiation. LLM-assisted authoring uses the same `ChatProvider` as the app ([06-llm-integration.md](06-llm-integration.md)); the deterministic core stays deterministic (P5) — the model drafts, the validator and a human gate.

## Source data and licensing (risk R6)

- **Primary frequency source**: Hermit Dave's **FrequencyWords** (OpenSubtitles-derived word frequency lists; CC-BY-SA-4.0) — colloquial, high-coverage, well-maintained. **Alternative/cross-check**: Leipzig Corpora Collection lists (CC-BY). Choose at implementation time after license review; the requirement is: license must permit derivative distribution (keeps the product door open, P8), and the choice is recorded per pack.
- **Provenance is embedded in the pack header**: source corpus + version, license, packtool version, authoring model + date. Raw inputs and their license files are vendored under `packs/sources/de/`.

## Pipeline stages

```
frequency list ──1─▶ candidates.csv ──2─▶ authored.json ──3─▶ validated pack
                                            ▲    │
                                            └─4──┘ human review diff
```

### Stage 1 — Candidate selection (deterministic)

- Take top-N source-language lemmas by corpus rank (the pipeline is **source-language-frequency driven**: we rank the *English* words the learner will encounter, then map to German — because replacement opportunities are governed by what appears on English pages).
- Assign `frequencyBand` 1–10 by rank decile; map bands to CEFR levels (1–3 ≈ A1, 4–6 ≈ A2, 7–10 ≈ B1).
- **Filters (the quality gates that make ambient replacement safe):**
  - **Sense stability**: drop or mark `reviewOnly` English words whose dominant senses diverge in German ("bank", "run", "light"). v1 mechanism: a curated stoplist + an LLM classification pass with human review of everything it flags as borderline.
  - **Inflection safety** (feeds R1a): classify by morphological risk. Safe for ambient: conjunctions, sentence adverbs, interjections, many nouns (singular/plural enumerable), fixed chunks. `reviewOnly` in v1: verbs (English tense system → German conjugation is not surface-enumerable), articles, pronouns (case system). These still appear in review sessions and unlock ambient later via patterns.
  - Profanity/sensitive-topic filter.
- Output: `candidates.csv` — `rank, sourceLemma, band, level, proposedKind, ambientSafety, notes`.

### Stage 2 — LLM authoring (via `ChatProvider`, structured output)

For each candidate, generate the full `VocabItem` draft:
- German target + `targetMeta` (gender, plural, POS, pronunciation).
- **`sourceForms`**: enumerated English surface forms each with its correct German form (`house→Haus`, `houses→Häuser`) — the offline inflection table (R1a).
- `explanation` (one sentence, learner-facing), 2–3 `examples` (source+target), `replacementPolicy` recommendation, `dependencies` for chunks.
- Batched with retries; a second **verification pass** with a different prompt (or model) re-checks each translation pair and flags disagreements for human review. Drafts are cached on disk so re-runs are incremental.

### Stage 3 — Deterministic validation (no LLM)

Hard failures block the pack:
- Schema validity; required fields per `kind`.
- **ID stability**: IDs are content-addressed (`de.word.haus` — language.kind.slug-of-canonical-target, with `-2` suffixes on collisions); every ID present in the previous pack version must persist or be explicitly tombstoned. Progress survival depends on this ([03-data-model-and-storage.md](03-data-model-and-storage.md)).
- **Surface-form collision check**: no two ambient items may claim the same match form ("like" can't belong to two items) — the matcher requires uniqueness ([05-extension.md](05-extension.md)).
- Duplicate targets flagged; homograph detection on source forms.
- Examples must contain the item's target form; example vocabulary should stay within ≤ item's band + 2 (warning, not failure).
- Dependency references must resolve to items in the same or lower band.
- Ambient items must be `ambientSafety == safe` from Stage 1.

### Stage 4 — Human review

- `packtool review` emits a markdown diff vs the previous pack version: new items, changed fields, validator warnings, and everything the verification pass flagged. Packs are **curated, not blindly generated** — the human accepts the diff before Stage 5 will run.

### Stage 5 — Emission

- `packs/build/de-2026.07.json` + sha256 checksum, header `{language, version, provenance, counts}`. The app's `Packs` module imports it transactionally with the checksum verified.

## Pack JSON schema (v1)

```jsonc
{
  "schema": 1,
  "language": "de",
  "version": "2026.07",
  "provenance": { "corpus": "FrequencyWords/OpenSubtitles 2018", "license": "CC-BY-SA-4.0",
                  "packtool": "1.0.0", "authoringModel": "…", "generatedAt": "…" },
  "items": [ { /* VocabItem — field-identical to the vocab_item row, 03 §schema */ } ]
}
```

## German v1 scope

- **~1,000 items**: ≈850 words, ≈120 chunks (fixed phrases: "es gibt", "zum Beispiel"), ≈30 patterns (reviewOnly in v1).
- Class mix skews to ambient-safe categories in bands 1–3 so early experience is smooth; verb coverage arrives as `reviewOnly` items from band 3 up.
- Target: bands 1–6 fully authored and human-reviewed; 7–10 authored + validator-clean, reviewed opportunistically.

## Language-agnosticism requirements

Adding language X later must require **no code changes**, only:
1. A frequency list + license under `packs/sources/x/`.
2. Language-specific authoring prompt parameters (what `targetMeta` contains, inflection-safety class rules — config, not code).
3. A grading config for the review engine (article list for article-optional grading, accent folding rules) shipped **inside the pack header**, so `Grader` ([04-learning-engine.md](04-learning-engine.md)) stays generic.

Anything that would violate this (a `de`-specific branch in packtool or LearnerCore) is a review-blocking defect.
