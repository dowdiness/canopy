#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
SPIKE=examples/spikes/lambda_annotation_capability_program
REF=66a160f557f01f53e6e721016cf12d75b3d4fca4
INCR_SOURCE=${INCR_NEXT_SOURCE:-$ROOT/deps/loom/incr}
EXPECTED_BASE=74d448e2ecdcbbd72c260769f254b6c069d1ddef
EXPECTED_MEMO_TREE=bac4a47edb7d13548389246fdc2d4ca4bea31595
EXPECTED_KERNEL_TREE=599b58072e11a47c6a7c62e9d3af6293688066ec
EXPECTED_FORMULA_TREE=855877d3dce3732f1c9cd1b312fe082c2299fda7
EXPECTED_PROGRAM_TREE=172c50488951fb8430ac3145a5bb7df2490c3c99
EXPECTED_SPIKE_ARCHIVE=5c6170b4a5bf7dc32e44dba94d5ae39e1326f20a3ea84d9cb4442073a43376c6
EXPECTED_CANOPY_TREE=e9db14c25edb5ba809a20e6dd0cb2e806252bc5e
EXPECTED_LAMBDA_TREE=29c6e306d1021f796c81955221bc16dcbd250296
EXPECTED_COMPANION_TREE=7533cd6a1cb0b0ea1d75ac33d7ac01b489540b91
MEMO_DIR=examples/spikes/incr_next_memo_eviction
KERNEL_DIR=$MEMO_DIR/incremental_provider
FORMULA_DIR=examples/spikes/incr_next_formula_exports
PROGRAM_DIR=$FORMULA_DIR/program
EVIDENCE_DIRS=(
  examples/spikes/incr_next_fresh_evaluator
  examples/spikes/incr_next_incremental_parity
  examples/spikes/incr_next_cycle_detection
  examples/spikes/incr_next_cutoff_backdating
  examples/spikes/incr_next_memo_eviction
  examples/spikes/incr_next_mounted_roots
  examples/spikes/incr_next_read_ports
  examples/spikes/incr_next_cross_program_ports
  examples/spikes/incr_next_formula_exports
)
COMPANION=modules/canopy/lang/lambda/companion
TEST_NAME=lambda_annotation_capability_program_wbtest

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

printf '%s\n' '== Lambda annotation capability Program evidence =='
git merge-base --is-ancestor "$EXPECTED_BASE" HEAD ||
  fail "Canopy HEAD does not contain expected base $EXPECTED_BASE"
[[ -d "$INCR_SOURCE/.git" || -f "$INCR_SOURCE/.git" ]] ||
  fail "Incr repository is missing: $INCR_SOURCE"
if ! git -C "$INCR_SOURCE" cat-file -e "$REF^{commit}" 2>/dev/null; then
  git -C "$INCR_SOURCE" fetch origin spike/incr-next-formula-exports
fi
[[ "$(git -C "$INCR_SOURCE" rev-parse "$REF^{commit}")" == "$REF" ]] ||
  fail "Incr repository does not contain exact commit $REF"
[[ -z "$(git -C "$INCR_SOURCE" status --porcelain)" ]] ||
  fail 'Incr repository has working-tree changes'

printf '%s\n' '-- exact production and submodule guards --'
[[ "$(git rev-parse HEAD:modules/canopy)" == "$EXPECTED_CANOPY_TREE" ]] ||
  fail 'Canopy production module tree changed'
[[ "$(git rev-parse HEAD:modules/canopy/lang/lambda)" == "$EXPECTED_LAMBDA_TREE" ]] ||
  fail 'Lambda production tree changed'
[[ "$(git rev-parse HEAD:modules/canopy/lang/lambda/companion)" == "$EXPECTED_COMPANION_TREE" ]] ||
  fail 'Lambda companion production tree changed'
parent_submodules=$(git submodule status --recursive | sed -E 's/ \([^)]*\)//')
if grep -Eq '^[+-]' <<<"$parent_submodules"; then
  fail 'parent checkout has an uninitialized or mismatched submodule'
fi

