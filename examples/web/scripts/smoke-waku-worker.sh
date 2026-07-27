#!/usr/bin/env bash

set -euo pipefail

PORT="${CANOPY_WAKU_WORKER_PORT:-8787}"
BASE_URL="http://127.0.0.1:${PORT}"
LOG_FILE="$(mktemp)"
BODY_FILE="$(mktemp)"
HEADER_FILE="$(mktemp)"
worker_pid=''
ready=false

cleanup() {
  local status="$?"
  trap - EXIT INT TERM HUP
  if [[ -n "$worker_pid" ]]; then
    kill -TERM -- "-$worker_pid" 2>/dev/null || true
    for _ in $(seq 1 20); do
      if ! kill -0 "$worker_pid" 2>/dev/null; then
        break
      fi
      sleep 0.1
    done
    if kill -0 "$worker_pid" 2>/dev/null; then
      kill -KILL -- "-$worker_pid" 2>/dev/null || true
    fi
    wait "$worker_pid" 2>/dev/null || true
  fi
  if [[ "$status" -ne 0 ]]; then
    cat "$LOG_FILE" >&2
  fi
  rm -f "$LOG_FILE" "$BODY_FILE" "$HEADER_FILE"
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP

fail() {
  echo "$1" >&2
  return 1
}

fetch() {
  local path="$1"
  HTTP_STATUS="$(curl \
    --silent \
    --show-error \
    --connect-timeout 5 \
    --max-time 15 \
    --output "$BODY_FILE" \
    --dump-header "$HEADER_FILE" \
    --write-out '%{http_code}' \
    "${BASE_URL}${path}")"
}

assert_status() {
  local path="$1"
  local expected="$2"
  fetch "$path"
  if [[ "$HTTP_STATUS" != "$expected" ]]; then
    fail "${path}: expected HTTP ${expected}, received ${HTTP_STATUS}"
  fi
}

assert_body_contains() {
  local path="$1"
  local marker="$2"
  assert_status "$path" 200
  if ! grep -Fq "$marker" "$BODY_FILE"; then
    fail "${path}: response did not contain ${marker}"
  fi
}

assert_redirect() {
  local source="$1"
  local destination="$2"
  assert_status "$source" 308
  local location
  location="$(awk 'tolower($1) == "location:" { sub(/\r$/, "", $2); print $2 }' "$HEADER_FILE")"
  if [[ "$location" != "$destination" ]]; then
    fail "${source}: expected Location ${destination}, received ${location:-<missing>}"
  fi
}

setsid npx wrangler dev \
  -c wrangler.waku.jsonc \
  -c wrangler-signaling.toml \
  --local \
  --port "$PORT" \
  --show-interactive-dev-session=false >"$LOG_FILE" 2>&1 &
worker_pid="$!"

for _ in $(seq 1 120); do
  if ! kill -0 "$worker_pid" 2>/dev/null; then
    fail 'Waku workerd process exited during startup.'
  fi
  if curl \
    --silent \
    --show-error \
    --connect-timeout 2 \
    --max-time 5 \
    --fail \
    "${BASE_URL}/" >"$BODY_FILE" 2>/dev/null; then
    ready=true
    break
  fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  fail 'Waku workerd process did not become ready within 120 seconds.'
fi

canonical_paths=(
  '/'
  '/index.html'
  '/ml'
  '/json'
  '/markdown'
  '/memo'
  '/posts'
  '/resume'
  '/genui'
  '/journey'
)
canonical_markers=(
  'Canopy demos'
  'Canopy demos'
  'Mini-ML CRDT Editor'
  'JSON CRDT Editor'
  'Markdown Editor'
  'data-memo-production-unavailable'
  'Post to yourself'
  'class="pilot-workbench"'
  'Run recorded candidate'
  'How should this journey change?'
)
for index in "${!canonical_paths[@]}"; do
  assert_body_contains "${canonical_paths[$index]}" "${canonical_markers[$index]}"
done

assert_status '/index.html' 200
if grep -qi '^location:' "$HEADER_FILE"; then
  fail '/index.html unexpectedly returned a Location header.'
fi

assert_body_contains '/memo' 'available only in local development'
if grep -Eq 'id="api-key"|Fix Typos|data-imperative-demo-host="memo"' "$BODY_FILE"; then
  fail 'Production Memo route exposed local provider controls.'
fi
assert_body_contains '/resume' 'data-resume-production-chat-unavailable'
assert_body_contains '/resume' 'Chat is available only in local development'
if grep -Eq 'aria-label="Chat message"|/api/pi-resume-chat|DEEPSEEK_API_KEY' "$BODY_FILE"; then
  fail 'Production Resume route exposed local chat controls or capability.'
fi
assert_body_contains '/genui' 'Run recorded candidate'
if grep -Eq '/api/genui-feasibility|__canopyGenUi(Test|FeasibilityTest)|127\.0\.0\.1:11434|GENUI_OLLAMA_MODEL' "$BODY_FILE"; then
  fail 'Production GenUI route exposed a local study capability.'
fi

legacy_paths=(
  '/json.html'
  '/markdown.html'
  '/memo.html'
  '/posts.html'
  '/resume.html'
  '/genui.html'
  '/genui-possibilities.html'
)
canonical_alias_targets=(
  '/json'
  '/markdown'
  '/memo'
  '/posts'
  '/resume'
  '/genui'
  '/journey'
)
for index in "${!legacy_paths[@]}"; do
  legacy="${legacy_paths[$index]}"
  canonical="${canonical_alias_targets[$index]}"
  assert_redirect "${legacy}?source=workerd" "${canonical}?source=workerd"
  assert_redirect "/RSC/R${legacy}.txt?source=workerd" "/RSC/R${canonical}.txt?source=workerd"
done

for canonical in '/ml' '/json' '/markdown' '/memo' '/posts' '/resume' '/genui' '/journey'; do
  assert_status "/RSC/R${canonical}.txt?source=workerd" 200
  if [[ ! -s "$BODY_FILE" ]]; then
    fail "/RSC/R${canonical}.txt: response body was empty."
  fi
done

asset_file="$(find dist/public/assets -type f -name '*.js' -print -quit)"
if [[ -z "$asset_file" ]]; then
  fail 'Waku build did not contain a JavaScript asset.'
fi
asset_path="${asset_file#dist/public}"
assert_status "$asset_path" 200

for missing_path in \
  '/__canopy_worker_probe_missing' \
  '/RSC/R/__canopy_worker_probe_missing.txt' \
  '/api/ast-grep' \
  '/api/pi-resume-chat' \
  '/api/pi-resume-chat/status' \
  '/api/genui-feasibility' \
  '/signaling/'; do
  assert_status "$missing_path" 404
done

assert_status '/signaling' 426
if ! grep -Fq 'Expected WebSocket upgrade' "$BODY_FILE"; then
  fail '/signaling did not delegate the non-upgrade response.'
fi

HTTP_STATUS="$(curl \
  --silent \
  --show-error \
  --connect-timeout 5 \
  --max-time 15 \
  --request OPTIONS \
  --output "$BODY_FILE" \
  --dump-header "$HEADER_FILE" \
  --write-out '%{http_code}' \
  "${BASE_URL}/signaling")"
if [[ "$HTTP_STATUS" != '200' ]]; then
  fail "/signaling OPTIONS: expected HTTP 200, received ${HTTP_STATUS}"
fi
if ! tr -d '\r' <"$HEADER_FILE" | grep -Eqi '^access-control-allow-origin: \*$'; then
  fail '/signaling OPTIONS did not preserve the Signaling Worker CORS response.'
fi

# Production Cloudflare supplies cf-visitor. Simulate it so Waku's local-only
# gzip workaround does not reconstruct the otherwise valid 101 response.
node scripts/smoke-signaling-websocket.mjs \
  "ws://127.0.0.1:${PORT}/signaling" \
  --cloudflare-local

echo 'Waku workerd route, availability, asset, and signaling smoke: OK'
