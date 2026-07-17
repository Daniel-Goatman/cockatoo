#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-run}"
APP_PATH="$ROOT_DIR/build/DerivedData/Build/Products/Debug/Cockatoo.app"
APP_BINARY="$APP_PATH/Contents/MacOS/Cockatoo"

case "$MODE" in
  run)
    exec "$ROOT_DIR/script/install-dev.sh" --debug
    ;;
  --verify|verify)
    "$ROOT_DIR/script/install-dev.sh" --debug
    sleep 2
    pgrep -x Cockatoo >/dev/null
    echo "✓ Cockatoo is running"
    ;;
  --debug|debug)
    "$ROOT_DIR/script/build.sh" --debug
    pkill -x Cockatoo >/dev/null 2>&1 || true
    exec lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    "$ROOT_DIR/script/install-dev.sh" --debug
    exec /usr/bin/log stream --info --style compact --predicate 'process == "Cockatoo"'
    ;;
  --telemetry|telemetry)
    "$ROOT_DIR/script/install-dev.sh" --debug
    exec /usr/bin/log stream --info --style compact --predicate 'process == "Cockatoo" OR process == "CockatooExtension Extension"'
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
