#!/bin/zsh
set -euo pipefail

MODE="${1:-run}"
ROOT="${0:A:h:h}"
APP_NAME="Hey Codex"
PROCESS_NAME="HeyCodex"
APP_BUNDLE="$ROOT/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$PROCESS_NAME"
BUNDLE_ID="com.mukulmalik.heycodex"

pkill -x "$PROCESS_NAME" >/dev/null 2>&1 || true
"$ROOT/scripts/build-app.sh"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$PROCESS_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$PROCESS_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
