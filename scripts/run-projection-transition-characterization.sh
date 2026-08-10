#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export NEW_MOON_MOD=0

moon test --target native \
  modules/canopy/core/projection_transition_characterization_wbtest.mbt
moon test --target native \
  modules/canopy/lang/lambda/companion/editor_hints_integration_wbtest.mbt
