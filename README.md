# Cockatoo

Learn a language while you read the web. A Safari extension quietly swaps a
few words per page into your target language (German first); hovering any
marked word shows the original English. A companion menu bar app owns the
vocabulary, progress, and scheduling — the extension just renders and reports.

Ground-up rebuild of the earlier prototype. The full design lives in
[docs/plan/](docs/plan/) — start with
[00-current-state-assessment.md](docs/plan/00-current-state-assessment.md)
(why rebuild) and [01-vision-and-principles.md](docs/plan/01-vision-and-principles.md)
(what this refuses to be).

## Layout

| Path | What |
|---|---|
| `Sources/LearnerCore/` | ALL learning logic: domain, SQLite store (GRDB), Leitner scheduler, activation/tiers, session planner + grading, sync (snapshot/events), LLM provider layer, pack import |
| `Sources/Cockatoo/` | SwiftUI menu bar app: dashboard, practice, library, tutor, settings, onboarding, XPC listener |
| `Sources/packtool/` | Content pipeline CLI: validate / checksum / review / import-test |
| `Sources/learnerctl/` | Debug CLI: import, overview, snapshot, 30-day simulation, session dump |
| `extension/` | TypeScript WebExtension: matcher, transformer, hover card, exposure tracker, event queue (Safari adapter is the only browser-specific code) |
| `packs/` | Language packs: `sources/de/build-seed.mjs` → `build/de-2026.07.json` (54 items, bands 1–4) |
| `protocol-fixtures/` | Shared JSON fixtures decoded by BOTH Swift and TS tests — protocol drift fails tests on either side |
| `App/` | Appex forwarder source, entitlements, and the manual Xcode packaging guide |

## Verify

```sh
swift test                      # 62 tests: scheduler properties, shuffle distribution,
                                # generative mode coverage, idempotency, 30-day simulated
                                # learner, snapshot size bound, privacy-tier gate
cd extension && npm install && npm test   # 31 tests: matcher, transformer budgets/
                                          # exclusions/incremental mutations, event queue,
                                          # page gate, protocol fixtures
npm run lint:boundaries         # sendNativeMessage confined to adapters/safari/
swift run packtool validate packs/build/de-2026.07.json
```

Full-loop simulation without Safari:

```sh
swift run learnerctl --db /tmp/dev.sqlite import packs/build/de-2026.07.json
swift run learnerctl --db /tmp/dev.sqlite simulate --days 30
swift run learnerctl --db /tmp/dev.sqlite overview
```

Run the app UI (dev, no extension): `swift run Cockatoo`.

## Safari packaging

Needs a one-time manual Xcode step (app + appex targets, entitlements,
extension resources) — the checklist, including the P0 XPC risk-spike drill,
is in [App/README.md](App/README.md).

## Status vs the roadmap ([docs/plan/08-roadmap.md](docs/plan/08-roadmap.md))

- **P1 LearnerCore** — done, all exit-criteria tests green
- **P2 pack** — seed pack (54 items) validator-green; the full ~1000-item
  frequency-list + LLM authoring run is pending (`packtool author`)
- **P3 extension core** — done, tests green
- **P4 Safari integration** — code ready; Xcode packaging + on-device spike manual
- **P5 app UI** — built (SwiftUI); GUI walkthrough pending
- **P6 LLM layer** — built + unit-tested; not yet exercised against a live provider
- **P7 hardening** — not started
