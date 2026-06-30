#!/usr/bin/env bash
#
# Run canvas Playwright E2E tests. Skips the MoonBit dep update step when
# CANOPY_SKIP_MOON_BUILD=1 (CI uses pre-built artifacts from build-js).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

if [[ "${CANOPY_SKIP_MOON_BUILD:-0}" != "1" ]]; then
    (
        cd examples/canvas
        # Retry-wrapped: transient mooncakes CDN 403 (issue #467) auto-recovers.
        "$SCRIPT_DIR/moon-update.sh"
    )
fi

echo "Running canvas Playwright E2E..."
cd examples/canvas/web

if [ ! -d node_modules ]; then
    echo "Installing canvas web dependencies..."
    npm ci
fi

# Workspace mode: vite/tsconfig paths point to workspace-level _build
# (../../_build/...). unset MOON_WORK so the Vite plugin's `moon build`
# (local dev only) uses workspace membership for rabbita lib deps.
# In CI, CANOPY_SKIP_MOON_BUILD=1 skips MoonBit entirely and vite-plugin
# loads pre-built artifacts from the build-js download.
unset MOON_WORK

CI="${CI:-1}" npx playwright test "$@"
