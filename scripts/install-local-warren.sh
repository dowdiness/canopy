#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RABBITA_ROOT="$PROJECT_ROOT/deps/rabbita"
RABBITA_REMOTE="$(git -C "$PROJECT_ROOT" config -f .gitmodules --get submodule.rabbita.url)"
EXPECTED_RABBITA="09968c4402c51645186d75c5044cf4d9346f9f06"
BIN_DIR="${1:-$PROJECT_ROOT/_build/tools/bin}"

actual_remote="$(git -C "$RABBITA_ROOT" remote get-url origin)"
if [ "$actual_remote" != "$RABBITA_REMOTE" ]; then
  echo "error: Rabbita origin is $actual_remote; expected $RABBITA_REMOTE" >&2
  printf 'run: cd %q && git submodule sync --recursive\n' "$PROJECT_ROOT" >&2
  printf 'then: git -C %q remote set-url origin %q\n' \
    "$RABBITA_ROOT" "$RABBITA_REMOTE" >&2
  exit 1
fi

if ! git -C "$RABBITA_ROOT" fetch --quiet origin "$EXPECTED_RABBITA"; then
  echo "error: Rabbita $EXPECTED_RABBITA is not reachable from $RABBITA_REMOTE" >&2
  exit 1
fi

actual_rabbita="$(git -C "$RABBITA_ROOT" rev-parse HEAD)"
if [ "$actual_rabbita" != "$EXPECTED_RABBITA" ]; then
  echo "error: Warren expects Rabbita $EXPECTED_RABBITA, found $actual_rabbita" >&2
  echo "update the pinned commit and installer together" >&2
  exit 1
fi

if [ -n "$(git -C "$RABBITA_ROOT" status --porcelain --untracked-files=all)" ]; then
  echo "error: Rabbita worktree is dirty; reset it before installing Warren" >&2
  exit 1
fi

mkdir -p "$BIN_DIR"
moon install "$RABBITA_ROOT/warren" --bin "$BIN_DIR"

echo "Installed pinned Warren at $BIN_DIR/warren"
