# Critical Assessment — UX, Progression, and Where to Take Cockatoo

Date: 2026-07-11. Scope: full codebase (LearnerCore, app UI, extension, packs,
docs) plus the prototype-branch research now ported to [research/](../research/).
Test state at time of writing: 63 Swift + 32 extension tests, all green.

> **Historical assessment:** later work resolved several findings and removed
> the Tutor/runtime model experiment. Use the root README and `docs/plan/` for
> current product and architecture claims.

## TL;DR

The engineering is unusually disciplined — one engine, one progress store,
honest UI, real tests, a strong privacy posture, and the best internal docs
this kind of project ever has. But the product currently optimizes for
*steady-state correctness* and ignores the *first week of use*. A new user
imports a pack and gets: an empty practice screen, a dashboard of zeros, and
no explanation of what will change or when. The progression gates are
mathematically incapable of offering any practice on day 1, hover-engagement
is a hard, undiscoverable requirement for ever unlocking practice, and no
surface shows the one thing an early user needs: *how close each word is to
becoming practicable*. The fix is not "make everything faster" — it's a
cold-start path, softer exposure gates, and progress visibility. The
prototype-branch brainstorm series (research/brainstorm-mockups/) already
designed most of the right answers.

## 1. How it works (verified against code)

- Pack import seeds `vocab_item` rows; `ActivationEngine` promotes up to 15
  `ambientSafe` items in unlocked tiers to `ambient` (tier 1 = 12 items, so
  all of tier 1, 3 slots idle).
- The Safari extension renders swaps from a versioned snapshot (stages
  ambient…known) and reports idempotent exposure events: `seen` (≥1 s, ≥50%
  viewport dwell, once per token per page, credit-capped 3/day/item),
  `engaged` (hover/focus ≥400 ms or pin, capped 2/day/item),
  `sentenceCaptured` (cloze material, no credit).
- `ambient → ready` requires **seen ≥ 6 AND engaged ≥ 2**.
- Practice sessions select: due learning/known (≤7), ready (≤3), 1 mastered.
  First answer moves ready → learning. Leitner ladder 1h/6h/24h/72h/168h/720h;
  correct-while-due advances, early answers don't, lapse drops 2 boxes.
- `learning → known` at box ≥ 4 with ≥1 correct recognition and recall;
  `known → mastered` after 2 cloze passes at box ≥ 5.
- Tier N+1 unlocks when 70% of tier N is ≥ known (plus a 7-day minimum
  interval — which never applies to tier 1→2, see §6).

## 2. What is genuinely strong

- **Architecture**: LearnerCore as the single rule owner (P1/P2) fixed the
  prototype's dual-engine disease for real. The CFMessagePort IPC + stateless
  appex + versioned snapshot + idempotent event queue is the right shape and
  is verified on-device including the app-down drill.
- **Test culture**: shuffle-distribution, generative mode coverage,
  idempotency, invariants, snapshot size bound, shared protocol fixtures on
  both sides, and a 30-day simulated learner. This is rare and worth
  protecting.
- **Honesty as a design system** (P4): the popup admits when the app is down;
  cloze degrades to recall *labelled* as recall; onboarding states the
  fidelity-tier deal plainly.
- **Privacy boundary**: local-first, page text hard-gated server-side, key in
  Keychain. A real differentiator per the market research.
- **The pedagogy core is research-aligned** in steady state: exposure primes,
  retrieval cements, spacing over cramming, no hover power-leveling.

## 3. The core problem: the first week is a dead end

### The math of day 1 (config defaults)

Practice only ever offers `ready`, due `learning/known`, or `mastered` items.
A fresh install has none and **cannot create any on day 1**:

- `seen` credit caps at 3/day/item → `seen ≥ 6` is reachable on **day 2 at
  the absolute earliest**, and only if the user encounters the word on 3+
  qualifying pages both days.
- `engaged ≥ 2` is a **hard AND**. A user who reads but never hovers a swapped
  word for 400 ms will **never unlock practice for any word, ever**. Nothing
  in the product says hovering is load-bearing — onboarding frames hover as a
  reassurance ("see the original"), not as the mechanic that graduates words.
- So the honest day-1 experience is: Overview all zeros, Practice = "Nothing
  due right now", Library all grey dots and "—", menu bar "0 due · tier 1".
  Four surfaces, none explains why or what will change.

### The design's own calibration says real usage is too sparse

The simulated learner (Phase-1 exit criterion) models a user who sees **every
ambient word 4×/day**, hovers **40% of encounters**, and completes **2
sessions/day** — and the pass bar is tier 2 *within 30 days*. Real browsing is
an order of magnitude sparser, and a real user hovers only when curious. The
gates were tuned so hovering can't power-level (correct) but were applied
uniformly to a cold start where there is nothing to level at all.

