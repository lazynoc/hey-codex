#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hey-codex-latest-test.XXXXXX")"
FIXTURE_ROOT="$TEST_ROOT/fixture/hey-codex-main"
ARCHIVE_PATH="$TEST_ROOT/hey-codex-main.tar.gz"
TEST_HOME="$TEST_ROOT/home"
LOG_PATH="$TEST_ROOT/actions.log"

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$FIXTURE_ROOT/scripts" "$TEST_HOME/hey-codex"
touch "$TEST_HOME/hey-codex/must-stay"

cat > "$FIXTURE_ROOT/scripts/build-app.sh" <<'SCRIPT'
#!/bin/zsh
print -r -- "build" >> "$HEY_CODEX_TEST_LOG"
SCRIPT

cat > "$FIXTURE_ROOT/scripts/uninstall.sh" <<'SCRIPT'
#!/bin/zsh
print -r -- "uninstall:$*" >> "$HEY_CODEX_TEST_LOG"
SCRIPT

cat > "$FIXTURE_ROOT/scripts/install.sh" <<'SCRIPT'
#!/bin/zsh
print -r -- "install:$*" >> "$HEY_CODEX_TEST_LOG"
SCRIPT

chmod +x "$FIXTURE_ROOT"/scripts/*.sh
tar -czf "$ARCHIVE_PATH" -C "$TEST_ROOT/fixture" hey-codex-main

export HOME="$TEST_HOME"
export HEY_CODEX_TEST_LOG="$LOG_PATH"
export HEY_CODEX_ARCHIVE_URL="file://$ARCHIVE_PATH"

"$ROOT/scripts/install-latest.sh" --fresh --no-open >/dev/null

EXPECTED=$'build\nuninstall:--purge\ninstall:--skip-build --no-open'
[[ "$(<"$LOG_PATH")" == "$EXPECTED" ]]
[[ -f "$TEST_HOME/hey-codex/must-stay" ]]

: > "$LOG_PATH"
"$ROOT/scripts/install-latest.sh" --no-open >/dev/null
[[ "$(<"$LOG_PATH")" == "install:--no-open" ]]

echo "HEY_CODEX_INSTALL_LATEST_TEST_PASS"
