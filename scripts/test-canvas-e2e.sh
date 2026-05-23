#!/usr/bin/env bash

# Build the canvas MoonBit JS output and run canvas Playwright tests.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

(
    cd examples/canvas
    moon update
)

echo "Running canvas Playwright E2E..."
cd examples/canvas/web

if [ ! -d node_modules ]; then
    echo "Installing canvas web dependencies..."
    npm ci
fi

# Disable workspace mode for the JS build that vite-plugin-moonbit kicks off.
# When examples/canvas is a moon.work member, `moon build --target js` only
# emits wasm-gc artifacts (moon picks the workspace's wasm-gc target over
# canvas's `preferred-target: js`), so vite can't find _build/js/.../main.js.
# MOON_WORK=off scopes moon to the canvas package only, restoring the JS path.
# Tracked as #335; remove once moon honors per-member preferred-target.
export MOON_WORK=off

CI="${CI:-1}" npx playwright test "$@"
