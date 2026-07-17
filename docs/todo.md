# Todo

Deferred ideas and outstanding work. Redesign decisions live in
docs/plan/10-learning-redesign.md; roadmap in docs/plan/08-roadmap.md.

## Future

- **Optional live-provider pack adapter:** schema-2 accepted source,
  deterministic builds, provenance, review records, agent instructions, and an
  offline Spanish fixture now ship. A future contributor-only adapter may call
  a provider, but Cockatoo has no runtime model gateway or API-key setting.
- **FSRS scheduler**: the ReviewScheduler protocol seam exists (decision
  D3). Revisit after the distinct-day gates have real usage data.

## Outstanding

- Learning-system redesign (docs/plan/10-learning-redesign.md): fully
  shipped 2026-07-14 — R1 engine, R2 app, R3 including rich examples
  (pack 2026.10: 3 authored examples per item, build-time guards, engine
  rotates cloze/rebuild across them).
- Complete Daniel's checksum-bound 50-item spot review
  (`docs/pack-review-2026.10.md`). Its deterministic sample covers all forms,
  metadata, explanations, and 150 examples, including 100 examples added in
  the rich-example expansion. Then migrate German from its legacy generator to
  the canonical accepted-source workflow in a future content release.
- Expand the German starter pack from 212 items toward the production target
  of ~1,000 reviewed items. The pipeline already carries 3–5 examples per item
  and anchor-word flags (redesign D-R3/D-R4).
- Production-size second language. Active-language selection and
  progress-preserving switching now ship; the small Spanish fixture proves the
  runtime and authoring boundary but is not a complete course.
