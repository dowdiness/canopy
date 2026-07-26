#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_ROOT="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(cd "$WEB_ROOT/../.." && pwd)"
VITE_PORT="${CANOPY_VITE_PORT:-5173}"
WAKU_PORT="${CANOPY_WAKU_PORT:-5183}"
children=()

cleanup() {
  trap - EXIT INT TERM HUP
  if ((${#children[@]} > 0)); then
    kill "${children[@]}" 2>/dev/null || true
    wait "${children[@]}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM HUP

cd "$PROJECT_ROOT"
moon build --target js --release
moon build --target js --release --watch &
children+=("$!")

cd "$WEB_ROOT"
CANOPY_EXTERNAL_MOON_WATCH=1 npm run dev:vite -- --port "$VITE_PORT" &
children+=("$!")
CANOPY_EXTERNAL_MOON_WATCH=1 npm run dev:waku -- --port "$WAKU_PORT" &
children+=("$!")

wait -n "${children[@]}"
