#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="Hey Codex"
APP_PATH="$ROOT/dist/$APP_NAME.app"
VERSION=""
REQUIRE_DEVELOPER_ID=false
NOTARIZE=false
NOTARY_PROFILE="${NOTARYTOOL_PROFILE:-}"

usage() {
  echo "Usage: $0 [VERSION] [--require-developer-id] [--notarize] [--notary-profile PROFILE]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --require-developer-id)
      REQUIRE_DEVELOPER_ID=true
      shift
      ;;
    --notarize)
      NOTARIZE=true
      REQUIRE_DEVELOPER_ID=true
      shift
      ;;
    --notary-profile)
      if [[ $# -lt 2 ]]; then
        usage
        exit 2
      fi
      NOTARY_PROFILE="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --*)
      usage
      exit 2
      ;;
    *)
      if [[ -n "$VERSION" ]]; then
        usage
        exit 2
      fi
      VERSION="$1"
      shift
      ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  VERSION="$(plutil -extract CFBundleShortVersionString raw "$ROOT/Info.plist")"
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid release version: $VERSION" >&2
  exit 2
fi

if $NOTARIZE && [[ -z "$NOTARY_PROFILE" ]]; then
  echo "Notarization requires --notary-profile PROFILE or NOTARYTOOL_PROFILE." >&2
  exit 2
fi

RELEASE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
if $REQUIRE_DEVELOPER_ID && [[ -z "$RELEASE_SIGN_IDENTITY" ]]; then
  RELEASE_SIGN_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' \
      | head -1
  )"
fi

if $REQUIRE_DEVELOPER_ID && [[ -z "$RELEASE_SIGN_IDENTITY" ]]; then
  echo "No Developer ID Application certificate is available in the keychain." >&2
  exit 1
fi

if $REQUIRE_DEVELOPER_ID && [[ "$RELEASE_SIGN_IDENTITY" != "Developer ID Application:"* ]]; then
  echo "Developer ID Application signing is required; requested: $RELEASE_SIGN_IDENTITY" >&2
  exit 1
fi

DMG_NAME="Hey-Codex-$VERSION.dmg"
DMG_PATH="$ROOT/dist/$DMG_NAME"
CHECKSUM_PATH="$DMG_PATH.sha256"
STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hey-codex-release.XXXXXX")"

cleanup() {
  rm -rf -- "$STAGING_ROOT"
}
trap cleanup EXIT

if [[ -n "$RELEASE_SIGN_IDENTITY" ]]; then
  CODE_SIGN_IDENTITY="$RELEASE_SIGN_IDENTITY" \
    HEY_CODEX_HARDENED_RUNTIME=true \
    HEY_CODEX_VERSION="$VERSION" \
    "$ROOT/scripts/build-app.sh"
else
  HEY_CODEX_HARDENED_RUNTIME=true \
    HEY_CODEX_VERSION="$VERSION" \
    "$ROOT/scripts/build-app.sh"
fi

codesign --verify --deep --strict "$APP_PATH"
plutil -lint "$APP_PATH/Contents/Info.plist" >/dev/null

SIGNING_AUTHORITY="$(
  codesign -dvv "$APP_PATH" 2>&1 | sed -n 's/^Authority=//p' | head -1 || true
)"
if [[ -z "$SIGNING_AUTHORITY" ]]; then
  SIGNING_AUTHORITY="ad hoc"
fi

if $REQUIRE_DEVELOPER_ID && [[ "$SIGNING_AUTHORITY" != "Developer ID Application:"* ]]; then
  echo "Developer ID Application signing is required; found: $SIGNING_AUTHORITY" >&2
  exit 1
fi

SIGNING_DETAILS="$(codesign -dvvv "$APP_PATH" 2>&1)"
if ! grep -Eq '^CodeDirectory .*flags=.*runtime' <<<"$SIGNING_DETAILS"; then
  echo "Release app is not signed with Hardened Runtime." >&2
  exit 1
fi

SIGNED_ENTITLEMENTS="$STAGING_ROOT/signed-entitlements.plist"
codesign -d --entitlements :- "$APP_PATH" >"$SIGNED_ENTITLEMENTS" 2>/dev/null
for entitlement in \
  com.apple.security.automation.apple-events \
  com.apple.security.device.audio-input
do
  if [[ "$(
    /usr/libexec/PlistBuddy -c "Print :$entitlement" "$SIGNED_ENTITLEMENTS" 2>/dev/null || true
  )" != true ]]; then
    echo "Release app is missing required entitlement: $entitlement" >&2
    exit 1
  fi
done

mkdir -p "$STAGING_ROOT/image"
ditto "$APP_PATH" "$STAGING_ROOT/image/$APP_NAME.app"
ln -s /Applications "$STAGING_ROOT/image/Applications"

rm -f -- "$DMG_PATH" "$CHECKSUM_PATH"
hdiutil create \
  -quiet \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_ROOT/image" \
  -format UDZO \
  -ov \
  "$DMG_PATH"
hdiutil verify -quiet "$DMG_PATH"

if [[ "$SIGNING_AUTHORITY" == "Developer ID Application:"* ]]; then
  codesign --force --timestamp --sign "$SIGNING_AUTHORITY" "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi

if $NOTARIZE; then
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl --assess --type open \
    --context context:primary-signature \
    --verbose=2 \
    "$DMG_PATH"
fi

(
  cd "$ROOT/dist"
  shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
)

echo "Signing authority: $SIGNING_AUTHORITY"
echo "DMG: $DMG_PATH"
echo "Checksum: $CHECKSUM_PATH"

if [[ "$SIGNING_AUTHORITY" != "Developer ID Application:"* ]]; then
  echo "Private test artifact only: this DMG is not Developer ID signed or notarized."
elif ! $NOTARIZE; then
  echo "Developer ID signed, but not notarized. Do not publish this DMG yet."
else
  echo "Developer ID signed, notarized, stapled, and Gatekeeper assessed."
fi
