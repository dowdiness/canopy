#!/usr/bin/env bash

set -euo pipefail

PORT="${CANOPY_WAKU_PREVIEW_PORT:-4193}"

CANOPY_SKIP_MOON_BUILD=1 npm run build:waku
exec npx wrangler dev --config wrangler.waku.jsonc --env preview --port "$PORT"
