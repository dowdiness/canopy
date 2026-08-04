#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validator="$root_dir/scripts/validate-pr-ready.sh"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "error: $*" >&2
  exit 1
}

assert_files_equal() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  if ! diff -u "$expected" "$actual"; then
    fail "$label"
  fi
}

if [ ! -x "$validator" ]; then
  fail "expected executable validator at $validator"
fi

list_output="$tmp_dir/list-output"
"$validator" \
  --list \
  --base origin/main \
  --target modules/canopy/lang/markdown/proj \
  --target modules/canopy/lang/markdown/edits >"$list_output"

expected_list="$tmp_dir/expected-list"
cat >"$expected_list" <<'EXPECTED_LIST'
01 preflight.clean
02 preflight.base origin/main
03 preflight.submodules
04 dependencies.check-deps
05 dependencies.shared-substrate
06 dependencies.egw-resolver-identity
07 dependencies.moon-update-wrapper
08 dependencies.agent-doc-links
09 dependencies.documentation-lifecycle
10 dependencies.export-manifest
11 dependencies.update-wrapper-test
12 dependencies.sync
13 format.canopy
14 interfaces.canopy
15 target.check modules/canopy/lang/markdown/proj
16 target.test modules/canopy/lang/markdown/proj
17 target.check modules/canopy/lang/markdown/edits
18 target.test modules/canopy/lang/markdown/edits
19 suite.check
20 suite.manifest-compat
21 suite.test
22 suite.build
23 build.js
24 diff.whitespace origin/main...HEAD
25 evidence.record
EXPECTED_LIST
assert_files_equal "$expected_list" "$list_output" "--list order changed"

missing_target_output="$tmp_dir/missing-target-output"
if "$validator" --list --base origin/main >"$missing_target_output" 2>&1; then
  fail "--list unexpectedly accepted a missing target policy"
fi
grep -q -- "--target or --no-target" "$missing_target_output" ||
  fail "missing-target diagnostic was not actionable"

invalid_target_output="$tmp_dir/invalid-target-output"
if "$validator" --list --target docs >"$invalid_target_output" 2>&1; then
  fail "--list unexpectedly accepted a non-package target"
fi
grep -q "not a MoonBit package directory" "$invalid_target_output" ||
  fail "non-package target diagnostic was not actionable"

duplicate_target_output="$tmp_dir/duplicate-target-output"
if "$validator" --list --target modules/canopy/lang/markdown/proj --target modules/canopy/lang/markdown/proj \
  >"$duplicate_target_output" 2>&1; then
  fail "--list unexpectedly accepted a duplicate target"
fi
grep -q "duplicate target" "$duplicate_target_output" ||
  fail "duplicate-target diagnostic was not actionable"

fixture="$tmp_dir/repo"
fake_bin="$tmp_dir/bin"
execution_log="$tmp_dir/execution.log"
mkdir -p "$fixture/scripts" "$fixture/pkg" "$fake_bin"
cp "$validator" "$fixture/scripts/validate-pr-ready.sh"

cat >"$fake_bin/moon" <<'FAKE_MOON'
#!/usr/bin/env bash
set -euo pipefail

printf 'moon' >>"$PR_READY_TEST_LOG"
if [ "$#" -gt 0 ]; then
  printf ' %s' "$@" >>"$PR_READY_TEST_LOG"
fi
printf '\n' >>"$PR_READY_TEST_LOG"

if [ "${PR_READY_MUTATE_MOON_COMMAND:-}" = "${1:-}" ]; then
  printf '// changed by fake moon\n' >>"${PR_READY_MUTATE_FILE:?}"
fi
FAKE_MOON

cat >"$fake_bin/node" <<'FAKE_NODE'
#!/usr/bin/env bash
set -euo pipefail

printf 'node' >>"$PR_READY_TEST_LOG"
if [ "$#" -gt 0 ]; then
  printf ' %s' "$@" >>"$PR_READY_TEST_LOG"
fi
printf '\n' >>"$PR_READY_TEST_LOG"
FAKE_NODE
chmod +x "$fake_bin/moon" "$fake_bin/node"

