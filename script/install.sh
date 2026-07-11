#!/bin/sh
# Build Cockatoo (app + Safari extension) and install to /Applications.
# Usage: script/install.sh [--debug] [--restart-safari]
#
# The /Applications copy is THE copy: stable path (extension registration
# survives), Release optimization, login-item capable. Use Xcode ⌘R only
# when you need the debugger.
set -eu

cd "$(dirname "$0")/.."
CONFIG=Release
RESTART_SAFARI=0
for arg in "$@"; do
  case "$arg" in
    --debug) CONFIG=Debug ;;
    --restart-safari) RESTART_SAFARI=1 ;;
    *) echo "unknown flag: $arg" >&2; exit 1 ;;
  esac
done

echo "▸ extension resources (npm run build)"
(cd extension && npm run build --silent)

echo "▸ xcodebuild ($CONFIG)"
xcodebuild -project App/Cockatoo/Cockatoo.xcodeproj \
  -scheme Cockatoo -configuration "$CONFIG" \
  -derivedDataPath build/DerivedData \
  build 2>&1 | grep -E "error:|warning: .*deprecated" || true

BUILT="build/DerivedData/Build/Products/$CONFIG/Cockatoo.app"
[ -d "$BUILT" ] || { echo "build failed — $BUILT missing" >&2; exit 1; }

echo "▸ installing to /Applications"
osascript -e 'quit app "Cockatoo"' 2>/dev/null || true
sleep 1
pkill -f "Cockatoo.app/Contents/MacOS/Cockatoo" 2>/dev/null || true
rm -rf /Applications/Cockatoo.app
ditto "$BUILT" /Applications/Cockatoo.app

# Safari loads the appex through pluginkit's registry. Stale registrations
# (DerivedData debug builds, backup copies of the app) silently win over the
# fresh install and the extension stops syncing — pin the /Applications copy
# and drop every other registration for this bundle id.
echo "▸ registering Safari extension (pluginkit)"
APPEX="/Applications/Cockatoo.app/Contents/PlugIns/CockatooExtension Extension.appex"
pluginkit -a "$APPEX" 2>/dev/null || true
pluginkit -m -v -i dev.cockatoo.app.Extension 2>/dev/null | awk -F'\t' '$NF ~ /^\// {print $NF}' | while read -r path; do
  [ "$path" = "$APPEX" ] && continue
  echo "  removing stale registration: $path"
  pluginkit -r "$path" 2>/dev/null || true
done
pkill -f "CockatooExtension Extension" 2>/dev/null || true

echo "▸ launching"
open /Applications/Cockatoo.app

if [ "$RESTART_SAFARI" = 1 ]; then
  echo "▸ restarting Safari"
  osascript -e 'quit app "Safari"' 2>/dev/null || true
  sleep 2
  open -a Safari
else
  echo "note: reload open tabs (or pass --restart-safari) so content scripts update"
fi

echo "✓ installed $(defaults read /Applications/Cockatoo.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo '?') ($CONFIG)"
