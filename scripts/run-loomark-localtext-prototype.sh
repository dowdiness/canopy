#!/usr/bin/env bash
# PROTOTYPE — build and run the disposable LocalText/four-clock experiment.
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
npm --prefix apps/loomark/examples/vanilla run bench:local-text-prototype
