#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fake_bin="$tmp_dir/bin"
mkdir -p "$fake_bin"
host_path="$PATH"

cat >"$fake_bin/lefthook" <<'FAKE_LEFTHOOK'
#!/usr/bin/env bash
set -euo pipefail

command="${1:-}"
printf '%s\n' "$command" >>"${FAKE_LEFTHOOK_LOG:?}"
case "$command" in
  validate)
    status="${FAKE_LEFTHOOK_VALIDATE_STATUS:-0}"
    if [ "$status" -ne 0 ]; then
      echo "fake lefthook validate failed" >&2
      exit "$status"
    fi
    echo "fake lefthook validate succeeded"
    ;;
  install)
    status="${FAKE_LEFTHOOK_INSTALL_STATUS:-0}"
    if [ "$status" -ne 0 ]; then
      echo "fake lefthook install failed" >&2
      exit "$status"
    fi
    echo "fake lefthook install succeeded"
    ;;
  *)
    echo "fake lefthook: unexpected command '$command'" >&2
    exit 2
    ;;
esac
FAKE_LEFTHOOK
chmod +x "$fake_bin/lefthook"

fail() {
  echo "error: $*" >&2
  exit 1
}

assert_eq() {
  actual="$1"
  expected="$2"
  label="$3"
  if [ "$actual" != "$expected" ]; then
    fail "$label: expected '$expected', got '$actual'"
  fi
}

assert_contains() {
  file="$1"
  needle="$2"
  label="$3"
  if ! grep -Fq -- "$needle" "$file"; then
    echo "--- $file ---" >&2
    cat "$file" >&2
    fail "$label: missing '$needle'"
  fi
}

new_case() {
  case_name="$1"
  case_root="$tmp_dir/$case_name"
  case_repo="$case_root/repo"
  case_home="$case_root/home"
  case_log="$case_root/lefthook.log"
  case_output="$case_root/output.log"
  mkdir -p "$case_repo" "$case_home/.config"
  : >"$case_log"
  git_isolated -C "$case_repo" init --quiet
}

git_isolated() {
  env -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS \
    HOME="$case_home" \
    XDG_CONFIG_HOME="$case_home/.config" \
    GIT_CONFIG_GLOBAL="$case_home/.gitconfig" \
    GIT_CONFIG_SYSTEM=/dev/null \
    GIT_CONFIG_NOSYSTEM=1 \
    LC_ALL=C \
    git "$@"
}

run_installer() {
  validate_status="$1"
  install_status="$2"
  if (
    cd "$case_repo"
    unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS
    HOME="$case_home" \
      XDG_CONFIG_HOME="$case_home/.config" \
      GIT_CONFIG_GLOBAL="$case_home/.gitconfig" \
      GIT_CONFIG_SYSTEM=/dev/null \
      GIT_CONFIG_NOSYSTEM=1 \
      LC_ALL=C \
      PATH="$fake_bin:$host_path" \
      FAKE_LEFTHOOK_LOG="$case_log" \
      FAKE_LEFTHOOK_VALIDATE_STATUS="$validate_status" \
      FAKE_LEFTHOOK_INSTALL_STATUS="$install_status" \
      nu "$root_dir/scripts/install-hooks.nu"
  ) >"$case_output" 2>&1; then
    return 0
  else
    return $?
  fi
}

assert_no_local_hooks() {
  actual=""
  actual="$(git_isolated -C "$case_repo" config --local --get-all core.hooksPath 2>/dev/null)" || actual=""
  assert_eq "$actual" "" "local core.hooksPath should be absent"
}

assert_local_hooks() {
  expected="$1"
  actual=""
  actual="$(git_isolated -C "$case_repo" config --local --get-all core.hooksPath 2>/dev/null)" || actual=""
  assert_eq "$actual" "$expected" "local core.hooksPath"
}

assert_effective_hooks() {
  expected="$1"
  actual="$(git_isolated -C "$case_repo" config --includes --get-all core.hooksPath)"
  assert_eq "$actual" "$expected" "effective core.hooksPath"
}

assert_calls() {
  expected="$1"
  actual="$(cat "$case_log")"
  assert_eq "$actual" "$expected" "Lefthook calls"
}

# No configured hook path is a normal install.
new_case no-hooks
if run_installer 0 0; then status=0; else status=$?; fi
assert_eq "$status" "0" "no-hooks exit status"
assert_calls $'validate\ninstall'
assert_no_local_hooks
assert_contains "$case_output" "fake lefthook install succeeded" "no-hooks install output"

# A direct local legacy value is removed only after validation succeeds.
new_case direct-legacy

