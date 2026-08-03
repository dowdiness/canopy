#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

git -C "$fixture" init -q
mkdir -p \
  "$fixture/docs/plans" \
  "$fixture/docs/archive" \
  "$fixture/docs/superpowers/archive"
printf '# Active plan\n\nStatus: In progress\n' > "$fixture/docs/plans/active.md"
printf '# Historical plan\n\n**Status:** Executed\n' > "$fixture/docs/archive/done.md"
printf 'Historical reference: docs/%s\n' 'TODO.md' > \
  "$fixture/docs/superpowers/archive/legacy.md"
git -C "$fixture" add docs

"$repo_root/scripts/check-documentation-lifecycle.sh" "$fixture"

legacy_backlog="$fixture/docs/TO"'DO.md'
printf '# Legacy backlog\n' > "$legacy_backlog"
if "$repo_root/scripts/check-documentation-lifecycle.sh" "$fixture" >"$fixture/output" 2>&1; then
  printf 'expected legacy backlog file to fail\n' >&2
  exit 1
fi
grep -Fq 'remove docs/TODO.md' "$fixture/output"
rm "$legacy_backlog"

printf 'See docs/%s for work.\n' 'TODO.md' > "$fixture/README.md"
git -C "$fixture" add README.md
if "$repo_root/scripts/check-documentation-lifecycle.sh" "$fixture" >"$fixture/output" 2>&1; then
  printf 'expected legacy backlog reference to fail\n' >&2
  exit 1
fi
grep -Fq 'README.md references the retired backlog' "$fixture/output"
rm "$fixture/README.md"
git -C "$fixture" add -u

printf '# Finished plan\n\n**Status:** Executed\n' > "$fixture/docs/plans/finished.md"
git -C "$fixture" add docs/plans/finished.md
if "$repo_root/scripts/check-documentation-lifecycle.sh" "$fixture" >"$fixture/output" 2>&1; then
  printf 'expected terminal plan in docs/plans to fail\n' >&2
  exit 1
fi
grep -Fq 'docs/plans/finished.md has terminal status Executed' "$fixture/output"

mv "$fixture/docs/plans/finished.md" "$fixture/docs/archive/finished.md"
git -C "$fixture" add -A
mkdir -p "$fixture/docs/plans/advisory"
printf '# Nested finished plan\n\nStatus: Implemented\n' > \
  "$fixture/docs/plans/advisory/implemented.md"
git -C "$fixture" add docs/plans/advisory/implemented.md
if "$repo_root/scripts/check-documentation-lifecycle.sh" "$fixture" >"$fixture/output" 2>&1; then
  printf 'expected nested implemented plan to fail\n' >&2
  exit 1
fi
grep -Fq 'docs/plans/advisory/implemented.md has terminal status Implemented' \
  "$fixture/output"
mv "$fixture/docs/plans/advisory/implemented.md" \
  "$fixture/docs/archive/nested-implemented.md"
git -C "$fixture" add -A
"$repo_root/scripts/check-documentation-lifecycle.sh" "$fixture"

printf '# Bad plan\n\n\377\376\n' > "$fixture/docs/plans/bad-utf8.md"
git -C "$fixture" add docs/plans/bad-utf8.md
if "$repo_root/scripts/check-documentation-lifecycle.sh" "$fixture" >"$fixture/output" 2>&1; then
  printf 'expected invalid UTF-8 active plan to fail\n' >&2
  exit 1
fi
grep -Fq 'docs/plans/bad-utf8.md cannot be read as UTF-8:' "$fixture/output"
rm "$fixture/docs/plans/bad-utf8.md"
git -C "$fixture" add -u

printf 'ok: documentation lifecycle guard rejects legacy backlog surfaces and terminal active plans\n'
