# Cockatoo — Design Brief

Handover context for brand-identity and visual-redesign work. Everything a
design session needs to ideate broadly without rediscovering the product.
Written 2026-07-11, after the Phase A/B UX work landed on main.

> **Historical design input:** this captures the product at that date. The
> optional Tutor and runtime model client were removed from the Developer
> Preview on 2026-07-16. Current scope lives in the root README and
> `docs/plan/08-roadmap.md`.

## 1. What Cockatoo is (one paragraph)

Cockatoo teaches you German **while you read the web**. A Safari extension
quietly swaps a few words per page into German — hover any marked word and
the English is right there. A companion macOS app owns the learning: short
practice sessions, a vocabulary library, progress, and an optional AI tutor.
The learning engine is serious (spaced repetition, exposure-primes /
retrieval-cements, tier progression with earned unlock checks) but the
product's whole personality is that it **never asks for your time — it
accepts it when offered**.

Personal tool today; the door to a product is deliberately kept open.
Audience if it ships: adult Mac users who read a lot and want a language to
seep in around the edges — people who bounced off streak-guilt apps.

## 2. Design values (binding — from docs/plan/01)

- **Calm, adult, high-signal.** The reward is understanding the German on a
  page you were reading anyway. Explicit anti-goals: **no streaks, XP,
  leagues, mascot guilt, or gamification theater**.
- **Honest UI (P4).** Nothing decorative: every number is real, every
  control works, a disabled button always says why. Recent UX work doubled
  down: hints never suggest actions that won't count ("done for today"),
  sync status shows real event timestamps.
- **Non-interruptive above all (P7).** In-page swaps must read as
  "vocabulary card in place", never as a broken page. No notifications.
- **Transparency as identity.** "Words and genders first, grammar later" is
  stated plainly, on-screen, always. Fidelity tiers (exact / form-matched /
  approximate) are a *user-visible concept* that needs visual encoding —
  approximate will carry a dotted underline when it ships.
- **The tension to explore: calm ≠ dead.** The current ask is to make it
  feel *alive* — motion, character, warmth — without tipping into Duolingo.
  "Patient coach, not a generic AI product" (from the original wireframes).

## 3. Where the product is today

All surfaces work end-to-end; the visual layer is default-SwiftUI utilitarian
and has never had a designer's pass. Screenshots should accompany this brief
(take them fresh: Overview, Practice mid-session + intro card + summary
ledger, Library, Tutor, Settings, onboarding, menu bar dropdown, Safari
popup, and a real page with swapped words + hover card).

Existing interaction design already decided (keep, restyle):
- **Session arc**: warm-up → new words → mix → tier check, with a progress
  strip where each answer collapses into a colored chip.
- **Motion language** (chosen in the brainstorm series): slide/stack as the
  base, collapse-to-progress on success, flip only for reveals; calm
  fallbacks under Reduce Motion.
- **Tier unlocks are earned moments** — a 3-question check inside the
  session, then a celebration beat. This is the emotional peak of the whole
  product; it currently gets a `sparkles` SF Symbol and deserves real craft.
- **Stage vocabulary** shown to users: upcoming → on pages → ready →
  practicing → known → mastered. Colors are currently ad hoc (blue / teal /
  orange / green); the identity should own this scale — it appears in
  chips, bars, progress strips, and hover cards.

## 4. Surfaces inventory (what needs design)

| Surface | Notes |
|---|---|
| **In-page swap treatment** | The most brand-visible pixel in the product. Underline style per fidelity tier, hover affordance, pin state. Must survive any website's styling, light/dark, and never look like an error or an ad. CSS-only, no webfonts. |
| **Hover card** | Translation, gender, example, "n more sightings" progress. Tiny, instant, page-safe. |
| **App: Overview** | Next-action card, stat tiles, tier progress + check-ready flag, extension status, stage bars. |
| **App: Practice** | The living deck: question cards ×3 modes, intro card, repair/tier-check beats, progress strip, session ledger, tier-unlock celebration. Where "alive" matters most. |
| **App: Library** | Tier-grouped table, stage chips, exposure progress ("3/6 seen · done today"), strength dots. |
| **App: Settings, Onboarding** | Native configuration and first-run guidance. |
| **Menu bar** | Original cockatoo template mark + actionable practice/status menu. The always-present touchpoint. |
| **Icons** | Original vector cockatoo mark shared by the app icon and compact toolbar treatment. |

## 5. Existing design material (hand all of this over)

- `research/brainstorm-mockups/*.html` — 8 interactive design-decision
  mockups, already in a coherent **warm-paper editorial** aesthetic
  (cream/tobacco/moss/indigo palette, Newsreader serif). This is candidate
  direction #1 and shows the practice-flow interactions in situ. Open in a
  browser.
- `research/app-overview-wireframes.md` — full wireframe set + the original
  visual-language notes ("mature, calm, high-signal…").
- `docs/plan/01-vision-and-principles.md` — vision, principles, anti-goals,
  glossary. §Fidelity tiers matters for the underline system.
- `docs/assessment-2026-07-11-ux-progression.md` — why the UX is shaped the
  way it is now.

## 6. Hard constraints

- **macOS 14 SwiftUI app** — native conventions, light *and* dark mode
  (dark is the primary daily environment), Reduce Motion honored, sidebar
  navigation stays. Custom drawing is fine; a web-app-in-a-window is not.
- **Extension UI is plain CSS/HTML** injected into arbitrary pages: no
  loaded fonts, minimal footprint, must not clash with host pages.
- **SF Symbols + system type** are the default palette unless the direction
  earns custom assets; any custom type must also work at caption sizes.
- **No marketing-page energy.** This is a tool people live in.

## 7. What to ask design for (suggested process)

1. **Broad ideation first**: 3–4 genuinely distinct brand directions as
   mood/brand boards — e.g. (a) the warm-paper editorial direction already
   latent in the mockups, (b) native-macOS quiet-glass minimalism, (c)
   character-forward but adult (pixel cockatoo as accent), (d) bold
   typographic/high-contrast. Each with palette (light+dark), type, the
   stage-color scale, swap-underline treatment, and one Practice-card
   mockup so directions are comparable on the same surface.
2. **Pressure-test each direction** on the three hardest moments: the
   in-page swap + hover card, the tier-unlock celebration, and the menu
   bar icon at 16px.
3. **Pick one, then prototype deep**: interactive HTML prototypes of
   Practice (full session arc with motion) and Overview before any SwiftUI
   work. Motion spec: durations, springs, what animates on answer/advance/
   unlock, Reduce Motion equivalents.
4. Only then translate to SwiftUI (that's a build phase, not design).

## 8. Words that describe the target feeling

Calm · literate · warm · quietly playful · trustworthy · Mac-native ·
"a patient coach who happens to be a bird" · never nagging · alive the way
a well-made paper notebook is alive, not the way a slot machine is.
