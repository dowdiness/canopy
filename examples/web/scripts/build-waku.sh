#!/usr/bin/env bash

set -euo pipefail

# Waku's Cloudflare enhancer writes a generic redirected deploy config. The
# repository-owned root config carries the required preview/production names,
# so remove the redirect after producing the official dist/server output.
# Waku beta.8 can fetch its internal SSG preview endpoint before the listener
# settles in CI; the preload retries only that loopback ECONNREFUSED race.
CANOPY_WAKU_BUILD_FETCH_RETRY=1 \
  NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--import=./scripts/waku-build-fetch-retry.mjs" \
  CLOUDFLARE=1 \
  CANOPY_SKIP_MOON_BUILD=1 \
  npx --no-install waku build
rm -f .wrangler/deploy/config.json
