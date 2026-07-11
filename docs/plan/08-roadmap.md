# 08 — Roadmap

> Build order, exit criteria, risk register, and what's deliberately parked. Each phase is independently verifiable; no phase depends on a later one's output.

## Phases

### P0 — Scaffold + risk spike (≈ small)
**Scope**: new repo per [02-architecture.md](02-architecture.md) layout; CI running `swift test` + `vitest`; the **R2 spike**: a throwaway menu bar app + minimal appex proving the XPC path (App-Group-prefixed mach service, D9).
**Exit criteria**: appex → XPC → app round-trip works with both sandboxes on; per-call latency < 50 ms; app-down path verified (appex launches the app and retries; with launch blocked, returns a clean `appUnavailable`); login-item registration (`SMAppService`) works.
**Verify**: run the spike by hand; CI green on empty test suites.

### P1 — LearnerCore (≈ large)
**Scope**: schema v1, domain records, pack import, `LeitnerScheduler`, stage machine, `ActivationEngine`, `SessionPlanner`/`QuestionFactory`/`Grader`, `EventIngestor`, `SnapshotBuilder`. Pure library + a tiny debug CLI (`learnerctl simulate`).
**Exit criteria**: full test plan from [04-learning-engine.md](04-learning-engine.md) green — including the shuffle-distribution test, the generative mode-coverage test, the idempotency test, and the **30-day simulated learner** reaching tier 2 with no stuck items. Snapshot size bound (R3) asserted.
**Verify**: `swift test`; `learnerctl simulate --days 30` output inspected.

### P2 — German pack v1 (≈ medium; parallel with P1 after schema freeze)
**Scope**: packtool pipeline end-to-end ([07-content-pipeline.md](07-content-pipeline.md)); ~1,000-item `de` pack.
**Exit criteria**: validator green; human review diff accepted; spot-review of 50 random items finds ≥ 48 correct (translation + sourceForms + examples); bands 1–6 fully reviewed.
**Verify**: `packtool validate`; manual spot-review checklist committed with the pack.

### P3 — Extension core (≈ medium; parallel with P2)
**Scope**: TypeScript `src/core/**` — pageGate, matcher, transformer, hoverCard, exposureTracker, eventQueue — against `FakeTransport` and fixture pages ([05-extension.md](05-extension.md)).
**Exit criteria**: vitest green incl. protocol fixture tests; perf budgets met on the infinite-scroll fixture (initial apply < 30 ms / 10k words, mutation batch < 10 ms); zero tokens on form/code fixtures.
**Verify**: `npm test`; fixture pages opened by hand in Safari Tech Preview with a dev snapshot.

### P4 — Safari integration (≈ medium)
**Scope**: appex forwarder (native message ⇄ XPC), the app's XPC listener, messaging envelope + `protocolVersion`, snapshot cache + freshness triggers, per-site gate, popup with per-site toggle and app-status line, `cockatoo://` URL scheme.
**Exit criteria**: on real sites — tokens appear within budget (nouns with citation-form articles per D10), hover works, events land in SQLite (visible via `learnerctl`), snapshot refreshes after progress changes **without any polling** (verified by logging native-message counts during 10 min of browsing: only event flushes + heartbeat). **App-down drill**: quit the app mid-browse — extension keeps rendering from cache, events queue, popup reports status, everything drains when the app relaunches.
**Verify**: manual browse session with logging; shared JSON fixtures pass on both Swift and TS sides.

### P5 — App UI (≈ large)
**Scope**: SwiftUI app — menu bar presence (login item, due-count badge, pause + per-site quick toggles), Practice (all three modes incl. in-session repair), Dashboard (real data only), Library (pack browser, item detail, deep-link target), Settings (per-site rules, language, provider placeholder, **"How swapping works" page**), and the **onboarding screen** stating the fidelity-tier philosophy (transparency requirements 1–3 in [01-vision-and-principles.md](01-vision-and-principles.md)).
**Exit criteria**: **the full loop works end-to-end**: browse → exposure accrues → item becomes `ready` → practice session → box advances → tier unlocks → new words appear in Safari on next snapshot refresh. No control on screen is decorative (P4 audit: click every control).
**Verify**: scripted manual walkthrough of the loop; `swift test` for view models.

