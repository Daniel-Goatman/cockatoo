# 08 — Roadmap

> Build order, exit criteria, risk register, and what's deliberately parked. Each phase is independently verifiable; no phase depends on a later one's output.

## Phases

### P0 — Scaffold + risk spike (≈ small)
**Scope**: new repo per [02-architecture.md](02-architecture.md) layout; CI running `swift test` + `vitest`; the **R2 spike**: a throwaway menu bar app + minimal appex proving sandboxed IPC (D9).
**Exit criteria**: appex → CFMessagePort → app round-trip works with both sandboxes on; app-down background requests return `appUnavailable`; explicit `openDashboard` can launch and retry; login-item registration (`SMAppService`) works.
**Verify**: run the spike by hand; CI green on empty test suites.

### P1 — LearnerCore (≈ large)
**Scope**: schema v1, domain records, pack import, `LeitnerScheduler`, stage machine, `ActivationEngine`, `SessionPlanner`/`QuestionFactory`/`Grader`, `EventIngestor`, `SnapshotBuilder`. Pure library + a tiny debug CLI (`learnerctl simulate`).
**Exit criteria**: full test plan from [04-learning-engine.md](04-learning-engine.md) green — including the shuffle-distribution test, the generative mode-coverage test, the idempotency test, and the **30-day simulated learner** reaching tier 2 with no stuck items. Snapshot size bound (R3) asserted.
**Verify**: `swift test`; `learnerctl simulate --days 30` output inspected.

### P2 — German starter pack (≈ medium; parallel with P1 after schema freeze)
**Developer Preview scope**: deterministic pack generation and a bundled 212-item German starter pack. A production-size ~1,000-item pack remains a future content milestone, not a v0.1 shipping claim.
**Current status**: validator, reproducibility, and import checks pass. The model-authored expansion's human content review is still incomplete; see `docs/pack-review-2026.10.md`. Do not represent this pack as production-reviewed until that checksum-bound record is accepted.
**Verify**: `script/check.sh`; before a production content release, commit a checksum-bound review record and completed spot-review evidence.

### P3 — Extension core (≈ medium; parallel with P2)
**Scope**: TypeScript `src/core/**` — pageGate, matcher, transformer, hoverCard, exposureTracker, eventQueue — against `FakeTransport` and fixture pages ([05-extension.md](05-extension.md)).
**Exit criteria**: vitest green incl. protocol fixture tests; perf budgets met on the infinite-scroll fixture (initial apply < 30 ms / 10k words, mutation batch < 10 ms); zero tokens on form/code fixtures.
**Verify**: `npm test`; fixture pages opened by hand in Safari Tech Preview with a dev snapshot.

### P4 — Safari integration (≈ medium)
**Scope**: appex forwarder (native message ⇄ CFMessagePort), the app's IPC listener, messaging envelope + `protocolVersion`, snapshot cache + freshness triggers, per-site gate, popup with app status/statistics, and native `openDashboard` routing.
**Exit criteria**: on real sites — tokens appear within budget (nouns with citation-form articles per D10), hover works, events land in SQLite (visible via `learnerctl`), snapshot refreshes after progress changes **without any polling** (verified by logging native-message counts during 10 min of browsing: only event flushes + heartbeat). **App-down drill**: quit the app mid-browse — extension keeps rendering from cache, events queue, popup reports status, everything drains when the app relaunches.
**Verify**: manual browse session with logging; shared JSON fixtures pass on both Swift and TS sides.

### P5 — App UI (≈ large)
**Scope**: SwiftUI app — menu bar presence (login item, due-count badge, pause controls), Practice, Overview, Library, Settings (per-site rules, pack import, practice controls, **"How swapping works" page**), and onboarding stating the fidelity-tier philosophy (transparency requirements 1–3 in [01-vision-and-principles.md](01-vision-and-principles.md)).
**Exit criteria**: **the full loop works end-to-end**: browse → exposure accrues → item becomes `ready` → practice session → box advances → tier unlocks → new words appear in Safari on next snapshot refresh. No control on screen is decorative (P4 audit: click every control).
**Verify**: scripted manual walkthrough of the loop; `swift test` for view models.

