#!/usr/bin/env bash
#
# Run canvas Playwright E2E tests. CI supplies pre-built artifacts from the
# build-js job.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo "Running canvas Playwright E2E..."
cd apps/canvas/web

if [ ! -d node_modules ]; then
    echo "Installing canvas web dependencies..."
    npm ci
fi

# Workspace mode: vite/tsconfig paths point to workspace-level _build
# (../../_build/...). unset MOON_WORK so the Vite plugin's `moon build`
# (local dev only) uses workspace membership for rabbita lib deps.
# In CI, vite-plugin loads pre-built artifacts from the build-js download.
unset MOON_WORK

CI="${CI:-1}" npx playwright test "$@"
