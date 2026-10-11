#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOOMARK_ROOT="$PROJECT_ROOT/apps/loomark"
WARREN="$PROJECT_ROOT/_build/tools/bin/warren"

"$SCRIPT_DIR/build-loomark-standalone.sh" "$PROJECT_ROOT"

cd "$LOOMARK_ROOT/examples/vanilla"
npm ci
npm run typecheck
PLAYWRIGHT_HTML_OPEN=never npm test -- "$@"

# Exercise the copied Sidebar's mobile branch in an isolated test entry.
# Its output is separate from the production dist checked above.
SIDEBAR_DIST="$LOOMARK_ROOT/.sidebar-e2e-dist"
(
  cd "$LOOMARK_ROOT"
  "$WARREN" build --browser-entry examples/sidebar_fixture --server-entry "" --dist "$SIDEBAR_DIST"
)
LOOMARK_STANDALONE_DIST="$SIDEBAR_DIST" \
  LOOMARK_PLAYWRIGHT_CONFIG=playwright.sidebar.config.ts \
  PLAYWRIGHT_HTML_OPEN=never npm test