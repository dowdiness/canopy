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

assert_contains "Primary module: dowdiness/canopy (modules/canopy)"
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
negative=""
trap 'rm -rf "$fixture" "$negative"' EXIT
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

# Negative fixture: no primary module manifest.
negative="$(mktemp -d)"
mkdir -p \
  "$negative/missing/scripts" \
  "$negative/missing/modules/other/pkg"
cp "$root_dir/scripts/package-overview.sh" "$negative/missing/scripts/package-overview.sh"
cat >"$negative/missing/modules/other/moon.mod.json" <<'EOF'
{"name":"example/other"}
EOF
cat >"$negative/missing/modules/other/pkg/moon.pkg.json" <<'EOF'
{}
EOF
cat >"$negative/missing/moon.work" <<'EOF'
members = ["./modules/other"]
EOF
git init -q "$negative/missing"
git -C "$negative/missing" add .
if output="$("$negative/missing/scripts/package-overview.sh" 2>"$negative/missing/err")"; then
  printf 'expected missing primary module to fail\n' >&2
  exit 1
fi
grep -Fq 'error: expected one dowdiness/canopy module manifest, found 0' \
  "$negative/missing/err"

# Negative fixture: two primary module manifests.
mkdir -p \
  "$negative/ambiguous/scripts" \
  "$negative/ambiguous/modules/one/src" \
  "$negative/ambiguous/modules/two/src"
cp "$root_dir/scripts/package-overview.sh" "$negative/ambiguous/scripts/package-overview.sh"
cat >"$negative/ambiguous/modules/one/moon.mod" <<'EOF'
name = "dowdiness/canopy"
source = "src"
EOF
cat >"$negative/ambiguous/modules/two/moon.mod" <<'EOF'
name = "dowdiness/canopy"
source = "src"
EOF
cat >"$negative/ambiguous/moon.work" <<'EOF'
members = ["./modules/one", "./modules/two"]
EOF
git init -q "$negative/ambiguous"
git -C "$negative/ambiguous" add .
if output="$("$negative/ambiguous/scripts/package-overview.sh" 2>"$negative/ambiguous/err")"; then
  printf 'expected ambiguous primary module to fail\n' >&2
  exit 1
fi
grep -Fq 'error: expected one dowdiness/canopy module manifest, found 2' \
  "$negative/ambiguous/err"

# Negative fixture: root moon.work without a members array.
mkdir -p \
  "$negative/no-members/scripts" \
  "$negative/no-members/modules/canopy/src/core"
cp "$root_dir/scripts/package-overview.sh" "$negative/no-members/scripts/package-overview.sh"
cat >"$negative/no-members/modules/canopy/moon.mod" <<'EOF'
name = "dowdiness/canopy"
source = "src"
EOF
cat >"$negative/no-members/modules/canopy/src/moon.pkg" <<'EOF'
options(is_main: false)
EOF
cat >"$negative/no-members/modules/canopy/src/core/moon.pkg" <<'EOF'
options(is_main: false)
EOF
cat >"$negative/no-members/moon.work" <<'EOF'
version = "0.1.0"
EOF
git init -q "$negative/no-members"
git -C "$negative/no-members" add .
if output="$("$negative/no-members/scripts/package-overview.sh" 2>"$negative/no-members/err")"; then
  printf 'expected moon.work without members array to fail\n' >&2
  exit 1
fi
grep -Fq 'error: root moon.work has no members array' "$negative/no-members/err"

printf 'ok: package overview reflects live repository topology\n'
