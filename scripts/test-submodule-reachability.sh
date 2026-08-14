#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
checker="$root_dir/scripts/check-submodule-reachability.nu"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "error: $*" >&2
  exit 1
}

setup_fixture() {
  local name="$1"
  local fixture="$tmp_dir/$name"
  local origin="$fixture/submodule-origin.git"
  local seed="$fixture/submodule-seed"
  local parent="$fixture/parent"

  git init --quiet --bare --initial-branch=main "$origin"
  git init --quiet --initial-branch=main "$seed"
  git -C "$seed" config user.email submodule-reachability@example.invalid
  git -C "$seed" config user.name submodule-reachability-test
  printf 'baseline\n' >"$seed/state.txt"
  git -C "$seed" add state.txt
  git -C "$seed" commit --quiet -m baseline
  git -C "$seed" remote add origin "$origin"
  git -C "$seed" push --quiet --set-upstream origin main

  git init --quiet --initial-branch=main "$parent"
  git -C "$parent" config user.email submodule-reachability@example.invalid
  git -C "$parent" config user.name submodule-reachability-test
  git -c protocol.file.allow=always -C "$parent" submodule add --quiet "$origin" deps/test-submodule
  git -C "$parent/deps/test-submodule" config protocol.file.allow always
  git -C "$parent/deps/test-submodule" config user.email submodule-reachability@example.invalid
  git -C "$parent/deps/test-submodule" config user.name submodule-reachability-test
  mkdir -p "$parent/scripts"
  cp "$checker" "$parent/scripts/check-submodule-reachability.nu"
  chmod +x "$parent/scripts/check-submodule-reachability.nu"
  git -C "$parent" add .
  git -C "$parent" commit --quiet -m baseline
  printf '%s\n' "$parent"
}

run_checker() {
  local parent="$1"
  (cd "$parent" && nu ./scripts/check-submodule-reachability.nu)
}

run_checker_at() {
  local parent="$1"
  local commit="$2"
  (cd "$parent" && nu ./scripts/check-submodule-reachability.nu --commit "$commit")
}

expect_pass() {
  local name="$1"
  local parent="$2"
  if ! run_checker "$parent" >"$tmp_dir/$name.out" 2>&1; then
    cat "$tmp_dir/$name.out" >&2
    fail "$name unexpectedly failed"
  fi
}

expect_fail() {
  local name="$1"
  local parent="$2"
  local message="$3"
  if run_checker "$parent" >"$tmp_dir/$name.out" 2>&1; then
    fail "$name unexpectedly passed"
  fi
  grep -Fq "$message" "$tmp_dir/$name.out" || {
    cat "$tmp_dir/$name.out" >&2
    fail "$name diagnostic did not contain: $message"
  }
}

expect_pass_at() {
  local name="$1"
  local parent="$2"
  local commit="$3"
  if ! run_checker_at "$parent" "$commit" >"$tmp_dir/$name.out" 2>&1; then
    cat "$tmp_dir/$name.out" >&2
    fail "$name unexpectedly failed"
  fi
}

expect_fail_at() {
  local name="$1"
  local parent="$2"
  local commit="$3"
  local message="$4"
  if run_checker_at "$parent" "$commit" >"$tmp_dir/$name.out" 2>&1; then
    fail "$name unexpectedly passed"
  fi
  grep -Fq "$message" "$tmp_dir/$name.out" || {
    cat "$tmp_dir/$name.out" >&2
    fail "$name diagnostic did not contain: $message"
  }
}

# Initialized checkout, matching gitlink, and a reachable normal origin ref.
parent="$(setup_fixture initialized-reachable)"
expect_pass initialized-reachable "$parent"

# The checkout can be present while pointing at a different commit than HEAD's gitlink.
parent="$(setup_fixture gitlink-mismatch)"
submodule="$parent/deps/test-submodule"
printf 'mismatch\n' >"$submodule/state.txt"
git -C "$submodule" add state.txt
git -C "$submodule" commit --quiet -m mismatch
expect_fail gitlink-mismatch "$parent" "does not match its recorded gitlink"