printf '%s\n' '-- exact #465/#469 source guard --'
[[ "$(git -C "$INCR_SOURCE" rev-parse "$REF:$MEMO_DIR")" == "$EXPECTED_MEMO_TREE" ]] ||
  fail '#465 module tree changed at the evidence commit'
[[ "$(git -C "$INCR_SOURCE" rev-parse "$REF:$KERNEL_DIR")" == "$EXPECTED_KERNEL_TREE" ]] ||
  fail '#465 incremental_provider tree changed at the evidence commit'
[[ "$(git -C "$INCR_SOURCE" rev-parse "$REF:$FORMULA_DIR")" == "$EXPECTED_FORMULA_TREE" ]] ||
  fail '#469 module tree changed at the evidence commit'
[[ "$(git -C "$INCR_SOURCE" rev-parse "$REF:$PROGRAM_DIR")" == "$EXPECTED_PROGRAM_TREE" ]] ||
  fail '#469 program tree changed at the evidence commit'
archive_hash=$(git -C "$INCR_SOURCE" archive --format=tar "$REF" "$MEMO_DIR" "$FORMULA_DIR" | sha256sum | awk '{print $1}')
[[ "$archive_hash" == "$EXPECTED_SPIKE_ARCHIVE" ]] ||
  fail "#465/#469 archive hash changed: $archive_hash"