for script_name in \
  check-deps.sh \
  check-shared-substrate.sh \
  check-egw-resolver-identity.sh \
  check-moon-update-wrapped.sh \
  check-agent-doc-links.sh \
  check-documentation-lifecycle.sh \
  test-moon-update-wrapper.sh \
  update-moon-deps.sh \
  check-strict.sh \
  check-moonbit-pkg-compat.sh \
  check-test-baseline.sh \
  build-js.sh; do
  cat >"$fixture/scripts/$script_name" <<'FAKE_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

step_name="$(basename "$0")"
printf '%s' "$step_name" >>"$PR_READY_TEST_LOG"
if [ "$#" -gt 0 ]; then
  printf ' %s' "$@" >>"$PR_READY_TEST_LOG"
fi
printf '\n' >>"$PR_READY_TEST_LOG"

if [ "${PR_READY_FAIL_STEP:-}" = "$step_name" ]; then
  exit 23
fi
FAKE_SCRIPT
  chmod +x "$fixture/scripts/$script_name"
done

printf 'pub fn answer() -> Int { 42 }\n' >"$fixture/pkg/main.mbt"
printf 'package "fixture/pkg"\n' >"$fixture/pkg/moon.pkg"
printf 'pub fn answer() -> Int\n' >"$fixture/pkg/pkg.generated.mbti"
printf '{"name":"fixture"}\n' >"$fixture/moon.pkg.json"
printf '_build/\n' >"$fixture/.gitignore"

git -C "$fixture" init --quiet --initial-branch=main
git -C "$fixture" config user.email "pr-ready-test@example.invalid"
git -C "$fixture" config user.name "PR Ready Test"

submodule_origin="$tmp_dir/submodule-origin.git"
submodule_seed="$tmp_dir/submodule-seed"
git init --quiet --bare --initial-branch=main "$submodule_origin"
git init --quiet --initial-branch=main "$submodule_seed"
git -C "$submodule_seed" config user.email "pr-ready-test@example.invalid"
git -C "$submodule_seed" config user.name "PR Ready Test"
printf 'reachable\n' >"$submodule_seed/state.txt"
git -C "$submodule_seed" add state.txt
git -C "$submodule_seed" commit --quiet -m "reachable submodule commit"
git -C "$submodule_seed" remote add origin "$submodule_origin"
git -C "$submodule_seed" push --quiet --set-upstream origin main
git -c protocol.file.allow=always -C "$fixture" submodule add --quiet \
  "$submodule_origin" vendor/test-submodule
git -C "$fixture/vendor/test-submodule" config protocol.file.allow always
git -C "$fixture/vendor/test-submodule" config \
  user.email "pr-ready-test@example.invalid"
git -C "$fixture/vendor/test-submodule" config user.name "PR Ready Test"

git -C "$fixture" add .
git -C "$fixture" commit --quiet -m "fixture base"
git -C "$fixture" tag fixture-base
git -C "$fixture" switch --quiet -c feature
git -C "$fixture" commit --quiet --allow-empty -m "fixture feature"

fake_moon_update_guard="$tmp_dir/fake-check-moon-update-wrapped.sh"
cp "$fixture/scripts/check-moon-update-wrapped.sh" "$fake_moon_update_guard"
cp "$root_dir/scripts/check-moon-update-wrapped.sh" \
  "$fixture/scripts/check-moon-update-wrapped.sh"
git -C "$fixture" add scripts/check-moon-update-wrapped.sh
git -C "$fixture" commit --quiet -m "exercise the real moon update guard"

bash32_output="$tmp_dir/bash32-output"
if ! (
  # Bash 3.2 has no mapfile builtin. Exporting a failing function with that name
  # gives newer Bash versions the same observable command boundary. The
  # validator's child Bash process invokes this exported function.
  # shellcheck disable=SC2329
  mapfile() { return 127; }
  export -f mapfile
  PATH="$fake_bin:$PATH" \
    PR_READY_TEST_LOG="$execution_log" \
    "$fixture/scripts/validate-pr-ready.sh" \
      --base fixture-base \
      --no-target "Bash 3.2 compatibility probe"
) >"$bash32_output" 2>&1; then
  fail "public validator did not complete without the Bash 4 mapfile builtin"
