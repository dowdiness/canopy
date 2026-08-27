#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
validator="$root_dir/scripts/local-validation.nu"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "error: $*" >&2
  exit 1
}

[ -f "$validator" ] || fail "missing local validation entry point: $validator"

fixture="$tmp_dir/repo"
fake_bin="$tmp_dir/bin"
log="$tmp_dir/calls.log"
mkdir -p "$fixture/pkg" "$fixture/other" "$fixture/nested/module/pkg" "$fixture/scripts" "$fake_bin"
cp "$validator" "$fixture/scripts/local-validation.nu"

printf 'name = "fixture"\n' >"$fixture/moon.mod"
printf 'package "fixture"\n' >"$fixture/moon.pkg"
printf 'pub fn root() -> Int { 0 }\n' >"$fixture/root.mbt"
printf 'package "fixture/pkg"\n' >"$fixture/pkg/moon.pkg"
printf 'pub fn answer() -> Int { 42 }\n' >"$fixture/pkg/main.mbt"
printf 'pub fn answer() -> Int\n' >"$fixture/pkg/pkg.generated.mbti"
printf 'package "fixture/other"\n' >"$fixture/other/moon.pkg"
printf 'pub fn other() -> Int { 7 }\n' >"$fixture/other/main.mbt"
printf 'name = "nested"\n' >"$fixture/nested/module/moon.mod"
printf 'package "fixture/nested"\n' >"$fixture/nested/module/pkg/moon.pkg"
printf 'pub fn nested() -> Int { 1 }\n' >"$fixture/nested/module/pkg/main.mbt"
printf '_build/\n' >"$fixture/.gitignore"

cat >"$fake_bin/moon" <<'FAKE_MOON'
#!/usr/bin/env bash
set -euo pipefail
printf 'moon' >>"$LOCAL_VALIDATION_TEST_LOG"
printf ' %s' "$@" >>"$LOCAL_VALIDATION_TEST_LOG"
printf '\n' >>"$LOCAL_VALIDATION_TEST_LOG"
FAKE_MOON
chmod +x "$fake_bin/moon"

git -C "$fixture" init --quiet --initial-branch=main
git -C "$fixture" config user.email local-validation@example.invalid
git -C "$fixture" config user.name local-validation-test
git -C "$fixture" add .
git -C "$fixture" commit --quiet -m baseline

printf 'pub fn answer() -> Int { 43 }\n' >"$fixture/pkg/main.mbt"
git -C "$fixture" add pkg/main.mbt

(
  cd "$fixture"
  PATH="$fake_bin:$PATH" LOCAL_VALIDATION_TEST_LOG="$log" \
    nu scripts/local-validation.nu prepare-commit
)

expected="$tmp_dir/expected.log"
cat >"$expected" <<'EXPECTED'
moon fmt pkg/main.mbt
moon info pkg
EXPECTED

diff -u "$expected" "$log" || fail "prepare-commit did not target the staged source and owning package"

git -C "$fixture" reset --hard --quiet HEAD
: >"$log"
printf 'package "fixture/pkg"\nwarn-list = "-20"\n' >"$fixture/pkg/moon.pkg"
git -C "$fixture" add pkg/moon.pkg
(
  cd "$fixture"
  PATH="$fake_bin:$PATH" LOCAL_VALIDATION_TEST_LOG="$log" \
    nu scripts/local-validation.nu prepare-commit
)

printf 'moon info pkg\n' >"$expected"
diff -u "$expected" "$log" || fail "prepare-commit did not regenerate the changed package manifest"

git -C "$fixture" reset --hard --quiet HEAD
: >"$log"
printf 'pub fn answer() -> Int64\n' >"$fixture/pkg/pkg.generated.mbti"
git -C "$fixture" add pkg/pkg.generated.mbti
(
  cd "$fixture"
  PATH="$fake_bin:$PATH" LOCAL_VALIDATION_TEST_LOG="$log" \
    nu scripts/local-validation.nu prepare-commit
)
printf 'moon info pkg\n' >"$expected"
diff -u "$expected" "$log" || fail "generated interface change did not regenerate its owning package"

