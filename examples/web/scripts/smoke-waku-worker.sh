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
curl -fsS "http://127.0.0.1:${PORT}/resume" >"$BODY_FILE"
grep -q 'class="pilot-workbench"' "$BODY_FILE"
grep -q 'data-resume-production-chat-unavailable' "$BODY_FILE"
grep -q 'Chat is available only in local development' "$BODY_FILE"
if grep -Eq 'aria-label="Chat message"|/api/pi-resume-chat|DEEPSEEK_API_KEY' "$BODY_FILE"; then
  echo 'Production Resume route exposed local chat controls or capability' >&2
  exit 1
fi
resume_chat_status="$(curl -sS -o /dev/null -w '%{http_code}' \
  "http://127.0.0.1:${PORT}/api/pi-resume-chat/status")"
test "$resume_chat_status" = '404'
curl -fsS "http://127.0.0.1:${PORT}/genui" >"$BODY_FILE"
grep -q 'Run recorded candidate' "$BODY_FILE"
if grep -Eq '/api/genui-feasibility|__canopyGenUi(Test|FeasibilityTest)|127\.0\.0\.1:11434|GENUI_OLLAMA_MODEL' "$BODY_FILE"; then
  echo 'Production GenUI route exposed a local study capability' >&2
  exit 1
fi
genui_feasibility_status="$(curl -sS -o /dev/null -w '%{http_code}' \
  "http://127.0.0.1:${PORT}/api/genui-feasibility")"
test "$genui_feasibility_status" = '404'
asset="$(find dist/public/assets -type f -name '*.js' -printf '%f\n' | sort | head -n 1)"
test -n "$asset"
curl -fsS -o /dev/null "http://127.0.0.1:${PORT}/assets/${asset}"
worker_status="$(curl -sS -o /dev/null -w '%{http_code}' \
  "http://127.0.0.1:${PORT}/__canopy_worker_probe_missing")"
test "$worker_status" = '404'
echo 'Waku workerd Hub and production Memo, Resume, and GenUI smoke: OK'