### P6 — Multilingual and agent-assisted pack authoring
**Scope**: language-agnostic pack metadata and grading rules, active-language selection, deterministic source-to-build pipeline, and an optional provider-neutral agent/LLM drafting CLI ([06-llm-integration.md](06-llm-integration.md)).
**Exit criteria**: a second-language fixture imports and practices without German-specific code; generated drafts carry provenance, reproduce byte-for-byte after acceptance, pass validation, and require an explicit human review record.
**Verify**: offline fixture-provider tests, pack reproducibility checks, validator tests, and a reviewed second-language sample. No runtime network path is introduced.

**2026-07-16 status**: foundation complete — schema 2, pack-configured grading
and validation, explicit source lemmas, canonical review-gated builds,
provider-neutral prompt/docs, a reviewed Spanish sample, and active-language
selection with progress-preserving switching are tested. A production-sized
second pack and optional contributor-only provider adapter remain future work.

### P7 — Hardening + packaging (≈ small-medium)
**Scope**: event pruning job, error surfaces, perf pass on heavy sites (Discord web, Google Docs excluded-by-gate check), signed/notarized build script, README, `make build`.
**Exit criteria**: **one week of daily personal use** with zero state corruption, zero Safari jank complaints, and no silent failures in the log.
**Verify**: the week itself; a final P4-audit sweep.

## Risk register

| ID | Risk | Mitigation | Owner doc |
|---|---|---|---|
| R1 | **Inflection**: dictionary-form swaps make sentences ungrammatical | per-surface-form authored targets incl. determiner-extended noun variants (D10), inflection-safe class restriction, fidelity tiers, and human-reviewed pack generation | 01, 05, 07, 09 |
| R2 | **App availability**: extension sync depends on the app process running (D9) | Login item makes app-down rare; only explicit `openDashboard` may launch it; cached snapshot keeps rendering; at-least-once event queue means progress is delayed, never lost; honest popup status; P0 spike + P4 app-down drill verify it | 02, 03, 05 |
| R3 | Snapshot too big / matcher too slow at 1,000-item packs | Active-slice-only snapshot (50–200 items), < 100 KB and < 5 ms bounds test-enforced | 03, 05 |
| R4 | Extension perf regressions (the prototype's disease) | Incremental added-subtree processing, 250 ms debounce, persistent budgets, CI perf fixtures incl. infinite scroll | 05 |
| R5 | Event loss or double-credit across crashy flushes | Client UUIDs + idempotent ingestion + at-least-once queue with ack-then-clear | 03, 04, 05 |
| R6 | Frequency-list license blocks future distribution | License review at source selection; provenance embedded in pack; CC-BY(-SA) candidates only | 07 |
| R7 | Legacy migration cruft creeps back in | Explicit no-import decision (D8); one ID scheme; ban on decode-time migrations | 03 |
| R8 | Generated pack content is malformed or misleading | separate drafts, provenance, deterministic validation, reproducible builds, and human acceptance | 06, 07 |

## Deferred / parked (explicitly out of v1)

- **Chrome/Firefox port** — the adapter seam is built; the port is not.
- **Second language** — pipeline is language-agnostic by requirement; content work parked.
- **FSRS scheduler** — `ReviewScheduler` protocol keeps it drop-in.
- **Ambient verbs** — `reviewOnly` in v1; full problem analysis, candidate approaches (chunk-ification → tagger+lexicon → LLM multi-token edits), and acceptance criteria in [09-open-problems.md](09-open-problems.md) OP-1.
- **Ambient grammar patterns / case agreement** — v2 design, parked with analysis in [09-open-problems.md](09-open-problems.md) OP-2/OP-3.
- **Monetization, onboarding polish, licensing, App Store distribution** (P8 principle).
- **Sync across devices / hosted backend** — would ride the adapter seam later.
- **Runtime Tutor, contextual forms, and model-generated enrichment** — removed from the Developer Preview; reconsider only with evidence and a separate privacy review.

## Suggested order & parallelism

P0 → P1 (schema freeze early) → {P2 ∥ P3} → P4 → P5 → P6 → P7. The single hard sequencing constraint was the **sandboxed IPC spike (R2) before the Sync API froze**; everything else tolerates reordering.
