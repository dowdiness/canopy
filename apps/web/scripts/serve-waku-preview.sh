#!/usr/bin/env bash

set -euo pipefail

PORT="${CANOPY_WAKU_PREVIEW_PORT:-4193}"

if [[ "${CANOPY_SKIP_WAKU_BUILD:-0}" != '1' ]]; then
  CANOPY_SKIP_MOON_BUILD=1 npm run build:waku
fi
test -f dist/server/index.js
test -f dist/public/index.html
exec npx wrangler dev --config wrangler.waku.jsonc --env preview --port "$PORT"
