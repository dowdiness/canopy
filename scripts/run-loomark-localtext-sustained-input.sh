#!/usr/bin/env bash
# PROTOTYPE — reproduce both counterbalanced 2k/10k sustained-input runs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export NEW_MOON_MOD=0
moon build --target js --release
./scripts/install-local-warren.sh
(
  cd apps/loomark
  ../../_build/tools/bin/warren build
)
if [[ ! -d apps/loomark/examples/vanilla/node_modules ]]; then
  npm --prefix apps/loomark/examples/vanilla ci
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/loomark-sustained-input.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
OUTPUT="${LOOMARK_SUSTAINED_OUTPUT:-$ROOT/docs/evidence/2026-08-23-loomark-localtext-sustained-input.json}"

run_benchmark() {
  local lines="$1"
  local samples="$2"
  local order="$3"
  local output="$4"
  LOOMARK_SUSTAINED_LINE_COUNTS="$lines" \
  LOOMARK_SUSTAINED_SAMPLES="$samples" \
  LOOMARK_SUSTAINED_LANE_ORDER="$order" \
  LOOMARK_SUSTAINED_OUTPUT="$output" \
    npm --prefix apps/loomark/examples/vanilla run bench:local-text-sustained-input
}

run_benchmark 2000 10 full-first "$WORK_DIR/2k-full-first.json"
run_benchmark 2000 10 local-first "$WORK_DIR/2k-local-first.json"
run_benchmark 10000 3 full-first "$WORK_DIR/10k-full-first.json"
run_benchmark 10000 3 local-first "$WORK_DIR/10k-local-first.json"

node scripts/aggregate-loomark-localtext-sustained-input.mjs \
  "$OUTPUT" \
  "$WORK_DIR/2k-full-first.json" \
  "$WORK_DIR/2k-local-first.json" \
  "$WORK_DIR/10k-full-first.json" \
  "$WORK_DIR/10k-local-first.json"
