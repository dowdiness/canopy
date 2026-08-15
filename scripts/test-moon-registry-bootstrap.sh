#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
action="$root_dir/.github/actions/setup-moonbit/action.yml"
justfile="$root_dir/justfile"

fail() {
  echo "error: $*" >&2
  exit 1
}

[ -f "$action" ] || fail "setup action is missing"
[ -f "$justfile" ] || fail "justfile is missing"

# The setup action is the only CI bootstrap boundary. Keep the cache contract
# explicit so an action edit cannot silently turn exact hits into network work.
grep -Fq 'id: moonbit-registry-cache' "$action" ||
  fail "registry cache step has no stable id"
grep -Fq 'uses: hustcer/setup-moonbit@9199da0ab63ea0c0bab1dc15f03d76e17ed4f75f' "$action" ||
  fail "MoonBit setup action is not pinned to the v1.22 commit"
grep -Fq 'uses: actions/cache@caa296126883cff596d87d8935842f9db880ef25' "$action" ||
  fail "registry cache action is not pinned to the v5 commit"
# shellcheck disable=SC2016 # Match literal GitHub Actions expressions.
grep -Fq 'key: moonbit-registry-v2-${{ runner.os }}-${{ runner.arch }}-toolchain-0.10.4+ade96c819-core-0.10.4+ade96c819-${{ hashFiles('\''moon.work'\'', '\''**/moon.mod'\'', '\''**/moon.mod.json'\'') }}' "$action" ||
  fail "registry cache key does not encode schema, platform, toolchain, core, and manifests"
# shellcheck disable=SC2016 # Match literal GitHub Actions expressions.
grep -Fq 'moonbit-registry-v2-${{ runner.os }}-${{ runner.arch }}-toolchain-0.10.4+ade96c819-core-0.10.4+ade96c819-' "$action" ||
  fail "registry cache restore key is not scoped to the toolchain/core pair"
# shellcheck disable=SC2088 # GitHub Actions cache paths intentionally use ~.
for path in \
  '~/.moon/registry/index' \
  '~/.moon/registry/cache' \
  '~/.moon/registry/symbols'; do
  grep -Fq "  $path" "$action" || fail "registry cache path is missing: $path"
done
grep -Fq "if: steps.moonbit-registry-cache.outputs.cache-hit != 'true'" "$action" ||
  fail "bootstrap does not distinguish exact cache hits"
# shellcheck disable=SC2016 # Match the literal GitHub Actions expression.
if [ "$(grep -Fc 'run: "$GITHUB_WORKSPACE/scripts/moon-update.sh"' "$action")" -ne 1 ]; then
  fail "setup action must bootstrap the registry through the retry wrapper exactly once"
fi

# Exercise the state boundary represented by the action condition.
bootstrap_count() {
  if [ "$1" = true ]; then
    printf '0\n'
  else
    printf '1\n'
  fi
}
[ "$(bootstrap_count true)" = 0 ] || fail "exact cache hit would bootstrap"
[ "$(bootstrap_count false)" = 1 ] || fail "cache miss would not bootstrap"
[ "$(bootstrap_count partial)" = 1 ] || fail "partial cache restore would not bootstrap"

# Registry freshness is now explicit and singular at the local manual entry
# point. There is deliberately no compatibility alias with ambiguous `update`.
grep -Fq 'registry-refresh:' "$justfile" || fail "just registry-refresh recipe is missing"
grep -Eq 'registry-refresh' "$root_dir/Makefile" || fail "Makefile must forward registry-refresh"
if grep -Eq '^update:' "$justfile"; then
  fail "ambiguous just update recipe still exists"
fi
registry_refresh_recipe="$(awk '/^registry-refresh:/{inside=1; next} inside && /^[^[:space:]]/{exit} inside{print}' "$justfile")"
[ "$(printf '%s\n' "$registry_refresh_recipe" | grep -Fc 'bash "{{ moon_update }}"')" -eq 1 ] ||
  fail "just registry-refresh must call the retry wrapper exactly once"

# Re-run the production wiring guard from the contract test so a newly added
# command-bearing file cannot bypass a fixed fixture list.
"$root_dir/scripts/check-moon-update-wrapped.sh"

# Every registry dependency in every checked-out workspace/submodule manifest
# must be pinned. Path dependencies are intentionally exempt.
python3 "$root_dir/scripts/check-moon-registry-manifests.py"

echo "ok: MoonBit registry bootstrap contract passes"
