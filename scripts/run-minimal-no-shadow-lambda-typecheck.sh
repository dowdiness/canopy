#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
P2A=examples/spikes/minimal_no_shadow_lambda_projection
MAIN=$P2A/main
TYPECHECK=deps/loom/examples/lambda/typecheck
OUTPUT_NATIVE=$(mktemp)
OUTPUT_JS=$(mktemp)
trap 'rm -f "$OUTPUT_NATIVE" "$OUTPUT_JS"' EXIT

printf '%s\n' '== P2a Runtime-free whole-module typecheck feasibility =='

printf '%s\n' '-- inherited no-shadow/provider gate --'
./scripts/run-minimal-no-shadow-lambda-projection.sh >/dev/null
printf '%s\n' 'P1.2 behavioral/provider/owner gate: PASS'

printf '%s\n' '-- selected production pure APIs --'
rg -q 'pub fn convert_from_cst\(' "$TYPECHECK/cst_convert.mbt"
rg -q 'pub fn resolve_typed\(' "$TYPECHECK/resolve.mbt"
rg -q 'pub fn infer\(' "$TYPECHECK/infer.mbt"
rg -q 'infer_impl\(env, term, DiagCtx::empty\(\)\)' "$TYPECHECK/infer.mbt"
rg -q 'diags: None' "$TYPECHECK/infer.mbt"
for symbol in convert_from_cst resolve_typed infer; do
  printf 'production_api=%s\n' "$symbol"
done
printf '%s\n' 'diagnostics_api=UNAVAILABLE_WITHOUT_CURRENT_ACCUMULATOR'

printf '%s\n' '-- no current reactive construction/read in P2a source --'
if rg -n \
  '(@incr|dowdiness/incr|@cells|@workspace|@loom\.new_parser|@lambda\.new_parser|LambdaAnalysis|attach_lambda_analysis|attach_typecheck|build_typecheck_pipeline|DerivedMap\(|Accumulator\(|add_on_change_listener|ProtectedCell::|\.watch\()' \
  "$MAIN"; then
  printf '%s\n' 'forbidden current reactive edge found in P2a source' >&2
  exit 1
fi
rg -q '"dowdiness/lambda/typecheck" @typecheck' "$MAIN/moon.pkg"
rg -q '@typecheck\.convert_from_cst\(commit\.parse_snapshot\.syntax\)' "$MAIN/model.mbt"
rg -q '@typecheck\.resolve_typed\(term\)' "$MAIN/typecheck_evidence.mbt"
rg -q '@typecheck\.infer\(' "$MAIN/typecheck_evidence.mbt"
if [[ $(rg -o 'region\.source\(' "$MAIN/model.mbt" | wc -l) -ne 1 ]]; then
  printf '%s\n' 'P2a must retain exactly one ProjectionCommit Source' >&2
  exit 1
fi
if [[ $(rg -o 'let store = @next\.Store\(\)' "$MAIN/model.mbt" | wc -l) -ne 1 ]]; then
  printf '%s\n' 'P2a must retain exactly one Store owner' >&2
  exit 1
fi
if [[ $(rg -o 'let region = must_region\(store\.region\(\)\)' "$MAIN/model.mbt" | wc -l) -ne 1 ]]; then
  printf '%s\n' 'P2a must retain exactly one Region owner' >&2
  exit 1
fi
printf '%s\n' 'application_owner=1 Store=1 Region=1 ProjectionCommit_Source=1'
printf '%s\n' 'current_Runtime=0 Scope=0 Derived=0 Watch=0 DerivedMap=0 Accumulator=0 listener=0 bridge=0'

printf '%s\n' '-- native behavior --'
NEW_MOON_MOD=0 moon check --target native "$MAIN"
NEW_MOON_MOD=0 moon test --target native \
  "$MAIN/typecheck_evidence_wbtest.mbt" | tee "$OUTPUT_NATIVE"
grep -Fq 'Total tests: 3, passed: 3, failed: 0.' "$OUTPUT_NATIVE"
NEW_MOON_MOD=0 moon run --target native "$MAIN" | tee "$OUTPUT_NATIVE"

printf '%s\n' '-- JS behavior --'
NEW_MOON_MOD=0 moon check --target js "$MAIN"
NEW_MOON_MOD=0 moon test --target js \
  "$MAIN/typecheck_evidence_wbtest.mbt" | tee "$OUTPUT_JS"
grep -Fq 'Total tests: 3, passed: 3, failed: 0.' "$OUTPUT_JS"
NEW_MOON_MOD=0 moon run --target js "$MAIN" | tee "$OUTPUT_JS"

for output in "$OUTPUT_NATIVE" "$OUTPUT_JS"; do
  grep -Fq 'P2a initial typed=0 typecheck=0 current_runtime=0' "$output"
  grep -Fq 'P2a first-demand typed=1 typecheck=1 defs=2 direct-trace=1/1' "$output"
  grep -Fq 'P2a repeated-read typed=1 typecheck=1' "$output"
  grep -Fq 'P2a body-edit-before-demand typed=1 typecheck=1' "$output"
  grep -Fq 'P2a body-edit-demand typed=2 typecheck=2 defs=2' "$output"
  grep -Fq 'P2a structural-edit-before-demand typed=2 typecheck=2' "$output"
  grep -Fq 'P2a structural-edit-demand typed=3 typecheck=3 defs=3' "$output"
  grep -Fq 'P2a close=Closed duplicate=AlreadyClosed post-close=ClosedRegion compute-delta=0' "$output"
  grep -Fq 'P2a RESULT: PASS WITH CONSTRAINTS' "$output"
done

printf '%s\n' '-- interface drift --'
NEW_MOON_MOD=0 moon info "$MAIN" >/dev/null
for interface in \
  "$MAIN/pkg.generated.mbti" \
  modules/canopy/lang/lambda/companion/pkg.generated.mbti; do
  if ! git diff --quiet HEAD -- "$interface" || \
      ! git diff --cached --quiet HEAD -- "$interface"; then
    printf 'P2a unexpectedly changed generated interface: %s\n' "$interface" >&2
    git diff HEAD -- "$interface" >&2
    git diff --cached HEAD -- "$interface" >&2
    exit 1
  fi
done
printf '%s\n' 'public_interface_delta=NONE'

printf '%s\n' 'P2a VERDICT: PASS WITH CONSTRAINTS — exact ParseSnapshot syntax feeds lazy TypedTerm and whole-module ModuleTypeResult Queries with one owner/Store/Region/Source and no current reactive objects; diagnostics parity, duplicate-name diagnostics, per-definition reuse, stable TypecheckIndex, and production construction remain unproven.'
