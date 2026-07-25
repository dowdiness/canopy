#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WEB_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(CDPATH= cd -- "$WEB_ROOT/../.." && pwd)

cd "$REPO_ROOT"
BUILD_LOG="${TMPDIR:-/tmp}/canopy-waku-hub-build-$$.log"
if ! scripts/build-js.sh >"$BUILD_LOG" 2>&1; then
  cat "$BUILD_LOG"
  rm -f "$BUILD_LOG"
  exit 1
fi
rm -f "$BUILD_LOG"

cd "$WEB_ROOT"
export CANOPY_SKIP_MOON_BUILD=1
exec vite \
  --config vite.waku-hub-prototype.config.ts \
  --open /waku-hub-prototype.html \
  "$@"
