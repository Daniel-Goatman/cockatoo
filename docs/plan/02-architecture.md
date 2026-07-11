# 02 — Architecture

> System shape, module boundaries, process model, and the decision log. Principles cited as P1–P8 are defined in [01-vision-and-principles.md](01-vision-and-principles.md).

## Component diagram

```
┌─────────────────────────────  macOS  ─────────────────────────────┐
│                                                                    │
│  ┌──────────────┐        ┌────────────────────────────────┐       │
│  │ Cockatoo.app │───────▶│           LearnerCore           │       │
│  │  (SwiftUI)   │        │  Domain · Store · Scheduling ·  │       │
│  └──────────────┘        │  Practice · Sync · LLM · Packs  │       │
│         ▲                └───────────────┬────────────────┘       │
│         │ Darwin notification            │ GRDB (SQLite, WAL)      │
│         │ "db changed"                   ▼                         │
│         │                ┌────────────────────────────────┐       │
│         └────────────────│   App Group container DB file   │       │
│                          └───────────────▲────────────────┘       │
│                                          │ same pool, stateless    │
│  ┌───────────────────────────────────────┴──────────────┐         │
│  │ CockatooExtension.appex — SafariWebExtensionHandler   │         │
│  │ thin RPC: getSnapshot / postEvents /                  │         │
│  │           getContextualForm / getSettings             │         │
│  └───────────────────────────▲──────────────────────────┘         │
│                              │ native messaging (JSON)             │
└──────────────────────────────┼─────────────────────────────────────┘
                               │
┌─────────────────────────  Safari  ─────────────────────────────────┐
│  ┌────────────────────────┐        ┌─────────────────────────┐    │
│  │ background script       │◀──────▶│ content script (per tab)│    │
│  │ snapshot cache ·        │ runtime │ pageGate · matcher ·    │    │
│  │ event queue · alarms    │ message │ transformer · hoverCard │    │
│  │ (storage.local)         │        │ · exposureTracker        │    │
│  └────────────────────────┘        └─────────────────────────┘    │
└────────────────────────────────────────────────────────────────────┘
```

Data flows one way per concern: **vocab flows down** (DB → snapshot → background cache → content script), **events flow up** (content script → background queue → native message → DB), and **UI reads the DB** (app observes via Darwin-notification-triggered refresh).

## Repo layout (new repo)

```
cockatoo/
  Package.swift                  # SwiftPM: LearnerCore lib, packtool exe, tests
  Sources/
    LearnerCore/
      Domain/                    # VocabItem, ItemProgress, ExposureEvent, CapturedSentence,
                                 # PracticeResult, LearnerSettings, Snapshot
      Store/                     # GRDB setup, numbered migrations, DAOs per aggregate
      Scheduling/                # ReviewScheduler protocol, LeitnerScheduler, ActivationEngine
      Practice/                  # SessionPlanner, QuestionFactory, Grader
      Sync/                      # SnapshotBuilder, EventIngestor, message envelope codecs
      LLM/                       # ChatProvider, OpenAICompatClient, feature clients
      Packs/                     # pack schema, import, upgrade, validation
    packtool/                    # CLI: frequency list → validated versioned pack
  Tests/LearnerCoreTests/
  App/                           # Xcode project
    Cockatoo/                    # SwiftUI app target
    CockatooExtension/           # appex target: handler + built extension resources
  extension/                     # TypeScript, esbuild → App/CockatooExtension/Resources
    src/core/                    # browser-agnostic: pageGate, matcher, transformer,
                                 # hoverCard, exposureTracker, eventQueue, snapshotStore
    src/adapters/safari/         # native-messaging bridge + storage.local cache
    src/adapters/chrome/         # stub (deferred)
    test/                        # vitest + jsdom + fixture HTML pages
  packs/
    sources/de/                  # raw frequency lists + licenses + provenance
    build/                       # de-YYYY.MM.json versioned outputs
  docs/plan/                     # these documents
```

Build system: SwiftPM for `LearnerCore`/`packtool`/tests; one Xcode project for app + appex; esbuild bundles TypeScript into the appex resources; a single `make build` (or `script/build.sh`) chains extension build → xcodebuild → sign. No file is generated into two places (anti-goal from [00-current-state-assessment.md](00-current-state-assessment.md) §2).

## Module responsibilities and the logic boundary (P1)

**LearnerCore** is the only module that knows what SRS, tiers, stages, due-ness, and mastery are. It is UI-free and process-agnostic — linked identically by the app, the appex, and packtool.

**The app** is a SwiftUI shell over LearnerCore: Dashboard (real data only, P4), Practice (the one review engine UI), Library (pack browser + item detail + enrichment), Tutor (chat), Settings (provider config, privacy toggles, per-site rules).

**The appex handler** is a stateless RPC dispatcher. Each handler method is ~10 lines: decode envelope → call LearnerCore → encode response. It holds no state between invocations (Safari may cold-start and kill it freely).

