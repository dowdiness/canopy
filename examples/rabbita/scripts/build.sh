#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(dirname "$SCRIPT_DIR")
EXAMPLES_ROOT=$(dirname "$PROJECT_ROOT")
REPO_ROOT=$(dirname "$EXAMPLES_ROOT")

ensure_moon() {
  if command -v moon >/dev/null 2>&1; then
    return
  fi

  if [ -x "$HOME/.moon/bin/moon" ]; then
    export PATH="$HOME/.moon/bin:$PATH"
    return
  fi

  echo "==> Installing MoonBit CLI..."
  curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
  export PATH="$HOME/.moon/bin:$PATH"
}

ensure_submodules() {
  if [ -f "$REPO_ROOT/loom/loom/moon.mod.json" ] \
    && [ -f "$REPO_ROOT/loom/examples/lambda/moon.mod.json" ] \
    && [ -f "$REPO_ROOT/event-graph-walker/moon.mod.json" ]; then
    return
  fi

  echo "==> Initializing git submodules..."
  (
    cd "$REPO_ROOT"
    git submodule update --init --recursive
  )
}

ensure_moon
ensure_submodules

if [ "${CI:-}" = "true" ] || [ ! -d "$REPO_ROOT/.mooncakes" ] || [ ! -d "$PROJECT_ROOT/.mooncakes" ]; then
  echo "==> Resolving MoonBit dependencies (repo root)..."
  (
    cd "$REPO_ROOT"
    moon update
  )

  echo "==> Resolving MoonBit dependencies (examples/rabbita)..."
  (
    cd "$PROJECT_ROOT"
    moon update
  )
fi

echo "==> Building Rabbita app..."
npx vite build
