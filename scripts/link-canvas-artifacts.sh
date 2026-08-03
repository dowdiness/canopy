#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

SOURCE="$PROJECT_ROOT/_build"
DEST="$PROJECT_ROOT/apps/canvas/_build"
ARTIFACT="$SOURCE/js/release/build/dowdiness/canopy-canvas/main/main.js"

[ -f "$ARTIFACT" ] || {
  echo "Missing Canvas artifact: $ARTIFACT" >&2
  exit 1
}
# `_build` is ignored generated output; only replace it when Git confirms that
# the exact destination is disposable.
if [ -e "$DEST" ] && [ ! -L "$DEST" ]; then
  git -C "$PROJECT_ROOT" check-ignore -q "$DEST" || {
    echo "Refusing to replace non-ignored directory: $DEST" >&2
    exit 1
  }
  rm -rf "$DEST"
fi
ln -sfnT "$SOURCE" "$DEST"
[ -f "$DEST/js/release/build/dowdiness/canopy-canvas/main/main.js" ]
echo "ok: Canvas artifacts linked at $DEST"