git -C "$fixture" reset --hard --quiet HEAD
: >"$log"
printf 'name = "fixture"\nsource = "changed"\n' >"$fixture/moon.mod"
git -C "$fixture" add moon.mod
(
  cd "$fixture"
  PATH="$fake_bin:$PATH" LOCAL_VALIDATION_TEST_LOG="$log" \
    nu scripts/local-validation.nu prepare-commit
)
printf 'moon info . other pkg\n' >"$expected"
diff -u "$expected" "$log" || fail "module manifest did not regenerate its own packages only"

git -C "$fixture" reset --hard --quiet HEAD
: >"$log"
printf 'members = ["."]\n' >"$fixture/moon.work"
git -C "$fixture" add moon.work
(
  cd "$fixture"
  PATH="$fake_bin:$PATH" LOCAL_VALIDATION_TEST_LOG="$log" \
    nu scripts/local-validation.nu prepare-commit >"$tmp_dir/workspace-prepare.out" 2>&1
)
[ ! -s "$log" ] || fail "workspace manifest unexpectedly triggered workspace-wide preparation"
grep -q 'deferred to GitHub CI' "$tmp_dir/workspace-prepare.out" ||
  fail "workspace manifest preparation did not report its global scope"

git -C "$fixture" reset --hard --quiet HEAD
: >"$log"
git -C "$fixture" rm --quiet nested/module/moon.mod
(
  cd "$fixture"
  PATH="$fake_bin:$PATH" LOCAL_VALIDATION_TEST_LOG="$log" \
    nu scripts/local-validation.nu prepare-commit >"$tmp_dir/removed-module.out" 2>&1
)
[ ! -s "$log" ] || fail "removed module manifest unexpectedly became a Moon target"
grep -q 'removed MoonBit module validation is deferred to GitHub CI' "$tmp_dir/removed-module.out" ||
  fail "removed module manifest did not report its unresolvable scope"

git -C "$fixture" reset --hard --quiet HEAD
: >"$log"
printf 'test { inspect(42, content="42") }\n' >"$fixture/pkg/answer_test.mbt"
git -C "$fixture" add pkg/answer_test.mbt
(
  cd "$fixture"
  PATH="$fake_bin:$PATH" LOCAL_VALIDATION_TEST_LOG="$log" \
    nu scripts/local-validation.nu prepare-commit
)
printf 'moon fmt pkg/answer_test.mbt\n' >"$expected"
diff -u "$expected" "$log" || fail "test-only preparation unexpectedly regenerated a public interface"

git -C "$fixture" reset --hard --quiet HEAD
: >"$log"
git -C "$fixture" rm --quiet pkg/main.mbt
(
  cd "$fixture"
  PATH="$fake_bin:$PATH" LOCAL_VALIDATION_TEST_LOG="$log" \
    nu scripts/local-validation.nu prepare-commit
)
printf 'moon info pkg\n' >"$expected"
diff -u "$expected" "$log" || fail "deleted source did not resolve its former package"

git -C "$fixture" reset --hard --quiet HEAD
: >"$log"
mkdir -p "$fixture/docs"
git -C "$fixture" mv pkg/main.mbt docs/main.txt
(
  cd "$fixture"
  PATH="$fake_bin:$PATH" LOCAL_VALIDATION_TEST_LOG="$log" \
    nu scripts/local-validation.nu prepare-commit
)
printf 'moon info pkg\n' >"$expected"
diff -u "$expected" "$log" || fail "rename pre-image did not resolve its former package"

