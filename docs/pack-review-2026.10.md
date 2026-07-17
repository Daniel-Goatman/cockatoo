# German pack 2026.10 — human spot-review record

## Status

**Incomplete — awaiting Daniel's review.** This record must not be marked
accepted by an agent or by the same model that helped author the content.

Review-bound artifacts:

```text
pack:      packs/build/de-2026.10.json
SHA-256:   f4752a8f17e72c42ffcc83671ef15287aa12973c9a2b5f17b189e123fd71550b
generator: packs/sources/de/build-seed.mjs
SHA-256:   2eb8f84337c172298702673cbe189f1a8b8e2930c75d9a6986ba8bbce307605f
sample:    cockatoo-de-2026.10-review-v1
```

Automated checks completed on 2026-07-17:

- [x] generator output is byte-for-byte identical to the built and bundled pack
- [x] `packtool validate`: 212 items, 0 failures, 0 warnings
- [x] `packtool import-test`: 212 items imported
- [x] every item has three examples (636 total)
- [x] invalid mass-noun source forms (`a money`, `an internet`, `a weather`,
  `a sun`, `a snow`) were removed before review
- [x] provenance is documented in `packs/sources/de/PROVENANCE.md`

## Human review procedure

Run:

```sh
node script/review-german-pack.mjs
```

The command refuses to run if the pack checksum differs from this record. For
each sampled item, check:

1. the English source represents the intended dominant sense;
2. German target, gender, plural, and part of speech are correct;
3. every source form maps safely to its target form on a normal web page;
4. the explanation is accurate;
5. all three example pairs are natural and equivalent.

Mark each ID below only after checking all five points. Record any failure in
the corrections table; fix the source generator, regenerate the pack, update
the hashes, and re-check the changed item before acceptance.

Acceptance bar: at least 48 of 50 sampled items pass on first inspection, all
found errors are corrected, and the final pack checksum matches this record.

## Deterministic 50-item sample

- [ ] `de.word.oder`
- [ ] `de.chunk.es-gibt`
- [ ] `de.chunk.zum-beispiel`
- [ ] `de.word.immer`
- [ ] `de.word.ja`
- [ ] `de.chunk.ich-glaube`
- [ ] `de.chunk.natuerlich`
- [ ] `de.word.bald`
- [ ] `de.word.leider`
- [ ] `de.word.schon`
- [ ] `de.word.trotzdem`
- [ ] `de.chunk.ich-weiss-nicht`
- [ ] `de.word.bruder`
- [ ] `de.word.ueberall`
- [ ] `de.word.acht`
- [ ] `de.word.apfel`
- [ ] `de.word.besonders`
- [ ] `de.word.brot`
- [ ] `de.word.fuenf`
- [ ] `de.word.kaffee`
- [ ] `de.word.lehrer`
- [ ] `de.word.neun`
- [ ] `de.word.sechs`
- [ ] `de.word.zehn`
- [ ] `de.word.draussen`
- [ ] `de.word.hundert`
- [ ] `de.word.mittwoch`
- [ ] `de.word.moment`
- [ ] `de.word.samstag`
- [ ] `de.word.stunde`
- [ ] `de.word.weniger`
- [ ] `de.chunk.kein-problem`
- [ ] `de.word.computer`
- [ ] `de.word.ende`
- [ ] `de.word.irgendwo`
- [ ] `de.word.person`
- [ ] `de.word.unten`
- [ ] `de.chunk.auf-jeden-fall`
- [ ] `de.chunk.zum-glueck`
- [ ] `de.word.november`
- [ ] `de.word.reise`
- [ ] `de.word.september`
- [ ] `de.word.uebermorgen`
- [ ] `de.word.garten`
- [ ] `de.word.wetter`
- [ ] `de.word.baum`
- [ ] `de.word.katze`
- [ ] `de.word.mund`
- [ ] `de.word.ohr`
- [ ] `de.word.see`

## Corrections

| Item | Problem | Correction | Re-checked |
|---|---|---|---|
| — | — | — | — |

## Sign-off

- First-pass result: _pending_ / 50
- Corrections resolved: _pending_
- Reviewer: _pending_
- Review date: _pending_
- Final pack SHA-256: _pending_
- Decision: **pending**
