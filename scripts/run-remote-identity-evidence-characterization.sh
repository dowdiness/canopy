#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export NEW_MOON_MOD=0

# This oracle is intentionally test-only. Refuse to run if any production
# path that owns admission, hint lifecycle, generic reconciliation, or the
# Lambda adapter is modified. The oracle exercises TestExpr's generic adapter;
# it does not execute Lambda directly. An independent source review verifies
# that the guarded Lambda adapter uses the matching hint keying.
production_paths=(
  modules/canopy/editor/sync_editor.mbt
  modules/canopy/editor/sync_editor_parser.mbt
  modules/canopy/editor/sync_editor_text.mbt
  modules/canopy/editor/sync_editor_tree_edit.mbt
  modules/canopy/editor/sync_editor_undo.mbt
  modules/canopy/editor/sync_editor_ws.mbt
  modules/canopy/core/identity_hint_consumer.mbt
  modules/canopy/core/identity_transform.mbt
  modules/canopy/core/projection_memo.mbt
  modules/canopy/core/reconcile.mbt
  modules/canopy/lang/runtime/language.mbt
  modules/canopy/lang/lambda/proj/projection_memo.mbt
)
if ! git diff --quiet HEAD -- "${production_paths[@]}"; then
  echo "remote identity evidence source guard failed: production source changed" >&2
  git diff --name-only HEAD -- "${production_paths[@]}" >&2
  exit 1
fi

# `moon info` has already produced the authoritative probe interface change:
# workspace/probe is explicit test support, not a production API. Verify these
# exact hashes before and after the targeted test; this deliberately does not
# invoke `moon info` or rewrite generated interfaces.
declare -A expected_interface_hashes=(
  [modules/canopy/editor/pkg.generated.mbti]=f6d3526fb957d8172c08013f598708fb23fa7481e04a65264831855718f4861d
  [modules/canopy/workspace/probe/pkg.generated.mbti]=6fed56380001d0ce270c90ec5b74f519a0e506fa22a70a088efcfc1eaa2c7b5e
)
interface_paths=(
  modules/canopy/editor/pkg.generated.mbti
  modules/canopy/workspace/probe/pkg.generated.mbti
)
declare -A interface_hashes
for path in "${interface_paths[@]}"; do
  before="$(sha256sum "$path" | awk '{print $1}')"
  if [[ "${expected_interface_hashes[$path]}" != "$before" ]]; then
    echo "generated interface hash mismatch before targeted oracle: $path" >&2
    echo "expected=${expected_interface_hashes[$path]} actual=$before" >&2
    exit 1
  fi
  interface_hashes["$path"]="$before"
done

moon test --target js modules/canopy/editor/remote_identity_evidence_wbtest.mbt

for path in "${interface_paths[@]}"; do
  after="$(sha256sum "$path" | awk '{print $1}')"
  if [[ "${interface_hashes[$path]}" != "$after" ]]; then
    echo "generated interface changed during targeted oracle: $path" >&2
    exit 1
  fi
done

echo "remote identity evidence characterization passed"
