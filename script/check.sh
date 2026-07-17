#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKIP_XCODE=0

if [[ "${1:-}" == "--skip-xcode" ]]; then
  SKIP_XCODE=1
elif [[ $# -gt 0 ]]; then
  echo "usage: $0 [--skip-xcode]" >&2
  exit 2
fi

if [[ ! -d "$ROOT_DIR/extension/node_modules" ]]; then
  echo "error: dependencies are missing; run script/bootstrap.sh first" >&2
  exit 1
fi

printf '▸ Swift tests\n'
(cd "$ROOT_DIR" && swift test)

printf '▸ Extension tests and boundaries\n'
(cd "$ROOT_DIR/extension" && npm audit --audit-level=high && npm test && npm run lint:boundaries && npm run build)

printf '▸ German pack reproducibility and validation\n'
GENERATED_PACK="$(mktemp -t cockatoo-pack)"
trap 'rm -f "$GENERATED_PACK"' EXIT
node "$ROOT_DIR/packs/sources/de/build-seed.mjs" > "$GENERATED_PACK"
cmp "$GENERATED_PACK" "$ROOT_DIR/packs/build/de-2026.10.json"
node "$ROOT_DIR/script/review-german-pack.mjs" >/dev/null
(cd "$ROOT_DIR" && swift run packtool validate packs/build/de-2026.10.json)
(cd "$ROOT_DIR" && swift run packtool import-test packs/build/de-2026.10.json)

printf '▸ Multilingual reviewed-source fixture\n'
GENERATED_SAMPLE="$(mktemp -t cockatoo-pack-es)"
trap 'rm -f "$GENERATED_PACK" "$GENERATED_SAMPLE"' EXIT
(cd "$ROOT_DIR" && swift run packtool build packs/sources/es/sample.accepted.json \
  --review packs/sources/es/sample.review.json --output "$GENERATED_SAMPLE")
cmp "$GENERATED_SAMPLE" "$ROOT_DIR/packs/build/es-sample-2026.01.json"
(cd "$ROOT_DIR" && swift run packtool import-test packs/build/es-sample-2026.01.json)

if (( SKIP_XCODE == 0 )); then
  printf '▸ Unsigned Xcode build\n'
  "$ROOT_DIR/script/build.sh" --debug --unsigned
fi

printf '\n✓ All checks passed.\n'
