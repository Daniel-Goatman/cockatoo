# 04 — Learning Engine

> The one review engine (P2): a single state machine, a single scheduler, and question generation that provably works for every eligible item. Replaces both prototype engines documented in [00-current-state-assessment.md](00-current-state-assessment.md) §1. Storage in [03-data-model-and-storage.md](03-data-model-and-storage.md); vocabulary source in [07-content-pipeline.md](07-content-pipeline.md).

## Stage state machine

Every item has exactly one `ItemProgress.stage`:

```
locked ──a──▶ ambient ──b──▶ ready ──c──▶ learning ──d──▶ known ──e──▶ mastered
                 │                          ▲  ▲ │
                 └────────────c'────────────┘  └f┘ (lapse loop within learning)
```

| # | Transition | Trigger | Who fires it |
|---|---|---|---|
| a | `locked → ambient` | ActivationEngine admits the item: its tier is unlocked, its `dependencies` are all ≥ `known`, and the ambient set has room | ActivationEngine (on ingestion/practice commits) |
| b | `ambient → ready` | Exposure threshold met: `seenCount ≥ 6`, **or** the engagement fast path `seenCount ≥ 3 && engagedCount ≥ 1` (defaults; tunable). Seen alone always suffices — engagement accelerates, it never gates | EventIngestor |
| c | `ready → learning` | First practice question about the item is answered (right or wrong) | Grader |
| c′ | `ambient → learning` | An **introduction question** is answered. Sessions introduce up to `sessionIntroLimit` (3) ambient items when due + ready leave room, so a fresh import can practice immediately (the cold-start path). The UI presents the word before asking; the question is recognition | SessionPlanner offers; Grader fires |
| d | `learning → known` | `srsBox ≥ 4` with at least one correct **recall** and one correct **recognition** answer | Grader |
| e | `known → mastered` | Two correct **cloze** answers at box ≥ 5 intervals | Grader |
| f | lapse | Wrong answer in `learning`/`known`: box drops by 2 (floor 1), `lapses += 1`; stage falls back to `learning` if it was `known` | Grader |

Rules:
- **Only the Grader moves `srsBox`.** Exposure events change `seenCount`/`engagedCount` and can fire transition (b) — nothing else. This is the codified "hovering can't power-level" rule inherited from the prototype's `WordStats` cap.
- `mastered` items retire from the ambient snapshot but are sampled back into sessions rarely (1 per session max) and can lapse back to `known`.
- Transitions are monotonic except the lapse edge (f). Enforced as an invariant test.

## Exposure crediting

Event taxonomy is defined in [05-extension.md](05-extension.md); crediting rules live here:

| Event | Credit | Caps / conditions |
|---|---|---|
| `seen` | `seenCount += 1` | Only counts if the token dwelled ≥ 1 s in viewport (enforced extension-side); max **3 seen credits per item per day** so one word-heavy page can't flood the counter |
| `engaged` | `engagedCount += 1` | Hover/focus ≥ 400 ms or pin; max **2 engaged credits per item per day** |
| `pinned` | counts as `engaged` | — |
| `sentenceCaptured` | stores cloze material only | no progress credit |

All ingestion is idempotent by event UUID (**R5**): re-sent batches after a crashed flush cannot double-credit.

## Scheduler

`ReviewScheduler` protocol (so FSRS can drop in later, D3):

```swift
protocol ReviewScheduler {
  func nextDue(after result: PracticeResult, progress: ItemProgress, now: Date) -> (box: Int, dueAt: Date)
  func isDue(_ progress: ItemProgress, now: Date) -> Bool
}
```

