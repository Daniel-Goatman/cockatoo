#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION=Release
FORCE_UNSIGNED=0

usage() {
  echo "usage: $0 [--debug] [--release] [--unsigned]" >&2
}

for argument in "$@"; do
  case "$argument" in
    --debug) CONFIGURATION=Debug ;;
    --release) CONFIGURATION=Release ;;
    --unsigned) FORCE_UNSIGNED=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

if [[ ! -d "$ROOT_DIR/extension/node_modules" ]]; then
  echo "error: dependencies are missing; run script/bootstrap.sh first" >&2
  exit 1
fi

printf '▸ Building WebExtension resources\n'
(cd "$ROOT_DIR/extension" && npm run build --silent)

DERIVED_DATA="$ROOT_DIR/build/DerivedData"
XCODE_ARGS=(
  -project "$ROOT_DIR/App/Cockatoo/Cockatoo.xcodeproj"
  -scheme Cockatoo
  -configuration "$CONFIGURATION"
  -destination "generic/platform=macOS"
  -derivedDataPath "$DERIVED_DATA"
)

if (( FORCE_UNSIGNED == 1 )); then
  XCODE_ARGS+=(
    'COCKATOO_CODE_SIGN_STYLE=Manual'
    'COCKATOO_CODE_SIGN_IDENTITY=-'
    'COCKATOO_DEVELOPMENT_TEAM='
    'COCKATOO_CODE_SIGNING_ALLOWED=NO'
    'CODE_SIGNING_REQUIRED=NO'
  )
fi

signing_label="configured signing"
if (( FORCE_UNSIGNED == 1 )) || [[ ! -f "$ROOT_DIR/App/Config/Local.xcconfig" ]]; then
  signing_label="unsigned"
fi
printf '▸ Building Cockatoo (%s, %s)\n' "$CONFIGURATION" "$signing_label"
xcodebuild "${XCODE_ARGS[@]}" build

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/Cockatoo.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: build completed without producing $APP_PATH" >&2
  exit 1
fi

printf '\n✓ %s\n' "$APP_PATH"
