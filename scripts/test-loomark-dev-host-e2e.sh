#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"
NEW_MOON_MOD=0 moon build --target js --release apps/loomark/internal/dev_host
cd apps/loomark/examples/vanilla
npm ci
npm run typecheck:dev-host
npm run test:dev-host -- "$@"
