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

# The note index prototype, assembled from its static page and its build.
NOTE_INDEX_DIST="$LOOMARK_ROOT/.note-index-e2e-dist"
NOTE_INDEX_PUBLIC="$LOOMARK_ROOT/examples/note_index/public"
moon -C "$PROJECT_ROOT" build --target js --release apps/loomark/examples/note_index
rm -rf "$NOTE_INDEX_DIST"
mkdir -p "$NOTE_INDEX_DIST/fonts"
cp "$NOTE_INDEX_PUBLIC/index.html" "$NOTE_INDEX_PUBLIC/styles.css" "$NOTE_INDEX_DIST/"
cp "$PROJECT_ROOT/_build/js/release/build/dowdiness/loomark/examples/note_index/note_index.js" "$NOTE_INDEX_DIST/"
cp "$LOOMARK_ROOT"/public/fonts/{iAWriterQuattroS-Regular-2.000.woff2,IBMPlexSansJP-Regular-1.004.woff2} "$NOTE_INDEX_DIST/fonts/"
LOOMARK_STANDALONE_DIST="$NOTE_INDEX_DIST" \
  LOOMARK_PLAYWRIGHT_CONFIG=playwright.note-index.config.ts \
  PLAYWRIGHT_HTML_OPEN=never npm test