#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd "$SCRIPT_DIR/.." && pwd)

LEFTHOOK_BIN=${LEFTHOOK_BIN:-lefthook}
if [ -x "$LEFTHOOK_BIN" ]; then
  case "$LEFTHOOK_BIN" in
    /*) ;;
    *) LEFTHOOK_BIN=$(CDPATH= cd "$(dirname "$LEFTHOOK_BIN")" && pwd)/$(basename "$LEFTHOOK_BIN") ;;
  esac
elif command -v "$LEFTHOOK_BIN" >/dev/null 2>&1; then
  LEFTHOOK_BIN=$(command -v "$LEFTHOOK_BIN")
else
  echo "error: Lefthook binary not found; set LEFTHOOK_BIN" >&2
  exit 1
fi

FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/canopy-lefthook-routing.XXXXXX")
LOG="$FIXTURE/calls.log"
OUTPUT="$FIXTURE/lefthook-output.log"
EXPECTED="$FIXTURE/expected.log"
trap 'rm -rf "$FIXTURE"' EXIT HUP INT TERM

mkdir -p "$FIXTURE/bin" "$FIXTURE/modules/canopy/core" "$FIXTURE/scripts"
cp "$REPO_ROOT/lefthook.yml" "$FIXTURE/lefthook.yml"
cp "$REPO_ROOT/scripts/run-moonbit-rename-route.sh" "$FIXTURE/scripts/run-moonbit-rename-route.sh"
chmod +x "$FIXTURE/scripts/run-moonbit-rename-route.sh"

cat > "$FIXTURE/bin/just" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$LEFTHOOK_ROUTING_LOG"
EOF
chmod +x "$FIXTURE/bin/just"
export LEFTHOOK_ROUTING_LOG="$LOG"
export PATH="$FIXTURE/bin:$PATH"

printf '%s\n' 'AGENTS fixture' > "$FIXTURE/AGENTS.md"
ln -s AGENTS.md "$FIXTURE/CLAUDE.md"
printf '%s\n' 'baseline' > "$FIXTURE/README.md"
printf '%s\n' 'baseline' > "$FIXTURE/justfile"
printf '%s\n' 'baseline' > "$FIXTURE/modules/canopy/core/deleted.mbt"
printf '%s\n' 'baseline' > "$FIXTURE/modules/canopy/core/rename-before.mbt"
printf '%s\n' 'baseline' > "$FIXTURE/scripts/run-moon-module.sh"
printf '%s\n' 'baseline' > "$FIXTURE/scripts/vendored-check-common.sh"

git -C "$FIXTURE" init --quiet
git -C "$FIXTURE" symbolic-ref HEAD refs/heads/main
git -C "$FIXTURE" config user.email lefthook-routing@example.invalid
git -C "$FIXTURE" config user.name lefthook-routing-test
git -C "$FIXTURE" add -A
git -C "$FIXTURE" commit --quiet -m baseline

if ! (cd "$FIXTURE" && "$LEFTHOOK_BIN" validate >"$OUTPUT" 2>&1); then
  cat "$OUTPUT" >&2
  echo "FAIL Lefthook configuration validation" >&2
  exit 1
fi

reset_fixture() {
  git -C "$FIXTURE" reset --hard --quiet HEAD
  git -C "$FIXTURE" clean -fdq
  : > "$LOG"
}

stage_file() {
  path=$1
  contents=$2
  mkdir -p "$FIXTURE/$(dirname "$path")"
  printf '%s\n' "$contents" > "$FIXTURE/$path"
  git -C "$FIXTURE" add -- "$path"
}

assert_calls() {
  name=$1
  shift
  : > "$EXPECTED"
  for expected_call in "$@"; do
    printf '%s\n' "$expected_call" >> "$EXPECTED"
  done
  if ! cmp -s "$EXPECTED" "$LOG"; then
    echo "FAIL $name: Lefthook call sequence mismatch" >&2
    echo 'expected:' >&2
    cat "$EXPECTED" >&2
    echo 'actual:' >&2
    cat "$LOG" >&2
    exit 1
  fi
  echo "PASS $name"
}

run_case() {
  name=$1
  setup=$2
  shift 2
  reset_fixture
  "$setup"
  if ! (cd "$FIXTURE" && "$LEFTHOOK_BIN" run pre-commit >"$OUTPUT" 2>&1); then
    cat "$OUTPUT" >&2
    echo "FAIL $name: Lefthook run failed" >&2
    exit 1
  fi
  assert_calls "$name" "$@"
}

test_unrelated() {
  stage_file notes.txt 'unrelated'
}

test_agent_docs() {
  stage_file AGENTS.md 'updated AGENTS fixture'
}

test_root_moonbit() {
  stage_file root.mbt 'root MoonBit source'
}

test_nested_moonbit() {
  stage_file modules/canopy/core/nested.mbt 'nested MoonBit source'
}

test_package_manifest() {
  stage_file moon.pkg 'package manifest'
}

test_package_manifest_json() {
  stage_file moon.pkg.json '{}'
}

test_module_manifest() {
  stage_file moon.mod 'module manifest'
}

test_module_manifest_json() {
  stage_file moon.mod.json '{}'
}

test_workspace_manifest() {
  stage_file moon.work 'workspace manifest'
}

test_workspace_manifest_json() {
  stage_file moon.work.json '{}'
}

test_moonbit_documentation() {
  stage_file guide.mbt.md 'MoonBit documentation'
}

test_generated_interface() {
  stage_file interface.mbti 'generated interface'
}

test_modules_zone() {
  stage_file modules/fixture/config.txt 'module change'
}

test_apps_zone() {
  stage_file apps/fixture/config.txt 'app change'
}

test_examples_zone() {
  stage_file examples/fixture/config.txt 'example change'
}

test_adapters_zone() {
  stage_file adapters/fixture/config.txt 'adapter change'
}

test_dependencies_zone() {
  stage_file deps/fixture/config.txt 'dependency change'
}

test_moonbit_runner_script() {
  stage_file scripts/run-moon-module.sh 'updated MoonBit runner'
}

test_vendored_check_script() {
  stage_file scripts/vendored-check-common.sh 'updated vendored check helper'
}

test_moonbit_rename_route_script() {
  cp "$REPO_ROOT/scripts/run-moonbit-rename-route.sh" "$FIXTURE/scripts/run-moonbit-rename-route.sh"
  printf '%s\n' '# staged route implementation change' >> "$FIXTURE/scripts/run-moonbit-rename-route.sh"
  git -C "$FIXTURE" add scripts/run-moonbit-rename-route.sh
}

test_tooling_config() {
  stage_file Makefile 'updated Makefile'
}

test_claude_settings() {
  stage_file .claude/settings.json '{}'
}

test_justfile() {
  stage_file justfile 'updated justfile'
}

test_moonbit_and_tooling() {
  stage_file modules/canopy/core/nested.mbt 'nested MoonBit source'
  stage_file .github/workflows/ci.yml 'updated CI workflow'
}

test_deleted_moonbit() {
  git -C "$FIXTURE" rm --quiet modules/canopy/core/deleted.mbt
}

test_renamed_moonbit() {
  git -C "$FIXTURE" mv modules/canopy/core/rename-before.mbt modules/canopy/core/rename-after.mbt
}

test_renamed_moonbit_outside_route() {
  mkdir -p "$FIXTURE/docs"
  git -C "$FIXTURE" mv modules/canopy/core/rename-before.mbt docs/rename-after.txt
}

test_renamed_moonbit_with_normal_route() {
  mkdir -p "$FIXTURE/docs"
  git -C "$FIXTURE" mv modules/canopy/core/rename-before.mbt docs/rename-after.txt
  stage_file modules/canopy/core/other.mbt 'normal MoonBit change'
}

test_renamed_moonbit_with_deleted_route() {
  mkdir -p "$FIXTURE/docs"
  git -C "$FIXTURE" mv modules/canopy/core/rename-before.mbt docs/rename-after.txt
  git -C "$FIXTURE" rm --quiet modules/canopy/core/deleted.mbt
}

run_case 'unrelated text only' test_unrelated \
  hook-repository-contract
run_case 'AGENTS.md only' test_agent_docs \
  hook-repository-contract
run_case 'root MoonBit file' test_root_moonbit \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check
run_case 'nested MoonBit file' test_nested_moonbit \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check
run_case 'Moon package manifest' test_package_manifest \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check
run_case 'Moon package JSON manifest' test_package_manifest_json \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check
run_case 'Moon module manifest' test_module_manifest \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check
run_case 'Moon module JSON manifest' test_module_manifest_json \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check
run_case 'Moon workspace manifest' test_workspace_manifest \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check
run_case 'Moon workspace JSON manifest' test_workspace_manifest_json \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check
run_case 'MoonBit documentation' test_moonbit_documentation \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check
run_case 'generated interface' test_generated_interface \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check
run_case 'modules zone' test_modules_zone \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check
run_case 'apps zone' test_apps_zone \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check
run_case 'examples zone' test_examples_zone \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check
run_case 'adapters zone' test_adapters_zone \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check
run_case 'dependencies zone' test_dependencies_zone \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check
run_case 'MoonBit runner script' test_moonbit_runner_script \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check
run_case 'vendored check script' test_vendored_check_script \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check
run_case 'MoonBit rename route script' test_moonbit_rename_route_script \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check hook-tooling-contract
run_case 'tooling configuration' test_tooling_config \
  hook-repository-contract hook-tooling-contract
run_case 'Claude settings' test_claude_settings \
  hook-repository-contract hook-tooling-contract
run_case 'justfile hook tasks' test_justfile \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check hook-tooling-contract
run_case 'MoonBit and tooling' test_moonbit_and_tooling \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check hook-tooling-contract
run_case 'deleted MoonBit file' test_deleted_moonbit \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check
run_case 'renamed MoonBit file' test_renamed_moonbit \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check
run_case 'renamed MoonBit file outside route' test_renamed_moonbit_outside_route \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check
run_case 'renamed MoonBit file with normal route' test_renamed_moonbit_with_normal_route \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check
run_case 'renamed MoonBit file with deleted route' test_renamed_moonbit_with_deleted_route \
  hook-repository-contract hook-moonbit-check hook-moonbit-format-check
