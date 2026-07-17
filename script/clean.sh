#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

rm -rf "$ROOT_DIR/.build"
rm -rf "$ROOT_DIR/build"
rm -rf "$ROOT_DIR/extension/dist-resources"

if [[ "${1:-}" == "--dependencies" ]]; then
  rm -rf "$ROOT_DIR/extension/node_modules"
elif [[ $# -gt 0 ]]; then
  echo "usage: $0 [--dependencies]" >&2
  exit 2
fi

echo "✓ Removed generated build output."
