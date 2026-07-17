# Contributing to Cockatoo

Thanks for your interest — Cockatoo is in its early stages and contributions are
genuinely welcome, from bug fixes and docs to whole language packs. This guide
covers how to get set up, the rules that keep the project coherent, and how to
land a change.

If anything here is unclear or out of date, fixing it is itself a welcome PR.

## Ground rules in one breath

Cockatoo is a local-first, deterministic language-learning tool: a Safari
extension that swaps words on the pages you read, backed by a macOS app that
owns all the learning logic. The single most important rule:

> **Swift owns all learning logic; the extension only renders and reports.**

Read [docs/plan/01-vision-and-principles.md](docs/plan/01-vision-and-principles.md)
(the principles P1–P8 that every change must respect) and
[docs/plan/02-architecture.md](docs/plan/02-architecture.md) before making
anything more than a surface change. [AGENTS.md](AGENTS.md) is a concise map of
the hard rules and the gotchas that have cost real debugging time — it's worth
reading even if you're not an AI agent.

## Getting set up

Requirements and the two ways to run the app are in the
[README](README.md#requirements). The short version:

```sh
git clone https://github.com/Daniel-Goatman/cockatoo.git
cd cockatoo
script/doctor.sh      # check your toolchain
script/bootstrap.sh   # npm ci + swift package resolve
swift run CockatooDev # explore the app with no Apple account
```

You only need an Apple Development team + a provisioned App Group to run the
**Safari extension** end to end (`script/install-dev.sh`). Most core, engine,
pack, and app-UI work does **not** require that — `swift run CockatooDev` and
the test suites cover it.

## Where help is most valuable right now

- **Practice** — session design, grading, pacing, and motivation. This is the
  roughest surface; the current design is
  [docs/plan/10-learning-redesign.md](docs/plan/10-learning-redesign.md).
- **Language packs** — authoring, reviewing, and expanding vocabulary. See
  [packs/README.md](packs/README.md). Frequency-accurate, genuinely useful
  vocabulary is the heart of the product.
- **Ambient coverage** — the verb problem (OP-1 in
  [docs/plan/09-open-problems.md](docs/plan/09-open-problems.md)) is the biggest
  gap between what's taught in practice and what can be swapped into pages.
- **A Chrome adapter** — the extension core is browser-agnostic TypeScript
  behind a single `Transport` interface; a Chrome port is one adapter.
- **Onboarding, accessibility, and docs.**

Opening an issue to discuss anything larger before you build it is appreciated —
it helps make sure the change fits the local-first, deterministic-core
direction.

## The rules that keep it coherent

These come from [AGENTS.md](AGENTS.md) and the plan docs; the ones most likely
to trip up a first PR:

- **P1 — no learning rule in TypeScript.** SRS, stages, due-ness, and
  eligibility live only in `Sources/LearnerCore/`. The extension receives a
  precomputed snapshot and emits raw exposure events.
- **P2 — one progress store.** `item_progress` is the only place progress
  exists. No parallel stores.
- **P4 — no fake UI.** A control that renders must function; a practice mode
  that's offered must be generatable for every item that can reach it.
- **Protocol changes touch both sides + a fixture.** The app⇄extension protocol
  is defined in Swift (`Sources/LearnerCore/Sync/Messages.swift`) and TypeScript
  (`extension/src/core/types.ts`) and pinned by `protocol-fixtures/*.json`,
  decoded by tests on both sides. Change all three in the same commit.
- **No model client or API-key path in the shipped app.** Model-assisted pack
  authoring is a separate, offline, opt-in contributor tool. Secrets never enter
  source, provenance, logs, or a pack.
- **Schema changes go through numbered GRDB migrations** in `AppDatabase.swift`
  — no decode-time migrations, no legacy imports.

## Verifying your change

Please keep the full check green before opening a PR — it's the same suite CI
runs:

```sh
script/check.sh          # add --skip-xcode to skip the ~1 min universal build
```

That runs the Swift suite (`swift test` — the deepest-tested part of the
project), the extension suite (`npm test`), the boundary lint, pack
reproducibility and validation, and an unsigned universal Xcode build.

For anything touching the **extension↔app boundary**, also drive the real flow:
`script/install-dev.sh`, then browse → see tokens → hover → check the popup
status line → run a practice session. The popup's status line reports live sync
errors with detail, so it's the fastest way to confirm the loop is healthy.

CI (`.github/workflows/ci.yml`) runs on every pull request across three jobs:
Swift + language pack, the browser extension, and the unsigned universal app
build. All must pass.

## Pull requests

- **Branch from `main`** and keep each PR focused on one change.
- **Commit messages use a `scope: summary` style**, matching the history —
  e.g. `app:`, `extension:`, `tooling:`, `docs:`, `ci:`, `packs:`.
- **Explain the "why."** Link the relevant issue or plan doc, and say how you
  verified the change (which commands, and for UI/extension work, what you drove
  in the app or Safari).
- **Update docs and fixtures in the same PR** as the code they describe.
- Don't add production dependencies, new cloud services, or a runtime network
  path — those cut against the local-first core and need discussion first.

## Reporting issues

Bug reports and ideas are both welcome as GitHub issues. For a bug, include your
macOS and Xcode versions, which path you were on (app-only vs full extension),
what you did, and what you expected. If it's an extension rendering issue, the
popup status line and the page you were on help a lot — but please don't paste
private URLs or personal vocabulary.

## Licensing

Cockatoo is [MIT-licensed](LICENSE). By contributing, you agree that your
contributions are licensed under the same terms.
</content>
