#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

WORKER_OUTPUT="$PROJECT_ROOT/_build/js/release/build/dowdiness/loomark/projection_worker/projection_worker.js"
STAGED_WORKER="$PROJECT_ROOT/apps/loomark/examples/vanilla/projection-worker.js"
WORKER_DIRECTORY="$(dirname "$STAGED_WORKER")"
WORK_DIR=""
WORKER_BACKUP=""
STAGING_WORKER=""
REPLACED_WORKER=false

cleanup() {
  if [ -n "$WORKER_BACKUP" ] &&
    { [ -e "$WORKER_BACKUP" ] || [ -L "$WORKER_BACKUP" ]; }; then
    rm -f "$STAGED_WORKER"
    mv "$WORKER_BACKUP" "$STAGED_WORKER"
  elif [ "$REPLACED_WORKER" = "true" ]; then
    rm -f "$STAGED_WORKER"
  fi
  if [ -n "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
  fi
}
trap cleanup EXIT

cd "$PROJECT_ROOT"
NEW_MOON_MOD=0 moon build --target js --release apps/loomark/internal/dev_host
NEW_MOON_MOD=0 moon build --target js --release apps/loomark/projection_worker
WORK_DIR="$(mktemp -d "$WORKER_DIRECTORY/.projection-worker.XXXXXX")"
WORKER_BACKUP="$WORK_DIR/backup"
STAGING_WORKER="$WORK_DIR/staged"
cp "$WORKER_OUTPUT" "$STAGING_WORKER"
if [ -e "$STAGED_WORKER" ] || [ -L "$STAGED_WORKER" ]; then
  mv "$STAGED_WORKER" "$WORKER_BACKUP"
fi
REPLACED_WORKER=true
mv "$STAGING_WORKER" "$STAGED_WORKER"
cd apps/loomark/examples/vanilla
npm ci
npm run typecheck:dev-host
npm run test:dev-host -- "$@"
