#!/usr/bin/env bash
set -euo pipefail

# Build a Developer ID-signed, notarized, stapled Cockatoo.app.
#
# WHY THIS EXISTS
# ---------------
# Safari only runs a web extension without the per-launch "Allow Unsigned
# Extensions" toggle when the containing app is signed with a Developer ID
# certificate AND notarized. A local Apple Development build (what
# script/install-dev.sh produces) is treated as unsigned and needs that toggle
# re-enabled every time Safari restarts. A notarized build loads the extension
# permanently — no Develop menu, no password.
#
# PREREQUISITES (one-time)
# ------------------------
#   1. A "Developer ID Application" certificate in your login keychain
#      (Xcode → Settings → Accounts → Manage Certificates → +).
#   2. App/Config/Local.xcconfig with a real COCKATOO_DEVELOPMENT_TEAM and a
#      bundle ID + App Group your team can provision (see docs/development.md).
#   3. A notarytool credential profile stored in your keychain, e.g.:
#        xcrun notarytool store-credentials cockatoo-notary \
#          --apple-id you@example.com --team-id ABCDE12345 \
#          --password <app-specific-password>
#      (or --key/--key-id/--issuer for an App Store Connect API key), then pass
#      its name via COCKATOO_NOTARY_PROFILE.
#
# USAGE
#   COCKATOO_NOTARY_PROFILE=cockatoo-notary script/release.sh [--install] [--system] [--no-notarize]
#
# ENV
#   COCKATOO_NOTARY_PROFILE   notarytool keychain profile name (required unless --no-notarize)
#   COCKATOO_RELEASE_IDENTITY signing identity (default: "Developer ID Application")
#   COCKATOO_DEVELOPMENT_TEAM team ID override (default: read from Local.xcconfig)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTITY="${COCKATOO_RELEASE_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${COCKATOO_NOTARY_PROFILE:-}"
DO_INSTALL=0
SYSTEM_INSTALL=0
DO_NOTARIZE=1

usage() { echo "usage: COCKATOO_NOTARY_PROFILE=<profile> $0 [--install] [--system] [--no-notarize]" >&2; }

for argument in "$@"; do
  case "$argument" in
    --install) DO_INSTALL=1 ;;
    --system) SYSTEM_INSTALL=1; DO_INSTALL=1 ;;
    --no-notarize) DO_NOTARIZE=0 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

LOCAL_CONFIG="$ROOT_DIR/App/Config/Local.xcconfig"
if [[ ! -f "$LOCAL_CONFIG" ]]; then
  echo "error: a Developer ID release needs App/Config/Local.xcconfig with your team and a" >&2
  echo "       provisioned bundle ID + App Group. See docs/development.md." >&2
  exit 1
fi

# Team: explicit override wins, else the value already configured for the app.
TEAM="${COCKATOO_DEVELOPMENT_TEAM:-}"
if [[ -z "$TEAM" ]]; then
  TEAM="$(sed -n 's/^[[:space:]]*COCKATOO_DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*//p' "$LOCAL_CONFIG" | tail -1 | tr -d '[:space:]')"
fi
if [[ -z "$TEAM" ]]; then
  echo "error: no signing team. Set COCKATOO_DEVELOPMENT_TEAM in Local.xcconfig or the environment." >&2
  exit 1
fi

if (( DO_NOTARIZE == 1 )) && [[ -z "$NOTARY_PROFILE" ]]; then
  echo "error: set COCKATOO_NOTARY_PROFILE to your notarytool keychain profile, or pass --no-notarize." >&2
  echo "       create one with: xcrun notarytool store-credentials <name> --apple-id … --team-id … --password …" >&2
  exit 1
fi

# Fail early if the Developer ID certificate is not installed.
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
  echo "error: no \"Developer ID Application\" certificate found in the keychain." >&2
  echo "       add one via Xcode → Settings → Accounts → Manage Certificates." >&2
  exit 1
fi

if [[ ! -d "$ROOT_DIR/extension/node_modules" ]]; then
  echo "error: dependencies are missing; run script/bootstrap.sh first" >&2
  exit 1
fi

BUILD_DIR="$ROOT_DIR/build"
ARCHIVE="$BUILD_DIR/Cockatoo.xcarchive"
EXPORT_DIR="$BUILD_DIR/release-export"
APP="$EXPORT_DIR/Cockatoo.app"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.release.plist"

printf '▸ Building WebExtension resources\n'
(cd "$ROOT_DIR/extension" && npm run build --silent)

# Archive with the normal automatic (development) signing — forcing the
# Developer ID identity here conflicts with automatic signing. The Developer ID
# re-sign happens at export time, which is how Xcode's Organizer does it.
printf '▸ Archiving Cockatoo (Release, team %s)\n' "$TEAM"
rm -rf "$ARCHIVE"
xcodebuild archive \
  -project "$ROOT_DIR/App/Cockatoo/Cockatoo.xcodeproj" \
  -scheme Cockatoo \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  COCKATOO_CODE_SIGN_STYLE=Automatic \
  COCKATOO_CODE_SIGNING_ALLOWED=YES \
  COCKATOO_DEVELOPMENT_TEAM="$TEAM"

printf '▸ Exporting a Developer ID app\n'
rm -rf "$EXPORT_DIR"
cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingCertificate</key><string>$IDENTITY</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

if [[ ! -d "$APP" ]]; then
  echo "error: export did not produce $APP" >&2
  exit 1
fi

if (( DO_NOTARIZE == 1 )); then
  ZIP="$BUILD_DIR/Cockatoo-notarize.zip"
  printf '▸ Submitting to the notary service (this can take a few minutes)\n'
  /usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  rm -f "$ZIP"
  printf '▸ Stapling the notarization ticket\n'
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
else
  printf '▸ Skipping notarization (--no-notarize): the app will still trip Gatekeeper.\n'
fi

printf '▸ Verifying signature and Gatekeeper acceptance\n'
codesign --verify --deep --strict --verbose=2 "$APP"
# Informational: a notarized, stapled app prints "accepted / Notarized Developer ID".
spctl -a -vvv -t exec "$APP" 2>&1 || true

if (( DO_INSTALL == 1 )); then
  if (( SYSTEM_INSTALL == 1 )); then
    INSTALL_DIR="/Applications"
  else
    INSTALL_DIR="$HOME/Applications"
  fi
  DESTINATION="$INSTALL_DIR/Cockatoo.app"
  case "$DESTINATION" in
    /Applications/Cockatoo.app|"$HOME/Applications/Cockatoo.app") ;;
    *) echo "error: refusing unexpected install destination: $DESTINATION" >&2; exit 1 ;;
  esac
  printf '▸ Installing to %s\n' "$DESTINATION"
  osascript -e 'tell application "Cockatoo" to quit' >/dev/null 2>&1 || true
  /usr/bin/pkill -x Cockatoo >/dev/null 2>&1 || true
  sleep 1
  mkdir -p "$INSTALL_DIR"
  rm -rf "$DESTINATION"
  /bin/cp -R "$APP" "$DESTINATION"
  /usr/bin/open "$DESTINATION"
fi

printf '\n✓ Notarized app at %s\n' "$APP"
if (( DO_NOTARIZE == 1 )); then
  printf '  Safari loads its extension permanently — no "Allow Unsigned Extensions" toggle.\n'
fi