TEMP_ROOT=$(mktemp -d)
WORK=$TEMP_ROOT/canopy
cleanup() {
  git -C "$ROOT" worktree remove --force "$WORK" >/dev/null 2>&1 || true
  rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

printf '%s\n' '-- temporary candidate formatting (parent source is never rewritten) --'
FMT_DIR=$TEMP_ROOT/formatted
mkdir -p "$FMT_DIR"
cp "$ROOT/$SPIKE/$TEST_NAME.mbt.disabled" "$FMT_DIR/$TEST_NAME.mbt"
moon fmt "$FMT_DIR/$TEST_NAME.mbt"
if ! cmp -s "$ROOT/$SPIKE/$TEST_NAME.mbt.disabled" "$FMT_DIR/$TEST_NAME.mbt"; then
  printf '%s\n' 'canonical disabled source is not moon-formatted:' >&2
  diff -u "$ROOT/$SPIKE/$TEST_NAME.mbt.disabled" "$FMT_DIR/$TEST_NAME.mbt" || true
  exit 1
fi
moon fmt --check "$FMT_DIR/$TEST_NAME.mbt"

printf '%s\n' '-- disposable Canopy worktree and exact evidence modules --'
git worktree add --detach "$WORK" HEAD >/dev/null
git -C "$WORK" submodule update --init --recursive >/dev/null
work_submodules=$(git -C "$WORK" submodule status --recursive | sed -E 's/ \([^)]*\)//')
if grep -Eq '^[+-]' <<<"$work_submodules"; then
  fail 'disposable worktree has an uninitialized or mismatched submodule'
fi
if [[ "$work_submodules" != "$parent_submodules" ]]; then
  printf '%s\n' 'submodule pointers differ between parent and disposable tree:' >&2
  diff -u <(printf '%s\n' "$parent_submodules") <(printf '%s\n' "$work_submodules") || true
  exit 1
fi
mkdir -p "$WORK/examples/spikes"
# Materialize only the exact committed evidence trees. The source repository's
# checkout may remain at its recorded submodule commit.
git -C "$INCR_SOURCE" archive --format=tar "$REF" "${EVIDENCE_DIRS[@]}" |
  tar -xf - -C "$WORK"

python3 - "$WORK/moon.work" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
entries = [
    '  "./examples/spikes/incr_next_memo_eviction",',
    '  "./examples/spikes/incr_next_formula_exports",',
]
if any(entry in text for entry in entries):
    raise SystemExit("candidate module already present in disposable moon.work")
closing = text.rfind("]")
if closing < 0:
    raise SystemExit("moon.work has no members terminator")
prefix = text[:closing].rstrip()
if not prefix.endswith(","):
    prefix += ","
path.write_text(prefix + "\n" + "\n".join(entries) + "\n]\n")
PY

disabled="$ROOT/$SPIKE/$TEST_NAME.mbt.disabled"
cp "$disabled" "$WORK/$COMPANION/$TEST_NAME.mbt"
cp "$WORK/$COMPANION/moon.pkg" "$TEMP_ROOT/companion.moon.pkg.before"
python3 - "$WORK/$COMPANION/moon.pkg" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
needle = '  "dowdiness/loom",\n} for "wbtest"'
replacement = (
    '  "dowdiness/loom",\n'
    '  "examples/spikes/incr_next_formula_exports/program" @next_program,\n'
    '  "examples/spikes/incr_next_memo_eviction/incremental_provider" @next_kernel,\n'
    '} for "wbtest"'
)
if text.count(needle) != 1:
    raise SystemExit("companion wbtest import boundary changed")
path.write_text(text.replace(needle, replacement))
PY
# Moon's module solver requires a local module dependency even when both modules
# are workspace members. This overlay exists only in the disposable worktree;
# the parent moon.mod and production package manifests are never touched.
python3 - "$WORK/modules/canopy/moon.mod" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
needle = '  "dowdiness/js_ffi@0.1.0",\n}'
replacement = (
    '  "dowdiness/js_ffi@0.1.0",\n'
    '  "examples/spikes/incr_next_memo_eviction@0.1.0",\n'
    '  "examples/spikes/incr_next_formula_exports@0.1.0",\n'
    '}'
)
if text.count(needle) != 1:
    raise SystemExit("Canopy module dependency boundary changed")
path.write_text(text.replace(needle, replacement))
PY

if git -C "$WORK" diff --name-only -- modules/canopy | grep -Ev '^(modules/canopy/moon\.mod|modules/canopy/lang/lambda/companion/moon\.pkg)$' | grep -q .; then
  fail 'disposable production diff is outside the test-only manifest allowlist'
fi

printf '%s\n' '-- generated interfaces (disposable only) --'
mbti_files=(
  "$WORK/$KERNEL_DIR/pkg.generated.mbti"
  "$WORK/$PROGRAM_DIR/pkg.generated.mbti"
  "$WORK/$COMPANION/pkg.generated.mbti"
)
for file in "${mbti_files[@]}"; do
  sha256sum "$file" | awk '{print $1}' > "$TEMP_ROOT/$(basename "$(dirname "$file")").mbti.sha256"
done
(
  cd "$WORK"
  NEW_MOON_MOD=0 moon info "$COMPANION" "$KERNEL_DIR" "$PROGRAM_DIR"
)
for file in "${mbti_files[@]}"; do
  key=$(basename "$(dirname "$file")")
  current=$(sha256sum "$file" | awk '{print $1}')
  expected=$(cat "$TEMP_ROOT/$key.mbti.sha256")
  [[ "$current" == "$expected" ]] || fail "generated interface changed: $file"
done
if rg -n 'next_program|next_kernel|incremental_provider|FormulaBuilder|ReadPort' \
  "$WORK/$COMPANION/pkg.generated.mbti"; then
  fail 'candidate-only Program/kernel imports leaked through companion public interface'
fi

printf '%s\n' '-- native and wasm-gc checks --'
(
  cd "$WORK"
  NEW_MOON_MOD=0 moon check --target native "$COMPANION" "$KERNEL_DIR" "$PROGRAM_DIR"
)
wasm_supported=1
if ! wasm_check_output=$(cd "$WORK" && NEW_MOON_MOD=0 moon check --target wasm-gc "$COMPANION" "$KERNEL_DIR" "$PROGRAM_DIR" 2>&1); then
  printf '%s\n' "$wasm_check_output"
  wasm_error_count=$(grep -c '^Error: \[' <<<"$wasm_check_output" || true)
  if [[ "$wasm_error_count" -eq 1 ]] &&
    grep -Fq 'Error: [4156]' <<<"$wasm_check_output" &&
    grep -Fq 'modules/canopy/ephemeral/ephemeral_time_native.mbt:9:1' <<<"$wasm_check_output" &&
    grep -Fq 'extern "C" is unsupported in wasm-gc backend' <<<"$wasm_check_output"; then
    wasm_supported=0
    printf '%s\n' 'wasm-gc: SKIP (known Canopy ephemeral_time_native extern only)' >&2
  else
    fail 'wasm-gc check has a candidate or unknown failure'
  fi
fi

printf '%s\n' '-- targeted companion tests and candidate output --'
native_output=$(cd "$WORK" && NEW_MOON_MOD=0 moon test --target native "$COMPANION" --filter 'lambda annotation capability*' 2>&1)
printf '%s\n' "$native_output"
if [[ "$wasm_supported" -eq 1 ]]; then
  wasm_output=$(cd "$WORK" && NEW_MOON_MOD=0 moon test --target wasm-gc "$COMPANION" --filter 'lambda annotation capability*' 2>&1)
  printf '%s\n' "$wasm_output"
  printf '%s\n' 'candidate exact output: lambda_annotation_capability_program native=PASS wasm-gc=PASS'
else
  printf '%s\n' 'candidate exact output: lambda_annotation_capability_program native=PASS wasm-gc=SKIP'
fi

printf '%s\n' '-- privacy, scope, and source guards --'
if rg -n '@incr|Decoration|Diagnostic|pretty|Mount|Action|Resource|effects|resources' \
  "$ROOT/$SPIKE/$TEST_NAME.mbt.disabled"; then
  fail 'out-of-scope production/effect surface found in candidate source'
fi
if rg -n 'examples/spikes/incr_next_(memo_eviction|formula_exports)' \
  "$ROOT/$SPIKE/$TEST_NAME.mbt.disabled"; then
  fail 'candidate source directly embeds exact evidence module paths'
fi
if ! grep -Fq 'examples/spikes/incr_next_formula_exports/program" @next_program' \
  "$WORK/$COMPANION/moon.pkg" ||
  ! grep -Fq 'examples/spikes/incr_next_memo_eviction/incremental_provider" @next_kernel' \
  "$WORK/$COMPANION/moon.pkg"; then
  fail 'disposable wbtest import aliases are missing'
fi

printf '%s\n' '-- blocking documentation lint --'
SLOP_JSON=$TEMP_ROOT/slopless.json
npx --yes slopless@0.2.35 "$ROOT/$SPIKE/README.md" > "$SLOP_JSON"
python3 - "$SLOP_JSON" <<'PY'
import json
import sys

reports = json.loads(open(sys.argv[1]).read())
messages = [
    message
    for report in reports
    for message in report.get("messages", [])
]
if messages:
    raise SystemExit(f"slopless findings: {messages}")
print("slopless: PASS")
PY

printf '%s\n' '-- parent production diff and allowlist --'
if ! git diff --quiet -- modules/canopy; then
  fail 'parent production modules changed'
fi
if [[ "$(git submodule status --recursive | sed -E 's/ \([^)]*\)//')" != "$parent_submodules" ]]; then
  fail 'parent submodule status changed during harness'
fi
changed_paths=$({
  git diff --name-only
  git diff --cached --name-only
  git ls-files --others --exclude-standard
} | sort -u)
forbidden_paths=$(grep -Ev '^examples/spikes/lambda_annotation_capability_program(/.*)?$' <<<"$changed_paths" || true)
if [[ -n "$forbidden_paths" ]]; then
  printf '%s\n' 'change outside the lambda annotation evidence allowlist:' >&2
  printf '%s\n' "$forbidden_paths" >&2
  exit 1
fi

wasm_state=PASS
if [[ "$wasm_supported" -eq 0 ]]; then
  wasm_state=SKIP
fi
printf '%s\n' "harness state: format=PASS source=#465/#469-exact submodules=PASS info=PASS privacy=PASS check-native=PASS check-wasm=$wasm_state test-native=PASS test-wasm=$wasm_state atomic=PASS slopless=PASS production=PASS"
grep -Fq '**Pass with constraints.**' "$ROOT/$SPIKE/README.md"
printf '%s\n' 'constrained verdict: PASS - closure oracle and shadow Formula maps match for the finite workloads.'