# Removing the checkout leaves the gitlink uninitialized.
parent="$(setup_fixture uninitialized)"
git -C "$parent" submodule deinit --quiet --force deps/test-submodule
expect_fail uninitialized "$parent" "is not initialized"

# Unmerged gitlink index entries are rejected before any fetch.
parent="$(setup_fixture conflict)"
submodule="$parent/deps/test-submodule"
recorded_sha="$(git -C "$parent" rev-parse HEAD:deps/test-submodule)"
printf 'conflict\n' >"$submodule/state.txt"
git -C "$submodule" add state.txt
git -C "$submodule" commit --quiet -m conflict
conflict_sha="$(git -C "$submodule" rev-parse HEAD)"
git -C "$parent" update-index --force-remove deps/test-submodule
git -C "$parent" update-index --index-info <<EOF
160000 $recorded_sha 1	deps/test-submodule
160000 $recorded_sha 2	deps/test-submodule
160000 $conflict_sha 3	deps/test-submodule
EOF
expect_fail conflict "$parent" "merge conflict"

# A configured origin that cannot be fetched is a blocking failure.
parent="$(setup_fixture origin-fetch-failure)"
git -C "$parent/deps/test-submodule" remote set-url origin "$parent/missing-origin.git"
expect_fail origin-fetch-failure "$parent" "could not fetch submodule origin"

# A local submodule commit absent from every normal origin ref is rejected.
parent="$(setup_fixture unreachable-local-commit)"
submodule="$parent/deps/test-submodule"
printf 'unreachable\n' >"$submodule/state.txt"
git -C "$submodule" add state.txt
git -C "$submodule" commit --quiet -m unreachable
git -C "$parent" add deps/test-submodule
git -C "$parent" commit --quiet -m "record unreachable submodule"
expect_fail unreachable-local-commit "$parent" "submodule commit is not fetchable from origin"

# An exact-SHA fetch is allowed when the object is reachable only through a non-normal ref.
parent="$(setup_fixture exact-sha-origin)"
submodule="$parent/deps/test-submodule"
printf 'exact sha\n' >"$submodule/state.txt"
git -C "$submodule" add state.txt
git -C "$submodule" commit --quiet -m "exact sha"
git -C "$parent" add deps/test-submodule
git -C "$parent" commit --quiet -m "record exact sha submodule"
git -C "$submodule" push --quiet origin "HEAD:refs/pull/1/head"
expect_pass exact-sha-origin "$parent"

# Keep the final assertion explicit: a normal origin ref is accepted without the SHA fallback.
parent="$(setup_fixture normal-origin-ref)"
submodule="$parent/deps/test-submodule"
printf 'normal ref\n' >"$submodule/state.txt"
git -C "$submodule" add state.txt
git -C "$submodule" commit --quiet -m "normal ref"
git -C "$submodule" push --quiet origin HEAD:main
git -C "$parent" add deps/test-submodule
git -C "$parent" commit --quiet -m "record normal ref submodule"
expect_pass normal-origin-ref "$parent"

# A pushed ref need not be the currently checked-out superproject HEAD. The
# commit mode validates gitlinks from that pushed tree without mutating the
# checkout, while retaining the exact-SHA origin contract.
parent="$(setup_fixture non-head-pushed-commit)"
submodule="$parent/deps/test-submodule"
printf 'non-head\n' >>"$submodule/state.txt"
git -C "$submodule" add state.txt
git -C "$submodule" commit --quiet -m "non-head submodule"
submodule_sha="$(git -C "$submodule" rev-parse HEAD)"
git -C "$parent" add deps/test-submodule
git -C "$parent" commit --quiet -m "record non-head submodule"
pushed_commit="$(git -C "$parent" rev-parse HEAD)"
git -C "$parent" switch --quiet --detach HEAD^
git -C "$parent" submodule update --quiet
expect_fail_at non-head-unreachable "$parent" "$pushed_commit" "submodule commit is not fetchable from origin"
git -C "$submodule" push --quiet origin "$submodule_sha:refs/pull/2/head"
expect_pass_at non-head-exact-sha "$parent" "$pushed_commit"

echo "ok: submodule reachability contract cases pass"
