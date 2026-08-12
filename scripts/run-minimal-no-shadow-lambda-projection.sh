#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
P1=examples/spikes/minimal_no_shadow_lambda_projection
EVIDENCE=$P1/evidence/incr_next_cutoff_backdating
MAIN=$P1/main
ADAPTER=modules/canopy/lang/lambda/companion/minimal_no_shadow_p1_evidence.mbt
COMPANION_MBTI=modules/canopy/lang/lambda/companion/pkg.generated.mbti
EXPECTED_PROVIDER_COMMIT=c640f65124b2a0eb362f3f08a1b6220e6647b6b7
EXPECTED_PROVIDER_MANIFEST_SHA256=1ba050605fc86e375bccade07f1776ef5eef34a0647619f2f46b42e6ac81ba04
P1_BASE=667aaf63b1144b4afd913f9ea6f995b1fa6ac56e
EXPECTED_INTERFACE_PATCH=$P1/evidence/expected-companion-p1.mbti.patch
OUTPUT=$(mktemp)
INTERFACE_PATCH=$(mktemp)
trap 'rm -f "$OUTPUT" "$INTERFACE_PATCH"' EXIT

printf '%s\n' '== minimal no-shadow Lambda Evaluation green path P1.2 =='

printf '%s\n' '-- unchanged resolved #464 provider evidence --'
if [[ "$(tr -d '\n' < "$EVIDENCE/ORIGIN_COMMIT")" != "$EXPECTED_PROVIDER_COMMIT" ]]; then
  printf '%s\n' 'provider origin commit mismatch' >&2
  exit 1
fi
if [[ "$(sha256sum "$EVIDENCE/provider.sha256" | cut -d' ' -f1)" != \
  "$EXPECTED_PROVIDER_MANIFEST_SHA256" ]]; then
  printf '%s\n' 'provider manifest differs from the reviewed #464 manifest' >&2
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
if [[ "$(rg -o 'region\.source\(' "$MAIN/model.mbt" | wc -l)" -ne 1 ]]; then
  printf '%s\n' 'P1.2 must retain exactly one canonical Source constructor' >&2
  exit 1
fi
rg -q 'region\.query_eq\(' "$MAIN/model.mbt"
printf '%s\n' 'canonical Sources: 1; typed Eq-cutoff selector: PRESENT'

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
  whitespace-green-path \
  close \
  duplicate-close \
  post-close-read; do
  grep -Fq "=== $stage ===" "$OUTPUT"
done
grep -Fq 'parser_update_count=4' "$OUTPUT"
grep -Fq 'projection_transition_count=3' "$OUTPUT"
grep -Fq 'parser_update_count=5' "$OUTPUT"
grep -Fq 'projection_transition_count=4' "$OUTPUT"
grep -Fq 'parser_update_count=6' "$OUTPUT"
grep -Fq 'projection_transition_count=5' "$OUTPUT"
grep -Fq 'registry_compute_count=1' "$OUTPUT"
grep -Fq 'source_map_compute_count=3' "$OUTPUT"
grep -Fq 'term_compute_count=3' "$OUTPUT"
grep -Fq 'eval_compute_count=2' "$OUTPUT"
grep -Fq 'annotation_compute_count=3' "$OUTPUT"
grep -Fq 'read_result=eval=→ 3, ViewNode consumer=pass' "$OUTPUT"
grep -Fq 'read_result=Term backdated, Evaluation green, eval_compute_delta=0' "$OUTPUT"
grep -Fq 'read_result=Err(ClosedRegion)' "$OUTPUT"
grep -Fq 'registry_metrics=compute:0,cutoff_calls:0,cache_hits:0,green_verifications:0,memo_count:0,direct_trace_length:none' "$OUTPUT"
grep -Fq 'registry_metrics=compute:1,cutoff_calls:0,cache_hits:1,green_verifications:0,memo_count:1,direct_trace_length:1' "$OUTPUT"
grep -Fq 'annotation_metrics=compute:1,cutoff_calls:0,cache_hits:1,green_verifications:0,memo_count:1,direct_trace_length:3' "$OUTPUT"
grep -Fq 'source_map_metrics=compute:1,cutoff_calls:0,cache_hits:3,green_verifications:0,memo_count:1,direct_trace_length:1' "$OUTPUT"
grep -Fq 'term_metrics=compute:3,cutoff_calls:2,cache_hits:1,green_verifications:0,memo_count:1,direct_trace_length:1' "$OUTPUT"
grep -Fq 'eval_metrics=compute:2,cutoff_calls:1,cache_hits:2,green_verifications:1,memo_count:1,direct_trace_length:1' "$OUTPUT"
grep -Fq 'source_map_metrics=compute:3,cutoff_calls:2,cache_hits:6,green_verifications:0,memo_count:1,direct_trace_length:1' "$OUTPUT"
grep -Fq 'annotation_metrics=compute:3,cutoff_calls:2,cache_hits:1,green_verifications:0,memo_count:1,direct_trace_length:3' "$OUTPUT"
grep -Fq 'registry_metrics=compute:1,cutoff_calls:0,cache_hits:1,green_verifications:0,memo_count:0,direct_trace_length:none' "$OUTPUT"
grep -Fq 'source_map_metrics=compute:3,cutoff_calls:2,cache_hits:6,green_verifications:0,memo_count:0,direct_trace_length:none' "$OUTPUT"
grep -Fq 'term_metrics=compute:3,cutoff_calls:2,cache_hits:1,green_verifications:0,memo_count:0,direct_trace_length:none' "$OUTPUT"
grep -Fq 'eval_metrics=compute:2,cutoff_calls:1,cache_hits:2,green_verifications:1,memo_count:0,direct_trace_length:none' "$OUTPUT"
grep -Fq 'annotation_metrics=compute:3,cutoff_calls:2,cache_hits:1,green_verifications:0,memo_count:0,direct_trace_length:none' "$OUTPUT"
grep -Fq 'P1.2 RESULT: PASS WITH CONSTRAINTS' "$OUTPUT"

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
  '^(moon\.work|scripts/run-minimal-no-shadow-lambda-projection\.sh|scripts/run-minimal-no-shadow-lambda-cutoff-benchmark\.sh|examples/spikes/minimal_no_shadow_lambda_projection(/.*)?|modules/canopy/lang/lambda/companion/minimal_no_shadow_p1_evidence\.mbt|modules/canopy/lang/lambda/companion/pkg\.generated\.mbti)$' \
  <<<"$changed_paths" || true)
if [[ -n "$forbidden_paths" ]]; then
  printf '%s\n' 'change outside the P1 allowlist:' >&2
  printf '%s\n' "$forbidden_paths" >&2
  exit 1
fi
printf '%s\n' 'prototype allowlist: PASS'

cat "$P1/virtual-deletion-ledger.txt"
printf '%s\n' 'P1.2 VERDICT: PASS WITH CONSTRAINTS — one typed Eq-cutoff Term selector backdates a whitespace-only changed commit and makes Evaluation verify green without recomputing; this is one-workload graph evidence, not general fine-grained incrementality or timing evidence.'
