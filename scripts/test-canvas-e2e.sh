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

# Workspace mode: vite/tsconfig paths point to workspace-level _build
# (../../_build/...). Explicitly unset MOON_WORK so child processes
# (vite → moon build) use workspace membership for rabbita lib deps.
unset MOON_WORK

CI="${CI:-1}" npx playwright test "$@"