**`LeitnerScheduler`** (v1): the proven 6-box ladder — intervals **1h, 6h, 24h, 72h, 168h (7d), 720h (30d)** for boxes 1–6. Correct while due → box + 1; correct while not due → no change (early review doesn't advance); wrong → lapse rule (f). Jitter of ±10% on intervals to avoid review pile-ups.

## ActivationEngine

Controls what becomes ambient (transition a) and when tiers unlock.

- **Ambient set size**: keep **8–15 items** in `ambient` at once (below the page replacement cap of 20 so a rich page can show most of the working set plus due `learning` items).
- **Admission order** within the unlocked tier: `isCore`/priority metadata first, then ascending `frequencyBand`, then corpus rank.
- **Dependency gating**: chunks/patterns require every ID in `dependencies` to be ≥ `known`.
- **Tier unlock is quiz-gated, never a background flip**: when **≥ 70% of tier N items are ≥ `known`** and at least 7 days have elapsed since tier N unlocked (comfort takes time, not just correct answers), the next practice session ends with a **tier-check burst** — the `tierCheckQuestionCount` (3) weakest current-tier items, normal mode ladder, riding on top of the session target. Passing (every check question correct on its first ask — repairs don't count; `SessionPlanner.tierCheckPassed`) fires `LearnerEngine.unlockNextTier`, which re-validates the condition server-side (P1) before unlocking and admitting new items. A miss lapses the item as usual, readiness self-corrects, and the check reappears in a later session.
- **Demotion**: if the ambient set is full and a new item is admitted, the oldest `ready` item without recent engagement yields its slot (stays `ready`, just leaves the snapshot).

## Session planner

A session is short by design (~2 minutes, P7 spirit): **default 10 questions, minimum 4** (if fewer items qualify, the session is shorter — never padded with repeats of the same question back-to-back, and never advertised as longer than it is, P4).

Sessions have a visible **arc** — warm-up → new words → mix → tier check —
where the warm-up is the 1–2 *easiest* (lowest-box) due items opening the
session and the tier check appears only when the unlock condition holds
(§ActivationEngine). Beats change ordering and framing only; **question
modes always follow the stage/box ladder** (forcing recognition for warm-ups
would starve recall and stall `learning → known` — tested by the simulated
learner).

Mix per session, in priority order:
1. All due `learning`/`known` items (up to 7; easiest 1–2 open as warm-up).
2. `ready` items awaiting their first question (up to 3).
3. `ambient` introductions, admission-ordered, filling leftover room (up to 3) — reviews always come first.
4. At most 1 sampled `mastered` item.
5. The tier-check burst (3) on top of the target, when readiness holds.

**Missed-question repair is real**: a wrongly answered item re-enters the same session's queue at position +3 (once). This implements what the prototype's "repair lane" faked.

Mode selection per item stage:

| Stage / box | Modes offered |
|---|---|
| `ready`, box 0–1 | recognition |
| box 2–3 | recognition, recall |
| box ≥ 4 | recall, cloze (cloze only if a `captured_sentence` exists; else recall) |
| `mastered` sample | cloze or recall |

## Question generation (`QuestionFactory`)

Three modes. **A mode may only be offered if it is generatable for every item that can reach it** — the generative test below makes the prototype's "unreachable mastery" bug class impossible.

- **Recognition** (target → source): show the German form; 4 options = correct source + 3 distractors. Distractors drawn from same-language items, preferring same `kind` and adjacent `frequencyBand`, never sharing the correct answer's text. **Options are shuffled with a seeded RNG; a unit test asserts the correct index is uniformly distributed across ≥ 100 generations** (this test would have caught the prototype's always-first-button bug and is a named requirement).
- **Recall** (source → target): show the English; free-text answer. Grading: case-insensitive, accent-insensitive, article-optional (`das Haus` == `Haus`), trimmed; near-miss (edit distance 1 on words ≥ 5 chars) shows the correction and counts as wrong-but-gentle: the box **holds** (scheduler `hold`, no drop, no `lapses` increment, no stage fall) but the streak resets and the item re-enters the repair lane.
- **Cloze**: a `captured_sentence` for the item with the token blanked; free-text answer graded as recall, expected answer = the *surface form that appeared in that sentence* (from `sourceForms`). Falls back to recall when no sentence exists — and the UI labels it as recall (P4: no silent degradation presented as cloze).

`Grader` applies results: writes `PracticeResult`, calls the scheduler, updates `ItemProgress`, commits in one transaction, bumps the snapshot version.

## Test plan

The engine is a pure library; it gets the deepest test investment in the project.

1. **Property tests, scheduler**: box never leaves 0–6; early correct never advances; interval monotonic in box; lapse floor respected.
2. **Generative mode-coverage test**: for a full imported pack, every item in every reachable (stage, box) state can produce every mode the planner would offer it. Kills the "4 of 6 modes never generated" class.
3. **Shuffle distribution test**: as above, correct-answer position ~uniform.
4. **Invariant tests**: `ItemProgress` invariants from [03](03-data-model-and-storage.md) hold under randomized event/result sequences.
5. **Simulated learner**: a 30-day simulation (reads pages → events, answers sessions with 85% accuracy) must unlock tier 2, produce no stuck items (item due in the past with no offerable mode), and keep the ambient set within bounds. This is Phase 1's exit criterion ([08-roadmap.md](08-roadmap.md)).
6. **Idempotency test**: replaying an event batch changes nothing.
