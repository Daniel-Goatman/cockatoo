# German starter-pack provenance

## Status

German `2026.10` is the 212-item pack bundled with the source-only v0.1
Developer Preview. It is reproducible and validator-clean. Its deterministic
human spot review is still pending and is tracked in
`docs/pack-review-2026.10.md`; do not describe it as production-reviewed until
that record is complete.

## Lineage

- The first 54 items were project-authored and shipped as `de-2026.07` in
  commit `7789644c80d0e0b22afccc81da3e20fdb1aadef6`.
- Commit `3b800f653d505ef74a485e7d0ea25b152ea1673a` expanded the pack from 54 to
  212 items. Its commit record identifies Daniel Goatman as author and Claude
  Fable 5 as co-author. The items were frequency-informed and hand-ordered;
  the planned FrequencyWords/OpenSubtitles ingestion pipeline was not used.
- Commit `5f4be9ba3e799d5e04176973db0ce990201ee126` added two project-authored,
  model-assisted examples to every item (424 additional examples), again with
  Daniel as author and Claude Fable 5 as co-author.
- `packs/sources/de/build-seed.mjs` is now the editable source of truth. It
  deterministically produces `packs/build/de-2026.10.json`, which is copied
  byte-for-byte into the app resources.

No third-party frequency list or corpus text is embedded in this pack. The
pack content is distributed with the repository under the PolyForm Noncommercial
License 1.0.0. Model assistance is disclosed in both this record and the built
pack's provenance metadata.

## Reproduce and verify

```sh
node packs/sources/de/build-seed.mjs > /tmp/de-2026.10.json
cmp /tmp/de-2026.10.json packs/build/de-2026.10.json
swift run packtool validate packs/build/de-2026.10.json
swift run packtool import-test packs/build/de-2026.10.json
```

Review-bound artifact hashes before human sign-off:

```text
pack SHA-256:      7597229f6257cb51160e8992058fd0cbfe5f575aa3359dbef3c507d0b14041e9
generator SHA-256: 73bfc619fe3873b6b212622e2dc537075a0af2162d046914a98fc3faf9be3485
```
