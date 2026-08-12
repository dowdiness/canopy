#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
P1=examples/spikes/minimal_no_shadow_lambda_projection
EVIDENCE=$P1/evidence/incr_next_incremental_parity
MAIN=$P1/main
ADAPTER=modules/canopy/lang/lambda/companion/minimal_no_shadow_p1_evidence.mbt
COMPANION_MBTI=modules/canopy/lang/lambda/companion/pkg.generated.mbti
EXPECTED_PROVIDER_COMMIT=d54e78087d3837eccee0c55247adb90c07625869
EXPECTED_PROVIDER_MANIFEST_SHA256=4f93472aafbb203901d426fca056ef7c4f3c2f423ef121e7e2c0c625e6fa6c27
P1_BASE=667aaf63b1144b4afd913f9ea6f995b1fa6ac56e
EXPECTED_INTERFACE_PATCH=$P1/evidence/expected-companion-p1.mbti.patch
OUTPUT=$(mktemp)
INTERFACE_PATCH=$(mktemp)
trap 'rm -f "$OUTPUT" "$INTERFACE_PATCH"' EXIT

printf '%s\n' '== minimal no-shadow Lambda annotations P1 =='

printf '%s\n' '-- unchanged #462 provider evidence --'
if [[ "$(tr -d '\n' < "$EVIDENCE/ORIGIN_COMMIT")" != "$EXPECTED_PROVIDER_COMMIT" ]]; then
  printf '%s\n' 'provider origin commit mismatch' >&2
  exit 1
fi
if [[ "$(sha256sum "$EVIDENCE/provider.sha256" | cut -d' ' -f1)" != \
  "$EXPECTED_PROVIDER_MANIFEST_SHA256" ]]; then
  printf '%s\n' 'provider manifest differs from the P0-reviewed manifest' >&2
  exit 1
fi
(
  cd "$EVIDENCE"
  sha256sum --check provider.sha256
)

printf '%s\n' '-- no current-Incr/shadow construction or read in P1 source --'
if rg -n \
  '(@incr|dowdiness/incr|build_(lambda_)?projection_memos|SyncEditor|ProtectedCell|\.watch\(|escalation_memo|get_eval_results)' \
  "$MAIN" "$ADAPTER"; then
  printf '%s\n' 'forbidden current/shadow construction or read found in P1 source' >&2
  exit 1
fi
printf '%s\n' 'current/shadow constructors: NONE'

printf '%s\n' '-- native package checks --'
NEW_MOON_MOD=0 moon check --target native \
  "$EVIDENCE/provider" \
  "$MAIN" \
  modules/canopy/lang/lambda/companion

printf '%s\n' '-- full observable state --'
NEW_MOON_MOD=0 moon run --target native "$MAIN" | tee "$OUTPUT"
for stage in \
  initial \
  raw-edit \
  structural-batch \
  demand-annotations \
  demand-registry \
  demand-source-map \
  evaluation-edit \
  close \
  duplicate-close \
  post-close-read; do
  grep -Fq "=== $stage ===" "$OUTPUT"
done
grep -Fq 'parser_update_count=4' "$OUTPUT"
grep -Fq 'projection_transition_count=3' "$OUTPUT"
grep -Fq 'parser_update_count=5' "$OUTPUT"
grep -Fq 'projection_transition_count=4' "$OUTPUT"
grep -Fq 'registry_compute_count=1' "$OUTPUT"
grep -Fq 'source_map_compute_count=2' "$OUTPUT"
grep -Fq 'eval_compute_count=2' "$OUTPUT"
grep -Fq 'annotation_compute_count=2' "$OUTPUT"
grep -Fq 'read_result=eval=→ 3, ViewNode consumer=pass' "$OUTPUT"
grep -Fq 'read_result=Err(ClosedRegion)' "$OUTPUT"
grep -Fq 'registry_metrics=compute:0,cache_hits:0,green_verifications:0,memo_count:0,trace_length:none' "$OUTPUT"
grep -Fq 'registry_metrics=compute:1,cache_hits:1,green_verifications:0,memo_count:1,trace_length:1' "$OUTPUT"
grep -Fq 'annotation_metrics=compute:1,cache_hits:1,green_verifications:0,memo_count:1,trace_length:3' "$OUTPUT"
grep -Fq 'source_map_metrics=compute:1,cache_hits:3,green_verifications:0,memo_count:1,trace_length:1' "$OUTPUT"
grep -Fq 'eval_metrics=compute:2,cache_hits:1,green_verifications:0,memo_count:1,trace_length:1' "$OUTPUT"
grep -Fq 'source_map_metrics=compute:2,cache_hits:5,green_verifications:0,memo_count:1,trace_length:1' "$OUTPUT"
grep -Fq 'annotation_metrics=compute:2,cache_hits:1,green_verifications:0,memo_count:1,trace_length:3' "$OUTPUT"
grep -Fq 'registry_metrics=compute:1,cache_hits:1,green_verifications:0,memo_count:0,trace_length:none' "$OUTPUT"
grep -Fq 'source_map_metrics=compute:2,cache_hits:5,green_verifications:0,memo_count:0,trace_length:none' "$OUTPUT"
grep -Fq 'eval_metrics=compute:2,cache_hits:1,green_verifications:0,memo_count:0,trace_length:none' "$OUTPUT"
grep -Fq 'annotation_metrics=compute:2,cache_hits:1,green_verifications:0,memo_count:0,trace_length:none' "$OUTPUT"
grep -Fq 'P1 RESULT: PASS WITH CONSTRAINTS' "$OUTPUT"

printf '%s\n' '-- evidence-only interface delta --'
git diff "$P1_BASE" -- "$COMPANION_MBTI" > "$INTERFACE_PATCH"
if ! cmp -s "$INTERFACE_PATCH" "$EXPECTED_INTERFACE_PATCH"; then
  printf '%s\n' 'companion interface differs from the reviewed one-function patch:' >&2
  diff -u "$EXPECTED_INTERFACE_PATCH" "$INTERFACE_PATCH" >&2 || true
  exit 1
fi
grep '^+pub fn' "$INTERFACE_PATCH"

printf '%s\n' '-- prototype branch allowlist --'
changed_paths=$({
  git diff --name-only origin/main...HEAD
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u)
forbidden_paths=$(grep -Ev \
  '^(moon\.work|scripts/run-minimal-no-shadow-lambda-projection\.sh|examples/spikes/minimal_no_shadow_lambda_projection(/.*)?|modules/canopy/lang/lambda/companion/minimal_no_shadow_p1_evidence\.mbt|modules/canopy/lang/lambda/companion/pkg\.generated\.mbti)$' \
  <<<"$changed_paths" || true)
if [[ -n "$forbidden_paths" ]]; then
  printf '%s\n' 'change outside the P1 allowlist:' >&2
  printf '%s\n' "$forbidden_paths" >&2
  exit 1
fi
printf '%s\n' 'prototype allowlist: PASS'

cat "$P1/virtual-deletion-ledger.txt"
printf '%s\n' 'P1 VERDICT: PASS WITH CONSTRAINTS — the P0 graph stays single-owner after Tier-1 evaluation and full present-projection annotations; constraints are unchanged #462 packaging, generic-reconciler fixture scope, evidence-only annotation visibility, no Tier-2 escalation, and owner/wiring-only evidence.'
