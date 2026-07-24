#!/bin/zsh
set -euo pipefail

ARCHIVE_URL="${HEY_CODEX_ARCHIVE_URL:-https://codeload.github.com/lazynoc/hey-codex/tar.gz/refs/heads/main}"
FRESH=false
OPEN_AFTER_INSTALL=true

usage() {
  echo "Usage: $0 [--fresh] [--no-open]"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fresh)
      FRESH=true
      shift
      ;;
    --no-open)
      OPEN_AFTER_INSTALL=false
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

for command in curl tar mktemp; do
  if ! command -v "$command" >/dev/null; then
    echo "Required command not found: $command" >&2
    exit 1
  fi
done

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hey-codex-latest.XXXXXX")"
ARCHIVE_PATH="$WORK_DIR/hey-codex.tar.gz"

cleanup() {
  rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT HUP INT TERM

echo "Downloading the latest Hey Codex source…"
curl --fail --location --silent --show-error "$ARCHIVE_URL" --output "$ARCHIVE_PATH"

while IFS= read -r entry; do
  case "$entry" in
  /*|..|../*|*/..|*/../*)
      echo "Refusing an archive with an unsafe path: $entry" >&2
      exit 1
      ;;
  esac
done < <(tar -tzf "$ARCHIVE_PATH")

tar -xzf "$ARCHIVE_PATH" -C "$WORK_DIR"
SOURCE_DIRS=("$WORK_DIR"/hey-codex-*(N/))
if [[ ${#SOURCE_DIRS[@]} -ne 1 ]]; then
  echo "The downloaded archive did not contain one Hey Codex source directory." >&2
  exit 1
fi
SOURCE_DIR="${SOURCE_DIRS[1]}"

REQUIRED_SCRIPTS=(build-app.sh install.sh uninstall.sh)
for script in "${REQUIRED_SCRIPTS[@]}"; do
  if [[ ! -x "$SOURCE_DIR/scripts/$script" ]]; then
    echo "The downloaded source is missing executable scripts/$script." >&2
    exit 1
  fi
done

if $FRESH; then
  # Prove the source builds before removing the currently installed app.
  "$SOURCE_DIR/scripts/build-app.sh"
  "$SOURCE_DIR/scripts/uninstall.sh" --purge
  INSTALL_ARGS=(--skip-build)
else
  INSTALL_ARGS=()
fi

if ! $OPEN_AFTER_INSTALL; then
  INSTALL_ARGS+=(--no-open)
fi

"$SOURCE_DIR/scripts/install.sh" "${INSTALL_ARGS[@]}"
echo "Hey Codex is up to date. No source checkout was created or changed."
