# Cockatoo v0.1.0 — source-only Developer Preview

Cockatoo is a local-first macOS language-learning app. Its Safari extension
replaces a small, controlled number of English words with German while you
read, and the native app provides practice, progress, a library, and settings.

## What is in this preview

- Safari WebExtension with marked swaps, compact/expanded hover details,
  cached popup status, and queued exposure events;
- native Overview, Practice, Library, Settings, onboarding, and menu-bar UI;
- deterministic Swift learning engine with SQLite/GRDB persistence;
- reproducible German 2026.10 starter pack with 212 items and three examples
  per item;
- language-pack authoring, validation, review, import, and simulation tools;
- Swift and TypeScript protocol fixtures plus automated CI.

## Source release only

**There is no downloadable `.app`, DMG, or installer in this release.** The
project does not yet have Developer ID signing or notarization. GitHub's source
archives and the `v0.1.0` tag are the release artifacts.

The companion app can be explored without signing using `swift run
CockatooDev`. Building the complete unsigned app requires macOS 15.6+, Xcode
26+, Node.js 20+, and Git. Running the Safari extension locally requires an
Apple Development team and a provisioned App Group; it does not require
Developer ID. Follow the root README for the exact commands and limitations.

## Preview limitations

- German 2026.10 is a compact starter pack, not the future ~1,000-item content
  milestone.
- The project is intended for contributors and technical evaluators rather
  than consumer installation.
- The experimental Tutor and all runtime LLM/API-key paths are intentionally
  excluded. Agent-assisted content generation is confined to the offline,
  human-reviewed pack workflow.

## Verification

The release candidate passed `script/bootstrap.sh`, `script/check.sh`, an
unsigned universal build, and the Apple Development signed contributor install
from a fresh clone. The final tag must also have an accepted German pack review
and seven-day dogfood record in `docs/`.

Licensed under MIT.
