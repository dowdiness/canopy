#!/usr/bin/env bash

# Build the current MoonBit JS outputs and run web Playwright tests.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

"$SCRIPT_DIR/build-js.sh"

echo "Running web Playwright E2E..."
cd examples/web

if [ ! -d node_modules ]; then
    echo "Installing web dependencies..."
    npm ci
fi

CI="${CI:-1}" npx playwright test "$@"
