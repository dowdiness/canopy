#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
WARREN_BIN_DIR="$PROJECT_ROOT/_build/tools/bin"

export NEW_MOON_MOD=0
export PATH="$HOME/.moon/bin:$PATH"

# Production builds bootstrap pinned dependencies; local development deliberately
# builds the current checkout, including uncommitted submodule changes.
if [ "${LOOMARK_LOCAL_BUILD:-0}" != "1" ]; then
  "$SCRIPT_DIR/moon-toolchain.sh" ensure
  cd "$PROJECT_ROOT"
  git submodule sync --recursive
  git submodule update --init --recursive
  scripts/moon-update.sh
  scripts/install-local-warren.sh "$WARREN_BIN_DIR"
  cd "$PROJECT_ROOT/apps/loomark"
  npm ci
else
  if [ ! -x "$WARREN_BIN_DIR/warren" ]; then
    "$SCRIPT_DIR/install-local-warren.sh" "$WARREN_BIN_DIR"
  fi
  cd "$PROJECT_ROOT/apps/loomark"
fi
npm run build:server
npm run build:styles
"$WARREN_BIN_DIR/warren" build
