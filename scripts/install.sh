#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="Hey Codex"
BUNDLE_ID="com.mukulmalik.heycodex"
SOURCE_APP="$ROOT/dist/$APP_NAME.app"
LIVE_DESTINATION="$HOME/Applications/$APP_NAME.app"
DESTINATION="$LIVE_DESTINATION"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
OPEN_AFTER_INSTALL=true
SKIP_BUILD=false

usage() {
  echo "Usage: $0 [--destination APP_PATH] [--no-open] [--skip-build]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --destination)
      if [[ $# -lt 2 ]]; then
        usage
        exit 2
      fi
      DESTINATION="$2"
      shift 2
      ;;
    --no-open)
      OPEN_AFTER_INSTALL=false
      shift
      ;;
    --skip-build)
      SKIP_BUILD=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ "$DESTINATION" != /* || "$DESTINATION" == "/" || "$DESTINATION" != *.app ]]; then
  echo "Refusing unsafe app destination: $DESTINATION"
  exit 2
fi

DESTINATION="${DESTINATION:A}"
LIVE_DESTINATION="${LIVE_DESTINATION:A}"

if [[ "${DESTINATION:t}" != "$APP_NAME.app" ]]; then
  echo "The destination must be named $APP_NAME.app: $DESTINATION"
  exit 2
fi

if [[ -e "$DESTINATION" ]]; then
  EXISTING_BUNDLE_ID="$(
    plutil -extract CFBundleIdentifier raw "$DESTINATION/Contents/Info.plist" 2>/dev/null || true
  )"
  if [[ "$EXISTING_BUNDLE_ID" != "$BUNDLE_ID" ]]; then
    echo "Refusing to replace an app not owned by Hey Codex: $DESTINATION"
    exit 2
  fi
fi

if $SKIP_BUILD; then
  if [[ ! -d "$SOURCE_APP" ]]; then
    echo "Built app not found at $SOURCE_APP. Run scripts/build-app.sh first." >&2
    exit 1
  fi
else
  "$ROOT/scripts/build-app.sh"
fi

if [[ "$DESTINATION" == "$LIVE_DESTINATION" ]] && pgrep -x HeyCodex >/dev/null; then
  pkill -x HeyCodex || true
  for _ in {1..50}; do
    if ! pgrep -x HeyCodex >/dev/null; then
      break
    fi
    sleep 0.1
  done
fi

if [[ "$DESTINATION" == "$LIVE_DESTINATION" ]] && pgrep -x HeyCodex >/dev/null; then
  echo "Could not stop the existing Hey Codex process. Quit it and run this installer again."
  exit 1
fi

mkdir -p "${DESTINATION:h}"
STAGING_PATH="$DESTINATION.installing.$$"
rm -rf -- "$STAGING_PATH"
trap 'rm -rf -- "$STAGING_PATH"' EXIT
ditto "$SOURCE_APP" "$STAGING_PATH"
codesign --verify --deep --strict "$STAGING_PATH"
rm -rf -- "$DESTINATION"
mv "$STAGING_PATH" "$DESTINATION"
trap - EXIT

if $OPEN_AFTER_INSTALL; then
  if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$DESTINATION"
  fi
  open "$DESTINATION"
fi

echo "Installed at $DESTINATION"
