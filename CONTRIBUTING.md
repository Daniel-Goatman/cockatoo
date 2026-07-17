# Contributing to Cockatoo

Cockatoo is in its early stages and contributions are genuinely welcome, from bug
fixes and docs to whole language packs. This guide covers setup, the rules that
keep the project coherent, and how to land a change. If anything here is unclear
or out of date, fixing it is a great first pull request.

## Get set up

Full instructions are in the [setup guide](docs/setup.md). The short version:

```sh
git clone https://github.com/Daniel-Goatman/cockatoo.git
cd cockatoo
script/doctor.sh      # check your toolchain
script/bootstrap.sh   # install dependencies
swift run CockatooDev # explore the app with no Apple account
```

You only need an Apple Development team and a provisioned App Group to run the
Safari extension end to end. Most core, engine, pack, and app UI work does not,
so `swift run CockatooDev` and the test suites cover it.

## The one rule to internalize

> Swift owns all learning logic. The extension only renders and reports.

Every rule about scheduling, stages, grading, and eligibility lives in
`Sources/LearnerCore/`. The extension receives a precomputed snapshot and emits
raw exposure events. Read
[docs/plan/01-vision-and-principles.md](docs/plan/01-vision-and-principles.md)
and [docs/plan/02-architecture.md](docs/plan/02-architecture.md) before making
anything larger than a surface change. [AGENTS.md](AGENTS.md) is a concise map of
the hard rules and the gotchas that have cost real debugging time.

## Where help is most valuable

- **Practice.** Session design, grading, pacing, and motivation. This is the
  roughest surface; the current design is
  [docs/plan/10-learning-redesign.md](docs/plan/10-learning-redesign.md).
- **Language packs.** Authoring, reviewing, and expanding vocabulary. See
  [packs/README.md](packs/README.md). Frequency-accurate, genuinely useful
  vocabulary is the heart of the product.
- **In-page coverage.** The verb problem (OP-1 in
  [docs/plan/09-open-problems.md](docs/plan/09-open-problems.md)) is the biggest
  gap between what practice teaches and what can appear on a page.
- **A Chrome adapter.** The extension core is browser-agnostic TypeScript behind
  one `Transport` interface, so a Chrome port is a single adapter.
- **Onboarding, accessibility, and docs.**

For anything larger, please open an issue first so we can check it fits the
local-first, deterministic-core direction.

## Rules that keep it coherent

These come from [AGENTS.md](AGENTS.md) and the plan docs. The ones most likely to
trip up a first pull request:

- **No learning rule in TypeScript.** Scheduling, stages, due-ness, and
  eligibility live only in `Sources/LearnerCore/`.
- **One progress store.** `item_progress` is the only place progress exists. No
  parallel stores.
- **No fake UI.** A control that renders must work. A practice mode that is
  offered must be generatable for every item that can reach it.
- **Protocol changes touch both sides and a fixture.** The app and extension
  protocol is defined in Swift (`Sources/LearnerCore/Sync/Messages.swift`) and
  TypeScript (`extension/src/core/types.ts`) and pinned by
  `protocol-fixtures/*.json`, decoded by tests on both sides. Change all three in
  one commit.
- **No model client or API key in the shipped app.** Model-assisted pack
  authoring is a separate, offline, opt-in contributor tool. Secrets never enter
  source, provenance, logs, or a pack.
- **Schema changes go through numbered GRDB migrations** in `AppDatabase.swift`.
  No decode-time migrations, no legacy imports.

## Repository map

| Path | Purpose |
|---|---|
| `Sources/LearnerCore/` | learning engine, storage, sync, packs |
| `App/Cockatoo/` | SwiftUI app and Safari app-extension targets |
| `extension/` | browser-agnostic TypeScript core and Safari adapter |
| `packs/` | language-pack source and built artifacts |
| `Sources/packtool/` | validation, checksum, review, and import CLI |
| `Sources/learnerctl/` | database and simulated-learner diagnostics |
| `protocol-fixtures/` | cross-language protocol contract |
| `docs/plan/` | product principles and architecture decisions |

## Verify before you open a pull request

Keep the full check green. It is the same suite CI runs:

```sh
script/check.sh          # add --skip-xcode to skip the universal build
```

That runs the Swift suite (`swift test`, the deepest tested part of the project),
the extension suite (`npm test`), the boundary lint, pack reproducibility and
validation, and an unsigned universal build.

For anything touching the boundary between the extension and the app, also drive
the real flow: `script/install-dev.sh`, then browse, see tokens, hover, check the
popup status line, and run a practice session. The popup status line reports live
sync errors with detail, so it is the fastest way to confirm the loop is healthy.

CI runs on every pull request across three jobs: Swift and language pack, the
browser extension, and the unsigned universal build. All must pass.

## Pull requests

- Branch from `main` and keep each pull request focused on one change.
- Use a `scope: summary` commit style, matching the history: `app:`, `extension:`,
  `tooling:`, `docs:`, `ci:`, `packs:`.
- Explain why. Link the relevant issue or plan doc, and say how you verified the
  change, including what you drove in the app or Safari for UI and extension work.
- Update docs and fixtures in the same pull request as the code they describe.
- Do not add production dependencies, cloud services, or a runtime network path.
  Those cut against the local-first core and need discussion first.

## Reporting issues

Bug reports and ideas are both welcome as GitHub issues. For a bug, include your
macOS and Xcode versions, whether you were on the app-only or full-extension
path, what you did, and what you expected. For a rendering issue, the popup status
line and the page you were on help a lot. Please do not paste private URLs or
personal vocabulary.

## License

Cockatoo is under the
[PolyForm Noncommercial License 1.0.0](LICENSE): free for personal and other
noncommercial use, with commercial use not permitted. By contributing, you agree
that your contributions are licensed under the same terms.
</content>