### Knock-on effects

- `known` requires box ≥ 4 ≈ four correct, *due-spaced* answers (1h+6h+24h
  cooldowns) — realistically ~4 days per word *after* it becomes ready. Tier 2
  (9 of 12 known) is realistically 3–6 weeks away for a normal user. With a
  54-item pack, that's the entire product surface for over a month.
- Mid-tier drought: once tier-1 items graduate past `ready`, nothing refills
  ambient (all tier-1 items already admitted, tier 2 locked). `ambientSetMin`
  exists in config but is used nowhere; the documented demotion rule is also
  unimplemented. Sessions shrink and page swaps thin out exactly when the
  user is finally engaged.
- "Words known: 0" for weeks is not calm-and-adult; it's demotivating. The
  research brief is explicit that exposure should unlock availability and
  retrieval should unlock mastery — here exposure gates *availability of
  retrieval itself*.

### Recommendations (progression)

1. **Kill the empty first session.** Introduce items through practice, not
   only through pages: an "introduction" beat (show word + gender + example,
   then immediate recognition) that any ambient item is eligible for, capped
   at ~5/day. First answer moves it to `learning` exactly as today. Every
   serious SRS product cold-starts this way; it doesn't violate the
   no-power-leveling rule because srsBox still only moves on graded retrieval.
2. **Make `engaged` an accelerant, not a gate.** e.g. ready when
   `seen ≥ 6` OR `seen ≥ 3 && engaged ≥ 1` (or count engaged as 2 seen).
   Alternatively keep the gate but *teach it* and *show it* — worse option.
3. **Relax the cold start, keep the steady state.** Consider waiving daily
   seen-caps until an item has been practiced once, or scaling
   `readySeenThreshold` by tier (tier 1: 3 seen; deeper tiers: 6).
4. **Reconsider `knownMinBox = 4` for the tier-unlock definition of known**
   (box 3 = proven at 24h→72h spacing), or drop `tierUnlockFraction` to ~0.6.
   Keep box ≥ 4 for the *label* "known" if you want, but don't chain the whole
   content pipeline behind the slowest definition.
5. **Make tier unlock an event, not a background condition.** The brainstorm
   series converged on a readiness meter + a short tier quiz as the unlock
   moment (mockup 08). That is both faster-feeling and more legible than a
   silent 70%-known check, and partially decouples unlocking from the
   slow-cook Leitner ladder.
6. **Implement ambient refill** (`ambientSetMin`): when ambient+ready < 8 and
   the unlocked tiers are exhausted, admit a trickle from the next tier
   (marked "preview") instead of letting the pipeline drain.

## 4. Progress visibility: the data exists, the UI hides it

`ItemProgress` already stores `seenCount`, `engagedCount`, streaks, per-mode
corrects — the snapshot even ships `seenCount` to hover cards. None of it is
shown.

- **Library**: for ambient items, replace grey dots + "—" with exposure
  progress: "4/6 seen · 1/2 hovered" or a small "almost ready" bar. This is
  the single highest-leverage change in the app: it converts the invisible
  waiting period into visible motion on day 1.
- **Overview**: make it a *next-action* surface, not a census. Primary CTA
  ("Practice 3 ready words" / "Keep reading — 4 words are almost ready"),
  tier progress stated as a goal ("5 of 9 known needed to unlock Tier 2"),
  today's activity (exposures/reviews — the events table has it). Drop or
  mute the `locked` bar: 42-locked dominating the chart tells a new user
  "almost everything is unavailable".
- **Stage names are engine jargon** leaking to users: locked/ambient/ready
  mean nothing without the state machine in your head. Rename in UI (e.g.
  upcoming / meeting on pages / ready to practice / practicing / known /
  mastered) and add a one-line legend.
