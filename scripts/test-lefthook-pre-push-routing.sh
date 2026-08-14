#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lefthook_bin="${LEFTHOOK_BIN:-}"
if [ -z "$lefthook_bin" ]; then
  lefthook_bin="$(command -v lefthook || true)"
fi
[ -x "$lefthook_bin" ] || {
  echo "error: Lefthook 2.1.10 binary not found; set LEFTHOOK_BIN" >&2
  exit 1
}

fixture="$(mktemp -d "${TMPDIR:-/tmp}/canopy-lefthook-pre-push.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT HUP INT TERM

parent="$fixture/parent"
parent_origin="$fixture/parent-origin.git"
submodule_origin="$fixture/submodule-origin.git"
submodule_seed="$fixture/submodule-seed"
log="$fixture/just.log"
legacy_args="$fixture/legacy-args"
legacy_stdin="$fixture/legacy-stdin"

mkdir -p "$fixture/bin"
cp "$root_dir/lefthook.yml" "$parent.lefthook.yml"
cp "$root_dir/.githooks/pre-push" "$fixture/pre-push"
cp "$root_dir/scripts/check-submodule-reachability.nu" "$fixture/check-submodule-reachability.nu"
cp "$root_dir/scripts/run-submodule-reachability.sh" "$fixture/run-submodule-reachability.sh"
chmod +x "$fixture/pre-push" "$fixture/check-submodule-reachability.nu" "$fixture/run-submodule-reachability.sh"

git init --quiet --bare --initial-branch=main "$parent_origin"
git init --quiet --bare --initial-branch=main "$submodule_origin"
git init --quiet --initial-branch=main "$submodule_seed"
git -C "$submodule_seed" config user.email lefthook-pre-push@example.invalid
git -C "$submodule_seed" config user.name lefthook-pre-push-test
printf 'baseline\n' >"$submodule_seed/state.txt"
git -C "$submodule_seed" add state.txt
git -C "$submodule_seed" commit --quiet -m baseline
git -C "$submodule_seed" remote add origin "$submodule_origin"
git -C "$submodule_seed" push --quiet --set-upstream origin main

git init --quiet --initial-branch=main "$parent"
git -C "$parent" config user.email lefthook-pre-push@example.invalid
git -C "$parent" config user.name lefthook-pre-push-test
git -C "$parent" remote add origin "$parent_origin"
git -c protocol.file.allow=always -C "$parent" submodule add --quiet "$submodule_origin" deps/test-submodule
git -C "$parent/deps/test-submodule" config protocol.file.allow always
git -C "$parent/deps/test-submodule" config user.email lefthook-pre-push@example.invalid
git -C "$parent/deps/test-submodule" config user.name lefthook-pre-push-test
mkdir -p "$parent/scripts" "$parent/.githooks" "$parent/docs" "$parent/modules/fixture" "$parent/bin"
cp "$parent.lefthook.yml" "$parent/lefthook.yml"
cp "$fixture/check-submodule-reachability.nu" "$parent/scripts/check-submodule-reachability.nu"
cp "$fixture/run-submodule-reachability.sh" "$parent/scripts/run-submodule-reachability.sh"
cp "$fixture/pre-push" "$parent/.githooks/pre-push"
chmod +x "$parent/scripts/check-submodule-reachability.nu" "$parent/scripts/run-submodule-reachability.sh" "$parent/.githooks/pre-push"

cat >"$parent/justfile" <<'JUSTFILE'
set shell := ["nu", "-c"]
hook-submodule-reachability:
    @nu ./scripts/check-submodule-reachability.nu
JUSTFILE

cat >"$fixture/bin/just" <<'FAKE_JUST'
#!/bin/sh
printf '%s\n' "$*" >>"$LEFTHOOK_ROUTING_LOG"
if [ "${1:-}" = hook-submodule-reachability ]; then
  shift
  exec nu "$LEFTHOOK_ROUTING_CHECKER" --commit "${1:-}"
fi
exit 0
FAKE_JUST
chmod +x "$fixture/bin/just"

cat >"$fixture/bin/lefthook" <<'FAKE_LEFTHOOK'
#!/bin/sh
printf '%s\n' "$*" >"$LEFTHOOK_LEGACY_ARGS"
cat >"$LEFTHOOK_LEGACY_STDIN"
exec "$LEFTHOOK_REAL" "$@" <"$LEFTHOOK_LEGACY_STDIN"
FAKE_LEFTHOOK
chmod +x "$fixture/bin/lefthook"

cat >"$parent/.git/hooks/pre-push" <<HOOK
#!/bin/sh
exec "$lefthook_bin" run pre-push "\$@"
HOOK
chmod +x "$parent/.git/hooks/pre-push"

# Git's first push exercises the real Lefthook binary and the checker once.
git -C "$parent" add .
git -C "$parent" commit --no-verify --quiet -m baseline
: >"$log"
LEFTHOOK_ROUTING_LOG="$log" LEFTHOOK_ROUTING_CHECKER="$parent/scripts/check-submodule-reachability.nu" \
  PATH="$fixture/bin:$PATH" git -C "$parent" push --quiet --set-upstream origin main >"$fixture/initial.out" 2>&1 || {
  cat "$fixture/initial.out" >&2
  cat "$log" >&2
  exit 1
}
reset_log() { : >"$log"; }
assert_skipped() {
  [ ! -s "$log" ] || { echo "error: $1 unexpectedly ran the checker" >&2; cat "$log" >&2; exit 1; }
}
assert_invoked_once() {
  [ "$(wc -l <"$log" | tr -d ' ')" -eq 1 ] || { echo "error: $1 did not invoke checker exactly once" >&2; cat "$log" >&2; exit 1; }
}

