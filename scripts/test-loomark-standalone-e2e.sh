#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOOMARK_ROOT="$PROJECT_ROOT/apps/loomark"
WARREN_BIN_DIR="$PROJECT_ROOT/_build/tools/bin"
WARREN="$WARREN_BIN_DIR/warren"
DEV_PORT="${LOOMARK_STANDALONE_DEV_PORT:-4318}"
WORK_DIR="$(mktemp -d)"
DEV_PID=""
DEV_GROUP="false"

stop_dev_server() {
  if [ -z "$DEV_PID" ]; then
    return
  fi
  if [ "$DEV_GROUP" = "true" ]; then
    kill -TERM -- "-$DEV_PID" 2>/dev/null || true
    sleep 1
    kill -KILL -- "-$DEV_PID" 2>/dev/null || true
  else
    pkill -TERM -P "$DEV_PID" 2>/dev/null || true
    kill -TERM "$DEV_PID" 2>/dev/null || true
  fi
  wait "$DEV_PID" 2>/dev/null || true
  DEV_PID=""
}

cleanup() {
  stop_dev_server
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT HUP INT TERM

"$PROJECT_ROOT/scripts/install-local-warren.sh" "$WARREN_BIN_DIR"

if curl --fail --silent "http://127.0.0.1:$DEV_PORT/" >/dev/null 2>&1; then
  echo "error: standalone development port $DEV_PORT is already serving HTTP" >&2
  exit 1
fi

if command -v setsid >/dev/null 2>&1; then
  (
    cd "$LOOMARK_ROOT"
    exec setsid "$WARREN" dev --direct \
      --entry capability-worker=worker \
      --entry projection-worker=projection_worker \
      --port "$DEV_PORT"
  ) >"$WORK_DIR/warren-dev.log" 2>&1 &
  DEV_GROUP="true"
else
  (
    cd "$LOOMARK_ROOT"
    exec "$WARREN" dev --direct \
      --entry capability-worker=worker \
      --entry projection-worker=projection_worker \
      --port "$DEV_PORT"
  ) >"$WORK_DIR/warren-dev.log" 2>&1 &
fi
DEV_PID=$!

attempt=0
while [ "$attempt" -lt 60 ]; do
  if curl --fail --silent --show-error \
      "http://127.0.0.1:$DEV_PORT/" >"$WORK_DIR/dev-index.html" 2>/dev/null &&
    curl --fail --silent --show-error \
      "http://127.0.0.1:$DEV_PORT/capability-worker.js" \
      >"$WORK_DIR/dev-capability-worker.js" 2>/dev/null &&
    curl --fail --silent --show-error \
      "http://127.0.0.1:$DEV_PORT/projection-worker.js" \
      >"$WORK_DIR/dev-projection-worker.js" 2>/dev/null; then
    break
  fi
  if ! kill -0 "$DEV_PID" 2>/dev/null; then
    cat "$WORK_DIR/warren-dev.log" >&2
    echo "error: Warren direct development server stopped before becoming ready" >&2
    exit 1
  fi
  attempt=$((attempt + 1))
  sleep 1
done
if [ "$attempt" -eq 60 ]; then
  cat "$WORK_DIR/warren-dev.log" >&2
  echo "error: Warren direct development server did not become ready" >&2
  exit 1
fi
grep -q '<main id="app"></main>' "$WORK_DIR/dev-index.html"
grep -q '/__warren/direct.js' "$WORK_DIR/dev-index.html"
test -s "$WORK_DIR/dev-capability-worker.js"
test -s "$WORK_DIR/dev-projection-worker.js"
if grep -q 'warren-devtool' "$WORK_DIR/dev-index.html"; then
  echo "error: Warren direct mode unexpectedly served the iframe development shell" >&2
  exit 1
fi
stop_dev_server

rm -rf "$LOOMARK_ROOT/dist"
(
  cd "$LOOMARK_ROOT"
  "$WARREN" build \
    --entry capability-worker=worker \
    --entry projection-worker=projection_worker
)

test -s "$LOOMARK_ROOT/dist/favicon.svg"
test -s "$LOOMARK_ROOT/dist/index.html"
test -s "$LOOMARK_ROOT/dist/index.js"
test -s "$LOOMARK_ROOT/dist/capability-worker.js"
test -s "$LOOMARK_ROOT/dist/projection-worker.js"
test -s "$LOOMARK_ROOT/dist/styles.css"
grep -q '<main id="app"></main>' "$LOOMARK_ROOT/dist/index.html"
grep -q '<script src="./index.js" type="module"></script>' "$LOOMARK_ROOT/dist/index.html"
grep -q '<link rel="icon" href="./favicon.svg" type="image/svg+xml"' "$LOOMARK_ROOT/dist/index.html"
grep -q '<link rel="stylesheet" href="./styles.css"' "$LOOMARK_ROOT/dist/index.html"
for private_name in \
  loomark-driver-target \
  loomark-event-target \
  mount_dev_host \
  dev_host_snapshot
do
  if grep -q "$private_name" "$LOOMARK_ROOT/dist/index.js"; then
    echo "error: production bundle contains private control $private_name" >&2
    exit 1
  fi
done
tracked_dist="$(git -C "$PROJECT_ROOT" ls-files -- apps/loomark/dist)"
if [ -n "$tracked_dist" ]; then
  echo "error: generated Loomark dist files are tracked:" >&2
  echo "$tracked_dist" >&2
  exit 1
fi
for output in favicon.svg index.html index.js capability-worker.js styles.css; do
  git -C "$PROJECT_ROOT" check-ignore -q "apps/loomark/dist/$output"
done

cd "$LOOMARK_ROOT/examples/vanilla"
npm ci
npm run typecheck:standalone
PLAYWRIGHT_HTML_OPEN=never npm run test:standalone -- "$@"
