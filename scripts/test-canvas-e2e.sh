#!/usr/bin/env bash

# Build the canvas MoonBit JS output and run canvas Playwright tests.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

(
    cd examples/canvas
    # Retry-wrapped: transient mooncakes CDN 403 (issue #467) auto-recovers.
    "$SCRIPT_DIR/moon-update.sh"
)

echo "Running canvas Playwright E2E..."
cd examples/canvas/web

if [ ! -d node_modules ]; then
    echo "Installing canvas web dependencies..."
    npm ci
fi

# Workspace mode is used: vite config and tsconfig now point to the
# workspace-level _build path (../../_build/...). No MOON_WORK=off
# needed — the rabbit libs' moon.mod imports resolve via workspace
# membership.

CI="${CI:-1}" npx playwright test "$@"
