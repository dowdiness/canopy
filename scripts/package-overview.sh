#!/usr/bin/env bash
# Compact package overview for SessionStart hook.
# Outputs package paths, pub symbol counts, key public types, and submodule deps.
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

# Capture outline once per package; reuse for both count and type extraction.
declare -A pkg_types

# Canopy-internal packages (sub-packages of the main module).
canopy_pkgs=(
  . core editor protocol projection relay
  ffi/host ffi/json ffi/lambda ffi/markdown
  lang/lambda lang/lambda/proj lang/lambda/eval lang/lambda/scope
  lang/lambda/semantic lang/lambda/edits lang/lambda/companion
  lang/json lang/json/proj lang/json/edits cmd/main
)

# Workspace members from moon.work (lib/*, examples/*) — excludes root "." already above.
mapfile -t workspace_pkgs < <(grep -oE '"\.\/[^"]*"' moon.work | tr -d '"' | sed 's|^\./||')

echo "=== Package Map (live) ==="
for dir in "${canopy_pkgs[@]}" "${workspace_pkgs[@]}"; do
  outline=$(NEW_MOON_MOD=0 moon ide outline "$dir" 2>/dev/null || true)
  count=$(printf '%s\n' "$outline" | grep -c "pub" || true)
  printf "  %-38s %s pub symbols\n" "$dir/" "${count:-0}"
  case "$dir" in core|editor|protocol|projection|relay)
    # Stop at `{` or `(` to capture the full type name including multi-param generics.
    pkg_types[$dir]=$(printf '%s\n' "$outline" \
      | grep -E '[|] pub (struct|enum|trait) ' \
      | sed -E 's/.*[|] pub (struct|enum|trait) ([^{(]+).*/\2/' \
      | sed 's/[[:space:]]*$//' \
      || true)
    ;;
  esac
done

echo ""
echo "=== Key Public Types (struct/enum/trait) ==="
for pkg in core editor protocol projection relay; do
  raw=${pkg_types[$pkg]:-}
  if [ -n "$raw" ]; then
    total=$(printf '%s\n' "$raw" | wc -l | tr -d ' ')
    displayed=$(printf '%s\n' "$raw" | head -8 | tr '\n' ' ')
    suffix=""
    [ "$total" -gt 8 ] && suffix="..."
    printf "  %-14s %s%s\n" "$pkg:" "$displayed" "$suffix"
  fi
done

echo ""
echo "=== Submodule deps ==="
grep 'path = ' .gitmodules 2>/dev/null | sed 's/.*= /  /' || echo "  (none)"

echo ""
echo "=== Use 'NEW_MOON_MOD=0 moon ide outline <path>' for package details ==="
echo "=== See 'docs/api-map.md' for task→API index ==="
