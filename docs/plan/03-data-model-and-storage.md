# 03 — Data Model and Storage

> The single source of truth: SQLite via GRDB, owned exclusively by the app process. Enforces **P2** (one progress store) and the **no-legacy-migration** anti-goal. The app-as-server design (decision D9 in [02-architecture.md](02-architecture.md)) means there is **no cross-process database access anywhere** — the appex reaches the data only through the app's XPC API. Risk **R2** covers the residual app-availability concern.

## Storage engine

- **GRDB `DatabasePool`**, SQLite in WAL mode, database file in the App Group container (`group.<bundle-prefix>.cockatoo`). The App Group location is kept so a future adapter or diagnostic tool has a stable home, but **only the app process ever opens the database**.
- **Single writer by design**: no busy-timeout choreography, no cross-process locking, no killed-mid-write recovery scenarios. The appex is a stateless XPC client with zero database code.
- **Live UI**: GRDB `ValueObservation` drives the SwiftUI dashboard directly — writes from event ingestion or practice grading appear in the UI without any signaling plumbing.
- **Migrations**: GRDB `DatabaseMigrator` with numbered, append-only migrations (`v1`, `v2`, …). No decode-time migration logic anywhere (the prototype's `Codable`-migration habit is banned).
- **Keychain**: LLM API keys live in the Keychain, never in the DB, UserDefaults, or any plist. Nothing learning-related lives in UserDefaults at all.

### R2 spike (must run in Phase 0, see [08-roadmap.md](08-roadmap.md))

The old R2 (cross-process SQLite) is eliminated by D9; what remains is verifying the XPC path and the app-down story. The Phase 0 spike proves: (a) a sandboxed appex can connect to the app's `NSXPCConnection` listener on the App-Group-prefixed mach service name (entitlements verified on both targets), (b) round-trip latency is acceptable for a per-message-batch hop (< 50 ms), (c) with the app not running, the appex's launch-and-retry path works, and (d) with launch blocked, the appex returns a clean `appUnavailable` error the extension handles by degrading to cache + queue. The Store API stays behind a protocol so even a transport change would touch no callers.

### R2 outcome (verified live, 2026-07-11)

`NSXPCListener(machServiceName:)` does NOT reliably register an App-Group-prefixed mach service from a normally launched app — it only worked when Xcode launched the process (launchd never owned the name otherwise). The shipped mechanism is **CFMessagePort**: the app registers a local port named `group.<prefix>.cockatoo.shared.api` (the group prefix is what the sandbox authorizes), the appex does a remote lookup + synchronous request/reply with the same JSON envelopes. Verified against an `open`-launched sandboxed app.

## Schema (migration v1)

```sql
CREATE TABLE pack (
  language      TEXT NOT NULL,          -- BCP-47-ish: "de"
  version       TEXT NOT NULL,          -- "2026.07"
  checksum      TEXT NOT NULL,          -- sha256 of pack file
  provenance    TEXT NOT NULL,          -- JSON: source corpus, license, tool versions
  importedAt    TEXT NOT NULL,          -- ISO-8601
  PRIMARY KEY (language, version)
);

CREATE TABLE vocab_item (
  id                TEXT PRIMARY KEY,   -- stable content-addressed: "de.word.haus"
  language          TEXT NOT NULL,
  kind              TEXT NOT NULL,      -- word | chunk | pattern
  sourceForms       TEXT NOT NULL,      -- JSON: [{form:"the house",  target:"das Haus"},
                                        --        {form:"a house",    target:"ein Haus"},
                                        --        {form:"house",      target:"Haus"},
                                        --        {form:"houses",     target:"Häuser"},
                                        --        {form:"the houses", target:"die Häuser"}]
  target            TEXT NOT NULL,      -- canonical target: "Haus"
  targetMeta        TEXT,               -- JSON: gender, plural, pronunciation, POS
  level             TEXT NOT NULL,      -- CEFR: a1 | a2 | b1
  frequencyBand     INTEGER NOT NULL,   -- 1..10, corpus-derived
  replacementPolicy TEXT NOT NULL,      -- ambientSafe | reviewOnly | never
  fidelityTier      TEXT NOT NULL,      -- exact | formMatched | approximate (01 §fidelity)
  dependencies      TEXT NOT NULL,      -- JSON array of item ids
  explanation       TEXT NOT NULL,
  examples          TEXT NOT NULL,      -- JSON array {source, target}
  packVersion       TEXT NOT NULL
);
CREATE INDEX idx_item_band ON vocab_item(language, frequencyBand);

CREATE TABLE item_progress (            -- THE one progress store (P2)
  itemId        TEXT PRIMARY KEY REFERENCES vocab_item(id),
  stage         TEXT NOT NULL DEFAULT 'locked',
                -- locked | ambient | ready | learning | known | mastered
  srsBox        INTEGER NOT NULL DEFAULT 0,       -- 0..6
  dueAt         TEXT,                             -- ISO-8601, NULL = not scheduled
  seenCount     INTEGER NOT NULL DEFAULT 0,
  engagedCount  INTEGER NOT NULL DEFAULT 0,
  correctStreak INTEGER NOT NULL DEFAULT 0,
  lapses        INTEGER NOT NULL DEFAULT 0,
  activatedAt   TEXT,
  lastResultAt  TEXT,
  updatedAt     TEXT NOT NULL
);
CREATE INDEX idx_progress_due ON item_progress(stage, dueAt);

CREATE TABLE exposure_event (           -- append-only inbox from the extension
  id           TEXT PRIMARY KEY,        -- client-generated UUID (idempotency, R5)
  itemId       TEXT NOT NULL,
  type         TEXT NOT NULL,           -- seen | engaged | pinned | sentenceCaptured
  occurredAt   TEXT NOT NULL,
  host         TEXT,                    -- eTLD+1 only, optional
  processedAt  TEXT                     -- NULL until ingested
);

CREATE TABLE captured_sentence (        -- cloze material; never leaves device
  id           TEXT PRIMARY KEY,        -- unless privacy tier sendsPageText is
  itemId       TEXT NOT NULL,           -- enabled AND the feature is invoked
  text         TEXT NOT NULL,
  sourceHost   TEXT,
  capturedAt   TEXT NOT NULL
);
CREATE INDEX idx_sentence_item ON captured_sentence(itemId);

CREATE TABLE enrichment (               -- cached LLM output (P5)
  itemId       TEXT NOT NULL,
  kind         TEXT NOT NULL,           -- deepDive | contextualForm | ...
  cacheKey     TEXT NOT NULL,           -- e.g. sentenceHash for contextualForm
  contentJSON  TEXT NOT NULL,
  model        TEXT NOT NULL,
  createdAt    TEXT NOT NULL,
  PRIMARY KEY (itemId, kind, cacheKey)
);

CREATE TABLE settings (                 -- sync-relevant flags only; no secrets
  key   TEXT PRIMARY KEY,               -- activeLanguage, pageContextOptIn,
  value TEXT NOT NULL                   -- blockedHosts, snapshotVersion, ...
);
```

## Domain types (GRDB `Codable` records in `LearnerCore/Domain`)

- **`VocabItem`** — evolves the prototype's `CurriculumItem` (`Sources/LanguageLearnerCore/CurriculumItem.swift`). Carried over: `kind`, `replacementPolicy`, `dependencies`, `frequencyBand`, `explanation`, `examples`. New and load-bearing: **`sourceForms`** — the enumerated English surface forms each with its own target-language form, authored at pack-build time. For nouns this includes the **determiner-extended variants** (`"the house" → "das Haus"`, `"a house" → "ein Haus"`, decision D10) so every noun swap shows the citation-form article and teaches gender, plus the bare number forms (`"houses" → "Häuser"`). This is the default (non-LLM) answer to the inflection problem **R1a**; the matcher matches forms, not lemmas ([05-extension.md](05-extension.md)), and the contextual LLM path ([06-llm-integration.md](06-llm-integration.md)) is an opt-in upgrade, not a requirement. Each item carries its **fidelity tier** (`exact` / `formMatched` / `approximate` — defined in [01-vision-and-principles.md](01-vision-and-principles.md)); `approximate` is unused in v1 (ambient verbs deferred, [09-open-problems.md](09-open-problems.md)).
  - `kind` drops the prototype's speculative `sentenceFrame` until a generator exists for it (P4).
- **`ItemProgress`** — the unification of the prototype's `WordStats` and `ItemLearningState`. Invariants (enforced in code, tested as properties):
  - stage transitions are monotonic except `learning → ready` on lapse (see [04-learning-engine.md](04-learning-engine.md));
  - `engagedCount` credit toward readiness is capped (the "hovering can't power-level" rule);
  - `srsBox` changes only via a graded practice result, never via exposure;
  - `dueAt` is non-NULL iff stage ∈ {learning, known, mastered}.
- **`ExposureEvent`**, **`CapturedSentence`**, **`PracticeResult`**, **`Snapshot`** — see [04](04-learning-engine.md) and [05](05-extension.md).

## Data lifecycle

### Pack import and upgrade (stable IDs)
- Item IDs are **content-addressed slugs** (`de.word.haus`, `de.chunk.es-gibt`) minted by packtool and stable across pack versions. Progress joins on `itemId`, so re-importing `de-2026.08` over `de-2026.07` preserves all progress.
- Import is transactional: upsert `vocab_item` rows, insert the `pack` row, delete items absent from the new pack **only if** they have no progress (otherwise mark `replacementPolicy = 'never'` and keep them reviewable).
- The pack's declared checksum is verified before import.

### Event ingestion
- `EventIngestor` runs inside one transaction: insert events (ignoring duplicate UUIDs — idempotency, **R5**), fold unprocessed events into `item_progress`, stamp `processedAt`, bump the snapshot version in `settings`. The dashboard updates automatically via `ValueObservation`; the extension learns the new version on its next event flush (piggyback, [05-extension.md](05-extension.md)).
- **Pruning**: processed events older than 30 days are deleted; counts already live in `item_progress`.

### Sentence capture retention
- Ring buffer per item: keep the newest **5** sentences per item, cap total store at ~2,000 rows. Privacy classification: device-local; participates in LLM calls only under the `sendsPageText` tier ([06-llm-integration.md](06-llm-integration.md)).

### No legacy migration (D8)
The rebuild does **not** read the prototype's `UserDefaults` state, does not implement `resolveItemID`/legacy-word-ID shims, and does not port the v2→v3 migration. Recorded here so it never gets rebuilt "just in case."

## Snapshot economics (R3)

The `SnapshotBuilder` output (active slice: stages `ambient`–`known`, typically 50–200 items) must stay **< 100 KB** JSON and the extension's matcher build from it **< 5 ms**. Mastered items leave the snapshot (they may re-enter rarely via the scheduler's sampling rule). Enforced by a LearnerCore test that builds a snapshot from a full 1,000-item pack with 200 active items and asserts the size bound.
