# Prototype v2 — the sulphur-crested direction

Interactive HTML prototypes for the visual redesign
(see `docs/visual-redesign-plan.md`). Open any file in a browser; the
pill button bottom-right flips light/dark. All surfaces share one
coherent data moment: 212-item pack, tiers 1–2 unlocked, tier 1 =
11/12 known, tier 2 = 8/12 known (9 needed → 1 to go, check ready),
3 due · 1 new word.

| File | Surface |
|---|---|
| `practice-session.html` | **Playable full session arc** (phase 1): answer for real — recognition (keys 1–4), typed recall, cloze; near-miss vs wrong grading, repair re-asks growing the queue, post-answer micro chips, tier check (inspector auto-tucks, first answers count), unlock celebration + quiet fail state, session ledger, capped empty state. This is the session *after* the frames below — the 9th tier-2 word graduated, so the check runs. Motion per `motion-spec.md`. |
| `practice.html` | Practice frame: intro card, outcome-coded session strip (with a repair growing the queue 8→9), collapsible inspector (tier ring + done-stack) |
| `overview.html` | Next-action card with cap-aware exposure hints, stat tiles, tier progress + check-ready flag, extension status, stage bars |
| `library.html` | Tier-grouped table: 4-stage chips + mastered star, exposure progress ("done today"), strength dots, locked tier |
| `inpage.html` | Host article with fidelity-tier underlines (exact / form-matched / approximate) and the graphite hover card — hover/click any gold word |
| `menubar.html` | 16px mark test (template vs gold crest) on light/dark bars, due badge, dropdown |

`motion-spec.md` records durations, curves, and the Reduce Motion
table. Next: phase 3, the SwiftUI translation
(`docs/visual-redesign-plan.md`).
