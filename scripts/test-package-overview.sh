#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="$("$root_dir/scripts/package-overview.sh")"

assert_contains() {
  local expected=$1
  if ! grep -Fq -- "$expected" <<<"$output"; then
    printf 'missing expected package-overview output: %s\n' "$expected" >&2
    exit 1
  fi
}

assert_matches() {
  local expected=$1
  if ! grep -Eq -- "$expected" <<<"$output"; then
    printf 'missing expected package-overview pattern: %s\n' "$expected" >&2
    exit 1
  fi
}

assert_absent() {
  local unexpected=$1
  if grep -Fq -- "$unexpected" <<<"$output"; then
    printf 'unexpected package-overview output: %s\n' "$unexpected" >&2
    exit 1
  fi
}

assert_contains "Primary module: dowdiness/canopy (.)"
assert_matches '^=== Primary module packages \([0-9]+\) ===$'
assert_matches '^=== Root workspace modules \([0-9]+\) ===$'
assert_matches '^=== Git submodules \([0-9]+\) ===$'

# These literals represent package families the old hand-maintained list missed.
assert_contains "dowdiness/canopy/ephemeral"
assert_contains "dowdiness/canopy/ffi/jsx"
assert_contains "dowdiness/canopy/lang/markdown/proj"
assert_contains "dowdiness/canopy/protocol/wire"
assert_contains "dowdiness/canopy/workspace/coordinator"

# Symbol counts depended on a stale MoonBit manifest mode and silently printed zero.
assert_absent "pub symbols"

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p \
  "$fixture/scripts" \
  "$fixture/modules/canopy/src/core" \
  "$fixture/modules/other/pkg"
cp "$root_dir/scripts/package-overview.sh" "$fixture/scripts/package-overview.sh"

cat >"$fixture/modules/canopy/moon.mod" <<'EOF'
name = "dowdiness/canopy"
source = "src"
EOF
cat >"$fixture/modules/canopy/src/moon.pkg" <<'EOF'
options(is_main: false)
EOF
cat >"$fixture/modules/canopy/src/core/moon.pkg" <<'EOF'
options(is_main: false)
EOF
cat >"$fixture/modules/canopy/src/core/moon.pkg.json" <<'EOF'
{}
EOF
cat >"$fixture/modules/other/moon.mod.json" <<'EOF'
{"name":"example/other"}
EOF
cat >"$fixture/modules/other/pkg/moon.pkg.json" <<'EOF'
{}
EOF
cat >"$fixture/moon.work" <<'EOF'
members = [
  "./modules/canopy",
  "./modules/other",
]
EOF
cat >"$fixture/.gitmodules" <<'EOF'
[submodule "dependency"]
  path = deps/dependency
  url = https://example.com/dependency.git
EOF

git init -q "$fixture"
git -C "$fixture" add .
output="$("$fixture/scripts/package-overview.sh")"

assert_contains "Primary module: dowdiness/canopy (modules/canopy)"
assert_contains "Primary module packages (2)"
assert_contains "dowdiness/canopy/core"
assert_absent "dowdiness/canopy/src/core"
assert_contains "Root workspace modules (2)"
assert_contains "Git submodules (1)"

printf 'ok: package overview reflects live repository topology\n'
