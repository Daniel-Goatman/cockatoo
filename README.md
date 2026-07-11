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
| `App/Cockatoo/Cockatoo/` | SwiftUI menu bar app sources — single copy, built by BOTH the Xcode app target (synchronized folder) and the `CockatooDev` SPM target |
| `App/Cockatoo/Cockatoo.xcodeproj` | The Xcode project: app + Safari extension (appex) targets |
| `App/Cockatoo/CockatooExtension Extension/` | Appex: the stateless CFMessagePort forwarder + Info.plist |
| `Sources/packtool/` | Content pipeline CLI: validate / checksum / review / import-test |
| `Sources/learnerctl/` | Debug CLI: import, overview, snapshot, sandboxed 30-day simulation, session dump |
| `extension/` | TypeScript WebExtension: matcher, transformer, hover card, exposure tracker, event queue (Safari adapter is the only browser-specific code) |
| `packs/` | Language packs: `sources/de/build-seed.mjs` → `build/de-2026.07.json` (54 items, bands 1–4) |
| `protocol-fixtures/` | Shared JSON fixtures decoded by BOTH Swift and TS tests — protocol drift fails tests on either side |
| `App/*.entitlements` | App + appex entitlements (App Group `group.dev.cockatoo.shared`) |

## Daily workflow

```sh
script/install.sh                    # build app + extension → install to /Applications → relaunch
script/install.sh --restart-safari   # same, and bounce Safari (content scripts in open tabs are stale otherwise)
script/install.sh --debug            # Debug configuration
```

The `/Applications` copy is THE copy: stable path (Safari extension
registration and login-item both depend on it), Release-optimized. Use
Xcode ⌘R only when you need the debugger. Launch-at-login is a toggle in
the app's Settings (requires the /Applications copy).

## Verify

```sh
swift test                      # 63 tests: scheduler properties, shuffle distribution,
                                # generative mode coverage, idempotency, 30-day simulated
                                # learner, snapshot size bound, privacy-tier gate,
                                # protocol fixtures (incl. envelope + fractional dates)
cd extension && npm install && npm test   # 32 tests: matcher, transformer budgets/
                                          # exclusions/incremental mutations, event queue,
                                          # page gate, protocol fixtures
npm run lint:boundaries         # sendNativeMessage confined to adapters/safari/
swift run packtool validate packs/build/de-2026.07.json
```

Full-loop simulation without Safari (sandboxed by default — saves nothing):

```sh
swift run learnerctl --db /tmp/dev.sqlite import packs/build/de-2026.07.json
swift run learnerctl --db /tmp/dev.sqlite simulate --days 30
swift run learnerctl --db /tmp/dev.sqlite overview
```

Run the app UI without installing: `swift run CockatooDev`.

## Architecture in one paragraph

The app (menu bar, login item) owns the SQLite database exclusively and
answers the extension over a **CFMessagePort** named
`group.dev.cockatoo.shared.api` (the App-Group prefix is what the sandbox
authorizes — see docs/plan/03 §R2 outcome for why not NSXPCListener). The
appex is a stateless forwarder: native message in → port request → response
out. The extension renders from a cached, versioned snapshot and queues
idempotent exposure events; freshness piggybacks on event flushes (no
polling). When the app isn't running the extension degrades gracefully and
says so honestly in its popup.

## Status vs the roadmap ([docs/plan/08-roadmap.md](docs/plan/08-roadmap.md))

- **P1 LearnerCore** — done, all exit-criteria tests green
- **P2 pack** — seed pack (54 items) validator-green; the full ~1000-item
  frequency-list + LLM authoring run is pending (`packtool author`)
- **P3 extension core** — done, tests green
- **P4 Safari integration** — **done and verified on-device**: snapshot/event
  round-trip, app-down drill (cached rendering + queued events + honest
  popup), openDashboard fronting, launch-path-independent IPC
- **P5 app UI** — done: dashboard, practice (3 modes + repair), tier-grouped
  library, settings (provider, privacy, blocked sites, launch-at-login),
  onboarding
- **P6 LLM layer** — built + unit-tested; not yet exercised against a live provider
- **P7 hardening** — in progress: daily-use soak underway
