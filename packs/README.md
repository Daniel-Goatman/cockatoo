# Language-pack authoring

Production Cockatoo packs are reviewed source artifacts, not runtime model
output. The app never calls an LLM and a model never writes directly to
`packs/build/`. The bundled German starter pack is a legacy seed-generator
artifact whose human review is explicitly still incomplete; it remains preview
content while it is migrated to the accepted-source workflow below.

## Directory contract

```text
packs/
  drafts/<language>/                 untrusted agent/LLM output; do not ship
  sources/<language>/*.accepted.json human-accepted editable source
  sources/<language>/*.review.json   human review gate bound to source checksum
  build/<language>-<version>.json    canonical packtool output
  schema/                            JSON Schema editing aids
  templates/agent-pack-prompt.md     provider-neutral drafting prompt
```

The Swift `PackFile` decoder and `PackValidator` are authoritative. JSON Schema
files improve editor and agent feedback but do not replace `packtool validate`.

## Create a pack

1. Copy `sources/es/sample.accepted.json` as a small starting point.
2. Set `sourceLanguage` and `language` to BCP 47 tags.
3. Configure `grading` and `validation`; these replace language-specific code.
4. Add stable item IDs prefixed by the target language, explicit `sourceLemma`,
   source forms, target metadata, examples, and safety policy.
5. Validate the accepted source:

```sh
swift run packtool validate packs/sources/es/sample.accepted.json
```

6. Review translations, forms, examples, ambient safety, and licensing. Record
   the exact source checksum in a separate review record:

```sh
swift run packtool checksum packs/sources/es/sample.accepted.json
```

7. Build. The command refuses mismatched checksums, incomplete review records,
   or validator failures and emits stable sorted JSON:

```sh
swift run packtool build packs/sources/es/sample.accepted.json \
  --review packs/sources/es/sample.review.json \
  --output packs/build/es-sample-2026.01.json
swift run packtool import-test packs/build/es-sample-2026.01.json
```

Running the same command from the same accepted source produces identical
bytes, regardless of which tool drafted the source.

To use a completed pack, open Cockatoo → Settings → Import language pack. An
explicit import makes that language active. Every installed language then
appears in the Active language picker; switching preserves each language's
progress and refreshes the extension snapshot.

## Draft with an agent or LLM

Use `templates/agent-pack-prompt.md` with a bounded candidate batch. Ask the
agent to write only a draft under `packs/drafts/<language>/`; then treat every
field as untrusted. A useful review cycle is:

```text
candidate list + language rules + prompt version
  → agent draft
  → schema/parse check
  → translation and morphology review
  → accepted source merge
  → packtool validate
  → human review checksum
  → packtool build
```

For an API-driven adapter, the provider is intentionally outside the shipped
app. It may use any base URL/model that returns the source schema. Pass secrets
through environment variables or a local secret store; never put them in a
draft, provenance, command log, or commit. Record only provider/model and prompt
version in `provenance`. CI uses the checked-in Spanish fixture and never calls
a network provider.

An agent cannot mark its own checklist complete. If generation is retried,
create a new draft and review the resulting diff again.

## Expand an existing pack

- Copy the latest accepted source and increment `version`.
- Preserve every existing item ID. Changing a translation does not justify a
  new ID; IDs are progress keys.
- Do not delete an introduced item. Keep it with `replacementPolicy: "never"`
  until a future explicit tombstone format exists.
- Add items in deterministic band/order and run:

```sh
swift run packtool validate new.accepted.json --previous old-built.json
swift run packtool review new.accepted.json --previous old-built.json > review-diff.md
```

- Recalculate the accepted-source checksum only after all edits are final.
- Update the review record and build output in the same pull request.
- For a bundled-pack upgrade, update the resource filename and references and
  verify that existing `item_progress` rows survive import.

## Language configuration

`grading` controls answer normalization:

- `articles`: optional leading target-language articles;
- `localeIdentifier`: locale used for case folding;
- `diacriticInsensitive`: whether omitted accents are accepted;
- `substitutions`: explicit equivalences such as German `ß` → `ss`.

`validation` controls ambient safety without code branches:

- `sourceDeterminers`: source-language prefixes used for noun-form checks;
- `nounPartsOfSpeech`: POS tags requiring determiner-extended forms;
- `disallowedAmbientPartsOfSpeech`: POS tags restricted to review;
- `allowApproximateAmbient`: normally `false` for fidelity.

The Spanish fixture deliberately uses Spanish grading, Spanish article display,
and strict accents while retaining English page-source rules. Tests also prove
that a French-source determiner configuration validates without code changes.
