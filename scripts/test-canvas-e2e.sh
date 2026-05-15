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

CI="${CI:-1}" npx playwright test "$@"
