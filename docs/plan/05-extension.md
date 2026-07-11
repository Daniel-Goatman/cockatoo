# 05 — Safari Extension

> Rendering, capture, and the sync protocol. The extension is a dumb renderer + event emitter (P1): it knows the snapshot and the DOM, never the learning rules. Carries forward the prototype's proven transformer rules and fixes its two performance faults (full-page re-apply per mutation; 2 s polling). Perf requirements resolve risk **R4**; inflection default resolves **R1a/R1b** (the LLM upgrade path R1c is in [06-llm-integration.md](06-llm-integration.md)).

## Page gate (`pageGate`)

Runs before anything else; if it says no, the content script does nothing (no observers, no messaging).

- Schemes: `http`/`https` only.
- **Sensitive-host denylist** carried over from the prototype's `policy.js`: banking/payment/health/government patterns, plus user-blocked hosts from settings.
- **Per-site toggle**: user can disable/enable per host (eTLD+1) from the toolbar popup; verdicts come with the settings in the snapshot payload.
- Skip if the cached snapshot has zero ambient items.

## Matcher

- Built **once per snapshot** from the snapshot's match table: `Map<lowercasedSurfaceForm, {itemId, formIndex}>`. Multi-word chunks are stored under their first word with full-phrase confirmation at match time.
- Matching is per **surface form** (`house`, `houses` are separate entries with separate targets) — this is the R1a mechanism: inflection is resolved at authoring time, not at match time.
- Word-boundary regex per form (`\bform\b`, case-insensitive; `(?<!\w)phrase(?!\w)` for chunks), compiled lazily and cached.
- Budget: matcher build **< 5 ms** for a 200-item snapshot (test-enforced, R3).

## Transformer

Carried-over rules (from `transformer.js`, validated by the prototype):

- **Block model**: only inside `p, li, blockquote, [role='listitem']` etc.; excluded: inputs, `contenteditable`, `code/pre/kbd/samp`, `nav/header/footer/button`, `[aria-hidden]`, anything inside a form with sensitive attributes (password/checkout/billing patterns).
- **Budget math**: page budget = `clamp(floor(totalWords/40), 3, 20)`; per-block = `max(1, floor(blockWords/25))`, blocks < 8 words skipped; even distribution across candidate blocks; one instance per item per block.
- **Token DOM contract**: `<span class="cck-token" data-cck-item data-cck-form data-cck-original tabindex="0" role="button" aria-label="Cockatoo vocabulary: <target>, originally <original>">` containing the target-language text. Original text restorable from the attribute. Tokens get a **subtle but visible mark** (light underline + tint) — the R1b stance: a swapped token reads as a vocabulary card in place, so an imperfectly inflected form doesn't read as broken prose.
- **Visibility check** fixed relative to prototype: element must have a non-empty client rect and effective `opacity > 0` before counting toward budget (closes the invisible-token "seen" credit hole).

New behavior (the R4 fixes — these are requirements, not suggestions):

