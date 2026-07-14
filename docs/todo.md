# Todo

Deferred ideas and outstanding work. Redesign decisions live in
docs/plan/10-learning-redesign.md; roadmap in docs/plan/08-roadmap.md.

## Future

- **LLM-generated practice sentences** (noted 2026-07-14): generate fresh
  cloze/rebuild sentences on demand via the P6 gateway, constrained to the
  learner's known vocabulary and built around anchor words. Infinite phrase
  variety without authoring cost. Prerequisites: P6 live verification
  (needs Daniel's API key), a validation pass so generated sentences only
  use library words, and a cache/store story (sentenceStoreCap applies).
- **FSRS scheduler**: the ReviewScheduler protocol seam exists (decision
  D3). Revisit after the distinct-day gates have real usage data.

## Outstanding

- Learning-system redesign (docs/plan/10-learning-redesign.md): fully
  shipped 2026-07-14 — R1 engine, R2 app, R3 including rich examples
  (pack 2026.09: 3 authored examples per item, build-time guards, engine
  rotates cloze/rebuild across them).
- Daniel's spot review of pack 2026.08 (docs/pack-review-2026.08.md) —
  now also covers the 424 new example sentences in 2026.09.
- ~1000-item packtool author pipeline — now also carries 3–5 examples per
  item and anchor-word flags (redesign D-R3/D-R4).
- P6 live LLM verification (needs API key).
