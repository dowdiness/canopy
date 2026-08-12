#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
P0=examples/spikes/minimal_no_shadow_lambda_projection
EVIDENCE=$P0/evidence/incr_next_incremental_parity
MAIN=$P0/main
EXPECTED_PROVIDER_COMMIT=d54e78087d3837eccee0c55247adb90c07625869
OUTPUT=$(mktemp)
trap 'rm -f "$OUTPUT"' EXIT

printf '%s\n' '== minimal no-shadow Lambda projection P0 =='

printf '%s\n' '-- unchanged #462 provider evidence --'
if [[ "$(tr -d '\n' < "$EVIDENCE/ORIGIN_COMMIT")" != "$EXPECTED_PROVIDER_COMMIT" ]]; then
  printf '%s\n' 'provider origin commit mismatch' >&2
  exit 1
fi
(
  cd "$EVIDENCE"
  sha256sum --check provider.sha256
)

printf '%s\n' '-- no current-Incr/shadow construction in P0 source --'
if rg -n \
  '(@incr|dowdiness/incr|build_(lambda_)?projection_memos|SyncEditor|ProtectedCell|\.watch\()' \
  "$MAIN"; then
  printf '%s\n' 'forbidden current/shadow construction found in P0 source' >&2
  exit 1
fi
printf '%s\n' 'current/shadow constructors: NONE'

printf '%s\n' '-- native package checks --'
NEW_MOON_MOD=0 moon check --target native "$EVIDENCE/provider" "$MAIN"

printf '%s\n' '-- full observable state --'
NEW_MOON_MOD=0 moon run --target native "$MAIN" | tee "$OUTPUT"
for stage in \
  initial \
  raw-edit \
  structural-batch \
  demand-registry \
  demand-source-map \
  close \
  duplicate-close \
  post-close-read; do
  grep -Fq "=== $stage ===" "$OUTPUT"
done
grep -Fq 'parser_update_count=4' "$OUTPUT"
grep -Fq 'projection_transition_count=3' "$OUTPUT"
grep -Fq 'registry_compute_count=1' "$OUTPUT"
grep -Fq 'source_map_compute_count=1' "$OUTPUT"
grep -Fq 'read_result=Err(ClosedRegion)' "$OUTPUT"
grep -Fq 'P0 RESULT: PASS' "$OUTPUT"

printf '%s\n' '-- prototype branch allowlist --'
changed_paths=$({
  git diff --name-only origin/main...HEAD
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u)
forbidden_paths=$(grep -Ev \
  '^(moon\.work|scripts/run-minimal-no-shadow-lambda-projection\.sh|examples/spikes/minimal_no_shadow_lambda_projection(/.*)?)$' \
  <<<"$changed_paths" || true)
if [[ -n "$forbidden_paths" ]]; then
  printf '%s\n' 'change outside the P0 allowlist:' >&2
  printf '%s\n' "$forbidden_paths" >&2
  exit 1
fi
printf '%s\n' 'prototype allowlist: PASS'

cat "$P0/virtual-deletion-ledger.txt"
printf '%s\n' 'P0 VERDICT: PASS WITH CONSTRAINTS — unchanged #462 packaging, generic-reconciler fixture scope, and owner/wiring-only evidence; owner graph and lazy behavior pass.'
