#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOOMARK_ROOT="$PROJECT_ROOT/apps/loomark"
WARREN_BIN_DIR="$PROJECT_ROOT/_build/tools/bin"

if [ ! -x "$WARREN_BIN_DIR/warren" ]; then
  "$PROJECT_ROOT/scripts/install-local-warren.sh" "$WARREN_BIN_DIR"
fi

(
  cd "$LOOMARK_ROOT"
  npm ci
  npm run build:server
  npm run build:styles
  rm -rf dist
  "$WARREN_BIN_DIR/warren" build --public-dir "$LOOMARK_ROOT/public"
)

(
  cd "$LOOMARK_ROOT/examples/vanilla"
  npm ci
  npx tsc --noEmit -p tsconfig.sync.json
  PLAYWRIGHT_HTML_OPEN=never node ./node_modules/playwright/cli.js \
    test --config=playwright.sync.config.ts "$@"
)
