#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
DOC=docs/research/2026-08-13-cut-b-prime-candidate-lifetime-allocation.md
EXPECTED_LOOM=ae3f222f3c3135c55fc574ac418e8a54144af1a2

python3 - "$ROOT" "$DOC" "$EXPECTED_LOOM" <<'PY'
from pathlib import Path
import re
import subprocess
import sys

root = Path(sys.argv[1])
doc_path = root / sys.argv[2]
expected_loom = sys.argv[3]
failures: list[str] = []
checks = 0


def require(condition: bool, label: str) -> None:
    global checks
    checks += 1
    if not condition:
        failures.append(label)


def source_has(path: str, *anchors: str) -> None:
    file = root / path
    require(file.is_file(), f"missing source: {path}")
    if not file.is_file():
        return
    text = file.read_text(encoding="utf-8")
    for anchor in anchors:
        require(anchor in text, f"missing anchor: {path} :: {anchor}")


require(doc_path.is_file(), f"missing ledger document: {doc_path.relative_to(root)}")
if not doc_path.is_file():
    print("\n".join(f"FAIL {failure}" for failure in failures))
    raise SystemExit(1)

doc = doc_path.read_text(encoding="utf-8")

# Every source path printed in the document must resolve in this checkout.
paths = sorted(set(re.findall(
    r"(?:apps|modules|deps)/[A-Za-z0-9_./-]+\.(?:mbt|ts)",
    doc,
)))
for path in paths:
    require((root / path).is_file(), f"stale document path: {path}")

# Required gate structure and scope boundaries.
for heading in (
    "## Candidate single owner / resource allocation",
    "## Typed ownership / lifetime graph",
    "## Alive / Closing / Closed state machine",
    "## Current → candidate positive deletion ledger",
    "## Responsibility delta",
    "## Remaining conditional blockers",
    "## Decision criteria application",
):
    require(heading in doc, f"missing section: {heading}")

for statement in (
    "PASS WITH CONSTRAINTS — ledger closure only",
    "CrossRuntime edge count in candidate: ZERO",
    "The candidate read-model Region is **Incr Next evidence**",
    "does **not** authorize:",
    "P1 performance is frozen",
    "ProjectionIdentityTracker",
    "unrelated",
    "current engine has no explicit close API",
    "Cut B′ implementation, migration, and ADR remain unauthorized",
):
    require(statement in doc, f"missing scope statement: {statement}")

require(
    "No-op editor operations publish nothing" not in doc,
    "document must not claim independent no-op detection",
)
require(
    "WorkspaceCellHandle" in doc and "OUT-OF-CUT" in doc,
    "WorkspaceCellHandle boundary missing",
)
require(
    sorted(int(value) for value in re.findall(r"^\| ([1-5]) \|", doc, re.MULTILINE)) == [1, 2, 3, 4, 5],
    "five-item numbered ledger must contain rows 1..5 exactly once",
)
for number in range(6, 26):
    require(f"| {number} |" in doc, f"missing deletion ledger row {number}")

# Current source anchors that make the allocation/deletion ledger source-closed.
source_has(
    "modules/canopy/core/projection_memo.mbt",
    "let prev_proj_ref : Ref[ProjNode[T]?] = Ref(None)",
    "let counter : Ref[Int] = Ref(0)",
)
source_has(
    "modules/canopy/core/identity_hint_consumer.mbt",
    "pub struct IdentityHintConsumer",
    "fn IdentityHintConsumer::take_pending",
)
source_has(
    "modules/canopy/editor/sync_editor.mbt",
    "priv pending_transforms : Ref[Array[@core.IdentityTransform]]",
    "fn[T] finish_editor(",
    "let projection_anchor = cached_proj_node.watch()",
    "let registry_anchor = registry_memo.watch()",
    "let source_map_anchor = source_map_memo.watch()",
    "fn setup_hub_and_cursor",
    "cursor_store.subscribe",
)
source_has(
    "modules/canopy/lang/lambda/companion/lambda_editor.mbt",
    "priv trace_ref : Ref[Array[@core.ReconcileTraceEvent]]",
    "@lambda_eval.build_eval_memo(parser)",
    "@lambda_eval.build_escalation_memo(parser, eval_memo)",
    "fn build_lambda_capabilities",
)
source_has(
    "modules/canopy/ffi/lambda/protected_cells.mbt",
    "priv struct LambdaProtectedCells",
    "fn LambdaProtectedCells::to_protected_reads",
)
source_has(
    "modules/canopy/ffi/lambda/lifecycle.mbt",
    "let coordinator : @workspace.Coordinator = @workspace.Coordinator::new()",
    "pub fn get_sync_editor()",
    "pub fn get_lambda_companion()",
    "fn try_destroy_editor",
)
source_has(
    "modules/canopy/workspace/coordinator/methods.mbt",
    "pub fn Coordinator::destroy_editor",
)
source_has(
    "deps/loom/loom/factories.mbt",
    "new_imperative_parser(",
    "new_parser(",
)
source_has(
    "deps/loom/loom/projection/projection_identity.mbt",
    "pub struct ProjectionIdentityTracker",
)
source_has(
    "deps/loom/examples/lambda/analysis.mbt",
    "pub fn attach_lambda_analysis",
    "self.typecheck.dispose()",
)
source_has(
    "deps/loom/examples/lambda/typed_parser.mbt",
    "pub fn attach_typecheck",
)
source_has(
    "deps/loom/examples/lambda/typecheck/typecheck.mbt",
    "@incr.DerivedMap(",
    "add_on_change_listener",
)
source_has(
    "apps/ideal/main/init.mbt",
    "@visualizer.RecomputeTap::attach(editor.parser_runtime())",
)
source_has(
    "modules/canopy/ffi/lambda/analysis.mbt",
    "pub fn apply_ast_grep_results_json",
)
source_has(
    "modules/canopy/ffi/lambda/file_io.mbt",
    "pub fn load_file",
    "pub fn save_file",
)
source_has(
    "apps/web/src/features/lambda/browser/editor.ts",
    "disposed = true;",
    "releaseHandle = () => crdt.destroy_editor(handle);",
)

# The current Lambda protected bundle remains exactly ten fields; drift requires
# deliberate reclassification of the deletion ledger.
protected = (root / "modules/canopy/ffi/lambda/protected_cells.mbt").read_text(encoding="utf-8")
match = re.search(r"priv struct LambdaProtectedCells \{(.*?)\n\}", protected, re.DOTALL)
require(match is not None, "cannot parse LambdaProtectedCells")
if match is not None:
    fields = re.findall(r"^\s{2}[a-z][a-z0-9_]*\s*:", match.group(1), re.MULTILINE)
    require(len(fields) == 10, f"LambdaProtectedCells field count changed: {len(fields)}")

# Record and verify the vendored Loom identity used for all submodule citations.
actual_loom = subprocess.check_output(
    ["git", "-C", str(root / "deps/loom"), "rev-parse", "HEAD"],
    text=True,
).strip()
require(actual_loom == expected_loom, f"deps/loom pointer drift: {actual_loom}")
require(expected_loom in doc, "deps/loom pointer not recorded in document")

if failures:
    for failure in failures:
        print(f"FAIL {failure}")
    print(f"#1236 candidate lifetime ledger: FAIL ({len(failures)}/{checks})")
    raise SystemExit(1)

print(f"document_paths={len(paths)}")
print(f"checks={checks}")
print("candidate_cross_runtime_edges=0 (documented contract assertion; not behaviorally proven)")
print("candidate_implementation=not_assessed")
print("#1236 candidate lifetime source/document drift check: PASS WITH CONSTRAINTS")
PY
