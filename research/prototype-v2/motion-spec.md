# Cockatoo — Motion spec (v2 direction)

What animates, how long, and what Reduce Motion gets instead. Matches
what `practice-session.html` implements; SwiftUI translation notes at
the end. Language chosen in the brainstorm series and kept here:
**slide/stack is the base, collapse-to-progress on success, flip only
for reveals** — one decisive flourish per moment, never two.

## Curves

| Token | Value | Use |
|---|---|---|
| `ease-standard` | `cubic-bezier(.3,.7,.2,1)` | movement: card advance, layout, ring fill |
| `ease-entrance` | `cubic-bezier(.2,.7,.2,1)` | things appearing: feedback, entrance stagger |
| linear-ish fades | plain `ease` ≤160ms | hovers, color changes |

SwiftUI equivalents: `ease-standard` ≈ `.spring(response: 0.38, dampingFraction: 0.86)`;
`ease-entrance` ≈ `.easeOut(duration: …)`.

## Timings

| Moment | What moves | Duration | Notes |
|---|---|---|---|
| Hover (buttons, tokens, cards) | background/border color | 140ms | never transforms text |
| Primary button hover | lift −1px + gold shadow slides in | 160–200ms | the gold "underline" shadow is the signature |
| Screen entrance (session start) | fade + rise 12px, staggered | 500ms, 90ms stagger | max 4 staggered elements |
| **Card advance** | old card −16px + fade out; new +18px + fade in | 220ms out, 340ms in | slide/stack base; no overlap of interactive states |
| Answer feedback panel | fade + rise 6px | 220ms | appears under the answer, never over it |
| **Collapse-to-progress** | newest strip segment pops (scaleY 0.4→1.5→1) | 300ms | the "answer becomes a chip" beat |
| Done-stack card arrival | fade + settle −8px→0, stack re-fans | 300–340ms | one card per answer, upsert on repair |
| Inspector tuck (tier check) | grid column 292→0 | 300ms | focus narrows for the check; reopens after |
| Tier ring fill | stroke-dashoffset | 1050ms | on load and on target change |
| **Unlock celebration** | ring draws 0→100% (900ms) → single gold bloom ring (900ms, 42px) → title/sub fade-rise (500ms, 550ms delay) | ~1.8s total | one bloom, no confetti, no sound; Continue appears after 900ms |
| Intro reveal → question | treat as reveal: flip is *allowed* here, current build uses slide | 480ms if flipped | flip only ever for reveals |
| Theme change | background/color crossfade | 250ms | prototype-only affordance |

## Reduce Motion table

| Moment | Reduced equivalent |
|---|---|
| Entrances, card advance | instant swap, no transform, no fade |
| Strip segment pop | color change only |
| Ring fills (inspector + celebration) | drawn instantly at final value |
| Unlock bloom | none — static filled ring, text visible immediately |
| Inspector tuck | still occurs (it is layout, not decoration) but without transition |
| Hovers | may keep ≤140ms color fades (no movement) |

Implementation rule: gate *transforms and choreography* behind
`prefers-reduced-motion`, keep *state changes* identical — reduced
motion users see every same fact at the same moment.

## Principles

- Motion always reports a fact (an answer landed, the queue grew, a
  tier opened). Nothing loops, nothing idles, nothing celebrates
  without an earned event.
- One flourish per moment. The unlock gets the ring-draw + bloom;
  therefore its text merely fades.
- Duration scales with meaning: hovers 140ms, answers ~300ms, the
  once-a-week unlock ~1.8s.
- Never animate during typing. Feedback appears only after submit.
