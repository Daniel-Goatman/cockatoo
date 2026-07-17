# 06 — Agent and LLM pack authoring

> Status: offline authoring foundation implemented. Schema-2 accepted source,
> checksum-bound human review, canonical `packtool build`, an agent prompt, and
> a no-network Spanish fixture ship in the repository. A live-provider adapter
> remains optional and external. No model client, Tutor, provider settings,
> API-key storage, contextual resolver, or network entitlement ships in the app.

## Boundary

Model use is a contributor tool, not a learner-facing runtime feature. It may
draft candidate pack source, explanations, forms, and examples. It may not:

- edit a built pack directly;
- mutate learner progress or the app database;
- bypass deterministic validation;
- mark its own output reviewed;
- send browsing history or captured learner sentences.

The shipped app remains fully local and contains no API-key path.

## Implemented pipeline

```text
licensed corpus + language config
  → deterministic candidate list
  → agent/LLM draft source
  → schema parse
  → deterministic normalization and validation
  → human review record
  → reproducible built pack + checksum
```

Generated drafts live in a reviewable source format separate from
`packs/build/*.json`. The build command must produce byte-identical output from
accepted source, regardless of which provider originally drafted it.

## Provider contract

The future CLI should accept a provider-neutral configuration such as base URL,
model, and structured-output capabilities. Provider secrets are passed through
the contributor's environment or local secret store and are never written to
the repository, provenance record, logs, or pack.

At least one fixture provider must make the authoring pipeline testable without
network access. Live-provider tests are opt-in and never part of pull-request CI.

## Required provenance

Every generated or assisted batch records:

- source and target BCP 47 language tags;
- source corpus name, version, URL, and license;
- authoring tool version and prompt/template version;
- provider/model identifier when applicable, but no secret or account data;
- generation timestamp and deterministic input checksum;
- validator version and output;
- human reviewer, checklist status, and accepted source commit.

## Failure posture

Malformed, incomplete, duplicated, ambiguous, or policy-violating output is a
failed draft. The tool never repairs a built pack silently. Retrying generation
creates a new draft and provenance entry; deterministic checks and human review
still apply.

Commands, schemas, expansion rules, and the provider-neutral prompt live in
[`packs/README.md`](../../packs/README.md). `packtool build` refuses validator
failures, incomplete review checklists, and review records whose checksum no
longer matches the accepted source.
