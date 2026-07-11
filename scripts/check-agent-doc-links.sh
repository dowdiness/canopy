#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$root_dir"

if [ ! -L "CLAUDE.md" ]; then
  echo "error: CLAUDE.md must be a symlink to AGENTS.md"
  exit 1
fi

target="$(readlink CLAUDE.md)"

if [ "$target" != "AGENTS.md" ]; then
  echo "error: CLAUDE.md must point to AGENTS.md (found: $target)"
  exit 1
fi

if [ ! -f "AGENTS.md" ]; then
  echo "error: AGENTS.md is missing"
  exit 1
fi

echo "ok: CLAUDE.md -> AGENTS.md"
