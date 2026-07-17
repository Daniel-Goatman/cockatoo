# Cockatoo

Cockatoo teaches German while you read the web. Its Safari extension swaps a
small, controlled number of English words for German ones; hovering always
reveals the original. A local macOS companion app owns vocabulary, practice,
progress, settings, and the language-pack database.

> **Developer Preview:** the source, tests, and local development workflow are
> usable today. There is no Developer ID-signed or notarized download yet, so
> this is not currently a consumer-ready app release.

## What is included

- Safari WebExtension with cached rendering and queued exposure events
- Overview, Practice, Library, Settings, onboarding, and menu-bar controls
- deterministic local learning engine backed by SQLite/GRDB
- bundled German pack 2026.10 with 212 items and three examples per item
- pack validation, checksum, review-diff, import, and simulation CLIs
- shared Swift/TypeScript protocol fixtures and automated CI

The experimental Tutor and all runtime LLM/network features have been removed
from this preview. Future model use belongs in the offline language-pack
authoring pipeline, not in the app's core runtime.

## Requirements

| Purpose | Requirement |
|---|---|
| Run the app | macOS 14 Sonoma or newer |
| Build app + Safari extension | macOS 15.6+, Xcode 26+, Node.js 20+, Git |
| Run core/pack tools | Swift 5.10+ and Node.js 20+ |
| Test the full Safari sync loop | an Apple Development team and provisioned App Group |
| Distribute to other users | Developer ID signing + notarization, not currently available |

Xcode must be installed because Apple compiles Safari app extensions through
its toolchain, but you do not need to open the Xcode IDE. Every supported
workflow below is a terminal command.

## Quick start

```sh
git clone https://github.com/Daniel-Goatman/cockatoo.git
cd cockatoo
script/bootstrap.sh
script/check.sh
```

`script/check.sh` runs the Swift and extension suites, protocol checks, pack
reproducibility/validation, and a universal unsigned Xcode build.

To explore the companion app without installing the Safari extension:

```sh
swift run CockatooDev
```

To compile the complete universal app bundle without an Apple account:

```sh
script/build.sh --unsigned
```

The unsigned artifact is a build-verification artifact. It cannot authorize
the App Group used by the extension and therefore is not a supported install.

## Run the Safari extension locally

Developer ID is **not** required for local development. Apple Development
signing is enough, but the app and extension must share a provisioned App Group.

```sh
cp App/Config/Local.example.xcconfig App/Config/Local.xcconfig
# Edit Local.xcconfig with your team, unique bundle ID, and App Group.
script/install-dev.sh
```

The development installer builds both architectures, installs to
`~/Applications/Cockatoo.app`, registers the extension, and launches the app.
Then enable Cockatoo in Safari → Settings → Extensions. Use
`script/install-dev.sh --restart-safari` after changing content scripts.

This repository's legacy `script/install.sh` entrypoint installs the same
development build to `/Applications`, which is useful for a stable login-item
path.

See [docs/development.md](docs/development.md) for configuration and every
command, and [docs/distribution.md](docs/distribution.md) for the exact
unsigned/signing limitations.

## Architecture

```text
Safari page
  ↕ TypeScript WebExtension (render + raw events only)
Safari app extension
  ↕ CFMessagePort in a shared App Group
macOS app
  ↕ LearnerCore (all learning rules)
SQLite database + imported language pack
```

Swift owns scheduling, eligibility, grading, progress, and pack import. The
extension is deliberately a renderer and event emitter. Protocol types exist
in Swift and TypeScript and are pinned by JSON fixtures decoded on both sides.

## Repository map

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
| `script/check.sh` | run all tests, pack checks, and unsigned app build |
| `script/build.sh [--debug] [--unsigned]` | build the universal app bundle |
| `script/install-dev.sh` | signed local install to `~/Applications` |
| `script/build_and_run.sh --verify` | signed build, install, launch, and process check |
| `script/clean.sh [--dependencies]` | remove generated output, optionally dependencies |

## Language packs

German `2026.10` is the bundled starter pack. Schema 2 records source and target
BCP 47 tags, explicit source lemmas, pack-configured grading and ambient safety
rules, and provenance. The canonical accepted-source workflow also requires a
separate checksum-bound human review. The checked-in Spanish sample proves that
workflow, deterministic building, import, and practice without German-specific
runtime code; it is a development fixture, not a complete bundled course.

The current German seed generator predates that canonical review gate. Its
model-authored expansion is validation-clean and reproducible, but its human
content review is still incomplete. Treat it as preview content, not a
production-reviewed course.

See [packs/README.md](packs/README.md) for creating a new language, safely
drafting batches with an agent or LLM, reviewing and building them, and
expanding a pack without breaking learner progress.

## Project principles

- local-first core: browsing, practice, and progress require no network
- one progress store shared by every surface
- deterministic learning rules; generated content must pass validation and review
- stable item IDs preserve progress across pack upgrades
- no fake controls or advertised-but-unverified features

Start with [docs/plan/01-vision-and-principles.md](docs/plan/01-vision-and-principles.md)
for the full design rationale.

## License

Cockatoo is available under the [MIT License](LICENSE).
