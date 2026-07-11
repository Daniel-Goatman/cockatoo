# 06 — LLM Integration

> One OpenAI-compatible provider layer (P6), features built on it under strict privacy tiers (P3), and graceful degradation everywhere (risk **R8**). Replaces the prototype's Ollama-specific, German-hardcoded, regex-sanitized tutor. The model assists; it never owns truth (P5).

## Provider layer

### `ChatProvider` protocol (`LearnerCore/LLM`)

```swift
protocol ChatProvider {
  func complete(_ messages: [ChatMessage], options: CompletionOptions) async throws -> Completion
  func stream(_ messages: [ChatMessage], options: CompletionOptions) -> AsyncThrowingStream<CompletionDelta, Error>
}
struct CompletionOptions { var maxTokens: Int; var temperature: Double
                           var responseSchema: JSONSchema?  // structured output, if supported
                           var timeout: TimeInterval }
```

### `OpenAICompatClient` — the only v1 implementation

- Config: **base URL + model name + API key reference (Keychain)**. This one client covers **OpenRouter** (`https://openrouter.ai/api/v1`), **OpenAI**, **llama.cpp server** (`http://127.0.0.1:8080/v1`), and **Ollama** (`http://127.0.0.1:11434/v1`) — all speak `/v1/chat/completions`. No provider-specific branches survive; base-URL presets in Settings are just prefilled strings.
- Settings UI: base URL, model, API key (stored to Keychain on save, D7), **Test connection** button (1-token completion; reports latency + model echo), per-feature enable toggles.
- Multiple named provider profiles are out of scope for v1; one active profile.

### Structured output strategy (replaces the regex sanitizer)

1. If `responseSchema` is set, send `response_format: {type: "json_schema", ...}`; providers that support it (OpenAI, OpenRouter for many models) return validated JSON.
2. Fallback ladder for providers/models that don't: strict "reply with only JSON matching…" prompt → `JSONDecoder` parse → on failure, **one retry** with the parse error appended → on second failure, surface a typed `LLMError.malformedOutput` to the feature layer.
3. Features never regex-patch model text. If output is unusable, the feature degrades (below) — the prototype's `GermanTutorResponseSanitizer` pattern is banned.

## Privacy tiers (P3) — enforced in code

Every LLM feature is declared with a tier; the enforcement point is `LLMGateway`, the single choke point through which all feature clients call the provider:

| Tier | May include in prompts | Gate |
|---|---|---|
| `localOnly` | nothing leaves the device (no LLM call at all) | always available |
| `sendsWordIds` | curriculum items, learner-state summaries (stages, counts), user-typed chat text | provider configured |
| `sendsPageText` | captured sentences / page-derived text | provider configured **AND** `pageContextOptIn == true` |

`LLMGateway` refuses a `sendsPageText` call when the opt-in flag is off — the appex handler applies the same check server-side for `getContextualForm` ([05-extension.md](05-extension.md)), so a compromised or stale extension cannot bypass it. The opt-in is a single explicit switch in Settings with plain-language copy about exactly what is sent.

## Features

### 1. Word deep-dive (`sendsWordIds`)
On demand from the Library item view (and later the hover card's "Explain"). Generates: full form table (gender, plural, conjugations as applicable), 3 graded example sentences (using only vocabulary at or below the learner's unlocked tier where possible), usage notes, one mnemonic. Structured-output JSON → rendered natively → **cached in `enrichment`** keyed `(itemId, kind: deepDive)` — generated once, free forever after.

### 2. Tutor chat (`sendsWordIds`)
- Prompt template **parameterized by language** — the template takes `(targetLanguage, learnerSummary, focusItems)`; no hardcoded German anywhere.
- Grounding: the system prompt includes a compact learner summary (unlocked tier, counts by stage, 5 weakest items by lapses) so answers meet the learner where they are.
- Streaming responses; conversation history kept in memory per session (not persisted in v1).
- No substring "intent detection" — the model sees the question; the app doesn't pre-classify it.

### 3. Contextual form resolver (`sendsPageText`, opt-in — the R1c upgrade)
- Given `(item, sentence)`, returns the correctly inflected target form for *that* sentence (e.g. "the **houses** were old" → `Häuser`; case-marked forms where German requires them).
- Called by the appex via `getContextualForm`; **cached in `enrichment`** keyed `(itemId, kind: contextualForm, cacheKey: sentenceHash)` so repeated encounters are free and offline-safe.
- Latency posture: the extension renders the authored `sourceForms` target **immediately** and upgrades the token text if/when the resolver answers (< 2 s budget, else keep authored form). Ambient rendering never blocks on the network.
- Also used at pack-build time in reverse ([07-content-pipeline.md](07-content-pipeline.md)) — same prompt family, different caller.

### 4. Pack authoring (build-time, packtool)
Not a runtime feature, but it rides the same `ChatProvider` — see [07-content-pipeline.md](07-content-pipeline.md).

## Failure / degradation matrix (R8)

Everything core works with no provider configured (P3). Per-feature behavior when the provider is unreachable, slow, or returns garbage:

| Feature | No provider | Timeout / error | Malformed output |
|---|---|---|---|
| Ambient replacement + hover | unaffected (localOnly path) | unaffected | — |
| Review sessions | unaffected | unaffected | — |
| Deep-dive | button hidden; pack `explanation`/`examples` shown | cached enrichment if any, else pack data + retry affordance | same as timeout |
| Tutor | tab shows setup notice with Settings link | inline error, input preserved | inline error |
| Contextual forms | authored `sourceForms` used (default anyway) | authored form kept (2 s budget) | authored form kept; bad output never cached |

Cost/rate posture: deep-dive and contextual-form are cached-by-design; the tutor is user-paced. No background/batch runtime LLM traffic exists, so cost scales with explicit user actions only. A settings-visible "requests this week" counter keeps it honest.
