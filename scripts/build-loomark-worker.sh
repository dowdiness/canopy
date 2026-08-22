#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
WARREN_BIN_DIR="$PROJECT_ROOT/_build/tools/bin"

export NEW_MOON_MOD=0
export PATH="$HOME/.moon/bin:$PATH"

# Cloudflare Workers Builds is an independent environment from GitHub Actions.
# Self-heal to the repository's MoonBit/compiler pair before Warren runs.
"$SCRIPT_DIR/moon-toolchain.sh" ensure

cd "$PROJECT_ROOT"
git submodule sync --recursive
git submodule update --init --recursive
scripts/moon-update.sh
scripts/install-local-warren.sh "$WARREN_BIN_DIR"

cd "$PROJECT_ROOT/apps/loomark"
"$WARREN_BIN_DIR/warren" build
