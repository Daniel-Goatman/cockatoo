# 10 — Learning-system redesign: practice-first intake

Decided 2026-07-14 with Daniel after a critical assessment of the learning +
ongoing-exposure system. Supersedes the phase/tier design in 04 where the two
conflict; 04 remains authoritative for everything not touched here (grading,
repair lane, session arc, snapshot protocol).

## The problem

A motivated learner cannot practice as much as they want. Three stacked
throttles cause it:

1. **Tier gating** — only `frequencyBand <= unlockedTier` items can enter
   ambient. Band 1 of pack 2026.08 has 12 items; tier 2 needs 70% known plus
   a hard 7-day calendar floor. Week-one vocabulary universe: 12 words.
2. **Due-only planning** — sessions serve due + ready + ≤3 intros. A second
   session minutes later has nothing due, so it yields ≤3 questions. The
   planner conflates "nothing due for credit" with "nothing to practice".
3. **Exposure thresholds** — ambient→ready needs 6 seen credits at 3/day.
   The intro path (c') already bypasses this; the ladder only slows intake.

At the same time, "knowing" is under-evidenced across days: boxes 1→2→3 span
1h + 6h, so a word can reach box 3 in one afternoon and `known` on day 2 with
most evidence from a single day. Unlimited practice must not make that worse.

What is already right and must be kept: the scheduler's asymmetry — correct
while not due never advances; wrong always lapses. Extra reps are already
harmless to SRS state. The redesign changes what the planner *serves* and
what promotion *requires*, not that guard.

## Decisions

**D-R1 — Practice-first intake.** New words debut in practice sessions,
highlighted as new, and join the library immediately. Web pages reinforce
after introduction (swap set = library items below mastered). Exposure
*crediting* is deleted; the phase ladder (locked/ambient/ready) goes with it.

**D-R2 — Distinct-day gates.** At most one box advance per word per calendar
day, stacked on top of the Leitner cooldowns. Promotion to `known`
additionally requires correct answers on ≥3 distinct calendar days. This
encodes "understanding across multiple days" directly and makes unlimited
same-day practice provably unable to inflate mastery.

**D-R3 — Drip + milestones.** Continuous frequency-ordered intake at a
tunable rate (auto-throttled when review debt is high), with hand-picked fun
anchor words mixed in so sentences/phrases can be built around them. Band
completion becomes a celebration event, never a gate. The tier-check quiz
machinery (gating form) is removed; its celebration UI is repurposed.

**D-R4 — Phrases are central.** Three tracks, all accepted:
- *Rich examples*: 3–5 authored examples per item in the ~1000-item pack
  pipeline, so cloze/rebuild stop recycling one sentence.
- *Phrases as first-class items*: chunks/collocations are scheduled items in
  their own right, introduced once component words are ≥ `learning` (was
  ≥ `known`). Requires fixing the `reviewOnly` activation gap — those items
  enter the library via practice even though they are never swapped in-page.
- *Sentence-weighted sessions*: once cloze/rebuild material exists for an
  item, sentence modes are weighted above bare recognition/recall so most
  reps happen inside a phrase.

LLM-generated sentences (P6 gateway constrained to known vocab) are a future
todo, not part of this redesign — see docs/todo.md.

## Target design

### Stages

`new → learning → known → mastered`. Library membership = the item has been
introduced in practice. `locked`, `ambient`, `ready` are removed. `new` is
transient: the intro question is answered in-session, so the item is
`learning` by session end. The UI marks recently introduced items as new.

### Intake drip

- `newPerDay` tunable (proposed default 5, range ~2–15; open question below).
- Auto-throttle: introductions pause (or halve) when due-review debt exceeds
  a threshold, so reviews never drown.
- Order: ascending frequency band, then id — with pack-flagged anchor items
  allowed to jump the queue so a fun word arrives alongside the base words
  (oder, aber, …) that its phrases are built from.
- Phrase items become eligible the moment their dependencies are ≥ learning.

### Sessions are never empty

Priority: (1) due reviews, (2) new introductions within the drip budget,
(3) reinforcement reps of non-due library items. Reinforcement reps go
through the normal grader: they cannot advance a box (early-review guard +
D-R2), but a wrong answer still lapses — evidence of not-knowing is valid
anytime. The session arc (warm-up / new words / mix / release) is unchanged;
the tier-check beat is removed.

### Promotion rules

- Box advance: correct AND due AND no prior advance for this item today.
- `learning → known`: box ≥ knownMinBox AND recognitionCorrect ≥ 1 AND
  recallCorrect ≥ 1 AND correct answers on ≥ 3 distinct days.
- `known → mastered`: unchanged (cloze ×2 at box ≥ 5), now inheriting the
  distinct-day advance gate implicitly.
- Schema additions to ItemProgress: last-advance day marker + distinct
  correct-day count (exact fields at implementation time).

### Extension / snapshot

Swap set = `learning` + `known` (mastered still evicted). Hover keeps the
example-rich form for recently introduced items. `seen`/`engaged` events no
longer credit progress; keep ingesting them for a "seen in the wild" stat
(display-only), and keep `sentenceCaptured` as cloze material.

### Milestones

When a band reaches 70% ≥ known, emit a milestone (non-gating) and celebrate
with the existing ring+bloom moment. No calendar floor, no quiz gate.

## Deleted vs kept

| Deleted | Kept |
| --- | --- |
| ambient/ready stages, exposure crediting + daily caps, ready thresholds | Leitner ladder + early-review guard, near-miss hold |
| almostReady / ExposureNeed dashboard surfaces | repair lane, session arc, self-grade release beat |
| tier unlock gate, 7-day floor, tier-check beat, unlockNextTier | 70% fraction (as milestone trigger), celebration UI |
| dependency gate at ≥ known | dependency gate at ≥ learning |

## Migration

Existing `learning/known/mastered` rows are untouched. `ambient`/`ready`
rows return to un-introduced (not in library); they re-enter via the drip,
which starts past everything already introduced. `seenCount`/`engagedCount`
are retained as legacy display stats. `unlockedTier` is ignored.

## Open questions (small, decide during implementation)

- `newPerDay` default, and whether an in-session "more new words" control
  can raid tomorrow's budget.
- Reinforcement-rep selection: weakest-first vs recent-miss-first vs mixed.
- Whether "seen in the wild" counts surface per-word or as a daily aggregate.

## Implementation phases

- **R1 (engine)**: stage collapse + migration, drip, distinct-day gates,
  never-empty planner, delete exposure crediting, milestone event. Rework
  ColdStartTests/TierCheckTests/IngestionTests; extend SimulatedLearner with
  a binge-practice learner asserting mastery cannot be crammed.
- **R2 (app)**: new-word highlight, drip setting, milestone celebration,
  remove exposure/almost-ready surfaces, endless "keep going" session flow.
- **R3 (phrases)**: rich-examples pack pipeline, first-class chunk items +
  reviewOnly activation fix, sentence-mode weighting.
