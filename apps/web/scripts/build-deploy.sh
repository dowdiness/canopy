#!/bin/sh
set -e

if [ "$#" -gt 1 ] || [ "${1:-waku}" != "waku" ]; then
  echo "Usage: $0 [waku]" >&2
  exit 2
fi

# Install MoonBit CLI
MOONBIT_VERSION="0.10.4+ade96c819"
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash -s -- "$MOONBIT_VERSION"
export PATH="$HOME/.moon/bin:$PATH"
moon version --all

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)"

# Move to repo root regardless of the caller's current working directory.
cd "$REPO_ROOT"

# Initialize git submodules
echo "==> Initializing submodules..."
git submodule update --init --recursive
echo "==> Submodules initialized"

# Pre-build MoonBit modules explicitly
echo "==> Building crdt module..."
moon build --target js --release

echo "==> Building graphviz module..."
(cd deps/graphviz && moon build --target js --release)

cd apps/web
npm run build:waku
