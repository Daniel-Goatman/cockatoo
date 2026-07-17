# Cockatoo

**Learn a language while you read the web.** Cockatoo's Safari extension quietly
swaps a small, controlled number of English words on the pages you already read
for their target-language equivalents. Hovering always reveals the original. A
local macOS companion app owns the vocabulary, practice, progress, settings, and
the language-pack database — the extension just renders what the app decides.

There are no streaks, no notifications, no "time to practice!" The language comes
to you inside your own reading, at a density low enough that comprehension never
breaks.

> **Early-stage project — and contributions are very welcome.** Cockatoo works
> today for local development: the source, tests, and full build/practice loop
> are usable. It is not yet a signed, notarized, download-and-run consumer app,
> and several areas (practice especially) are actively evolving. If you want to
> help build a genuinely useful language-learning tool, see
> [Contributing](#contributing) — pull requests, issues, and language packs are
> all appreciated.

<p align="center">
  <img src="docs/media/02-web-swap-hover.png" alt="A German word swapped into an English Wikipedia article, with a hover card showing the original English 'or'" width="760">
  <br>
  <sub><em>Reading Wikipedia in English — one word is German. Hover it for the original, its meaning, and more.</em></sub>
</p>

### See it in action

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/media/05-overview.png" alt="The app Overview: 9 due to review, progress by stage, and a milestone ring" width="100%">
      <br><sub><b>Overview</b> — what's due, progress by stage, and a non-gating milestone ring.</sub>
    </td>
    <td width="50%" valign="top">
      <img src="docs/media/04-practice.png" alt="A practice session building the German sentence for 'It is always cold here' from word tiles" width="100%">
      <br><sub><b>Practice</b> — tiny sessions with a visible arc (warm-up → new → mix → check).</sub>
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <img src="docs/media/06-library.png" alt="The Library listing words by frequency band with stage, SRS progress, and next review time" width="100%">
      <br><sub><b>Library</b> — every word by frequency band, with stage, SRS progress, and next review.</sub>
    </td>
    <td width="50%" valign="top">
      <img src="docs/media/03-extension-popup.png" alt="The Safari extension popup showing the active language, due/new/library/known counts, and a Practice button" width="100%">
      <br><sub><b>Extension popup</b> — active language, live counts, and a one-click short session.</sub>
    </td>
  </tr>
</table>

_More capture notes (and a planned short demo) are in
[docs/media/README.md](docs/media/README.md)._

## The idea: applicability first

Most apps teach you words in the order a textbook likes. Cockatoo teaches the
words you are statistically most likely to *actually meet on the web*, in the
order that gets you reading fastest.

- **Frequency-first vocabulary.** Word order comes from real corpus-frequency
  data mapped to CEFR bands. The top ~1,000 words cover the bulk of running
  text, so early wins are immediately visible on real pages.
- **Comprehensible input, engineered.** A page with 3–20 swapped words out of
  thousands is *i+1* by construction — everything around the unknown word is
  context. The replacement budget is a pedagogical parameter, not just a UX one.
- **Meaningful phrases, not just tokens.** Beyond single words, packs teach
  multi-word chunks that carry real meaning ("there is" → *es gibt*, "for
  example" → *zum Beispiel*). A chunk only becomes eligible once the words it's
  built from are already in your library, so you never meet a phrase whose parts
  you haven't started learning.
- **Practice advances a word; the web reinforces it.** New words are introduced
  a few at a time in short practice sessions (a tunable daily drip), and only
  answering questions moves a word's scheduled strength. Seeing or hovering a
  word on a page is tracked as "seen in the wild" and reinforces recognition,
  but exposure never advances the schedule — reading can't power-level, and a
  word's strength only climbs across distinct days, so extra practice sharpens
  without rushing it.

The full rationale lives in
[docs/plan/01-vision-and-principles.md](docs/plan/01-vision-and-principles.md).

## How it works

Cockatoo is two halves that share one source of truth:

```text
Safari page
  ↕ TypeScript WebExtension (renders swaps + reports raw exposure events)
Safari app extension  (stateless message forwarder)
  ↕ CFMessagePort in a shared App Group
macOS app  (SwiftUI: Overview, Practice, Library, Settings)
  ↕ LearnerCore  — the one place every learning rule lives
SQLite database + imported language pack
```

**The Swift app owns everything that counts as "learning"** — scheduling,
eligibility, grading, progress, pack import. The extension is deliberately a
dumb renderer and event emitter: it receives a precomputed *snapshot* of what to
show and emits raw *exposure events*. No learning rule is ever implemented
twice. Details: [docs/plan/02-architecture.md](docs/plan/02-architecture.md).

### The in-page language system (how words get swapped)

When you open a page, the extension asks the app for the current snapshot — a
compact, versioned table of the vocabulary the app wants shown on pages: the
words you're actively practicing or already know (mastered words retire from
pages, and anything not safe to swap is excluded), each with its surface forms
and hover content. Rendering then follows a few deliberate rules:

- **A page gate runs first.** Only `http`/`https` pages are touched, and a
  sensitive-host denylist (banking, payment, health, government) plus your own
  per-site toggles can switch Cockatoo off entirely. On a blocked or empty page
  it does nothing at all.
- **Matching is per surface form, resolved at authoring time.** `house` and
  `houses` are separate entries pointing at *das Haus* and *die Häuser* — the
  extension never conjugates or declines anything itself. Determiner-extended
  forms win preferentially: "the house" swaps as a unit to *das Haus*, teaching
  gender through the citation-form article.
- **A hard replacement budget keeps pages readable.** Roughly `floor(words/40)`
  swaps per page, clamped to 3–20, spread evenly across paragraphs, one instance
  per item. Inputs, code blocks, navigation, and sensitive forms are excluded.
- **Every swapped token is marked** (a subtle underline + tint) and is
  keyboard-focusable. Hovering or focusing it opens a card with the original
  English, the canonical target form, its gender/part of speech, and an example
  — the ground truth is always one hover away.
- **Exposure is reported, not scored, in the browser.** The extension emits
  idempotent events (`seen`, `engaged`, `sentenceCaptured`) that the app ingests
  and credits under its own caps. There's no polling loop; the snapshot refreshes
  on activity and a slow heartbeat.

The extension core is browser-agnostic TypeScript behind a single `Transport`
interface, so a Chrome port is a matter of writing one adapter. Full spec:
[docs/plan/05-extension.md](docs/plan/05-extension.md).

### Practice (the companion app)

Practice is where words actually advance. A session is deliberately tiny
(~2 minutes, around 10 questions) and has a visible arc: **warm-up → new words →
mix → release**, where the warm-up opens on your easiest due items and the
release is one light self-graded production card to close.

- **One progress store.** A single record per item is shared by the browser, the
  practice sessions, the Library, and the Overview. Progress you earn anywhere
  shows up everywhere. A word moves through **practicing → known → mastered**
  (words not yet introduced show as *upcoming*).
- **A Leitner spacing ladder** (1h → 6h → 24h → 3d → 7d → 30d) schedules reviews;
  items surface when they're due, not when it's convenient for a counter. A word
  can advance **at most one box per calendar day**, so a binge session can't
  cram a word to "known" — the evidence unit is distinct days, not reps.
- **Five question modes**, chosen by the word's strength and what the pack can
  actually generate for it (a mode is never offered if it can't be built — no
  dead ends):
  - **Recognition** — see the German, pick the English meaning from options.
  - **Recall** — see the English, type the German.
  - **Cloze** — a real sentence with the word blanked out; type what fills it.
  - **Rebuild** — reassemble the target sentence from shuffled word tiles
    (production without typing — this is the "Build the German for…" card).
  - **Self-grade** — a release-beat prompt to say or think a small sentence with
    the word, then honestly report whether it came easily. The app never
    pretends it can grade free production.
- **Missed answers are repaired in-session**, not just marked wrong: a wrong
  answer re-enters the queue a few questions later, and a near-miss (a typo
  within one edit) holds the word's box instead of lapsing it.
- **Milestones celebrate, they never gate.** Finishing most of a frequency band
  is a one-time celebration; there are no locked tiers or quizzes standing
  between you and the next words.

> **Practice is the roughest surface today and the one most worth improving.**
> The mechanics above are implemented and tested, but the pedagogy, pacing, and
> feel are still early. If you have ideas about session design, grading, or
> motivation, this is a great place to contribute. The current design is
> [docs/plan/10-learning-redesign.md](docs/plan/10-learning-redesign.md), which
> supersedes parts of the earlier
> [docs/plan/04-learning-engine.md](docs/plan/04-learning-engine.md).

### Honest about grammar: fidelity tiers

A German word dropped into an English sentence can't always be perfectly
inflected — German case only means something inside a German sentence. Cockatoo
treats this as a named, user-visible concept rather than hiding it. Every item
declares a **fidelity tier**:

| Tier | Guarantee | Example | Status |
|---|---|---|---|
| **Exact** | Grammatically perfect — invariant words | "and" → *und* | shipping |
| **Form-matched** | Word, gender/article, and number correct; case not attempted | "the houses" → *die Häuser* | shipping |
| **Approximate** | Word correct; form may not agree with context | conservative verb swaps | reserved (see below) |

So v1 teaches **vocabulary and noun gender** honestly, and marks anything less
than perfect. What it deliberately does **not** yet do:

- **Verbs are practice-only, never swapped into pages.** Conjugation is
  context-dependent and separable verbs ("stehe … auf") structurally break a
  single-token swap. This is the biggest coverage limit in v1.
- **Case agreement in mixed-language sentences is out of scope** — it's often
  genuinely undefined, not merely unknown.
- **Whole German phrases/clauses ("layer on grammar as comfort grows")** are the
  v2 ambition, not built yet.

Each of these is analyzed in depth, with candidate approaches, in
[docs/plan/09-open-problems.md](docs/plan/09-open-problems.md).

### Where language models fit (and where they don't)

**The shipped app is fully local and contains no model client, no API key path,
and no network entitlement.** That's a hard principle, not a temporary state.
Language models have a real role in Cockatoo's future, but on the *authoring*
side of a strict boundary:

- **Today — offline pack authoring.** An agent or LLM may *draft* candidate pack
  source (translations, forms, examples) as an untrusted contributor tool. It
  never writes canonical build output or touches learner progress; every field
  passes deterministic validation and a checksum-bound human review before it
  ships. See [docs/plan/06-llm-integration.md](docs/plan/06-llm-integration.md)
  and [packs/README.md](packs/README.md).
- **Being investigated — grammatically-correct placement.** Using a model to
  resolve the *contextual* form of a word or phrase for a given sentence (so a
  verb or a multi-word chunk could be placed in grammatically correct German in
  a real text area) is a direction worth exploring. It would be opt-in,
  network-gated, and would extend the transformer from "swap one span" to "edit
  a range" — the analysis is in OP-1/OP-3 of
  [docs/plan/09-open-problems.md](docs/plan/09-open-problems.md).
- **On the horizon — an LLM tutor.** A conversational tutor that can explain a
  word, its grammar, and usage on demand is of real interest. Any such feature
  would keep the same boundary: opt-in, clearly scoped, and never a silent
  dependency of the local core.

## Requirements

| Purpose | Requirement |
|---|---|
| Run the app | macOS 14 Sonoma or newer |
| Build app + Safari extension | macOS 15.6+, Xcode 26+, Node.js 20+, Git |
| Run core/pack tools | Swift 5.10+ and Node.js 20+ |
| Test the full Safari sync loop | an Apple Development team and provisioned App Group |
| Distribute to other users | Developer ID signing + notarization, not currently available |

Xcode must be installed because Apple compiles Safari app extensions through its
toolchain, but you do not need to open the Xcode IDE — every supported workflow
below is a terminal command. Run `script/doctor.sh` to check your machine.

## Two ways to try it

**1. Explore the companion app — no Apple account needed.** This is the fastest
way to see Cockatoo. It runs the SwiftUI app (Overview, Practice, Library,
Settings) against the bundled German pack, without the Safari extension:

```sh
git clone https://github.com/Daniel-Goatman/cockatoo.git
cd cockatoo
script/bootstrap.sh      # doctor check + npm ci + swift package resolve
swift run CockatooDev    # launches the app
```

**2. Run the full Safari extension — needs an Apple Development team.** The
extension and app must share a provisioned App Group, so this path requires an
Apple developer account with an App Group registered to your team. Developer ID
signing and notarization are **not** required for local use — Apple Development
signing is enough:

```sh
cp App/Config/Local.example.xcconfig App/Config/Local.xcconfig
# Edit Local.xcconfig: your team ID, a unique bundle ID, and an App Group.
script/install-dev.sh    # builds both arches, installs to ~/Applications, launches
```

Then enable Cockatoo in **Safari → Settings → Extensions**. Use
`script/install-dev.sh --restart-safari` after changing content scripts.

To verify a clean checkout end to end (Swift + extension suites, protocol checks,
pack reproducibility, and an unsigned universal build):

```sh
script/check.sh          # add --skip-xcode to skip the ~1 min Xcode build
```

See [docs/development.md](docs/development.md) for every command and
configuration detail, and [docs/distribution.md](docs/distribution.md) for the
exact signing/notarization limitations.

## Contributing

Cockatoo is in its early stages and pull requests are genuinely welcome — from
bug fixes to whole language packs. **[CONTRIBUTING.md](CONTRIBUTING.md) is the
full guide**; the essentials:

- **Understand the shape first.** Read
  [docs/plan/01-vision-and-principles.md](docs/plan/01-vision-and-principles.md)
  (the principles every change must respect) and
  [docs/plan/02-architecture.md](docs/plan/02-architecture.md). The golden rule:
  **Swift owns all learning logic; the extension only renders and reports.**
- **Set up and verify.** `script/bootstrap.sh` then `script/check.sh`. Please
  keep `script/check.sh` green — it's the same suite CI runs.
- **High-value areas right now:** improving practice (session design, grading,
  pacing — see [docs/plan/10-learning-redesign.md](docs/plan/10-learning-redesign.md)),
  authoring and reviewing language packs, expanding in-page coverage
  (the verb problem, OP-1), and a Chrome adapter for the extension core.
- **Language packs** have their own guide: [packs/README.md](packs/README.md).
  Packs are reviewed source artifacts, not runtime model output — an LLM may
  produce a *draft*, but human review and a deterministic build gate everything
  that ships.
- **Open an issue** to discuss anything larger before you build it, so we can
  make sure it fits the local-first, deterministic-core direction.

## Architecture and repository map

Swift owns scheduling, eligibility, grading, progress, and pack import. The
extension is deliberately a renderer and event emitter. Protocol types exist in
both Swift and TypeScript and are pinned by shared JSON fixtures decoded on both
sides, so the two halves can't drift.

| Path | Purpose |
|---|---|
| `Sources/LearnerCore/` | deterministic learning engine, storage, sync, packs |
| `App/Cockatoo/` | SwiftUI app and Safari app-extension targets |
| `extension/` | browser-agnostic TypeScript core plus Safari adapter |
| `packs/` | language-pack source and built artifacts |
| `Sources/packtool/` | validation/checksum/review/import CLI |
| `Sources/learnerctl/` | database and simulated-learner diagnostics |
| `protocol-fixtures/` | cross-language protocol contract |
| `docs/plan/` | product principles and architecture decisions |

## Common commands

| Command | Result |
|---|---|
| `script/doctor.sh` | verify the local toolchain and signing mode |
| `script/bootstrap.sh` | install locked npm dependencies and resolve Swift packages |
| `script/check.sh [--skip-xcode]` | run all tests, pack checks, and unsigned app build |
| `swift run CockatooDev` | launch the companion app with no Apple account |
| `script/build.sh [--debug] [--unsigned]` | build the universal app bundle |
| `script/install-dev.sh` | signed local install to `~/Applications` |
| `script/build_and_run.sh --verify` | signed build, install, launch, and process check |
| `script/clean.sh [--dependencies]` | remove generated output, optionally dependencies |

## Language packs

German `2026.10` is the bundled starter pack: 212 items with three examples each.
Schema 2 records source and target BCP 47 tags, explicit source lemmas,
pack-configured grading and ambient-safety rules, and provenance. The canonical
workflow also requires a separate checksum-bound human review; the checked-in
Spanish sample proves that pipeline — deterministic build, import, and practice —
with no German-specific runtime code.

The current German seed predates that review gate. Its model-authored expansion
is validation-clean and reproducible, but its human content review is still
incomplete, so treat it as **preview content, not a production-reviewed course.**

See [packs/README.md](packs/README.md) for creating a new language, drafting
batches with an agent or LLM, reviewing and building them, and expanding a pack
without breaking learner progress.

## Project principles

- local-first core: browsing, practice, and progress require no network
- one progress store shared by every surface
- deterministic learning rules; generated content must pass validation and review
- stable item IDs preserve progress across pack upgrades
- no fake controls or advertised-but-unverified features

## License

Cockatoo is available under the [MIT License](LICENSE).
</content>
