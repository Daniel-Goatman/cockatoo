# extension/ — agent instructions

TypeScript WebExtension. This side renders and reports; it must never know
what SRS, tiers, or mastery are (P1 — see repo-root AGENTS.md).

## Commands

- `npm test` — vitest (jsdom) incl. shared protocol fixtures
- `npm run build` — esbuild → `dist-resources/` (the appex copies this at
  Xcode build time; `script/install.sh` runs both steps)
- `npm run lint:boundaries` — enforces the adapter seam

## Structure rules

- `src/core/**` is browser-agnostic. `browser.runtime.sendNativeMessage`
  may appear ONLY in `src/adapters/safari/` (lint-enforced). A Chrome port
  replaces the adapter, nothing else.
- All native calls go through the background script's watched `Transport`
  wrapper (`background.ts`) so popup status stays truthful. Don't call the
  transport directly from content/popup code.
- Envelope building goes through `buildEnvelope()` in `core/types.ts` —
  payload is a JSON **string** (mirrors Swift; fixture-pinned).
- Protocol types in `core/types.ts` mirror Swift's
  `Sources/LearnerCore/Sync/Messages.swift`. Changing either side requires
  updating the other AND `../protocol-fixtures/` in the same commit.
- Event IDs are client-generated UUIDs; the queue is at-least-once with
  ack-then-clear — duplicates are harmless (idempotent ingestion), lost
  events are not. Don't "optimize" the queue into fire-and-forget.
- Perf budgets are tested (initial apply, incremental mutations, infinite
  scroll fixture). The transformer must never re-scan the whole page on
  mutation — added subtrees only, debounced, budget persists across batches.

## Styling

`styles.css` + `popup.css` carry the native app's graphite/ivory brand with
system light/dark variants, Iowan target-language type, blue "on pages"
tokens, and restrained gold actions. Keep new UI in that language; tokens
stay subtle (P7: never make a page feel broken).
