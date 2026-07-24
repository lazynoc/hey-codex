#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/hey-codex-uninstall.XXXXXX")"
BUNDLE_ID="com.mukulmalik.heycodex"
APP_PATH="$TEST_HOME/Applications/Hey Codex.app"
PREFERENCES="$TEST_HOME/Library/Preferences/$BUNDLE_ID.plist"
CACHE="$TEST_HOME/Library/Caches/$BUNDLE_ID"
SUPPORT="$TEST_HOME/Library/Application Support/$BUNDLE_ID"
STATS_SUPPORT="$TEST_HOME/Library/Application Support/Hey Codex"
SAVED_STATE="$TEST_HOME/Library/Saved Application State/$BUNDLE_ID.savedState"
CODEX_BINDINGS="$TEST_HOME/.codex/keybindings.json"
CODEX_HISTORY="$TEST_HOME/.codex/transcription-history.jsonl"

cleanup() {
  rm -rf -- "$TEST_HOME"
}
trap cleanup EXIT

make_fixture() {
  mkdir -p "$APP_PATH" "${PREFERENCES:h}" "$CACHE" "$SUPPORT" "$STATS_SUPPORT" "$SAVED_STATE" "${CODEX_BINDINGS:h}"
  mkdir -p "$APP_PATH/Contents"
  plutil -create xml1 "$APP_PATH/Contents/Info.plist"
  plutil -insert CFBundleIdentifier -string "$BUNDLE_ID" "$APP_PATH/Contents/Info.plist"
  touch "$PREFERENCES" "$STATS_SUPPORT/stats.json" "$CODEX_BINDINGS" "$CODEX_HISTORY"
}

make_fixture
"$ROOT/scripts/uninstall.sh" --dry-run --purge --home "$TEST_HOME" >/dev/null
[[ -d "$APP_PATH" ]]
[[ -f "$PREFERENCES" ]]

"$ROOT/scripts/uninstall.sh" --home "$TEST_HOME" >/dev/null
"$ROOT/scripts/uninstall.sh" --home "$TEST_HOME" >/dev/null
[[ ! -e "$APP_PATH" ]]
[[ -f "$PREFERENCES" ]]
[[ -f "$CODEX_BINDINGS" ]]
[[ -f "$CODEX_HISTORY" ]]

mkdir -p "$APP_PATH/Contents"
plutil -create xml1 "$APP_PATH/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string "com.example.not-heycodex" "$APP_PATH/Contents/Info.plist"
if "$ROOT/scripts/uninstall.sh" --home "$TEST_HOME" >/dev/null 2>&1; then
  echo "Uninstaller replaced an app with the wrong bundle identifier." >&2
  exit 1
fi
[[ -d "$APP_PATH" ]]
rm -rf -- "$APP_PATH"

mkdir -p "$APP_PATH/Contents"
plutil -create xml1 "$APP_PATH/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string "$BUNDLE_ID" "$APP_PATH/Contents/Info.plist"
"$ROOT/scripts/uninstall.sh" --purge --home "$TEST_HOME" >/dev/null
[[ ! -e "$APP_PATH" ]]
[[ ! -e "$PREFERENCES" ]]
[[ ! -e "$CACHE" ]]
[[ ! -e "$SUPPORT" ]]
[[ ! -e "$STATS_SUPPORT" ]]
[[ ! -e "$SAVED_STATE" ]]
[[ -f "$CODEX_BINDINGS" ]]
[[ -f "$CODEX_HISTORY" ]]

LIVE_DRY_RUN_OUTPUT="$("$ROOT/scripts/uninstall.sh" --dry-run --home "$HOME/.")"
[[ "$LIVE_DRY_RUN_OUTPUT" == *"Quit the HeyCodex process"* ]]

echo "HEY_CODEX_UNINSTALL_TEST_PASS"