fi
grep -q "PR-ready validation passed" "$bash32_output" ||
  fail "Bash 3.2 compatibility probe did not complete the public CLI"
grep -q "validated-no-target=Bash 3.2 compatibility probe" "$bash32_output" ||
  fail "Bash 3.2 compatibility probe did not record its scope"

cp "$fake_moon_update_guard" "$fixture/scripts/check-moon-update-wrapped.sh"
git -C "$fixture" add scripts/check-moon-update-wrapped.sh
git -C "$fixture" commit --quiet -m "restore the fake moon update guard"

printf 'not pushed\n' >"$fixture/vendor/test-submodule/state.txt"
git -C "$fixture/vendor/test-submodule" add state.txt
git -C "$fixture/vendor/test-submodule" commit --quiet \
  -m "unpushed submodule commit"
git -C "$fixture" add vendor/test-submodule
git -C "$fixture" commit --quiet -m "record the unpushed submodule commit"

: >"$execution_log"
unpushed_output="$tmp_dir/unpushed-submodule-output"
if PATH="$fake_bin:$PATH" \
  PR_READY_TEST_LOG="$execution_log" \
  "$fixture/scripts/validate-pr-ready.sh" \
    --base fixture-base \
    --target pkg >"$unpushed_output" 2>&1; then
  fail "unpushed submodule commit unexpectedly passed"
fi
grep -q "submodule commit is not reachable from origin" "$unpushed_output" ||
  fail "unpushed submodule diagnostic was not actionable"
if [ -s "$execution_log" ]; then
  fail "unpushed submodule failure ran dependency commands"
fi
if "$fixture/scripts/validate-pr-ready.sh" \
  --verify-evidence >"$tmp_dir/unpushed-evidence-output" 2>&1; then
  fail "unpushed submodule failure unexpectedly preserved evidence"
fi
grep -q "evidence is missing" "$tmp_dir/unpushed-evidence-output" ||
  fail "unpushed submodule failure did not invalidate earlier evidence"

git -C "$fixture/vendor/test-submodule" push --quiet origin HEAD:main

PATH="$fake_bin:$PATH" \
  PR_READY_TEST_LOG="$execution_log" \
  "$fixture/scripts/validate-pr-ready.sh" \
    --base fixture-base \
    --target pkg >"$tmp_dir/success-output"

fixture_plan="$tmp_dir/fixture-plan"
execution_plan="$tmp_dir/execution-plan"
"$fixture/scripts/validate-pr-ready.sh" \
  --list \
  --base fixture-base \
  --target pkg >"$fixture_plan"
sed -n 's/^==> //p' "$tmp_dir/success-output" >"$execution_plan"
assert_files_equal "$fixture_plan" "$execution_plan" "listed and executed phases diverged"

expected_execution="$tmp_dir/expected-execution"
cat >"$expected_execution" <<'EXPECTED_EXECUTION'
check-deps.sh
check-shared-substrate.sh
check-egw-resolver-identity.sh
check-moon-update-wrapped.sh
check-agent-doc-links.sh
check-documentation-lifecycle.sh
node ./scripts/check-export-manifest.mjs
test-moon-update-wrapper.sh
update-moon-deps.sh
moon fmt --check pkg/main.mbt
moon info --frozen . pkg
check-strict.sh pkg
moon test --release pkg
check-strict.sh
check-moonbit-pkg-compat.sh
check-test-baseline.sh 7 moon test --release
moon build --release
build-js.sh
EXPECTED_EXECUTION
assert_files_equal "$expected_execution" "$execution_log" "validation command order changed"

validated_head="$(git -C "$fixture" rev-parse HEAD)"
grep -q "validated-head=$validated_head" "$tmp_dir/success-output" ||
  fail "success output did not identify the validated HEAD"
grep -q "validated-target=pkg" "$tmp_dir/success-output" ||
  fail "success output did not identify the validated target"

PATH="$fake_bin:$PATH" \
  PR_READY_TEST_LOG="$execution_log" \
  "$fixture/scripts/validate-pr-ready.sh" \
    --verify-evidence >"$tmp_dir/verified-output"
grep -q "validated-head=$validated_head" "$tmp_dir/verified-output" ||
  fail "evidence verification did not report the validated HEAD"
