#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
MOONBIT_VERSION="0.10.8+8606a5800"
WARREN_BIN_DIR="$PROJECT_ROOT/_build/tools/bin"

export NEW_MOON_MOD=0
export PATH="$HOME/.moon/bin:$PATH"

# Cloudflare Workers Builds is an independent environment from GitHub Actions.
# Install the same MoonBit/compiler pair when the environment does not already
# provide it; this keeps async@0.21.0 and Warren on the repository contract.
if ! command -v moon >/dev/null 2>&1 || \
  ! moon version --all 2>/dev/null | grep -Fq "moonc v$MOONBIT_VERSION"; then
  curl -fsSL https://cli.moonbitlang.com/install/unix.sh |
    bash -s -- "$MOONBIT_VERSION"
  export PATH="$HOME/.moon/bin:$PATH"
fi

cd "$PROJECT_ROOT"
git submodule sync --recursive
git submodule update --init --recursive
scripts/moon-update.sh
scripts/install-local-warren.sh "$WARREN_BIN_DIR"

cd "$PROJECT_ROOT/apps/loomark"
"$WARREN_BIN_DIR/warren" build