- **Practice empty state must say why** — the mockup-08 rule ("the start
  button should never just be disabled without saying why") is currently
  violated in spirit. List the nearest items: "aber — 2 more sightings;
  heute — hover it once". That message also *teaches the mechanic*.
- **Menu bar**: "0 due · tier 1" reads as a shrug. Show the actionable state:
  "3 ready to practice", "12 words in rotation", badge only when nonzero.
- **Session end**: show what moved ("porque recall +1 · next review in 3d"),
  per the micro-progress-chips + end-ledger decision (mockups 06/03).
- **Hover card**: show "2 more sightings until practice" — makes hovering
  feel consequential and quietly reveals the engagement mechanic.

## 5. Surface-by-surface UX notes

- **Onboarding** covers philosophy but not the actual setup cliff: enabling
  the extension in Safari, granting site access, verifying the connection.
  There is no system-status surface anywhere (extension reachable? port
  alive? last event received?). The old wireframes doc had status cards for
  exactly this. Also: bundle the seed pack — making a first-run user locate a
  JSON file is a dev workflow leaking into UX.
- **Practice** is functional but bare: no session shape, no motion, no
  keyboard numbers for choices, no post-answer item detail (gender, example,
  why), no way to practice when nothing is due. Switching sidebar tabs
  mid-session resets the queue (`.onAppear { startSession() }`).
- **Library** lacks search/filter, any item-detail view (the roadmap's
  deep-link target doesn't exist yet), and any click affordance.
- **Tutor** is a raw chat: no streaming (P6 promises it), no conversation
  persistence, no integration with the loop. The research is blunt that open
  chat is the weakest LLM shape — the coach-drawer + one end-of-session
  checkpoint (mockups 04/05) is the design worth building instead.
- **Settings** is fine as a dev tool; missing: pack import/update after
  onboarding, a language row (activeLanguage is a setting but `de` is
  hardcoded in LibraryView/PracticeView/TutorView), extension status.
- **Popup** is honest and good; per-site toggle from the P4 scope isn't
  there (blocked hosts only editable as comma-text in Settings).

## 6. Doc–code drift and defects found

1. **Near-miss takes the full lapse penalty.** docs/plan/04 promises
   "wrong-but-gentle (no double lapse penalty)", but the UI routes near-miss
   through the same `record(correct: false)` as wrong: box −2, `lapses += 1`,
   streak reset, plus repair requeue. The gentle copy hides a harsh penalty.
2. **`ambientSetMin` and the demotion rule are documented, unimplemented.**
3. ~~`tierUnlockedAt(1)` is never written at import~~ — correction: it *is*
   written by PackImporter when it first sets `unlockedTier`, so the 7-day
   minimum interval applies from day one as designed.
4. **Session reset on tab switch** (above).
5. **`AppModel.init` fatalErrors** if the DB can't open — acceptable for a
   personal tool, but a corrupt DB currently means a crash loop.
6. Practice/Library/Tutor hardcode `"de"`/"German" — multilingual debt that
   contradicts the settings-driven `activeLanguage`.
7. Minor: `Overview.dueNow` excludes due mastered items that sessions will
   still include.

## 7. Documentation state

docs/plan/ is exceptional — vision with numbered binding principles, a
post-mortem that names bug classes, open problems with acceptance criteria.
AGENTS.md files are current. Gaps: no user-facing help (the app explains
swapping but nothing explains *progression* — directly implicated in §3–4),
no LICENSE, no CI (roadmap P0 claims CI as an exit criterion; there is no
.github/), no CHANGELOG, and the roadmap's P5 "done" claim predates the
per-site-toggle and item-detail gaps noted above. The prototype research was
stranded on dead branches until today (now in research/).

## 8. Where to take it — priority order

**Phase A — fix the first week (do before anything else):**
bundle + auto-import the pack; onboarding → extension setup with live
status; introduction sessions (§3.1); ready-gate rework (§3.2–3);
progress-visibility package (§4); near-miss fix (§6.1).

**Phase B — make practice feel alive** (the brainstorm decisions, already
made): session arc (warmup → mix → tier check → release), living-deck motion
(slide/stack, collapse-to-progress, flip for reveals), micro-progress chips +
end ledger, tier readiness + quiz as the unlock moment, sentence-rebuild and
self-grade modes (Core Five).

**Phase C — content is a pacing feature:** the ~1000-item pack (`packtool
author`) matters for UX, not just coverage — more items means more matches
per page, faster exposure, denser sessions. Plus verb-collocation chunks
(OP-1 C) and live LLM verification of P6 (currently untested against a real
provider).

**Phase D — depth and expansion:** tutor as coach-drawer/checkpoint, hover
deep-dives with enrichment cache, FSRS behind the existing protocol,
pronunciation/TTS, second language, Chrome port, distribution.

The wedge (ambient acquisition inside real reading, privacy-first, calm) is
validated by both the research and the market scan. What's missing isn't
more machinery — it's letting the user *feel* the machinery working from
minute one.

---

## Addendum (same day): Phase A implemented

Everything in Phase A landed on this branch: introduction sessions
(transition c′, `sessionIntroLimit`), the ready-gate rework (seen-only path
+ engagement fast path), the near-miss `hold` fix, the progress-visibility
package (dashboard next-action card + tier progress + extension status,
library exposure column, humanized stage names, practice empty-state
reasons, session-end ledger, menu bar copy), bundled starter pack with
one-click onboarding, resumable practice sessions, and the docs/plan/04
updates. 76 tests green (13 new). The 30-day simulation now reaches tier 3
by day 22 with 11 questions answered on day 1 (previously 0 possible).
