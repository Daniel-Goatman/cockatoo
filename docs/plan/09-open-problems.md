# 09 — Open Problems

> Design problems that are deliberately **not** solved in v1, recorded with enough analysis that future work starts from understanding, not rediscovery. Each entry states why it's hard, what v1 does instead, candidate approaches, and the criteria a solution must meet.

## OP-1: Ambient verbs

**Status: deferred (decision D11). Verbs are `replacementPolicy: reviewOnly` in v1 — they appear in practice sessions but are never swapped into pages.**

### Why verbs matter
Verbs are among the most frequent words in any text; excluding them from ambient replacement caps how much of a page Cockatoo can teach from. This is the single biggest coverage limitation in v1 and the highest-value unlock after launch.

### Why they're hard (in increasing order of severity)

1. **Conjugation is context-dependent.** "runs" → *läuft* requires knowing person and number; recoverable from the English surface form most of the time ("runs" is 3sg present), but "ran" maps to *lief* (Präteritum) or *ist gelaufen* (Perfekt) depending on register — German narrative past vs conversational past has no English cue.
2. **Tense systems don't align 1:1.** English progressive ("is running") has no German equivalent form; English present perfect ("has run") straddles German Perfekt and Präteritum; English "do"-support ("does he run?") has no German analog at all.
3. **Separable verbs break the swap model entirely.** "I get up early" → *ich stehe früh **auf*** — the German verb splits into two pieces in different sentence positions. A single-token swap cannot reorder a sentence. Roughly a third of common German verbs are separable (aufstehen, anfangen, mitkommen, …). No amount of morphological cleverness fixes this; it's a structural mismatch.
4. **Phrasal/idiomatic divergence.** "run out of milk," "run a company" — the sense-stability problem is worst for verbs.

### Candidate approaches (to be evaluated when this reopens)

**A. On-device tagger + morphological lexicon (the local non-LLM path).**
- Apple's NaturalLanguage framework (`NLTagger`) performs POS tagging and lemmatization for English **on-device, offline, in microseconds** — no training, no model to ship.
- German conjugation is irregular but *finite and enumerable*: open morphological lexicons (Wiktionary extracts, DEMorphy, Morphy/Zmorge — license review required) list every form of every common verb.
- Pipeline: English sentence → NLTagger features (lemma, POS, person/number/tense heuristics from the surface form + subject) → deterministic German generation-table lookup → inflected form.
- Properties: deterministic, testable, instant, cannot hallucinate. Limitations: only as good as the English-side feature extraction (subject detection for person agreement is the weak point), and structurally unable to handle problems 2–3.
- **Verdict so far**: viable for a conservative subset — non-separable verbs, simple present, third-person or easily-resolved subjects — rendered at the `approximate` fidelity tier (dotted marker, [01-vision-and-principles.md](01-vision-and-principles.md)).

**B. Hosted LLM contextual resolution (extends the existing opt-in path).**
- The `getContextualForm` resolver ([06-llm-integration.md](06-llm-integration.md)) already ships for nouns; verbs would reuse it. Handles problems 1–2 well. Cannot handle problem 3 within a single-token swap, but *could* handle it by returning a **multi-token edit** (replace "get up" as a chunk with *stehe … auf* placed correctly) — which requires extending the transformer's token model from swap-one-span to edit-a-range. Significant extension-side work; gated on `sendsPageText` opt-in and network.

**C. Chunk-ification (no new machinery).**
- Author frequent verb *collocations* as fixed chunks in the pack: "there is" → *es gibt* already works; "I think" → *ich glaube*, "it depends" → *es kommt darauf an*. Sidesteps conjugation entirely for high-frequency fixed expressions. Cheap, shippable incrementally through pack updates, but covers only the frozen subset.

**D. Small trained model (the "train something" option).**
- A compact seq2seq/classifier fine-tuned for English-context → German-form prediction could exceed approach A's accuracy on person/tense resolution. Deferred until A is measured: A's failure modes must be quantified first, because a lexicon+tagger that's 95% right beats a model that's 97% right but non-deterministic and needs a training pipeline. Revisit only with evidence.

### Recommended sequence when this reopens
1. Ship **C** opportunistically (pure content work, no code).
2. Prototype **A** on a fixture corpus; measure agreement accuracy per verb class; ship behind the `approximate` tier if ≥ ~95% on the conservative subset.
3. Layer **B** as the opt-in quality upgrade, evaluating the multi-token-edit extension for separable verbs.
4. Consider **D** only if A+B leave a measured, material gap.

### Acceptance criteria for any solution
- Never renders a form that misleads about the **lemma or its core meaning** (wrong inflection is tolerable at the `approximate` tier; wrong word is not).
- Separable verbs are either handled correctly (multi-token edit) or excluded — never rendered joined (*"ich aufstehe"* is worse than no swap).
- Fully deterministic fallback when offline (degrade to no-swap, never to guess).
- `approximate` marker and the fidelity-tier documentation ship in the same release (transparency requirements, [01-vision-and-principles.md](01-vision-and-principles.md)).

## OP-2: Case agreement in mixed-language sentences

**Status: explicitly out of scope for ambient swaps; partially ill-posed.**

German case (der/den/dem) is determined by a word's grammatical role *in a German sentence*. An ambient swap places a German word in an **English** sentence — the German sentence doesn't exist, so "the correct case" is often undefined rather than merely unknown. This is why nouns swap with **citation-form articles** (nominative — "das Haus") as a deliberate design (D10), not a limitation to apologize for: consistent citation forms drill gender, which is the durable, transferable fact.

Case becomes a real (well-posed) problem only when Cockatoo starts rendering **whole German clauses** (see OP-3) or when the opt-in contextual resolver constructs an implied German frame around the swap. Revisit then; until then, any "fix" would be teaching an arbitrary answer to an ill-posed question.

## OP-3: Ambient grammatical structures (the v2 ambition)

**Status: future design; the vision's "layer on grammatical structures as comfort grows" endpoint.**

The progression after words → chunks is rendering growing spans of genuine German: fixed patterns ("zum Beispiel"), then clause fragments, then full sentences for advanced learners. Open questions parked here:
- **Span selection**: which English spans are safe to render fully in German without breaking comprehension (the i+1 budget for *structures* rather than words).
- **Grammar fidelity flips**: inside a fully-German span, case/word order *must* be correct — the fidelity-tier model needs a fourth tier or a different contract for spans.
- **Generation vs authoring**: full-sentence rendering almost certainly needs the LLM path (opt-in), with authored patterns as the offline floor.
- **Dependency model**: patterns already declare word dependencies; structures need *grammar* prerequisites (a learner model of known constructions, not just known words) — a real extension of the learning engine.

## OP-4: Sense disambiguation at scale

**Status: v1 mitigates with the sense-stability filter ([07-content-pipeline.md](07-content-pipeline.md)); the residue is accepted.**

The build-time filter drops polysemous English words ("bank", "light") from ambient duty, which costs coverage. A future context-aware matcher (local embeddings or the opt-in LLM) could disambiguate per occurrence and recover those words. Not worth machinery until the pack's ambient coverage is measured as insufficient on real browsing — collect that telemetry first (locally, per P3).