git_isolated -C "$case_repo" config --local core.hooksPath .githooks
if run_installer 0 0; then status=0; else status=$?; fi
assert_eq "$status" "0" "direct legacy exit status"
assert_calls $'validate\ninstall'
assert_no_local_hooks
assert_contains "$case_output" "Removed legacy local core.hooksPath=.githooks" "direct legacy removal diagnostic"

# Validation failure leaves a direct legacy value untouched.
new_case validate-failure
git_isolated -C "$case_repo" config --local core.hooksPath .githooks
if run_installer 17 0; then status=0; else status=$?; fi
assert_eq "$status" "17" "validation failure exit status"
assert_calls "validate"
assert_local_hooks ".githooks"
assert_contains "$case_output" "Lefthook validation failed" "validation failure diagnostic"
assert_contains "$case_output" "fake lefthook validate failed" "validation failure output"

# An unrelated direct local value is preserved and never reaches Lefthook.
new_case unknown-local
unknown_path="$case_repo/custom-hooks"
git_isolated -C "$case_repo" config --local core.hooksPath "$unknown_path"
if run_installer 0 0; then status=0; else status=$?; fi
assert_eq "$status" "1" "unknown local exit status"
assert_calls ""
assert_local_hooks "$unknown_path"
assert_contains "$case_output" "refusing to replace effective core.hooksPath configuration" "unknown local refusal diagnostic"
assert_contains "$case_output" "value=$unknown_path" "unknown local path diagnostic"

# A global value is part of the effective configuration and is preserved.
new_case global

global_path="$case_repo/global-hooks"
git_isolated -C "$case_repo" config --global core.hooksPath "$global_path"
if run_installer 0 0; then status=0; else status=$?; fi
assert_eq "$status" "1" "global path exit status"
assert_calls ""
assert_effective_hooks "$global_path"
assert_contains "$case_output" "scope=global" "global scope diagnostic"
assert_contains "$case_output" "value=$global_path" "global path diagnostic"

# An included .githooks value is observed but is never treated as removable local state.
new_case included-legacy
included_file="$case_root/included.gitconfig"
printf '[core]\n\thooksPath = .githooks\n' >"$included_file"
git_isolated -C "$case_repo" config --local include.path "$included_file"
if run_installer 0 0; then status=0; else status=$?; fi
assert_eq "$status" "1" "included legacy exit status"
assert_calls ""
assert_effective_hooks ".githooks"
assert_contains "$case_output" "origin=file:$included_file" "included origin diagnostic"
assert_contains "$case_output" "Only direct local .githooks values" "included refusal diagnostic"
grep -Fq $'hooksPath = .githooks' "$included_file" || fail "included .githooks value was modified"

# A worktree-level path is never treated as a removable local value.
new_case worktree-path

git_isolated -C "$case_repo" config extensions.worktreeConfig true
git_isolated -C "$case_repo" config --worktree core.hooksPath .githooks
if run_installer 0 0; then status=0; else status=$?; fi
assert_eq "$status" "1" "worktree path exit status"
assert_calls ""
assert_contains "$case_output" "scope=worktree" "worktree scope diagnostic"
assert_effective_hooks ".githooks"

# A system-level path is also refused without modifying repository config.
new_case system-path
system_file="$case_root/system.gitconfig"
printf '[core]\n\thooksPath = system-hooks\n' >"$system_file"
if (
  cd "$case_repo"
  HOME="$case_home" \
    XDG_CONFIG_HOME="$case_home/.config" \
    GIT_CONFIG_GLOBAL="$case_home/.gitconfig" \
    GIT_CONFIG_SYSTEM="$system_file" \
    GIT_CONFIG_NOSYSTEM=0 \
    LC_ALL=C \
    PATH="$fake_bin:$host_path" \
    FAKE_LEFTHOOK_LOG="$case_log" \
    nu "$root_dir/scripts/install-hooks.nu"
) >"$case_output" 2>&1; then
  status=0
else
  status=$?
fi
assert_eq "$status" "1" "system path exit status"
assert_calls ""
assert_contains "$case_output" "scope=system" "system scope diagnostic"
assert_contains "$case_output" "value=system-hooks" "system path diagnostic"

# Every removed direct value is restored when Lefthook installation fails.
new_case install-failure-restore
git_isolated -C "$case_repo" config --local --add core.hooksPath .githooks
git_isolated -C "$case_repo" config --local --add core.hooksPath .githooks
if run_installer 0 23; then status=0; else status=$?; fi
assert_eq "$status" "23" "install failure exit status"
assert_calls $'validate\ninstall'
assert_local_hooks $'.githooks\n.githooks'
assert_contains "$case_output" "Lefthook installation failed; restored" "restore diagnostic"
assert_contains "$case_output" "fake lefthook install failed" "install failure diagnostic"

printf '%s\n' "ok: install-hooks config safety, include handling, and rollback are covered"
