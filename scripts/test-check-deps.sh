#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

mkdir -p \
  "$fixture/scripts" \
  "$fixture/modules/independent/pkg" \
  "$fixture/modules/canopy/core"
cp "$root_dir/scripts/check-deps.sh" "$fixture/scripts/check-deps.sh"

cat >"$fixture/modules/independent/moon.mod" <<'EOF'
name = "example/independent"
EOF
cat >"$fixture/modules/independent/pkg/moon.pkg" <<'EOF'
import {
  "dowdiness/canopy/core",
}
EOF
cat >"$fixture/modules/canopy/moon.mod" <<'EOF'
name = "dowdiness/canopy"
EOF
cat >"$fixture/modules/canopy/core/moon.pkg" <<'EOF'
options(is_main: false)
EOF
cat >"$fixture/moon.work" <<'EOF'
members = [
  "./modules/independent",
  "./modules/canopy",
]
EOF
: >"$fixture/.gitmodules"

git init -q "$fixture"
git -C "$fixture" add .

if output="$($fixture/scripts/check-deps.sh 2>&1)"; then
  printf 'expected modules/* importing dowdiness/canopy/* to fail\n' >&2
  exit 1
fi

grep -Fq '[A] lib pkg modules/independent/pkg' <<<"$output"
printf 'ok: modules/* dependency rule enforced\n'
