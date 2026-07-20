#!/usr/bin/env bash
#
# Run web Playwright E2E tests. Skips the MoonBit JS build step when
# CANOPY_SKIP_MOON_BUILD=1 (CI uses pre-built artifacts from build-js).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

if [[ "${CANOPY_SKIP_MOON_BUILD:-0}" != "1" ]]; then
    "$SCRIPT_DIR/build-js.sh"
fi

echo "Running web Playwright E2E..."
cd examples/web

if [ ! -d node_modules ]; then
    echo "Installing web dependencies..."
    npm ci
fi

echo "Running GenUI recipe contract tests..."
node --test src/features/genui/core/genui-spike-recipe.test.mjs

CI="${CI:-1}" npx playwright test "$@"

if [ "$#" -eq 0 ]; then
    echo "Running GenUI production preview tests..."
    CI="${CI:-1}" npx playwright test --config=playwright.preview.config.ts
fi
