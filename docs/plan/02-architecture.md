# 02 — Architecture

> System shape, module boundaries, process model, and the decision log. Principles cited as P1–P8 are defined in [01-vision-and-principles.md](01-vision-and-principles.md).

## Component diagram

```
┌─────────────────────────────  macOS  ─────────────────────────────┐
│                                                                    │
│  ┌──────────────────────────────────────────────────────┐         │
│  │ Cockatoo.app — menu bar app, login item (SwiftUI)     │         │
│  │                                                        │         │
│  │   UI ──▶ LearnerCore (Domain · Store · Scheduling ·   │         │
│  │          Practice · Sync · LLM · Packs)               │         │
│  │                      │ GRDB (SQLite) — SOLE DB owner   │         │
│  │                      ▼                                 │         │
│  │        App Group container DB file                    │         │
│  │                                                        │         │
│  │   CFMessagePort listener:                             │         │
│  │   "group.<prefix>.cockatoo.api"                       │         │
│  └────────────────▲─────────────────────────────────────┘         │
│                   │ CFMessagePort request/reply (App-Group-        │
│                   │ prefixed port name authorizes both sides)      │
│  ┌────────────────┴─────────────────────────────────────┐         │
│  │ CockatooExtension.appex — stateless forwarder         │         │
│  │ native message ⇄ XPC call; NO database access;        │         │
│  │ launches the app if unreachable                       │         │
│  └────────────────────────────▲─────────────────────────┘         │
│                               │ native messaging (JSON)            │
└───────────────────────────────┼─────────────────────────────────────┘
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

**The app is the server.** It runs as a menu bar app registered as a login item (`SMAppService`), owns the SQLite database exclusively, and vends an XPC API. The appex holds no state and never touches the database — it translates native messages into XPC calls and back. Data flows one way per concern: **vocab flows down** (DB → snapshot → XPC → background cache → content script), **events flow up** (content script → background queue → native message → XPC → DB), and **UI reads the DB in-process** (GRDB `ValueObservation` gives the SwiftUI dashboard live queries — no cross-process signaling needed).

**When the app isn't running** (rare, given the login item): background sync returns a structured `appUnavailable` error immediately — an explicit quit is respected, never overridden by a background call. Only `openDashboard` (explicit user intent) launches the app via `NSWorkspace`. The extension then degrades gracefully — replacement and hover continue from the cached snapshot, events keep queuing in `storage.local` (at-least-once, drained on reconnect), and the popup shows "Cockatoo isn't running — progress is being saved locally." Progress is delayed, never lost.

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

**LearnerCore** is the only module that knows what SRS, tiers, stages, due-ness, and mastery are. It is UI-free and process-agnostic — fully linked by the app and packtool; the appex links only its `Sync` message types (it forwards, it doesn't compute).

**The app** is a SwiftUI shell over LearnerCore: Dashboard (real data only, P4), Practice (the one review engine UI), Library (pack browser + item detail + enrichment), Tutor (chat), Settings (provider config, privacy toggles, per-site rules).

**The appex handler** is a stateless forwarder. Each handler method is ~10 lines: decode envelope → forward over XPC to the app → encode response. It links only the `Sync` message types from LearnerCore, holds no state between invocations (Safari may cold-start and kill it freely), and never opens the database.

**The extension JS** knows nothing about learning. Its entire input is the **snapshot** (versioned active-item slice with a surface-form match table and hover content); its entire output is **events** and protocol requests. Allowed knowledge per side:

| | May know | Must never know |
|---|---|---|
| LearnerCore | everything | DOM, page URLs beyond host policy needs |
| Extension JS | snapshot contents, page DOM, host policy verdicts | SRS math, stage rules, tier logic, migrations |

## Process model and lifecycles

- **App**: long-lived — a menu bar app registered as a login item, so it is effectively always running. Sole owner of the GRDB `DatabasePool`; the SwiftUI dashboard observes queries live via `ValueObservation` (in-process, which is now the only process that matters). Registers the XPC listener on the App-Group-prefixed mach service name at launch. Menu bar affordances: due-count badge, pause toggle, per-site quick toggle, open dashboard.
- **Appex**: cold-started per message batch by Safari, possibly killed immediately after. Therefore: decode → XPC call (connecting per invocation) → encode → return. If the XPC connection fails, attempt one app launch via `NSWorkspace`, retry once, then return `appUnavailable`. No caches, no database, no background work.
- **Background script**: event-driven (MV3-style); owns the snapshot cache in `browser.storage.local` and the event queue; wakes on runtime messages, queue flush triggers, and a slow `browser.alarms` heartbeat.
- **Content script**: per-tab at `document_idle`; asks the background for the current snapshot once, transforms, observes mutations incrementally, emits events. Never talks to native messaging directly.

## Sync in one paragraph (spec in [05-extension.md](05-extension.md))

The snapshot carries a monotonic version. The background script caches it and serves content scripts from cache. Freshness is achieved without polling: every `postEvents` response piggybacks `latestVersion`; if newer than cached, the background pulls a fresh snapshot. Since browsing itself generates events, staleness is bounded by user activity; a 10-minute `browser.alarms` heartbeat is the floor, and browser/extension startup always refreshes. This replaces the prototype's 2-second poll. When the app is unreachable, freshness simply pauses on the cached snapshot and queued events drain on reconnect — no special-case sync logic.

## Chrome portability seam (P8)

Everything under `extension/src/core/` is WebExtension-standard and browser-agnostic. The only Safari-specific code is `src/adapters/safari/` (native messaging + storage cache). The app-as-server design makes the Chrome port cleaner: a Chrome adapter would talk to **the same app API** over a token-authenticated localhost HTTP listener the app could add later — same methods, different transport. (Localhost HTTP is deliberately *not* used for Safari: an open local port is callable by any process, whereas XPC peers are code-signature-verifiable.) **Rule: no `sendNativeMessage` call outside the adapter directory** — enforced by a lint rule in the extension build.

## Decision log

| # | Decision | Rationale | Rejected |
|---|---|---|---|
| D1 | **GRDB/SQLite in the App Group, opened by the app only** | Real queries ("50 due items ordered by dueAt"), per-row writes, explicit numbered migrations, in-memory DBs for tests, live `ValueObservation` for the UI; single-writer by design | JSON-blob-in-UserDefaults (whole-blob rewrite per event, no queries — the prototype's approach); SwiftData/Core Data (opaque migrations, weaker query/test story) |
| D2 | **TypeScript** for the extension | Types across the messaging boundary (protocol structs mirrored from Swift Codables), refactor safety in the transformer, same esbuild pipeline | plain JS (the prototype's drift between untyped modules) |
| D3 | **Leitner-6 behind a `ReviewScheduler` protocol** | The prototype's ladder is proven and simple; the protocol keeps FSRS as a drop-in later without touching callers | FSRS now (better retention modeling, but more state and tuning; deferred — see [08-roadmap.md](08-roadmap.md)) |
| D4 | **Pull-with-piggyback + slow heartbeat** for extension freshness | Safari can't push native→extension; event flushes are frequent exactly when freshness matters (user is browsing) | 2 s polling (prototype; battery/perf cost on every tab); push via storage events (not available cross-process in Safari) |
| D5 | **Snapshot = active slice only** (~50–200 items), never the full pack | Keeps messages tens of KB, matcher build O(active items); full pack stays in SQLite | shipping the pack into the extension (prototype's generated `curriculum.js` — triple-definition disease) |
| D6 | **One OpenAI-compatible client** | User decision; covers OpenRouter/OpenAI/llama.cpp/Ollama with base URL + key + model | per-provider SDKs; keeping Ollama-specific code |
| D7 | **API keys in Keychain** (shared access group) | Never in the DB, UserDefaults, or a plist | env vars / settings table |
| D8 | **No legacy import** | 13 words of progress is disposable; dual-ID resolver shims and mirrored migrations must not be rebuilt | migrating v3 `LearningState` |
| D9 | **App-as-server**: menu bar app (login item) owns the DB exclusively; appex is a stateless XPC client via an App-Group-prefixed mach service | Eliminates cross-process SQLite entirely (old risk R2); single writer; live in-process observation; appex trivially thin; same API serves a future Chrome adapter over another transport. Cost: app-down state — mitigated by login item, appex auto-launch, cached snapshot + queued events | Shared cross-process SQLite from the appex (WAL-across-sandboxes risk, killed-mid-write recovery, Darwin-notification plumbing); localhost HTTP for Safari (unauthenticated local port) |
| D10 | **Nouns swap with their determiner, citation-form article** — "the house" → "das Haus", "a house" → "ein Haus" | Deterministic (authored in `sourceForms`), reads naturally, and every noun encounter teaches gender — the highest-value German noun fact. Case agreement is explicitly not attempted (fidelity tier "form-matched", see [01-vision-and-principles.md](01-vision-and-principles.md)) | Bare-noun swaps ("the Haus" — reads broken, wastes the gender-teaching opportunity); contextual case (ill-defined in a mixed-language sentence — see [09-open-problems.md](09-open-problems.md)) |
| D11 | **Ambient verbs deferred** — verbs are `reviewOnly` until the investigation in [09-open-problems.md](09-open-problems.md) resolves | Separable verbs break the swap model; English→German tense mapping isn't 1:1; not blocking v1 | conservative tagger+lexicon verb swaps in v1 (viable candidate, but unproven — parked, not rejected) |

## Cross-references

- Data model and cross-process storage detail: [03-data-model-and-storage.md](03-data-model-and-storage.md)
- Learning state machine and scheduling: [04-learning-engine.md](04-learning-engine.md)
- Extension internals and messaging protocol: [05-extension.md](05-extension.md)
- LLM provider layer and privacy tiers: [06-llm-integration.md](06-llm-integration.md)
- Content pipeline and pack schema: [07-content-pipeline.md](07-content-pipeline.md)
- Build order and risk register: [08-roadmap.md](08-roadmap.md)
- Open problems (ambient verbs, case, ambient patterns): [09-open-problems.md](09-open-problems.md)
