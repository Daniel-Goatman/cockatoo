#!/usr/bin/env bash
# Backward-compatible entrypoint. New documentation uses install-dev.sh.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$ROOT_DIR/script/install-dev.sh" --system "$@"