git -C "$fixture" reset --hard --quiet HEAD
: >"$log"
mkdir -p "$fixture/second/module/pkg" "$fixture/pkg space"
printf 'name = "second"\n' >"$fixture/second/module/moon.mod"
printf 'package "fixture/second"\n' >"$fixture/second/module/pkg/moon.pkg"
printf 'pub fn second() -> Int { 1 }\n' >"$fixture/second/module/pkg/main.mbt"
printf 'package "fixture/spaced"\n' >"$fixture/pkg space/moon.pkg"
tabbed_path=$'pkg space/name\t雪.mbt'
printf 'pub fn spaced() -> Int { 2 }\n' >"$fixture/$tabbed_path"
git -C "$fixture" add second/module "$tabbed_path" 'pkg space/moon.pkg'
(
  cd "$fixture"
  PATH="$fake_bin:$PATH" LOCAL_VALIDATION_TEST_LOG="$log" \
    nu scripts/local-validation.nu prepare-commit
)
printf 'moon fmt pkg space/name\t雪.mbt second/module/pkg/main.mbt\nmoon info pkg space second/module/pkg\n' >"$expected"
diff -u "$expected" "$log" || fail "NUL-safe resolver lost nested, spaced, tabbed, or Unicode paths"

git -C "$fixture" reset --hard --quiet HEAD
: >"$log"
cat >"$fixture/scripts/check-strict.sh" <<'FAKE_STRICT'
#!/usr/bin/env bash
set -euo pipefail
printf 'check-strict.sh %s\n' "$*" >>"$LOCAL_VALIDATION_TEST_LOG"
if [ "${LOCAL_VALIDATION_FAIL_STRICT:-0}" = 1 ]; then
  exit 1
fi
FAKE_STRICT
chmod +x "$fixture/scripts/check-strict.sh"
git -C "$fixture" add scripts/check-strict.sh
git -C "$fixture" commit --quiet -m "add strict checker"
git -C "$fixture" tag base
printf 'pub fn answer() -> Int { 44 }\n' >"$fixture/pkg/main.mbt"
printf 'name = "fixture"\nsource = "changed"\n' >"$fixture/moon.mod"
printf 'members = ["."]\n' >"$fixture/moon.work"
git -C "$fixture" add pkg/main.mbt
git -C "$fixture" add moon.mod
git -C "$fixture" add moon.work
git -C "$fixture" commit --quiet -m "change package"

if (
  cd "$fixture"
  PATH="$fake_bin:$PATH" LOCAL_VALIDATION_TEST_LOG="$log" LOCAL_VALIDATION_FAIL_STRICT=1 \
    nu scripts/local-validation.nu validate-push --base base >"$tmp_dir/failed-push.out" 2>&1
); then
  fail "failed package validation unexpectedly succeeded"
fi
: >"$log"

(
  cd "$fixture"
  PATH="$fake_bin:$PATH" LOCAL_VALIDATION_TEST_LOG="$log" \
    nu scripts/local-validation.nu validate-push --base base >"$tmp_dir/global-push.out" 2>&1
)
cat >"$expected" <<'EXPECTED_PUSH'
check-strict.sh .
moon test --release .
check-strict.sh other
moon test --release other
check-strict.sh pkg
moon test --release pkg
EXPECTED_PUSH
diff -u "$expected" "$log" || fail "pre-push validation did not check and test the changed module packages"
grep -q 'workspace validation is deferred to GitHub CI: moon.work' "$tmp_dir/global-push.out" ||
  fail "workspace manifest validation did not report its global scope"

: >"$log"
git -C "$fixture" tag nested-base
printf 'pub fn nested() -> Int { 2 }\n' >"$fixture/nested/module/pkg/main.mbt"
printf 'pub fn answer() -> Int { 45 }\n' >"$fixture/pkg/main.mbt"
git -C "$fixture" add nested/module/pkg/main.mbt pkg/main.mbt
git -C "$fixture" commit --quiet -m "change nested and root module packages"
(
  cd "$fixture"
  PATH="$fake_bin:$PATH" LOCAL_VALIDATION_TEST_LOG="$log" \
    nu scripts/local-validation.nu validate-push --base nested-base
)
cat >"$expected" <<'EXPECTED_NESTED_PUSH'
check-strict.sh nested/module/pkg
moon test --release pkg
check-strict.sh pkg
moon test --release pkg
EXPECTED_NESTED_PUSH
diff -u "$expected" "$log" || fail "pre-push validation leaked the nested module directory into another package"

echo "ok: local validation prepares and validates affected MoonBit targets"
