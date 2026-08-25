#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOOMARK_ROOT="$PROJECT_ROOT/apps/loomark"
WARREN_BIN_DIR="$PROJECT_ROOT/_build/tools/bin"
WARREN="$WARREN_BIN_DIR/warren"

"$PROJECT_ROOT/scripts/install-local-warren.sh" "$WARREN_BIN_DIR"

rm -rf "$LOOMARK_ROOT/dist"
(
  cd "$LOOMARK_ROOT"
  "$WARREN" build --public-dir "$LOOMARK_ROOT/public"
)

test -s "$LOOMARK_ROOT/dist/favicon.svg"
test -s "$LOOMARK_ROOT/dist/index.html"
test -s "$LOOMARK_ROOT/dist/index.js"
test -s "$LOOMARK_ROOT/dist/styles.css"
test ! -e "$LOOMARK_ROOT/dist/capability-worker.js"
test ! -e "$LOOMARK_ROOT/dist/projection-worker.js"
grep -q '<main id="app"></main>' "$LOOMARK_ROOT/dist/index.html"
grep -Eq '<script src="(/|\./)index\.js" type="module"></script>' "$LOOMARK_ROOT/dist/index.html"
grep -q '<link rel="icon" href="./favicon.svg" type="image/svg+xml"' "$LOOMARK_ROOT/dist/index.html"
grep -q '<link rel="stylesheet" href="./styles.css"' "$LOOMARK_ROOT/dist/index.html"
for forbidden_name in \
  capability-worker \
  projection-worker \
  loomark-driver-target \
  loomark-event-target \
  mount_dev_host \
  dev_host_snapshot \
  gate-r0-full-history-oracle
do
  if grep -q "$forbidden_name" "$LOOMARK_ROOT/dist/index.js"; then
    echo "error: production bundle contains removed feature $forbidden_name" >&2
    exit 1
  fi
done
unexpected_javascript="$(
  find "$LOOMARK_ROOT/dist" -maxdepth 1 -type f -name '*.js' ! -name 'index.js' -print
)"
if [ -n "$unexpected_javascript" ]; then
  echo "error: production release contains unexpected JavaScript:" >&2
  echo "$unexpected_javascript" >&2
  exit 1
fi
tracked_dist="$(git -C "$PROJECT_ROOT" ls-files -- apps/loomark/dist)"
if [ -n "$tracked_dist" ]; then
  echo "error: generated Loomark dist files are tracked:" >&2
  echo "$tracked_dist" >&2
  exit 1
fi
for output in favicon.svg index.html index.js styles.css; do
  git -C "$PROJECT_ROOT" check-ignore -q "apps/loomark/dist/$output"
done

cd "$LOOMARK_ROOT/examples/vanilla"
npm ci
npm run typecheck
PLAYWRIGHT_HTML_OPEN=never npm test -- "$@"
