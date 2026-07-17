#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION=Release
FORCE_UNSIGNED=0
RESTART_SAFARI=0
SYSTEM_INSTALL=0

usage() {
  echo "usage: $0 [--debug] [--release] [--restart-safari] [--system]" >&2
}

BUILD_ARGS=()
for argument in "$@"; do
  case "$argument" in
    --debug) CONFIGURATION=Debug; BUILD_ARGS+=(--debug) ;;
    --release) CONFIGURATION=Release; BUILD_ARGS+=(--release) ;;
    --unsigned) FORCE_UNSIGNED=1 ;;
    --restart-safari) RESTART_SAFARI=1 ;;
    --system) SYSTEM_INSTALL=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

if (( FORCE_UNSIGNED == 1 )); then
  echo "error: an unsigned install cannot use Cockatoo's App Group IPC; use script/build.sh --unsigned for compile verification only" >&2
  exit 1
fi
if [[ ! -f "$ROOT_DIR/App/Config/Local.xcconfig" ]]; then
  echo "error: installing the Safari extension requires an Apple Development configuration at App/Config/Local.xcconfig" >&2
  echo "copy App/Config/Local.example.xcconfig and follow docs/development.md" >&2
  exit 1
fi

"$ROOT_DIR/script/build.sh" "${BUILD_ARGS[@]}"

BUILT_APP="$ROOT_DIR/build/DerivedData/Build/Products/$CONFIGURATION/Cockatoo.app"
if (( SYSTEM_INSTALL == 1 )); then
  INSTALL_DIR="/Applications"
else
  INSTALL_DIR="$HOME/Applications"
fi
DESTINATION="$INSTALL_DIR/Cockatoo.app"

mkdir -p "$INSTALL_DIR"
case "$DESTINATION" in
  /Applications/Cockatoo.app|"$HOME/Applications/Cockatoo.app") ;;
  *) echo "error: refusing unexpected install destination: $DESTINATION" >&2; exit 1 ;;
esac

printf '▸ Replacing %s\n' "$DESTINATION"
osascript -e 'quit app "Cockatoo"' >/dev/null 2>&1 || true
pkill -x Cockatoo >/dev/null 2>&1 || true

STAGING="$INSTALL_DIR/.Cockatoo.app.staging.$$"
trap 'rm -rf "$STAGING"' EXIT
rm -rf "$STAGING"
ditto "$BUILT_APP" "$STAGING"
rm -rf "$DESTINATION"
mv "$STAGING" "$DESTINATION"
trap - EXIT

APPEX="$DESTINATION/Contents/PlugIns/CockatooExtension Extension.appex"
EXTENSION_ID="$(defaults read "$APPEX/Contents/Info.plist" CFBundleIdentifier)"
printf '▸ Registering Safari extension %s\n' "$EXTENSION_ID"
pluginkit -a "$APPEX"
pluginkit -m -v -i "$EXTENSION_ID" 2>/dev/null | awk -F'\t' '$NF ~ /^\// { print $NF }' | while IFS= read -r registered_path; do
  [[ "$registered_path" == "$APPEX" ]] && continue
  printf '  removing stale registration: %s\n' "$registered_path"
  pluginkit -r "$registered_path" >/dev/null 2>&1 || true
done
pkill -x "CockatooExtension Extension" >/dev/null 2>&1 || true

printf '▸ Launching Cockatoo\n'
open "$DESTINATION"

if (( RESTART_SAFARI == 1 )); then
  osascript -e 'quit app "Safari"' >/dev/null 2>&1 || true
  open -a Safari
else
  echo "note: reload existing Safari tabs when extension resources changed"
fi

printf '✓ Installed development build at %s\n' "$DESTINATION"
