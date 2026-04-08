#!/usr/bin/env bash
# Headless housekeeping — run repo health checks without an interactive session.
#
# Usage:
#   ./scripts/housekeeping.sh          # full audit (default)
#   ./scripts/housekeeping.sh check    # read-only quick check
#   ./scripts/housekeeping.sh fix      # auto-fix safe items
#
# Output is printed to stdout. Pipe to a file for logging:
#   ./scripts/housekeeping.sh > housekeeping-$(date +%Y%m%d).log 2>&1

set -euo pipefail
cd "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

MODE="${1:-}"

case "$MODE" in
  check)
    PROMPT="Run /moonbit-housekeeping check. Output the report only, no follow-up questions."
    ;;
  fix)
    PROMPT="Run /moonbit-housekeeping fix. Output the report only, no follow-up questions."
    ;;
  *)
    # Default: full audit-and-fix, but skip destructive prompts in headless mode
    PROMPT="Run /moonbit-housekeeping fix. Output the report only, no follow-up questions."
    ;;
esac

claude -p "$PROMPT" \
  --allowedTools "Bash,Read,Grep,Glob,Agent" \
  --model haiku
