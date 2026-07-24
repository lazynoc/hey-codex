#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 VERSION" >&2
  exit 2
fi

DMG_PATH="$ROOT/dist/Hey-Codex-$VERSION.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hey-codex-public-release.XXXXXX")"
MOUNT_POINT="$TEST_ROOT/mount"
MOUNTED=false

cleanup() {
  if $MOUNTED; then
    hdiutil detach -quiet -force "$MOUNT_POINT" || true
  fi
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

[[ -f "$DMG_PATH" ]]
[[ -f "$CHECKSUM_PATH" ]]

(
  cd "$ROOT/dist"
  shasum -a 256 -c "${CHECKSUM_PATH:t}"
)

hdiutil verify -quiet "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open \
  --context context:primary-signature \
  --verbose=2 \
  "$DMG_PATH"

mkdir -p "$MOUNT_POINT"
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$DMG_PATH"
MOUNTED=true

APP_PATH="$MOUNT_POINT/Hey Codex.app"
[[ -d "$APP_PATH" ]]
[[ -L "$MOUNT_POINT/Applications" ]]
[[ "$(readlink "$MOUNT_POINT/Applications")" == "/Applications" ]]

plutil -lint "$APP_PATH/Contents/Info.plist" >/dev/null
[[ "$(plutil -extract CFBundleShortVersionString raw "$APP_PATH/Contents/Info.plist")" == "$VERSION" ]]
codesign --verify --deep --strict "$APP_PATH"

SIGNING_DETAILS="$(codesign -dvvv "$APP_PATH" 2>&1)"
grep -q '^Authority=Developer ID Application:' <<<"$SIGNING_DETAILS"
grep -Eq '^CodeDirectory .*flags=.*runtime' <<<"$SIGNING_DETAILS"

SIGNED_ENTITLEMENTS="$TEST_ROOT/signed-entitlements.plist"
codesign -d --entitlements :- "$APP_PATH" >"$SIGNED_ENTITLEMENTS" 2>/dev/null
[[ "$(
  /usr/libexec/PlistBuddy \
    -c "Print :com.apple.security.automation.apple-events" \
    "$SIGNED_ENTITLEMENTS"
)" == true ]]
[[ "$(
  /usr/libexec/PlistBuddy \
    -c "Print :com.apple.security.device.audio-input" \
    "$SIGNED_ENTITLEMENTS"
)" == true ]]

spctl --assess --type execute --verbose=2 "$APP_PATH"

hdiutil detach -quiet "$MOUNT_POINT"
MOUNTED=false

echo "HEY_CODEX_PUBLIC_RELEASE_PASS"