grep -q "validated-target=pkg" "$tmp_dir/verified-output" ||
  fail "evidence verification did not report the validated target"

submodule_origin_url="$(
  git -C "$fixture/vendor/test-submodule" remote get-url origin
)"
git -C "$fixture/vendor/test-submodule" remote set-url origin \
  "$tmp_dir/missing-submodule-origin.git"
: >"$execution_log"
fetch_failure_output="$tmp_dir/submodule-fetch-failure-output"
if PATH="$fake_bin:$PATH" \
  PR_READY_TEST_LOG="$execution_log" \
  "$fixture/scripts/validate-pr-ready.sh" \
    --base fixture-base \
    --target pkg >"$fetch_failure_output" 2>&1; then
  fail "submodule fetch failure unexpectedly passed"
fi
grep -q "could not fetch submodule origin" "$fetch_failure_output" ||
  fail "submodule fetch failure diagnostic was not actionable"
if [ -s "$execution_log" ]; then
  fail "submodule fetch failure ran dependency commands"
fi
if "$fixture/scripts/validate-pr-ready.sh" \
  --verify-evidence >"$tmp_dir/fetch-failure-evidence-output" 2>&1; then
  fail "submodule fetch failure unexpectedly preserved evidence"
fi
grep -q "evidence is missing" "$tmp_dir/fetch-failure-evidence-output" ||
  fail "submodule fetch failure did not invalidate earlier evidence"

git -C "$fixture/vendor/test-submodule" remote set-url origin \
  "$submodule_origin_url"
: >"$execution_log"
PATH="$fake_bin:$PATH" \
  PR_READY_TEST_LOG="$execution_log" \
  "$fixture/scripts/validate-pr-ready.sh" \
    --base fixture-base \
    --target pkg >"$tmp_dir/restored-submodule-success-output"
"$fixture/scripts/validate-pr-ready.sh" \
  --verify-evidence >"$tmp_dir/restored-submodule-evidence-output"

if "$fixture/scripts/validate-pr-ready.sh" \
  --verify-evidence \
  --target pkg >"$tmp_dir/incompatible-mode-output" 2>&1; then
  fail "--verify-evidence unexpectedly accepted target options"
fi
grep -q "does not accept" "$tmp_dir/incompatible-mode-output" ||
  fail "incompatible-mode diagnostic was not actionable"

: >"$execution_log"
if PATH="$fake_bin:$PATH" \
  PR_READY_TEST_LOG="$execution_log" \
  PR_READY_FAIL_STEP="check-shared-substrate.sh" \
  "$fixture/scripts/validate-pr-ready.sh" \
    --base fixture-base \
    --target pkg >"$tmp_dir/fail-fast-output" 2>&1; then
  fail "dependency failure unexpectedly passed"
fi
expected_fail_fast="$tmp_dir/expected-fail-fast"
cat >"$expected_fail_fast" <<'EXPECTED_FAIL_FAST'
check-deps.sh
check-shared-substrate.sh
EXPECTED_FAIL_FAST
assert_files_equal "$expected_fail_fast" "$execution_log" "dependency failure did not stop later steps"
if "$fixture/scripts/validate-pr-ready.sh" \
  --verify-evidence >"$tmp_dir/failed-run-evidence-output" 2>&1; then
  fail "a failed rerun unexpectedly preserved earlier evidence"
fi
grep -q "evidence is missing" "$tmp_dir/failed-run-evidence-output" ||
  fail "failed rerun did not invalidate earlier evidence"

: >"$execution_log"
PATH="$fake_bin:$PATH" \
  PR_READY_TEST_LOG="$execution_log" \
  "$fixture/scripts/validate-pr-ready.sh" \
    --base fixture-base \
    --target pkg >"$tmp_dir/restored-success-output"

: >"$execution_log"
if PATH="$fake_bin:$PATH" \
  PR_READY_TEST_LOG="$execution_log" \
  PR_READY_MUTATE_MOON_COMMAND="info" \
  PR_READY_MUTATE_FILE="$fixture/pkg/pkg.generated.mbti" \
  "$fixture/scripts/validate-pr-ready.sh" \
    --base fixture-base \
    --target pkg >"$tmp_dir/mutation-output" 2>&1; then
  fail "tracked interface mutation unexpectedly passed"
