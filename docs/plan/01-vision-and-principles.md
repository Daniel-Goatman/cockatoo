# 01 — Vision and Principles

> What Cockatoo is, what it refuses to be, and the rules every other document must obey.

## Product vision

Cockatoo teaches you a language **while you do what you were already doing**. Its core surface is a Safari extension that quietly swaps a small, budgeted number of words on the pages you read with their target-language equivalents. Hovering shows the translation. That's the whole interruption model: zero tasks, zero notifications, zero "time to practice!" — the language comes to you inside your own reading, at a density low enough that comprehension never breaks.

Depth is available *on request*, never pushed: hover a word for its translation; click through for explanation, forms, and examples; open the companion Mac app for a two-minute review session, a vocabulary library, or a tutor conversation. The app owns truth — vocabulary, progress, scheduling — and the extension renders it.

Difficulty layers on with demonstrated comfort. You start with high-frequency, sense-stable words whose swap costs nothing to understand ("and" → "und", "but" → "aber"). As exposure and successful retrieval accumulate, the system unlocks lower-frequency vocabulary, multi-word chunks ("there is" → "es gibt"), and eventually grammatical patterns. **Simple lexical swaps come before foreign grammar** — you never meet a structure whose parts you don't already know.

## Learning philosophy

- **Comprehensible input, engineered.** A page with 3–20 swapped words out of thousands is i+1 by construction: everything around the unknown word is context. The replacement budget is a pedagogical parameter, not just a UX one.
- **Frequency-first.** Vocabulary order comes from real corpus frequency data mapped to CEFR bands, because the top ~1,000 words cover the bulk of running text. See [07-content-pipeline.md](07-content-pipeline.md).
- **Exposure primes; retrieval cements.** Ambient encounters (seeing, hovering) prepare a word; only active retrieval (short review sessions) advances its scheduled strength. Hovering can never power-level a word — this cap is a hard rule inherited from the prototype ([04-learning-engine.md](04-learning-engine.md)).
- **Spacing over cramming.** A Leitner cooldown ladder (1h → 720h) spaces reviews; items surface in the browser and in sessions when due, not when convenient for a streak counter.
- **Dependencies before structures.** Chunks and patterns declare the words they're built from and unlock only when those are known.

## Design principles

These are binding on all other documents. Each has a number; later docs cite them.

- **P1 — Swift owns all learning logic; JS renders and reports.** Every rule about SRS, eligibility, tiers, mastery, and scheduling lives in one Swift library (`LearnerCore`). The extension receives a precomputed *snapshot* of what to render and emits raw *exposure events*. No learning rule is ever implemented twice. (Kills the drift disease documented in [00-current-state-assessment.md](00-current-state-assessment.md) §3.)
- **P2 — One progress store.** A single `item_progress` record per vocabulary item is the only place progress exists. Every surface (extension, review sessions, library, dashboard) reads and writes it. (Kills the dual-engine fragmentation, §1.)
- **P3 — Local-first; cloud is opt-in and tiered.** Everything core — replacement, hover, review, progress — works with no network and no API key. LLM features are annotated by privacy tier (`localOnly` / `sendsWordIds` / `sendsPageText`) and the last tier is hard-gated behind an explicit user opt-in. See [06-llm-integration.md](06-llm-integration.md).
- **P4 — No fake UI.** A control that renders must function; a mode that's advertised must be generatable for every eligible item; a number on screen must come from real data. If a feature isn't built, it doesn't appear. (Kills the decorative panels, §1.)
- **P5 — Deterministic core, model as assistant.** The curriculum, scheduler, and progress rules are deterministic and testable. The LLM proposes, explains, enriches, and generates practice material — it never mutates canonical curriculum or progress directly.
- **P6 — Provider-agnostic model access.** One OpenAI-compatible chat client (configurable base URL + key + model) serves OpenRouter, OpenAI, llama.cpp server, and Ollama alike. No provider-specific code paths.
- **P7 — Non-interruptive above all.** The extension must never make a page feel broken, slow, or unsafe: hard replacement budgets, strict exclusion zones (inputs, code, sensitive forms/hosts), incremental processing with explicit perf budgets, and visible-but-subtle marking of swapped tokens so imperfect grammar reads as "vocabulary card in place," not corrupted prose.
- **P8 — Personal tool first, product door open.** Built for one user now. The things that keep the door open — versioned language packs, stable item IDs, the provider abstraction, a portable extension core — are in scope. Monetization, onboarding polish, and licensing are not.

## Anti-goals

- **Not a Duolingo clone.** No streaks, XP, leagues, mascot guilt, or gamification theater. The reward is reading a page and understanding the German in it.
- **No decorative UI.** (P4, stated twice because it was the prototype's worst habit.)
- **No task interruption.** Cockatoo never asks for time; it accepts it when offered.
- **No page-text exfiltration by default.** (P3.)
- **No second implementation of any learning rule.** (P1.)
- **No legacy migration.** The rebuild does not import prototype state — 13 words of progress is disposable. One ID scheme from day one. (See [03-data-model-and-storage.md](03-data-model-and-storage.md).)
- **Not a translation tool.** Cockatoo swaps *known-curriculum* items; it is not a general translator and shouldn't grow page-translation features.

## Glossary

Used consistently across all documents.

| Term | Meaning |
|---|---|
| **Item** | One vocabulary unit (`VocabItem`): a word, chunk (multi-word phrase), or pattern. Identified by a stable content-addressed ID (e.g. `de.word.haus`). |
| **Pack** | A versioned, validated JSON file of items for one language, produced by the content pipeline and imported into the app's database. |
| **Tier / band** | `frequencyBand` — the item's difficulty stratum derived from corpus frequency (band 1 ≈ most frequent). Tiers unlock progressively. |
| **Stage** | An item's position in the unified learning state machine: `locked → ambient → ready → learning → known → mastered`. |
| **Ambient** | Stage in which an item is eligible for in-page replacement in Safari. |
| **Seen** | Passive exposure credit: the token dwelled in the viewport. |
| **Engaged** | Active exposure credit: the user hovered/focused/pinned the token. Capped; never advances SRS. |
| **Snapshot** | The versioned, precomputed slice of active items (with surface-form match table and hover content) that LearnerCore hands the extension. The extension's entire knowledge of the curriculum. |
| **Event** | An append-only, idempotent exposure record (`seen`, `engaged`, `sentenceCaptured`, …) emitted by the extension and ingested by LearnerCore. |
| **Session** | A short (~2 min) review session in the app: recognition, recall, and cloze questions over due items. |
| **Enrichment** | Cached LLM-generated depth content for an item (forms, examples, mnemonic, deep-dive). |
