# Historical research archive

Product and pedagogy research carried over from the prototype branches so it
survives on main. This material is design history, **not the current product
contract**. It predates the ground-up rebuild and includes discarded Tutor,
runtime-model, and paid-beta directions. Current scope and architecture live in
`README.md` and `docs/plan/`; do not infer shipped features from this folder.

## Provenance

| File | From branch | Date |
|---|---|---|
| `language-learning-with-llms.md` | `feature/safari-inline-learning-mvp` | 2026-05-27 |
| `paid-beta-release-scope.md` | `feature/safari-inline-learning-mvp` | 2026-05-28 |
| `app-overview-wireframes.md` | `feature/safari-inline-learning-mvp` | 2026-05-27 |
| `multilingual-learning-architecture.md` | `feature/safari-inline-learning-mvp` | 2026-05-28 |
| `cockatoo-architecture-visual.html` | `feature/safari-inline-learning-mvp` | 2026-05 |
| `brainstorm-mockups/*.html` | `claude/language-extension-analysis-de4abe` | 2026-06 |

## What each covers

- **language-learning-with-llms.md** — the pedagogy brief: cited research on
  digital reading, lexical coverage (95–98% comprehension floor), exposure vs
  retrieval, spacing, Nation's four strands, and where LLMs help vs hurt.
  The source of "exposure primes; retrieval cements."
- **paid-beta-release-scope.md** — competitive landscape (Toucan, LingQ,
  Readlang, Language Reactor, Migaku), beta thesis, blockers, and scope cuts
  for a paid beta.
- **app-overview-wireframes.md** — full wireframe set for the dashboard
  surfaces (Overview, Learn, Vocabulary, Tutor, Sites, Settings) with visual
  language guidance (calm, adult, no streak pressure).
- **multilingual-learning-architecture.md** — the five-language (es/fr/de/it/pt)
  curriculum-graph architecture direction; "the app owns truth, the model
  proposes."
- **brainstorm-mockups/** — an interactive design-decision series on the
  practice/quiz experience, in order. Open in a browser. The series converged
  on: unified practice surface (01), a session arc — warmup → mix → tier
  check → release (02), the "Core Five" modes: recognition, recall, cloze,
  sentence rebuild, quick self-grade (03), tutor as coach-drawer + one
  end-of-session checkpoint (04), miss handling = show-then-repair-later plus
  a tutor checkpoint on one shaky item (05), progression feedback = card
  micro-progress chips + a tier journey map, ledger only at session end (06),
  motion language = slide/stack base, collapse-to-progress on success, flip
  for reveals (07), and a full quiz/progress cockpit mockup, including the
  rule that a locked quiz must always say *why* it's locked and what to do
  next (08).
