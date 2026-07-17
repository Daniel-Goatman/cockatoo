# Cockatoo — Visual Redesign Integration Plan

Agreed 2026-07-12 from the critique of the first frame prototype
(`research/prototype-v2/practice.html`, originally `~/Downloads/practice.html`).
Companion to `docs/design-brief.md`; this plan turns the "sulphur-crested"
direction into the shipped app UI.

> **Historical implementation plan:** retained as design rationale. References
> to the Tutor predate its removal from the Developer Preview on 2026-07-16.

## Direction (locked)

Graphite surfaces, ivory ink, serif German. **Decisions from the critique
session:**

- **Palette — two hues plus a functional third.** Stage ramp runs
  *cold → gold*: slate/indigo for upcoming / on pages, warming through
  practicing to a gold known. Indigo also tints selection/focus. Terracotta
  is the functional colour for wrong / near-miss / repair — never gold,
  never green. Moss green stays reserved for the live/connected dot.
- **Chrome — maximum flush.** Hidden titlebar + full-size content view:
  sidebar runs to the top of the window, traffic lights float over it,
  "End session" floats top-right over the background. **No status bar**
  (sync time moves to the sidebar footer next to the extension dot).
  **No 1px zone borders** — sidebar / content / inspector separate by
  background tint only. Watch this in light mode; it's the hardest case.
- **Inspector (tier ring + done-stack): collapsible, open by default.**
  Auto-collapse during the tier-check beat for focus.
- **Intro card:** single action ("Got it — quiz me"). Skip is cut — no
  engine path; revisit as a real defer feature only if demand shows up.
- **End session = finish early → ledger.** Shows the session ledger for
  what was answered, drops the rest. Implicit pause-on-leave already covers
  the other intent.
- **Light + dark designed together from the start** (dark remains "home").
- **Done-stack cards lead with outcome** (introduced / strengthened /
  almost / repaired / missed); stage + exposure detail on the hover peek.

## Phase 0 — Fix the prototype's truth conflicts

The frame is right; the information isn't. In `practice.html`:

1. **Four user-facing stages**, not six: upcoming → on pages → practicing →
   known, mastered as a star badge (matches `Views.swift` after b45f683).
   Rebuild the stage ramp on 4 steps of cold→gold.
2. **Tier ring targets the unlock threshold**, not tier size: needed =
   ceil(0.7 × tier items) per `ActivationEngine`/`LearnerEngine.unlockNextTier`.
   "8 of 9 needed · 1 to go", then the 3-question check.
3. **Progress strip encodes answer outcome** (the app's `answerTrail`),
   not word stage — outcome colours: gold-family for good, terracotta for
   almost/missed.
4. **Queue total is dynamic** — misses requeue repairs, 8 can become 10;
   the strip must absorb growth without reflow jank.
5. Remove "Skip" (decision above).
6. Remove "Hover a card to review it" — hover is a peek, not a review
   queue. Reword hint or drop it.
7. Done-stack cards: outcome chip first; "seen n×" (exposure) moves to the
   hover peek so exposure and practice data don't blur.

Also from the critique: contrast-check the 10px mono `--faint` labels,
and make sure every card's key info survives the messy-stack overlap.

## Phase 1 — Prototype the full Practice arc (HTML, light + dark)

The intro card is Practice at its calmest; the direction is proven only
when the hard states look calm too. Prototype, in order:

- The three question modes: recognition (choices), typed recall, cloze.
- Feedback states: correct, near-miss (terracotta, box held), wrong +
  the repair re-ask beat.
- Post-answer micro chip (what just changed for the word).
- Tier-check beat (inspector auto-collapses) and the **unlock
  celebration** — the emotional peak; deserves the most craft in the
  product. Design its Reduce Motion equivalent explicitly.
- Session ledger (session end and early-finish via "End session").
- Empty / capped state ("done for today" — cap-aware hints, never a
  suggestion that won't credit).
- Motion spec while doing the above: durations, springs, what animates on
  answer/advance/unlock, Reduce Motion table.

## Phase 2 — Remaining surfaces (HTML or targeted mockups)

- **Overview**: next-action card, four stage bars, stat tiles (Due now /
  In rotation / Practicing / Words known), tier progress + check-ready flag.
- **Library**: tier-grouped table with 4-stage chips + mastered star,
  exposure progress, strength dots — restyle sketch is enough.
- **In-page swap + hover card**: underline per fidelity tier using the
  new palette (approximate = dotted); CSS-only, host-page-safe.
- **Menu bar icon at 16px** + dropdown; app icon exploration from the
  prototype's cockatoo mark.

## Phase 3 — SwiftUI translation (build phase)

- Theme layer first: colour assets (light+dark pairs approximating the
  oklch values), type styles (Iowan Old Style for target-language text,
  SF elsewhere), spacing/radius tokens.
- Window chrome: hidden titlebar, full-size content, full-height sidebar,
  floating controls; delete the toolbar/statusbar equivalents.
- Rebuild Practice per prototype, then Overview, Library, Tutor/Settings.
- App-side deltas the plan creates (no engine changes): "End session"
  finish-early path in `PracticeSessionModel`; inspector wiring for
  needed-count (engine already computes it).
- Verify per repo rules: build + `script/install.sh`, screenshots of every
  surface light+dark, Reduce Motion pass, contrast audit.

## Out of scope for this track

Mascot dosage beyond the titlebar mark, Core Five remaining modes,
pack pipeline — separate tracks. The pixel-cockatoo idle animation stays
parked until an unlock-celebration or empty-state use earns it.
