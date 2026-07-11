# 03 — Data Model and Storage

> The single source of truth: SQLite via GRDB in the App Group container. Resolves risk **R2** (cross-process access) and enforces **P2** (one progress store) and the **no-legacy-migration** anti-goal. See [02-architecture.md](02-architecture.md) decisions D1, D7, D8, D9.

## Storage engine

- **GRDB `DatabasePool`**, SQLite in **WAL mode**, database file in the App Group container (`group.<bundle-prefix>.cockatoo`).
- Both the app and the appex open the same file. WAL permits one writer + concurrent readers across processes; writes set a **busy timeout** (e.g. 2 s) and retry once on `SQLITE_BUSY`.
- **Change signaling**: any process that commits a write posts a Darwin notification `<bundle-prefix>.cockatoo.db.changed`. The app listens and refreshes its queries. GRDB's `ValueObservation` is in-process only and must not be relied on for cross-process freshness.
- **Appex statelessness**: the appex opens the pool, handles one message, posts the notification if it wrote, and returns. It never caches state between invocations.
- **Migrations**: GRDB `DatabaseMigrator` with numbered, append-only migrations (`v1`, `v2`, …). No decode-time migration logic anywhere (the prototype's `Codable`-migration habit is banned).
- **Keychain**: LLM API keys live in the Keychain under a shared access group, never in the DB, UserDefaults, or any plist. Nothing learning-related lives in UserDefaults at all.

### R2 spike (must run in Phase 0, see [08-roadmap.md](08-roadmap.md))

Prove before building on it: app + minimal appex, both with the App Group entitlement, can (a) open the same `DatabasePool`, (b) appex writes while app reads, (c) appex is killed mid-transaction without corrupting the DB (WAL recovery), (d) Darwin notification wakes the app. **Fallback if blocked**: the appex talks to the app via `NSXPCConnection` (app-owned agent) and only the app touches SQLite. The Store API is designed so this swap changes no callers.

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
  sourceForms       TEXT NOT NULL,      -- JSON: [{form:"house", target:"Haus"},
                                        --        {form:"houses", target:"Häuser"}]
  target            TEXT NOT NULL,      -- canonical target: "Haus"
  targetMeta        TEXT,               -- JSON: gender, plural, pronunciation, POS
  level             TEXT NOT NULL,      -- CEFR: a1 | a2 | b1
  frequencyBand     INTEGER NOT NULL,   -- 1..10, corpus-derived
  replacementPolicy TEXT NOT NULL,      -- ambientSafe | reviewOnly | never
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

- **`VocabItem`** — evolves the prototype's `CurriculumItem` (`Sources/LanguageLearnerCore/CurriculumItem.swift`). Carried over: `kind`, `replacementPolicy`, `dependencies`, `frequencyBand`, `explanation`, `examples`. New and load-bearing: **`sourceForms`** — the enumerated English surface forms each with its own target-language form (`"houses" → "Häuser"`), authored at pack-build time. This is the default (non-LLM) answer to the inflection problem **R1a**; the matcher matches forms, not lemmas ([05-extension.md](05-extension.md)), and the contextual LLM path ([06-llm-integration.md](06-llm-integration.md)) is an opt-in upgrade, not a requirement.
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
- `EventIngestor` runs inside one transaction: insert events (ignoring duplicate UUIDs — idempotency, **R5**), fold unprocessed events into `item_progress`, stamp `processedAt`, bump the snapshot version in `settings`, post the Darwin notification.
- **Pruning**: processed events older than 30 days are deleted; counts already live in `item_progress`.

### Sentence capture retention
- Ring buffer per item: keep the newest **5** sentences per item, cap total store at ~2,000 rows. Privacy classification: device-local; participates in LLM calls only under the `sendsPageText` tier ([06-llm-integration.md](06-llm-integration.md)).

### No legacy migration (D8)
The rebuild does **not** read the prototype's `UserDefaults` state, does not implement `resolveItemID`/legacy-word-ID shims, and does not port the v2→v3 migration. Recorded here so it never gets rebuilt "just in case."

## Snapshot economics (R3)

The `SnapshotBuilder` output (active slice: stages `ambient`–`known`, typically 50–200 items) must stay **< 100 KB** JSON and the extension's matcher build from it **< 5 ms**. Mastered items leave the snapshot (they may re-enter rarely via the scheduler's sampling rule). Enforced by a LearnerCore test that builds a snapshot from a full 1,000-item pack with 200 active items and asserts the size bound.