**The extension JS** knows nothing about learning. Its entire input is the **snapshot** (versioned active-item slice with a surface-form match table and hover content); its entire output is **events** and protocol requests. Allowed knowledge per side:

| | May know | Must never know |
|---|---|---|
| LearnerCore | everything | DOM, page URLs beyond host policy needs |
| Extension JS | snapshot contents, page DOM, host policy verdicts | SRS math, stage rules, tier logic, migrations |

## Process model and lifecycles

- **App**: long-lived while open. Opens the GRDB `DatabasePool` (WAL). Subscribes to the Darwin notification `<bundle-prefix>.cockatoo.db.changed`; on receipt, re-runs its queries. (GRDB `ValueObservation` is in-process only — cross-process freshness comes from the Darwin signal, not from observation.)
- **Appex**: cold-started per message batch by Safari, possibly killed immediately after. Therefore: open pool → handle → post Darwin notification if it wrote → return. No caches, no background work.
- **Background script**: event-driven (MV3-style); owns the snapshot cache in `browser.storage.local` and the event queue; wakes on runtime messages, queue flush triggers, and a slow `browser.alarms` heartbeat.
- **Content script**: per-tab at `document_idle`; asks the background for the current snapshot once, transforms, observes mutations incrementally, emits events. Never talks to native messaging directly.

## Sync in one paragraph (spec in [05-extension.md](05-extension.md))

The snapshot carries a monotonic version. The background script caches it and serves content scripts from cache. Freshness is achieved without polling: every `postEvents` response piggybacks `latestVersion`; if newer than cached, the background pulls a fresh snapshot. Since browsing itself generates events, staleness is bounded by user activity; a 10-minute `browser.alarms` heartbeat is the floor, and browser/extension startup always refreshes. This replaces the prototype's 2-second poll.

## Chrome portability seam (P8)

Everything under `extension/src/core/` is WebExtension-standard and browser-agnostic. The only Safari-specific code is `src/adapters/safari/` (native messaging + storage cache). A Chrome port replaces that adapter with a different transport (e.g. localhost HTTP to the app, or hosted sync) and supplies its own manifest. **Rule: no `sendNativeMessage` call outside the adapter directory** — enforced by a lint rule in the extension build.

## Decision log

| # | Decision | Rationale | Rejected |
|---|---|---|---|
| D1 | **GRDB/SQLite (WAL) in the App Group** for all learning state | Real queries ("50 due items ordered by dueAt"), per-row writes, proven cross-process access via WAL + busy timeout, explicit numbered migrations, in-memory DBs for tests | JSON-blob-in-UserDefaults (whole-blob rewrite per event, no queries — the prototype's approach); SwiftData/Core Data (cross-process access from an appex is unsupported/painful; opaque migrations) |
| D2 | **TypeScript** for the extension | Types across the messaging boundary (protocol structs mirrored from Swift Codables), refactor safety in the transformer, same esbuild pipeline | plain JS (the prototype's drift between untyped modules) |
| D3 | **Leitner-6 behind a `ReviewScheduler` protocol** | The prototype's ladder is proven and simple; the protocol keeps FSRS as a drop-in later without touching callers | FSRS now (better retention modeling, but more state and tuning; deferred — see [08-roadmap.md](08-roadmap.md)) |
| D4 | **Pull-with-piggyback + slow heartbeat** for extension freshness | Safari can't push native→extension; event flushes are frequent exactly when freshness matters (user is browsing) | 2 s polling (prototype; battery/perf cost on every tab); push via storage events (not available cross-process in Safari) |
| D5 | **Snapshot = active slice only** (~50–200 items), never the full pack | Keeps messages tens of KB, matcher build O(active items); full pack stays in SQLite | shipping the pack into the extension (prototype's generated `curriculum.js` — triple-definition disease) |
| D6 | **One OpenAI-compatible client** | User decision; covers OpenRouter/OpenAI/llama.cpp/Ollama with base URL + key + model | per-provider SDKs; keeping Ollama-specific code |
| D7 | **API keys in Keychain** (shared access group) | Never in the DB, UserDefaults, or a plist | env vars / settings table |
| D8 | **No legacy import** | 13 words of progress is disposable; dual-ID resolver shims and mirrored migrations must not be rebuilt | migrating v3 `LearningState` |
| D9 | **Appex opens the DB directly** (pending P0 spike, risk R2) | Simplest correct path; both targets share the App Group entitlement | XPC to the app (fallback if the spike fails — documented in [03-data-model-and-storage.md](03-data-model-and-storage.md)) |

## Cross-references

- Data model and cross-process storage detail: [03-data-model-and-storage.md](03-data-model-and-storage.md)
- Learning state machine and scheduling: [04-learning-engine.md](04-learning-engine.md)
- Extension internals and messaging protocol: [05-extension.md](05-extension.md)
- LLM provider layer and privacy tiers: [06-llm-integration.md](06-llm-integration.md)
- Content pipeline and pack schema: [07-content-pipeline.md](07-content-pipeline.md)
- Build order and risk register: [08-roadmap.md](08-roadmap.md)
