#!/usr/bin/env bash
set -euo pipefail

failures=0

pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1" >&2; failures=$((failures + 1)); }

printf 'Cockatoo development environment\n'

if [[ "$(uname -s)" == "Darwin" ]]; then
  macos_version="$(sw_vers -productVersion)"
  macos_major="${macos_version%%.*}"
  macos_remainder="${macos_version#*.}"
  macos_minor="${macos_remainder%%.*}"
  if (( macos_major > 15 || (macos_major == 15 && macos_minor >= 6) )); then
    pass "macOS $macos_version (15.6+ build host)"
  else
    fail "macOS 15.6+ is required to run Xcode 26; found $macos_version"
  fi
else
  fail "macOS is required to build the app and Safari extension"
fi

for command in git swift xcodebuild node npm; do
  if command -v "$command" >/dev/null 2>&1; then pass "$command available"; else fail "$command is missing"; fi
done

if command -v xcodebuild >/dev/null 2>&1; then
  xcode_version="$(xcodebuild -version | awk 'NR == 1 { print $2 }')"
  xcode_major="${xcode_version%%.*}"
  if [[ "$xcode_major" =~ ^[0-9]+$ ]] && (( xcode_major >= 26 )); then
    pass "Xcode $xcode_version (26.0+)"
  else
    fail "Xcode 26.0+ required by the project format; found ${xcode_version:-unknown}"
  fi
fi

if command -v node >/dev/null 2>&1; then
  node_version="$(node --version | tr -d v)"
  node_major="${node_version%%.*}"
  if [[ "$node_major" =~ ^[0-9]+$ ]] && (( node_major >= 20 )); then
    pass "Node.js $node_version (20+)"
  else
    fail "Node.js 20+ required; found ${node_version:-unknown}"
  fi
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "$ROOT_DIR/App/Config/Local.xcconfig" ]]; then
  if grep -Eq 'YOUR_TEAM_ID|com\.yourname' "$ROOT_DIR/App/Config/Local.xcconfig"; then
    fail "App/Config/Local.xcconfig still contains example placeholders"
  else
    pass "local Apple Development configuration present"
  fi
else
  pass "no local signing config (unsigned build-only mode)"
fi

if (( failures > 0 )); then
  printf '\n%d check(s) failed.\n' "$failures" >&2
  exit 1
fi

printf '\nEnvironment ready.\n'
