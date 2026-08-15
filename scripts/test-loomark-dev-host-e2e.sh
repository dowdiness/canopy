#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

WORKER_OUTPUT="$PROJECT_ROOT/_build/js/release/build/dowdiness/loomark/projection_worker/projection_worker.js"
STAGED_WORKER="$PROJECT_ROOT/apps/loomark/examples/vanilla/projection-worker.js"

cleanup() {
  rm -f "$STAGED_WORKER"
}
trap cleanup EXIT

cd "$PROJECT_ROOT"
NEW_MOON_MOD=0 moon build --target js --release apps/loomark/internal/dev_host
NEW_MOON_MOD=0 moon build --target js --release apps/loomark/projection_worker
cp "$WORKER_OUTPUT" "$STAGED_WORKER"
cd apps/loomark/examples/vanilla
npm ci
npm run typecheck:dev-host
npm run test:dev-host -- "$@"
