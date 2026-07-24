#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="Hey Codex"
APP_DIR="$ROOT/dist/$APP_NAME.app"

cd "$ROOT"
swift build -c release
BUILD_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/HeyCodex" "$APP_DIR/Contents/MacOS/HeyCodex"
cp "$ROOT/Info.plist" "$APP_DIR/Contents/Info.plist"
if [[ -n "${HEY_CODEX_VERSION:-}" ]]; then
  # Stamp the full release version (including any -test.N prerelease
  # suffix) so Check for Updates compares against the real version.
  plutil -replace CFBundleShortVersionString -string "$HEY_CODEX_VERSION" \
    "$APP_DIR/Contents/Info.plist"
fi
cp "$ROOT/Assets/HeyCodex.icns" "$APP_DIR/Contents/Resources/HeyCodex.icns"

SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
HARDENED_RUNTIME="${HEY_CODEX_HARDENED_RUNTIME:-false}"
ENTITLEMENTS_PATH="${CODE_SIGN_ENTITLEMENTS:-$ROOT/HeyCodex.entitlements}"

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' \
      | head -1
  )"
fi

if [[ "$SIGN_IDENTITY" == "Developer ID Application:"* ]]; then
  HARDENED_RUNTIME=true
fi

if [[ "$HARDENED_RUNTIME" == true ]]; then
  plutil -lint "$ENTITLEMENTS_PATH" >/dev/null
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  SIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
  if [[ "$HARDENED_RUNTIME" == true ]]; then
    SIGN_ARGS+=(--options runtime --entitlements "$ENTITLEMENTS_PATH")
  fi
  if [[ "$SIGN_IDENTITY" == "Developer ID Application:"* ]]; then
    SIGN_ARGS+=(--timestamp)
  else
    SIGN_ARGS+=(--timestamp=none)
  fi
  codesign "${SIGN_ARGS[@]}" "$APP_DIR"
  echo "Signed with: $SIGN_IDENTITY"
else
  SIGN_ARGS=(--force --sign -)
  if [[ "$HARDENED_RUNTIME" == true ]]; then
    SIGN_ARGS+=(--options runtime --entitlements "$ENTITLEMENTS_PATH")
  fi
  codesign "${SIGN_ARGS[@]}" "$APP_DIR"
  echo "Signed ad-hoc. Set CODE_SIGN_IDENTITY for stable macOS permissions."
fi

echo "$APP_DIR"
