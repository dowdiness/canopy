#!/usr/bin/env bash

set -euo pipefail

PORT="${CANOPY_WAKU_WORKER_PORT:-8787}"
LOG_FILE="$(mktemp)"
BODY_FILE="$(mktemp)"
worker_pid=''

cleanup() {
  if [[ -n "$worker_pid" ]]; then
    kill -TERM -- "-$worker_pid" 2>/dev/null || true
    wait "$worker_pid" 2>/dev/null || true
  fi
  rm -f "$LOG_FILE" "$BODY_FILE"
}
trap cleanup EXIT INT TERM HUP

setsid npx wrangler dev --config wrangler.waku.jsonc --env preview --port "$PORT" >"$LOG_FILE" 2>&1 &
worker_pid="$!"

for _ in $(seq 1 120); do
  if curl -fsS "http://127.0.0.1:${PORT}/" >"$BODY_FILE" 2>/dev/null; then
    break
  fi
  if ! kill -0 "$worker_pid" 2>/dev/null; then
    cat "$LOG_FILE" >&2
    exit 1
  fi
  sleep 1
done

grep -q 'Canopy demos' "$BODY_FILE"
curl -fsS "http://127.0.0.1:${PORT}/memo" >"$BODY_FILE"
grep -q 'data-memo-production-unavailable' "$BODY_FILE"
grep -q 'available only in local development' "$BODY_FILE"
if grep -Eq 'id="api-key"|Fix Typos|data-imperative-demo-host="memo"' "$BODY_FILE"; then
  echo 'Production Memo route exposed local provider controls' >&2
  exit 1
fi
asset="$(find dist/public/assets -type f -name '*.js' -printf '%f\n' | sort | head -n 1)"
test -n "$asset"
curl -fsS -o /dev/null "http://127.0.0.1:${PORT}/assets/${asset}"
worker_status="$(curl -sS -o /dev/null -w '%{http_code}' \
  "http://127.0.0.1:${PORT}/__canopy_worker_probe_missing")"
test "$worker_status" = '404'
echo 'Waku workerd Hub and production Memo smoke: OK'
