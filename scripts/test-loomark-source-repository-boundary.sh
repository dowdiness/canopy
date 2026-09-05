#!/bin/sh

# Compile the positive app dependency and a temporary sibling package that must
# be rejected by MoonBit's `internal/` visibility rule.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
module="$root/apps/loomark"
parent="$module/internal/recent_documents"
parent_created=0
probe=
output=$(mktemp "${TMPDIR:-/tmp}/loomark-source-repository-boundary.XXXXXX")
cleanup() {
  if [ -n "$probe" ]; then
    rm -rf -- "$probe"
  fi
  rm -f -- "$output"
  if [ "$parent_created" -eq 1 ]; then
    rmdir -- "$parent" 2>/dev/null || :
  fi
}
trap cleanup EXIT HUP INT TERM

cd "$module"
NEW_MOON_MOD=0 moon check app --target js

if [ -e "$parent" ]; then
  if [ ! -d "$parent" ]; then
    echo "probe parent is not a directory: $parent" >&2
    exit 1
  fi
else
  if mkdir -- "$parent" 2>/dev/null; then
    parent_created=1
  elif [ -d "$parent" ]; then
    :
  else
    echo "could not create probe parent: $parent" >&2
    exit 1
  fi
fi
probe=$(mktemp -d "$parent/source_repository_boundary_probe.XXXXXX")
probe_rel=${probe#"$module"/}
probe_package="dowdiness/loomark/$probe_rel"
cat >"$probe/moon.pkg" <<'EOF'
import {
  "dowdiness/loomark/app/internal/source_repository",
}

supported_targets = "js"
EOF
cat >"$probe/probe.mbt" <<'EOF'
fn boundary_probe() -> Int {
  0
}
EOF

if NEW_MOON_MOD=0 moon check "$probe_rel" --target js >"$output" 2>&1; then
  echo "expected sibling import of app/internal/source_repository to fail" >&2
  cat "$output" >&2
  exit 1
fi

if ! grep -Fq 'Error 1: Cannot import internal package dowdiness/loomark/app/internal/source_repository@' "$output" \
  || ! grep -Fq " in ${probe_package}@" "$output" \
  || ! grep -Fq ' due to internal visibility rules' "$output"; then
  echo "compiler rejected the probe without the expected internal visibility error" >&2
  cat "$output" >&2
  exit 1
fi

echo "Loomark source_repository boundary: app import accepted; sibling import rejected"
