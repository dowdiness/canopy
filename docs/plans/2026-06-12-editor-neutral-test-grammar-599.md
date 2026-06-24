# Editor neutral test grammar — design (#599 STALE-waiver retirement)

Status: DESIGN (prose-only; no implementation pasted). Branch
`editor-neutral-test-grammar-599` in worktree `canopy-s4-spike`, based on
`origin/main` (which carries the #599 import-graph lint, squash `ababb1f`).

## Goal

Make `editor/` stop importing any language in test/wbtest scope so the four
`[G]` waivers in `scripts/check-deps.sh` EXCEPTIONS can be removed in the
same PR (the STALE mechanism fails CI the moment an import disappears while
its waiver remains). Source of intent: redesign proposal
`docs/plans/2026-06-11-architecture-redesign-proposal.md`, "Dependency and
boundary rules": *"editor must not import any `lang/*` including test imports
— the lambda test fixture is replaced by a TestExpr-style neutral grammar."*

## The four waivers to retire (all rule `[G]`, package `editor`)

| scope  | import |
|--------|--------|
| test   | `dowdiness/canopy/lang/lambda` |
| wbtest | `dowdiness/canopy/lang/lambda` |
| test   | `dowdiness/lambda` |
| test   | `dowdiness/lambda/ast` |

`moon.pkg` edits and EXCEPTIONS removals MUST land together.

## Inventory (what the 18 editor test files actually use)

- `@lambda` = `dowdiness/canopy/lang/lambda` — 293 refs (the real fixture).
- `@ast` = `dowdiness/lambda/ast` — `Term` (12), `print_term` (29).
- `@parser` = `dowdiness/lambda` — **0 refs (dead import)**; its waiver is
  removable on its own.

### Classification (by what each file exercises)

- **Group A — generic editor (10 files):** `error_path_wbtest`,
  `error_recovery_test`, `sync_editor_history_test`,
  `sync_editor_runtime_threading_test`, `sync_editor_text_wbtest`,
  `sync_editor_undo_test`, `sync_editor_ws_wbtest`, `sync_status_wbtest`,
  `view_updater_test`, `view_updater_benchmark_wbtest`. Construct an editor +
  text/cursor/undo/sync only. Repoint constructor → `new_test_editor`.
- **Group B — generic + AST readback (4 files):** `pretty_view_test`,
  `sync_editor_accessors_test`, `sync_editor_parser_test` (49 refs),
  `sync_editor_test` (66 refs). Assert on the *parsed AST structure*;
  assertions must be **re-derived** for the TestExpr shape (NOT mechanical).
- **Group C — lambda tree-edit semantics (3 files):** `tree_edit_json_test`
  (tests `parse_tree_edit_op`), `tree_edit_bridge_test` (tests
  `apply_lambda_tree_edit`), `sync_editor_tree_edit_wbtest` (mixed:
  generic `move_node`/`Drop` + lambda ops). Test `lang/lambda` logic.
- **Group D — lambda eval (1 file):** `eval_memo_wbtest`. Tests
  `lang/lambda/eval` logic.

## Decisions (user-confirmed 2026-06-12)

1. **Groups C+D → move to `lang/lambda` (de-dup).** They test lang/lambda
   logic, not the editor (test-ownership principle). Relocate; delete any
   case `lang/lambda` already covers. De-dup signals found:
   - `eval_memo_wbtest` (D): `lang/lambda/eval/eval_memo_wbtest.mbt` AND
     `eval_memo_test.mbt` already exist → editor copy is likely **redundant
     → delete** (must diff to confirm before deleting).
   - `parse_tree_edit_op` is tested **nowhere** in lang/lambda →
     `tree_edit_json_test` is **unique → move to `lang/lambda/companion`**.
   - `apply_lambda_tree_edit` → `tree_edit_bridge_test` moves to
     `lang/lambda/companion`.
   - `sync_editor_tree_edit_wbtest`: split — generic `move_node`/`Drop`
     mechanics stay in editor (repointed to TestExpr); lambda-op cases move
     or delete.
   - **Test-count accounting required**: record per-file `test "..."` counts
     before move/delete; the relocated + retained total must equal the
     original (minus only proven-redundant cases, each named).
2. **Neutral grammar lives in `workspace/probe`** (proposal-named
   "cross-package contract-test home"; already exists). Currently wbtest-only
   → the grammar goes in **normal scope** (new public surface) so both
   editor blackbox `*_test.mbt` and whitebox `*_wbtest.mbt` can import it.
   Test-scope import cycle (probe → editor → probe) is fine; the current
   lang/lambda fixture already relies on the same cycle.

## Neutral grammar design

### AST — `TestExpr` (model exists)

`core/test_expr_wbtest.mbt` already defines a proven neutral AST:
`enum TestExpr { Leaf(String); Branch(String, Array[TestExpr]) }` with full
`@loomcore.TreeNode` + `Renderable` + `Eq` + `ToJson` + `Show` impls. It is
`priv` (core wbtest only) so it cannot be imported. Re-define it as a `pub`
type in `workspace/probe` normal scope, copying those trait impls verbatim
(byte-equivalent move discipline; ~70 lines).

### Required trait bounds (from Group A+B editor-method usage)

`Eq` (text/edit ops), `Renderable` (`get_view_tree` ×2, `move_node`),
`@loomcore.TreeNode` (for `@core.build_projection_memos`). No `Pretty` via
the editor surface (`get_pretty_view` unused by A+B; `pretty_view_test`
asserts via an AST pretty-printer, not `editor.get_pretty_view`).

### Projection pipeline (generic — no lambda copy)

`@core.build_projection_memos(rt, syntax_tree_derived, syntax→ProjNode,
sourcemap_filler, label?)` is generic over `T: TreeNode + Eq` and returns the
exact `(Derived[ProjNode[T]?], Derived[registry], Derived[SourceMap])` triple
`SyncEditor::new_generic` wants. The lambda flat-projection (341 lines,
incremental, def-index/`final_expr` specific) is **not** reproduced — a
straight `SyntaxNode → ProjNode[TestExpr]` converter feeds the generic
builder.

### Editor construction

`SyncEditor::new_generic(agent_id, parserFactory, projectionPipeline,
capture_timeout_ms?, parent_runtime?, capabilities?)`. Capabilities are
**all-`None`** for the neutral grammar (eval/decoration/annotation are
lambda-only and optional). Wrap as:
`new_test_editor(source) -> @editor.SyncEditor[TestExpr]` plus
`get_test_ast(editor) -> TestExpr` (read `parser_ast` / `get_tree`).

### The one genuinely new piece — the loom grammar (OPEN, Codex input)

`@loom.Grammar::new(spec=, lex=, fold_node=, ...)` needs a lexer + parser
spec + CST fold. The smallest existing full grammar (`dowdiness/json-settings`)
is 432 src lines; a minimal s-expression-ish TestExpr grammar
(`tag(child child)` → `Branch`, bare atom → `Leaf`, graceful on arbitrary
inserted text) is ~150–250 loom lines. **Build-vs-borrow for the grammar is
the key Codex question.** Options:

- **(a) Build minimal TestExpr loom grammar** in `workspace/probe`. Honors
  the proposal's "TestExpr-style neutral grammar" wording; full control;
  ~150–250 lines of loom lexer/spec/fold.
- **(b) Borrow a non-GRAMMAR_MODULE loom example** (`dowdiness/json-settings`
  is smallest and `[G]`-safe — only `dowdiness/{lambda,json,markdown}` are
  registered grammar-modules). Less code; but couples editor tests to a real
  example language, against the "neutral" intent.

Leaning (a) per proposal wording; Codex to validate the grammar shape is
sufficient to host Group A (arbitrary text insertion) and Group B (structural
assertions), and that the minimal-grammar cost is justified vs (b).

## Execution outline (delegation-shaped after pattern converges)

1. Build `workspace/probe` neutral grammar surface (AST + grammar +
   converter + `new_test_editor`/`get_test_ast`). **Main context** (judgment).
2. Convert ONE Group-B file (e.g. `sync_editor_accessors_test`) as the
   reference pattern; verify test-count parity. **Main context.**
3. Port Group A (repoint constructor) + remaining Group B (re-derive
   assertions). **Delegation-shaped** (checkpoint at batch start).
4. Move Groups C+D to `lang/lambda` (de-dup, with test-count accounting).
   **Delegation-shaped.**
5. Remove the 4 EXCEPTIONS entries + the editor `moon.pkg` test/wbtest
   lambda imports together; `./scripts/check-deps.sh` must pass (no STALE).
6. `moon test` workspace + per-affected-package; `moon fmt`/`moon info`
   (NEW_MOON_MOD=0); restore sibling `.mbti` churn. Codex pre-PR review.

## Codex design-validation revisions (2026-06-12)

Verdict: build (not borrow), generic projection, trait bounds, and the probe
cycle all confirmed. Three revisions:

1. **Grammar must be TOTAL over arbitrary input.** `SyncEditor::get_tree`
   assumes malformed input still yields an AST, and `build_projection_memos`
   *unconditionally* converts the syntax tree to a `ProjNode`. So the
   lexer + parser + `fold_node` + `SyntaxNode→ProjNode` converter must never
   abort/miss on garbage, partial, or non-BMP input — `sync_editor_text_wbtest`
   deliberately inserts emoji / ZWJ / regional-indicator surrogates and
   parse-error states. Unparseable spans must map to a stable error `Leaf`,
   not panic. This is the load-bearing grammar requirement.
2. **Hidden lambda tendrils are test-case-level, not file-level.** Three
   "generic" files each contain ONE lambda-semantic test that must be
   surgically extracted (moved to lang/lambda), the rest repointed:
   - `view_updater_test.mbt:259` "semantic decorations are emitted and
     stable" — exercises lambda capabilities (`semantic-binder`/
     `semantic-bound` decorations). Other view_updater tests are generic.
   - `sync_editor_parser_test.mbt:121` — `get_lambda_resolution`.
   - `sync_editor_test.mbt:422` — `get_lambda_resolution`.
   Decoration/resolution are lambda-capability behavior; the neutral grammar
   (all-None capabilities) cannot reproduce them.
3. **`eval_memo_wbtest` is NOT pure-eval-redundant — do not blanket-delete.**
   It tests editor↔companion *capability wiring* via `get_pretty_view`,
   `get_eval_annotations`, `get_view_tree`. Classify retained coverage by
   behavior; move (not delete) unless companion-level coverage is proven.
   Test-count parity is necessary but **not sufficient** — also classify
   retained coverage by behavior.

Edge case on the probe cycle (PASS): once `workspace/probe` gains normal
scope, its normal-scope deps must stay free of `lang/*` and `GRAMMAR_MODULES`
(loom + core + editor only). Leave probe's *existing wbtest* lambda imports
as-is — they test probe's own contracts, not the editor.

## Risks / watch

- Group B is a real rewrite, not a port — asserted values change with the AST.
- Test-count parity across the C+D move is the primary correctness gate
  (`feedback_test_count_delta`).
- The grammar must not be added to `GRAMMAR_MODULES` and must not live under
  `lang/*`, or `[G]` fires on the replacement.
- `workspace/probe` gaining a normal-scope public surface may need a
  `pkg.generated.mbti` update + moon.work/CI awareness.
