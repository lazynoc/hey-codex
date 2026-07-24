#!/bin/zsh
set -euo pipefail

BUNDLE_ID="com.mukulmalik.heycodex"
PURGE=false
DRY_RUN=false
TARGET_HOME="$HOME"

usage() {
  echo "Usage: $0 [--purge] [--dry-run] [--home PATH]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge)
      PURGE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --home)
      if [[ $# -lt 2 ]]; then
        usage
        exit 2
      fi
      TARGET_HOME="$2"
      shift 2
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

if [[ "$TARGET_HOME" != /* || "$TARGET_HOME" == "/" ]]; then
  echo "Refusing unsafe home path: $TARGET_HOME"
  exit 2
fi

TARGET_HOME="${TARGET_HOME:A}"
LIVE_HOME="${HOME:A}"

if [[ "$TARGET_HOME" == "/" ]]; then
  echo "Refusing unsafe home path: $TARGET_HOME"
  exit 2
fi

APP_PATHS=("$TARGET_HOME/Applications/Hey Codex.app")
if [[ "$TARGET_HOME" == "$LIVE_HOME" ]]; then
  APP_PATHS+=("/Applications/Hey Codex.app")
fi
OWNED_DATA_PATHS=(
  "$TARGET_HOME/Library/Preferences/$BUNDLE_ID.plist"
  "$TARGET_HOME/Library/Caches/$BUNDLE_ID"
  "$TARGET_HOME/Library/Application Support/$BUNDLE_ID"
  "$TARGET_HOME/Library/Application Support/Hey Codex"
  "$TARGET_HOME/Library/Saved Application State/$BUNDLE_ID.savedState"
)

if $DRY_RUN; then
  echo "Hey Codex uninstall would:"
  if [[ "$TARGET_HOME" == "$LIVE_HOME" ]]; then
    echo "- Quit the HeyCodex process"
  fi
  for app_path in "${APP_PATHS[@]}"; do
    echo "- Remove $app_path"
  done
  if $PURGE; then
    for owned_path in "${OWNED_DATA_PATHS[@]}"; do
      echo "- Remove $owned_path"
    done
    if [[ "$TARGET_HOME" == "$LIVE_HOME" ]]; then
      echo "- Reset Accessibility, Apple Events, Microphone, and Speech Recognition for $BUNDLE_ID"
    else
      echo "- Skip live permission reset for disposable home $TARGET_HOME"
    fi
  fi
  echo "- Keep Codex settings and transcription history"
  exit 0
fi

if [[ "$TARGET_HOME" == "$LIVE_HOME" ]] && pgrep -x HeyCodex >/dev/null; then
  pkill -x HeyCodex || true
  for _ in {1..50}; do
    if ! pgrep -x HeyCodex >/dev/null; then
      break
    fi
    sleep 0.1
  done
fi

if [[ "$TARGET_HOME" == "$LIVE_HOME" ]] && pgrep -x HeyCodex >/dev/null; then
  echo "Could not stop Hey Codex. Quit it and run this uninstaller again."
  exit 1
fi

for app_path in "${APP_PATHS[@]}"; do
  if [[ -e "$app_path" ]]; then
    EXISTING_BUNDLE_ID="$(
      plutil -extract CFBundleIdentifier raw "$app_path/Contents/Info.plist" 2>/dev/null || true
    )"
    if [[ "$EXISTING_BUNDLE_ID" != "$BUNDLE_ID" ]]; then
      echo "Refusing to remove an app not owned by Hey Codex: $app_path" >&2
      exit 2
    fi
  fi
  rm -rf -- "$app_path"
done

if $PURGE; then
  for owned_path in "${OWNED_DATA_PATHS[@]}"; do
    rm -rf -- "$owned_path"
  done

  if [[ "$TARGET_HOME" == "$LIVE_HOME" ]]; then
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    for service in Accessibility AppleEvents Microphone SpeechRecognition; do
      tccutil reset "$service" "$BUNDLE_ID" >/dev/null 2>&1 || true
    done
  fi
fi

if $PURGE; then
  echo "Hey Codex and its local settings were removed. Codex data was kept."
else
  echo "Hey Codex was removed. Run with --purge to also reset its settings and permissions."
fi
