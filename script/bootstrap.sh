#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/script/doctor.sh"
printf '\nInstalling extension dependencies with npm ci…\n'
(cd "$ROOT_DIR/extension" && npm ci)
printf '\nResolving Swift packages…\n'
(cd "$ROOT_DIR" && swift package resolve)

printf '\nBootstrap complete. Run script/check.sh next.\n'
