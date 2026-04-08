#!/usr/bin/env bash
# Compact package overview for SessionStart hook.
# Outputs package paths, pub symbol counts, and submodule deps.
set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

echo "=== Package Map (live) ==="
for dir in . core editor protocol projection relay ffi \
  lang/lambda lang/lambda/proj lang/lambda/flat lang/lambda/eval lang/lambda/edits \
  lang/json lang/json/proj lang/json/edits cmd/main; do
  count=$(moon ide outline "$dir" 2>/dev/null | grep -c "pub" 2>/dev/null || echo 0)
  printf "  %-30s %s pub symbols\n" "$dir/" "$count"
done

echo "=== Submodule deps ==="
grep 'path = ' .gitmodules 2>/dev/null | sed 's/.*= /  /' || echo "  (none)"

echo "=== Use 'moon ide outline <path>' for package details ==="
