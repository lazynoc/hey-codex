#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="0.1.0-ci"
DMG_PATH="$ROOT/dist/Hey-Codex-$VERSION.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hey-codex-dmg.XXXXXX")"
MOUNT_POINT="$TEST_ROOT/mount"
MOUNTED=false

cleanup() {
  if $MOUNTED; then
    hdiutil detach -quiet -force "$MOUNT_POINT" || true
  fi
  rm -rf -- "$TEST_ROOT"
  rm -f -- "$DMG_PATH" "$CHECKSUM_PATH"
}
trap cleanup EXIT

"$ROOT/scripts/build-release.sh" "$VERSION" >/dev/null
[[ -f "$DMG_PATH" ]]
[[ -f "$CHECKSUM_PATH" ]]

(
  cd "$ROOT/dist"
  shasum -a 256 -c "${CHECKSUM_PATH:t}" >/dev/null
)

mkdir -p "$MOUNT_POINT"
hdiutil attach -quiet -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$DMG_PATH"
MOUNTED=true

[[ -d "$MOUNT_POINT/Hey Codex.app" ]]
[[ -L "$MOUNT_POINT/Applications" ]]
[[ "$(readlink "$MOUNT_POINT/Applications")" == "/Applications" ]]
plutil -lint "$MOUNT_POINT/Hey Codex.app/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict "$MOUNT_POINT/Hey Codex.app"

hdiutil detach -quiet "$MOUNT_POINT"
MOUNTED=false

echo "HEY_CODEX_DMG_TEST_PASS"