fi
grep -q "worktree is not clean" "$tmp_dir/mutation-output" ||
  fail "tracked mutation diagnostic was not actionable"
if grep -q "check-strict.sh" "$execution_log"; then
  fail "tracked interface mutation did not stop before targeted checks"
fi
git -C "$fixture" restore pkg/pkg.generated.mbti
if "$fixture/scripts/validate-pr-ready.sh" \
  --verify-evidence >"$tmp_dir/mutation-evidence-output" 2>&1; then
  fail "a mutating rerun unexpectedly preserved earlier evidence"
fi
grep -q "evidence is missing" "$tmp_dir/mutation-evidence-output" ||
  fail "mutating rerun did not invalidate earlier evidence"

: >"$execution_log"
PATH="$fake_bin:$PATH" \
  PR_READY_TEST_LOG="$execution_log" \
  "$fixture/scripts/validate-pr-ready.sh" \
    --base fixture-base \
    --no-target "shell-only fixture" >"$tmp_dir/no-target-success-output"
grep -q "validated-no-target=shell-only fixture" "$tmp_dir/no-target-success-output" ||
  fail "success output did not identify the no-target reason"

fixture_base_sha="$(git -C "$fixture" rev-parse fixture-base)"
git -C "$fixture" tag --force fixture-base HEAD >/dev/null
if "$fixture/scripts/validate-pr-ready.sh" \
  --verify-evidence >"$tmp_dir/base-stale-output" 2>&1; then
  fail "evidence unexpectedly survived base-ref movement"
fi
grep -q "fixture-base changed" "$tmp_dir/base-stale-output" ||
  fail "base-ref movement diagnostic was not actionable"
git -C "$fixture" tag --force fixture-base "$fixture_base_sha" >/dev/null

"$fixture/scripts/validate-pr-ready.sh" \
  --verify-evidence >"$tmp_dir/restored-base-output"
grep -q "validated-no-target=shell-only fixture" "$tmp_dir/restored-base-output" ||
  fail "restored base did not restore matching evidence"

git -C "$fixture" commit --quiet --allow-empty -m "advance HEAD"
if PATH="$fake_bin:$PATH" \
  PR_READY_TEST_LOG="$execution_log" \
  "$fixture/scripts/validate-pr-ready.sh" \
    --verify-evidence >"$tmp_dir/stale-output" 2>&1; then
  fail "evidence unexpectedly survived a HEAD change"
fi
grep -q "stale" "$tmp_dir/stale-output" ||
  fail "stale evidence diagnostic was not actionable"

: >"$execution_log"
printf 'dirty\n' >"$fixture/untracked.txt"
if PATH="$fake_bin:$PATH" \
  PR_READY_TEST_LOG="$execution_log" \
  "$fixture/scripts/validate-pr-ready.sh" \
    --base fixture-base \
    --target pkg >"$tmp_dir/dirty-output" 2>&1; then
  fail "dirty worktree unexpectedly passed"
fi
grep -q "worktree is not clean" "$tmp_dir/dirty-output" ||
  fail "dirty-worktree diagnostic was not actionable"
if [ -s "$execution_log" ]; then
  fail "dirty-worktree failure ran validation commands"
fi
rm "$fixture/untracked.txt"

git -C "$fixture" switch --quiet main
git -C "$fixture" commit --quiet --allow-empty -m "advance base"
git -C "$fixture" switch --quiet feature
: >"$execution_log"
if PATH="$fake_bin:$PATH" \
  PR_READY_TEST_LOG="$execution_log" \
  "$fixture/scripts/validate-pr-ready.sh" \
    --base main \
    --target pkg >"$tmp_dir/behind-output" 2>&1; then
  fail "branch behind the configured base unexpectedly passed"
fi
grep -q "does not contain base" "$tmp_dir/behind-output" ||
  fail "behind-base diagnostic was not actionable"
if [ -s "$execution_log" ]; then
  fail "behind-base failure ran validation commands"
fi

echo "ok: PR-ready validation order and HEAD evidence are enforced"