printf 'docs\n' >"$parent/docs/README.md"
git -C "$parent" add docs/README.md && git -C "$parent" commit --no-verify --quiet -m docs
reset_log
LEFTHOOK_ROUTING_LOG="$log" LEFTHOOK_ROUTING_CHECKER="$parent/scripts/check-submodule-reachability.nu" PATH="$fixture/bin:$PATH" \
  git -C "$parent" push --quiet origin main
assert_skipped docs-only

printf 'fn fixture() -> Int { 1 }\n' >"$parent/modules/fixture/main.mbt"
git -C "$parent" add modules/fixture/main.mbt && git -C "$parent" commit --no-verify --quiet -m moonbit
reset_log
LEFTHOOK_ROUTING_LOG="$log" LEFTHOOK_ROUTING_CHECKER="$parent/scripts/check-submodule-reachability.nu" PATH="$fixture/bin:$PATH" \
  git -C "$parent" push --quiet origin main
assert_skipped normal-moonbit

make_unpushed_parent_commit() {
  local label="$1"
  local submodule="$parent/deps/test-submodule"
  printf '%s\n' "$label" >>"$submodule/state.txt"
  git -C "$submodule" add state.txt
  git -C "$submodule" commit --quiet -m "$label"
  git -C "$parent" add deps/test-submodule
  git -C "$parent" commit --no-verify --quiet -m "record $label"
}

make_unpushed_parent_commit unpushed
if nu "$parent/scripts/check-submodule-reachability.nu" >"$fixture/direct-check.out" 2>&1; then
  echo "error: direct checker accepted unpushed commit" >&2
  exit 1
fi
reset_log
if LEFTHOOK_ROUTING_LOG="$log" LEFTHOOK_ROUTING_CHECKER="$parent/scripts/check-submodule-reachability.nu" PATH="$fixture/bin:$PATH" \
  git -C "$parent" push --quiet origin main >"$fixture/unpushed.out" 2>&1; then
  echo "error: unpushed submodule commit unexpectedly passed" >&2
  exit 1
fi
grep -Fq 'submodule commit is not fetchable from origin' "$fixture/unpushed.out" || { cat "$fixture/unpushed.out" >&2; exit 1; }
assert_invoked_once unpushed

git -C "$parent/deps/test-submodule" push --quiet origin HEAD:main
reset_log
LEFTHOOK_ROUTING_LOG="$log" LEFTHOOK_ROUTING_CHECKER="$parent/scripts/check-submodule-reachability.nu" PATH="$fixture/bin:$PATH" \
  git -C "$parent" push --quiet origin main
assert_invoked_once pushed-submodule

printf '# routing marker\n' >>"$parent/.gitmodules"
git -C "$parent" add .gitmodules && git -C "$parent" commit --no-verify --quiet -m gitmodules
reset_log
LEFTHOOK_ROUTING_LOG="$log" LEFTHOOK_ROUTING_CHECKER="$parent/scripts/check-submodule-reachability.nu" PATH="$fixture/bin:$PATH" \
  git -C "$parent" push --quiet origin main
assert_invoked_once gitmodules

make_unpushed_parent_commit mixed-gitlink-and-normal
printf 'fn mixed() -> Int { 2 }\n' >"$parent/modules/fixture/mixed.mbt"
git -C "$parent" add modules/fixture/mixed.mbt && git -C "$parent" commit --no-verify --quiet -m mixed-normal
reset_log
if LEFTHOOK_ROUTING_LOG="$log" LEFTHOOK_ROUTING_CHECKER="$parent/scripts/check-submodule-reachability.nu" PATH="$fixture/bin:$PATH" \
  git -C "$parent" push --quiet origin main >"$fixture/mixed.out" 2>&1; then
  echo "error: mixed unpushed submodule commit unexpectedly passed" >&2
  exit 1
fi
assert_invoked_once mixed-gitlink-and-normal
git -C "$parent/deps/test-submodule" push --quiet origin HEAD:main
reset_log
LEFTHOOK_ROUTING_LOG="$log" LEFTHOOK_ROUTING_CHECKER="$parent/scripts/check-submodule-reachability.nu" PATH="$fixture/bin:$PATH" \
  git -C "$parent" push --quiet origin main
assert_invoked_once mixed-after-push

# Switch to the retained core.hooksPath shim and verify Git's hook arguments and stdin.
git -C "$parent" config core.hooksPath .githooks
make_unpushed_parent_commit legacy-shim
reset_log
if LEFTHOOK_ROUTING_LOG="$log" LEFTHOOK_ROUTING_CHECKER="$parent/scripts/check-submodule-reachability.nu" \
  LEFTHOOK_REAL="$lefthook_bin" LEFTHOOK_LEGACY_ARGS="$legacy_args" LEFTHOOK_LEGACY_STDIN="$legacy_stdin" \
  PATH="$fixture/bin:$PATH" git -C "$parent" push --quiet origin main >"$fixture/legacy.out" 2>&1; then
  echo "error: legacy shim accepted an unpushed submodule commit" >&2
  exit 1
fi
assert_invoked_once legacy-shim
grep -Fq 'run pre-push origin ' "$legacy_args" || { cat "$legacy_args" >&2; exit 1; }
grep -Fq 'refs/heads/main' "$legacy_stdin" || { cat "$legacy_stdin" >&2; exit 1; }
grep -Fq 'submodule commit is not fetchable from origin' "$fixture/legacy.out" || { cat "$fixture/legacy.out" >&2; exit 1; }

echo "ok: Lefthook pre-push routing and legacy shim pass"
