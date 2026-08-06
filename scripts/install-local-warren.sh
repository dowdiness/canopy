#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RABBITA_ROOT="$PROJECT_ROOT/deps/rabbita"
PATCH="$PROJECT_ROOT/patches/rabbita/warren-standalone.patch"
EXPECTED_RABBITA="3b5bb38964611bad772883c912010a9555e1748a"
BIN_DIR="${1:-$PROJECT_ROOT/_build/tools/bin}"

if ! git -C "$RABBITA_ROOT" fetch --quiet origin "$EXPECTED_RABBITA"; then
  echo "error: Rabbita $EXPECTED_RABBITA is not reachable from the configured origin" >&2
  exit 1
fi

actual_rabbita="$(git -C "$RABBITA_ROOT" rev-parse HEAD)"
if [ "$actual_rabbita" != "$EXPECTED_RABBITA" ]; then
  echo "error: Warren patch expects Rabbita $EXPECTED_RABBITA, found $actual_rabbita" >&2
  echo "rebase patches/rabbita/warren-standalone.patch before changing the submodule pointer" >&2
  exit 1
fi

work_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT HUP INT TERM

git clone --quiet --no-checkout --no-hardlinks "$RABBITA_ROOT" "$work_dir/rabbita"
git -C "$work_dir/rabbita" -c advice.detachedHead=false checkout --quiet "$EXPECTED_RABBITA"
git -C "$work_dir/rabbita" apply --check "$PATCH"
git -C "$work_dir/rabbita" apply "$PATCH"

mkdir -p "$BIN_DIR"
moon install "$work_dir/rabbita/warren" --bin "$BIN_DIR"

echo "Installed locally patched Warren at $BIN_DIR/warren"
