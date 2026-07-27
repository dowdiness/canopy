#!/usr/bin/env bash

set -euo pipefail

# Waku's Cloudflare enhancer writes a generic redirected deploy config. The
# repository-owned root config carries the required preview/production names,
# so remove the redirect after producing the official dist/server output.
CLOUDFLARE=1 CANOPY_SKIP_MOON_BUILD=1 npx --no-install waku build
rm -f .wrangler/deploy/config.json
