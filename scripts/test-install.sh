#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hey-codex-install.XXXXXX")"
DESTINATION="$TEST_ROOT/Hey Codex.app"
FOREIGN_APP="$TEST_ROOT/foreign/Hey Codex.app"

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$FOREIGN_APP/Contents"
cp "$ROOT/Info.plist" "$FOREIGN_APP/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string com.example.foreign "$FOREIGN_APP/Contents/Info.plist"
if "$ROOT/scripts/install.sh" --destination "$FOREIGN_APP" --no-open >/dev/null 2>&1; then
  echo "Installer replaced a foreign app" >&2
  exit 1
fi
[[ "$(plutil -extract CFBundleIdentifier raw "$FOREIGN_APP/Contents/Info.plist")" == "com.example.foreign" ]]

"$ROOT/scripts/install.sh" --destination "$DESTINATION" --no-open >/dev/null
"$ROOT/scripts/install.sh" --destination "$DESTINATION" --no-open >/dev/null
"$ROOT/scripts/install.sh" --destination "$DESTINATION" --no-open --skip-build >/dev/null

[[ -d "$DESTINATION" ]]
[[ -x "$DESTINATION/Contents/MacOS/HeyCodex" ]]
[[ "$(plutil -extract CFBundleIdentifier raw "$DESTINATION/Contents/Info.plist")" == "com.mukulmalik.heycodex" ]]
[[ "$(plutil -extract CFBundleDisplayName raw "$DESTINATION/Contents/Info.plist")" == "Hey Codex" ]]
[[ "$(plutil -extract CFBundleIconFile raw "$DESTINATION/Contents/Info.plist")" == "HeyCodex.icns" ]]
[[ -f "$DESTINATION/Contents/Resources/HeyCodex.icns" ]]
plutil -lint "$DESTINATION/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict "$DESTINATION"

echo "HEY_CODEX_INSTALL_TEST_PASS"
