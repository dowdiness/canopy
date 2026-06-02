#!/usr/bin/env bash

# Guard: every `moon update` invocation in CI workflows and shell scripts must
# go through scripts/moon-update.sh, the bounded-retry wrapper for the transient
# mooncakes CDN 403 (issue #467). A bare `moon update` silently loses that retry
# coverage — a CDN flake then fails the job (and, in deploy-cloudflare.yml, a
# production deploy) instead of auto-recovering. Coverage erodes by default
# without this enforcement, so fail the build if a bare invocation reappears.

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root_dir"

# Scan every command-bearing tracked file, wherever it lives: workflows/actions
# (*.yml/*.yaml), shell scripts (*.sh/*.bash/*.zsh) anywhere in the tree, and
# build files (Makefile/*.mk/justfile/Taskfile). Scoping to .github + scripts
# alone left blind spots — the Makefile `update:` target and examples/*/scripts/
# build-deploy.sh ran bare `moon update` undetected. Markdown/source/config are
# excluded by the allowlist (they only mention the command in prose). The wrapper
# itself is the one legitimate `moon update` caller, so exclude it.
mapfile -t files < <(
  git ls-files |
    grep -E '(\.(ya?ml|sh|bash|zsh|mk)$)|(^|/)(Makefile|justfile|Taskfile[^/]*)$' |
    grep -vx 'scripts/moon-update.sh'
)

# `moon-update.sh` (hyphen) never matches `moon update` (space), so the wrapper's
# own call is ignored for free. Match only command-position `moon update` so that
# prose mentions (a step `name:`, an `echo` string, a doc sentence) don't
# false-positive. A command-position invocation has `moon` at a shell command
# boundary, optionally behind inline `VAR=val` env prefixes:
#   - line start, optionally as a YAML value    moon update / run: moon update
#   - after a shell operator                    && | ; ( {  moon update
#   - after a conditional/loop head             if/while/until moon update
#   - any of the above + env prefix             MOON_WORK=off moon update
# The YAML-value arm is anchored to a line-start `key:` (with an optional `- `
# list dash), NOT any colon. A bare colon arm flagged prose like
# `name: "Fix issue: moon update deps"` (the inner `issue:` tripped it); requiring
# the colon to follow a line-start key avoids that while still matching
# `run: moon update` and matrix `moon-update: moon update`.
# The env prefix is matched ONLY when it itself follows a boundary, so a `VAR=val`
# token inside a quoted echo/argument string (e.g. `echo "X=y moon update"`) is
# not mistaken for a command. Comment lines (`#`) are dropped first.
#
# The keyword arm is scoped to `if|while|until` — the command-taking heads with
# real precedent (benchmark.yml had `if moon update`). Common-word keywords like
# `time`/`command`/`then` are deliberately excluded: they collide with prose
# inside string literals (`name: at build time moon update ...`) and a
# `time`/`command`-prefixed dependency update never occurs in practice.
boundary='(^[[:space:]]*(- )?([A-Za-z0-9_-]+:[[:space:]]+)?|[;&|({][[:space:]]*|\b(if|while|until)[[:space:]]+)'
env_prefix='([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
violations="$(
  grep -nE "${boundary}${env_prefix}moon update\b" "${files[@]}" |
    grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' ||
    true
)"

if [ -n "$violations" ]; then
  echo "error: bare 'moon update' found — route it through scripts/moon-update.sh (issue #467)." >&2
  echo "       Use \"\$GITHUB_WORKSPACE/scripts/moon-update.sh\" in workflows," >&2
  echo "       \"\$SCRIPT_DIR/moon-update.sh\" (or \"\$REPO_ROOT/...\") in scripts," >&2
  echo "       or \$(CURDIR)/scripts/moon-update.sh in the Makefile. Offending lines:" >&2
  echo "$violations" >&2
  exit 1
fi

echo "ok: all 'moon update' invocations route through scripts/moon-update.sh"