- **Incremental mutation handling**: the `MutationObserver` collects **added subtrees only** (plus text changes inside candidate blocks), ignores self-inflicted mutations, and processes the batch after a **250 ms trailing debounce**. It never re-scans the whole page after initial apply.
- **Persistent page budget**: the budget is initialized from the initial page word count and decremented as tokens are placed; mutation batches may add tokens only from remaining budget (infinite scroll grows the budget by the *added* text's word count, same 1/40 ratio, still hard-capped at 20 visible tokens per page).
- **Perf budgets** (measured on fixture pages in CI): initial apply < 30 ms on a 10k-word article; mutation batch < 10 ms on an infinite-scroll append; zero work on pages with no candidates (gate short-circuits).

## Hover card

Carried over from the prototype's `hoverCard.js` design: floating card appended to `<body>`, `role="dialog"`, viewport-aware positioning with flip, open on `mouseover`/`focusin`, close after 90 ms grace on out, **click pins**, `Escape` closes, repositions on scroll/resize. Keyboard: tokens are tabbable; `Enter` pins.

Content (all from the snapshot — no lookups, no learning math): target form, original text, canonical target + gender/POS from `targetMeta`, one example, seen-count display. Buttons appear **only if functional** (P4): v1 ships exactly one — "Open in Cockatoo" (deep-links the app's Library to the item). "Explain" appears in v1.1 wired to enrichment ([06-llm-integration.md](06-llm-integration.md)).

## Exposure tracking and events

- **`seen`**: `IntersectionObserver` — token ≥ 50% visible for ≥ 1 s continuous dwell, at most one `seen` per token per page load.
- **`engaged`**: hover/focus ≥ 400 ms, one per token per page load. **`pinned`**: click-pin.
- **`sentenceCaptured`**: on `engaged`, capture the containing sentence — extracted from the block's normalized `innerText` (fixes the prototype's node-concatenation mangling) with the token's *original* English restored in place, sentence-split on `[.!?…]` with min/max length guards. Local only.
- **Event envelope**: `{id: uuid, itemId, type, occurredAt, host?: eTLD+1}` — idempotent by `id` (**R5**).
- **Event queue** (background script): append to `storage.local` queue; flush when queue ≥ 20 events, every 30 s while events exist, and on tab hide. Flush is at-least-once: the queue is cleared only after the native response acknowledges; duplicates are harmless by idempotency. No silent `catch`-and-drop (the prototype's fire-and-forget flaw).

## Messaging protocol

All messages are JSON envelopes: `{protocolVersion: 1, method, payload}`. The Swift handler rejects unknown/mismatched `protocolVersion` with a structured error the popup surfaces as "Update Cockatoo". TypeScript types for the payloads are the mirror of Swift Codables in `LearnerCore/Sync` — one spec, two encodings, covered by shared JSON fixture tests on both sides.

| Method | Request | Response |
|---|---|---|
| `getSnapshot` | `{sinceVersion?: number}` | `{version, unchanged: true}` or `{version, snapshot}` |
| `postEvents` | `{events: ExposureEvent[]}` | `{accepted: number, latestVersion: number}` |
| `getSettings` | `{}` | `{enabled, blockedHosts, pageContextOptIn, activeLanguage}` |
| `getContextualForm` | `{itemId, sentence, sentenceHash}` | `{form}` or `{error}` — **only callable when `pageContextOptIn` is true**; the handler enforces the gate server-side, not just UI-side |
| `openDashboard` | `{itemId?}` | `{}` — launches the app via its registered URL scheme (`cockatoo://item/<id>`), not bundle-path arithmetic |

### Snapshot payload

```jsonc
{
  "version": 412,                    // monotonic; bumped on any progress/settings/pack change
  "language": "de",
  "settings": { "blockedHosts": [], "pageContextOptIn": false },
  "items": [                         // active slice only: stages ambient..known, ~50–200 items
    {
      "id": "de.word.haus",
      "kind": "word",
      "forms": [ {"match": "house", "display": "Haus"},
                 {"match": "houses", "display": "Häuser"} ],
      "hover": { "target": "das Haus", "pos": "noun", "original": null,
                 "example": {"source": "…", "target": "…"}, "seenCount": 4 }
    }
  ]
}
```

Size bound < 100 KB (R3, enforced by a LearnerCore test). The full pack never crosses the boundary (D5).

### Freshness (no polling — replaces the prototype's 2 s loop)

1. Background caches `{version, snapshot}` in `storage.local`; content scripts request it via one runtime message at `document_idle`.
2. Every `postEvents` response carries `latestVersion`; if newer than cached, background calls `getSnapshot(sinceVersion)`. Browsing generates events, so freshness tracks activity.
3. Floor: a `browser.alarms` heartbeat every **10 min** calls `getSnapshot(sinceVersion)` (cheap `unchanged` reply when stale-free).
4. Always refresh on browser/extension startup and popup open.

## Adapters and portability

`src/core/**` is browser-agnostic and imports a single `Transport` interface: `{call(method, payload), cacheGet/cachePut}`. `src/adapters/safari/` implements it over `browser.runtime.sendNativeMessage` + `storage.local`. A Chrome port implements the same interface over another transport ([02-architecture.md](02-architecture.md)). Lint rule: `sendNativeMessage` may appear only under `adapters/safari/`.

## Test harness

- **Vitest + jsdom** for matcher/transformer/eventQueue units; a `FakeTransport` with scripted snapshots.
- **Fixture pages** (static HTML in `extension/test/fixtures/`): long-form article, list-heavy page, form/checkout page (expects zero tokens), code-heavy page (zero tokens in code), and an **infinite-scroll simulator** that appends blocks on a timer — the perf budgets above are asserted against it.
- Shared JSON fixtures for every protocol message, decoded by both the Swift tests and the TS tests, so the two sides can't drift.
