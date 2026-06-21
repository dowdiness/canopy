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

    # Pre-build JS artifacts with retry-wrapped mooncakes CDN resilience.
    # MOON_WORK=off keeps the canvas `preferred-target: js` for the vite
    # web build (issue #335). Doing it here — before playwright starts —
    # avoids CDN flakes during the vite dev-server's lazy moon build.
    MOON_WORK=off "$SCRIPT_DIR/moon-update.sh"
    MOON_WORK=off moon build --target js
)

echo "Running canvas Playwright E2E..."
cd examples/canvas/web

if [ ! -d node_modules ]; then
    echo "Installing canvas web dependencies..."
    npm ci
fi

# Pre-built above; vite finds artifacts up-to-date and skips moon build.
export MOON_WORK=off

CI="${CI:-1}" npx playwright test "$@"