### P6 — LLM layer (≈ medium)
**Scope**: `OpenAICompatClient` + Keychain + test-connection; deep-dive + enrichment cache; tutor (streaming, language-parameterized); opt-in page context + `getContextualForm` with server-side gate ([06-llm-integration.md](06-llm-integration.md)).
**Exit criteria**: all features verified against **both** OpenRouter and a local llama.cpp server; degradation matrix behaviors confirmed by pulling the network/killing the server mid-use; with no provider configured the app is fully functional and shows no broken affordances.
**Verify**: manual matrix run; unit tests for the structured-output retry ladder and the tier gate (a `sendsPageText` call with opt-in off must throw, both in-app and via the appex).

### P7 — Hardening + packaging (≈ small-medium)
**Scope**: event pruning job, error surfaces, perf pass on heavy sites (Discord web, Google Docs excluded-by-gate check), signed/notarized build script, README, `make build`.
**Exit criteria**: **one week of daily personal use** with zero state corruption, zero Safari jank complaints, and no silent failures in the log.
**Verify**: the week itself; a final P4-audit sweep.

## Risk register

| ID | Risk | Mitigation | Owner doc |
|---|---|---|---|
| R1 | **Inflection**: dictionary-form swaps make sentences ungrammatical | (a) per-surface-form authored targets incl. determiner-extended noun variants (D10) + inflection-safe class restriction (verbs deferred, D11 → [09-open-problems.md](09-open-problems.md)); (b) fidelity tiers with visible token marking and in-app transparency; (c) opt-in LLM contextual forms, cached | 01 (tiers), 05 (a,b), 06 (c), 07 (authoring), 09 (verbs) |
| R2 | **App availability**: extension sync depends on the app process running (D9) | Login item + appex auto-launch make app-down rare; cached snapshot keeps rendering; at-least-once event queue means progress is delayed, never lost; honest popup status; P0 spike + P4 app-down drill verify it | 02, 03, 05 |
| R3 | Snapshot too big / matcher too slow at 1,000-item packs | Active-slice-only snapshot (50–200 items), < 100 KB and < 5 ms bounds test-enforced | 03, 05 |
| R4 | Extension perf regressions (the prototype's disease) | Incremental added-subtree processing, 250 ms debounce, persistent budgets, CI perf fixtures incl. infinite scroll | 05 |
| R5 | Event loss or double-credit across crashy flushes | Client UUIDs + idempotent ingestion + at-least-once queue with ack-then-clear | 03, 04, 05 |
| R6 | Frequency-list license blocks future distribution | License review at source selection; provenance embedded in pack; CC-BY(-SA) candidates only | 07 |
| R7 | Legacy migration cruft creeps back in | Explicit no-import decision (D8); one ID scheme; ban on decode-time migrations | 03 |
| R8 | LLM unreachable/slow/garbage degrades the core | Tiered features, local-first defaults, degradation matrix, no regex patching, cached enrichment | 06 |

## Deferred / parked (explicitly out of v1)

- **Chrome/Firefox port** — the adapter seam is built; the port is not.
- **Second language** — pipeline is language-agnostic by requirement; content work parked.
- **FSRS scheduler** — `ReviewScheduler` protocol keeps it drop-in.
- **Ambient verbs** — `reviewOnly` in v1; full problem analysis, candidate approaches (chunk-ification → tagger+lexicon → LLM multi-token edits), and acceptance criteria in [09-open-problems.md](09-open-problems.md) OP-1.
- **Ambient grammar patterns / case agreement** — v2 design, parked with analysis in [09-open-problems.md](09-open-problems.md) OP-2/OP-3.
- **Hover-card "Explain"/enrichment in the extension** — v1.1, after P6.
- **Monetization, onboarding polish, licensing, App Store distribution** (P8 principle).
- **Sync across devices / hosted backend** — would ride the adapter seam later.
- **Multiple LLM provider profiles** — one active profile in v1.

## Suggested order & parallelism

P0 → P1 (schema freeze early) → {P2 ∥ P3} → P4 → P5 → P6 → P7. The single hard sequencing constraint: **the XPC spike (R2) before the Sync API freezes**; everything else tolerates reordering.
