#!/usr/bin/env bash

# Guard the single MoonBit registry bootstrap boundary. Registry refresh is an
# environment/bootstrap concern; build, test, benchmark, deploy, and release
# operations consume the state prepared by setup-moonbit instead of refreshing
# it themselves.
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
action="$root_dir/.github/actions/setup-moonbit/action.yml"
justfile="$root_dir/justfile"
makefile="$root_dir/Makefile"

fail() {
  echo "error: $*" >&2
  exit 1
}

[ -f "$action" ] || fail "setup action is missing"
[ -f "$justfile" ] || fail "justfile is missing"
[ -f "$makefile" ] || fail "Makefile is missing"

# Keep these checks deliberately narrow: this is a wiring guard, not a YAML or
# shell parser. The contract test exercises the same stable boundary directly.
grep -Fqx '      id: moonbit-registry-cache' "$action" ||
  fail "setup action lacks the stable registry cache id"
grep -Fqx '      uses: hustcer/setup-moonbit@9199da0ab63ea0c0bab1dc15f03d76e17ed4f75f' "$action" ||
  fail "MoonBit setup action is not pinned to the approved full SHA"
grep -Fqx '      uses: actions/cache@caa296126883cff596d87d8935842f9db880ef25' "$action" ||
  fail "registry cache action is not pinned to the approved full SHA"
grep -Fq "key: moonbit-registry-v2-\${{ runner.os }}-\${{ runner.arch }}-toolchain-0.10.4+ade96c819-core-0.10.4+ade96c819-\${{ hashFiles('moon.work', '**/moon.mod', '**/moon.mod.json') }}" "$action" ||
  fail "registry cache key does not encode schema, platform, toolchain, core, and manifests"
grep -Fq "moonbit-registry-v2-\${{ runner.os }}-\${{ runner.arch }}-toolchain-0.10.4+ade96c819-core-0.10.4+ade96c819-" "$action" ||
  fail "registry cache restore key is not scoped to schema/platform/toolchain/core"
# shellcheck disable=SC2088 # GitHub Actions cache paths intentionally use ~.
for path in \
  '~/.moon/registry/index' \
  '~/.moon/registry/cache' \
  '~/.moon/registry/symbols'; do
  grep -Fq "  $path" "$action" || fail "registry cache path is missing: $path"
done
grep -Fqx "      if: steps.moonbit-registry-cache.outputs.cache-hit != 'true'" "$action" ||
  fail "bootstrap does not require an exact cache hit"

cache_line="$(grep -nF 'id: moonbit-registry-cache' "$action" | cut -d: -f1)"
bootstrap_line="$(grep -nF 'name: Bootstrap MoonBit registry' "$action" | cut -d: -f1)"
[ -n "$cache_line" ] && [ -n "$bootstrap_line" ] && [ "$cache_line" -lt "$bootstrap_line" ] ||
  fail "registry bootstrap must follow the registry cache step"
# shellcheck disable=SC2016 # Match the literal GitHub Actions expression.
if [ "$(grep -Fc 'run: "$GITHUB_WORKSPACE/scripts/moon-update.sh"' "$action")" -ne 1 ]; then
  fail "setup action must bootstrap the registry through the retry wrapper exactly once"
fi

[ "$(grep -Ec '^registry-refresh:' "$justfile")" -eq 1 ] ||
  fail "just registry-refresh must be defined exactly once"
grep -Eq 'registry-refresh' "$makefile" ||
  fail "Makefile must forward registry-refresh to just"
if grep -Eq '^update:' "$justfile" || grep -Eq '(^|[[:space:]])update:' "$makefile"; then
  fail "ambiguous update recipe remains in justfile or Makefile"
fi
registry_refresh_recipe="$(awk '/^registry-refresh:/{inside=1; next} inside && /^[^[:space:]]/{exit} inside{print}' "$justfile")"
[ "$(printf '%s\n' "$registry_refresh_recipe" | grep -Fc 'bash "{{ moon_update }}"')" -eq 1 ] ||
  fail "just registry-refresh must call the retry wrapper exactly once"

# Scan every tracked command-bearing surface, but keep the allowlist explicit.
# This catches a newly added workflow/script without attempting to parse shell
# or YAML. Path-only cache invalidation entries do not match the command forms.
command_pathspecs=(
  '*.yml' '*.yaml' '*.sh' '*.bash' '*.zsh'
  'Makefile' 'justfile' 'Taskfile*'
  '.claude/settings.json' '.cursor/install.sh'
)
# shellcheck disable=SC2016 # Match the literal command text.
bare_refreshes="$(
  git -C "$root_dir" grep -nE \
    '(^|[[:space:];|({])moon update([[:space:];&|)}]|$)' -- \
    "${command_pathspecs[@]}" |
    grep -vE '^scripts/(check-moon-update-wrapped|test-moon-registry-bootstrap)\.sh:' |
    grep -vE '^scripts/moon-update\.sh:' ||
    true
)"
[ -z "$bare_refreshes" ] || {
  printf '%s\n' "$bare_refreshes" >&2
  fail "bare moon update remains outside scripts/moon-update.sh"
}
# shellcheck disable=SC2016 # Match literal shell variables in operation text.
wrapper_refreshes="$(
  git -C "$root_dir" grep -nE \
    '(\$GITHUB_WORKSPACE|\$SCRIPT_DIR|\$REPO_ROOT|\$root_dir)[^[:space:]]*moon-update\.sh|(^|[[:space:];|({])(\./)?scripts/moon-update\.sh' -- \
    "${command_pathspecs[@]}" |
    grep -vE '^(\.cursor/install\.sh|\.github/actions/setup-moonbit/action\.yml|justfile|scripts/(check-moon-update-wrapped|moon-update|test-moon-update-wrapper|test-moon-registry-bootstrap)\.sh):' ||
    true
)"
[ -z "$wrapper_refreshes" ] || {
  printf '%s\n' "$wrapper_refreshes" >&2
  fail "registry refresh remains outside setup-moonbit or the explicit local/test boundary"
}
# shellcheck disable=SC2016 # Match the literal recipe/key text.
other_refreshes="$(
  git -C "$root_dir" grep -nE 'update-moon-deps\.sh|just update|moon-update:' -- \
    "${command_pathspecs[@]}" |
    grep -vE '^(scripts/(check-moon-update-wrapped|moon-update|test-moon-registry-bootstrap)\.sh):' ||
    true
)"
[ -z "$other_refreshes" ] || {
  printf '%s\n' "$other_refreshes" >&2
  fail "obsolete or operation-owned registry refresh wiring remains"
}

[ ! -e "$root_dir/scripts/update-moon-deps.sh" ] ||
  fail "obsolete update-moon-deps.sh still exists"

# Do not silently omit a submodule manifest from the audit when a checkout was
# created without recursive initialization.
submodule_status="$(git -C "$root_dir" submodule status --recursive)" ||
  fail "could not inspect submodule initialization state"
while IFS= read -r submodule_line; do
  [ -n "$submodule_line" ] || continue
  case "${submodule_line:0:1}" in
    -) fail "submodule is not initialized: $submodule_line" ;;
    +) fail "submodule does not match its recorded gitlink: $submodule_line" ;;
    U) fail "submodule has a merge conflict: $submodule_line" ;;
  esac
done <<EOF
$submodule_status
EOF

# Audit every checked-out manifest, including initialized submodules. Registry
# imports need explicit versions; local path imports are intentionally exempt.
python3 "$root_dir/scripts/check-moon-registry-manifests.py"

echo "ok: MoonBit registry bootstrap wiring passes"
