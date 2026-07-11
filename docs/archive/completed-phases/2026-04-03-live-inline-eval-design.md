# Live Inline Evaluation — Design

**Date:** 2026-04-03
**Status:** Design

## Goal

Show evaluation results next to definitions as you type. Both the pretty-print view and structural tree view display results through the framework protocol — no per-editor special logic.

```
let double = (x) => x + x          → ‹closure›
let result = double 5            → 10
if result then result else 0     → 10
```

## Non-Goals

- Partial evaluation of incomplete programs (Phase 1 / egglog — future)
- Type annotations (needs egglog Phase 1 — future)
- Per-subexpression evaluation (only top-level definitions and body)

## Architecture

### Eval Memo (editor layer)

A new `@incr.Memo` in the SyncEditor projection pipeline. Recomputes when the AST changes.

**Input:** `@ast.Term` from `SyncEditor::get_ast()`

**Output:** `Array[EvalResult]` — one per definition + one for the body expression.

```moonbit
pub(all) enum EvalResult {
  Value(String)     // rendered: "10", "‹closure›", "()"
  Stuck(String)     // rendered: "‹unbound: x›", "‹type error›"
  Suppressed        // Incomplete or ParseError — expected during editing
}
```

**Evaluation logic:**

For `Module(defs, body)`:
1. Evaluate each definition in sequence, building the environment
2. Record `EvalResult` per definition (index 0..N-1)
3. Evaluate body, record as index N
4. Fuel limit: 1000 (default). If exceeded → `Stuck("‹diverges›")`

For non-Module terms (single expression): evaluate directly, record as index 0.

**Suppression rules:**
- `StuckReason::Incomplete` → `Suppressed` (user is still typing)
- `StuckReason::ParseError` → `Suppressed` (parse error shown via diagnostics)
- All other StuckReasons → `Stuck(rendered_message)`

**Value rendering:**
- `VInt(n)` → `"{n}"`
- `VClosure(_, _, _)` → `"‹closure›"`
- `VUnit` → `"()"`

**Memo placement:** After `proj_memo` in the pipeline (needs AST). Independent of `registry_memo` and `source_map_memo` — no dependency.

```
parser → syntax_tree signal
           ├→ proj_memo → cached_proj_node → registry_memo
           │                               → source_map_memo
           └→ eval_memo (NEW)
```

### Pretty-Print View Integration

Eval annotations are injected **into the Layout** before conversion to ViewNode. This makes them part of the rendered text — WYSIWYG.

**Flow:**

```
SyncEditor::get_pretty_view()
  1. ast = get_ast()
  2. eval_results = eval_memo.get()
  3. layout = Pretty::to_layout(ast)
  4. annotated_layout = inject_eval_annotations(layout, eval_results)  // NEW
  5. layout_to_view_tree(annotated_layout, width=80)
```

**`inject_eval_annotations`:** Builds a new Layout that wraps the original, appending an eval annotation after each definition's group. Layout is an immutable enum, so this constructs a new tree (zero-copy for shared subtrees). The annotation per definition is:

```moonbit
// For Value("10"):
Annotate(EvalAnnotation, Text("  → 10"))

// For Stuck("‹unbound: x›"):
Annotate(EvalError, Text("  → ‹unbound: x›"))

// For Suppressed:
(nothing appended)
```

This requires adding two new variants to `SyntaxCategory`:

```moonbit
pub(all) enum SyntaxCategory {
  Keyword
  Identifier
  Number
  StringLit
  Operator
  Punctuation
  Comment
  Error
  EvalAnnotation   // NEW — successful eval result
  EvalError        // NEW — stuck/error eval result
}
```

And extending `category_to_role` in `formatted_view.mbt`:

```moonbit
EvalAnnotation => "eval-annotation"
EvalError => "eval-error"
```

The web editor styles these with CSS classes (`.eval-annotation`, `.eval-error`).

**Layout structure for a definition:**

The `Pretty::to_layout` for `Module` produces a sequence of definition layouts separated by `HardLine`. Each definition is a `Group(...)`. We need to append the eval annotation **after** each definition group but **before** the `HardLine` separator.

**Implementation approach:** Rather than modifying `Pretty::to_layout` (which is in the loom submodule), create a wrapper function in `editor/` or `lang/lambda/` that:
1. Calls `Pretty::to_layout(ast)` to get the base layout
2. If the term is `Module(defs, body)`, builds a new layout that interleaves definition layouts with eval annotations
3. For non-Module terms, appends eval annotation at the end

This keeps `Pretty::to_layout` pure (no eval dependency) and the annotation logic in the editor layer.

### Structural View Integration

Add an `annotations` field to `ViewNode` for semantic metadata.

```moonbit
pub(all) struct ViewNode {
  // existing fields...
  annotations : Array[ViewAnnotation]   // NEW, default []
}

pub(all) struct ViewAnnotation {
  kind : String      // "eval", "scope", "type" — extensible
  label : String     // "→ 10", "bound", "Int → Int"
  severity : String  // "info", "warning", "error"
}
```

**Attachment point:** `proj_to_view_node` takes an optional annotations map:

```moonbit
pub fn proj_to_view_node[T : @loomcore.Renderable](
  node : @core.ProjNode[T],
  source_map : @core.SourceMap,
  annotations? : Map[@core.NodeId, Array[ViewAnnotation]] = {},
) -> ViewNode
```

For eval, the SyncEditor builds the annotations map by matching definition indices to their ProjNode NodeIds (available from the registry memo).

**Patch delivery:** `diff_view_nodes` already compares ViewNodes field-by-field. Annotation changes produce `UpdateNode` patches. The `UpdateNode` variant needs extension to carry annotations:

```moonbit
UpdateNode(
  node_id~ : @core.NodeId,
  label~ : String,
  css_class~ : String,
  text~ : String?,
  annotations~ : Array[ViewAnnotation],  // NEW
)
```

### Web Editor CSS

Minimal CSS additions for the pretty-print view:

```css
.token-eval-annotation {
  color: var(--color-eval);
  opacity: 0.7;
  font-style: italic;
}
.token-eval-error {
  color: var(--color-error);
  opacity: 0.7;
  font-style: italic;
}
```

For the structural tree view, renderers display `ViewAnnotation` as a badge/label:
```css
.annotation-eval {
  color: var(--color-eval);
  margin-left: 0.5em;
  font-style: italic;
}
```

### FFI Surface

No new FFI exports needed. Eval results flow through existing `get_pretty_view_json` / `compute_pretty_patches_json` (pretty-print) and `get_view_tree_json` / `compute_view_patches_json` (structural). The JSON serialization of `ViewAnnotation` is automatic via `ToJson`.

### Incrementality

The eval memo recomputes when the AST changes. For a single keystroke:
1. Parser incrementally reparses → new AST
2. Eval memo re-evaluates all definitions (not incremental — fuel-limited, fast for small programs)
3. Pretty view rebuilds with new annotations → `diff_view_nodes` computes minimal patches
4. Structural view rebuilds with new annotations → same diff

Future optimization: per-definition eval caching (skip re-evaluating unchanged definitions). Not needed for the lambda demo scale.

### Error UX

| Eval State | Pretty-Print | Structural |
|---|---|---|
| `Value("10")` | ` → 10` (italic, dim) | badge: `→ 10` |
| `Stuck("‹unbound: x›")` | ` → ‹unbound: x›` (red, italic) | badge: `→ ‹unbound: x›` (warning) |
| `Suppressed` | nothing shown | nothing shown |

Suppression prevents noisy error flash while typing. Only genuine semantic errors (type mismatch, unbound variable, divergence) are shown.

## Files Changed

| File | Change |
|---|---|
| `loom/pretty/ann.mbt` | Add `EvalAnnotation`, `EvalError` to `SyntaxCategory` |
| `protocol/view_node.mbt` | Add `annotations` field + `ViewAnnotation` struct |
| `protocol/view_patch.mbt` | Add `annotations` to `UpdateNode` variant |
| `protocol/formatted_view.mbt` | Extend `category_to_role` for new categories |
| `protocol/convert.mbt` | Pass annotations map to `proj_to_view_node` |
| `editor/eval_memo.mbt` | NEW — eval memo + EvalResult type |
| `editor/sync_editor_pretty.mbt` | Inject eval annotations into layout |
| `editor/sync_editor.mbt` | Wire eval memo into SyncEditor constructor |
| `editor/projection_memo.mbt` | Build eval memo alongside projection memos |
| `editor/view_updater.mbt` | Diff annotations in `diff_view_nodes` |
| `lang/lambda/proj/` or `lang/lambda/edits/` | Eval annotation builder (def index → Layout annotation) |
| `examples/web/src/editor.ts` | CSS for eval annotation tokens |
| `examples/web/src/style.css` | `.token-eval-annotation`, `.token-eval-error` |

## Testing

- Unit tests for `eval_memo`: Module with mixed values/errors/suppression
- Unit tests for `inject_eval_annotations`: Layout output matches expected
- Unit tests for ViewNode annotation diffing
- Integration test: edit text → verify pretty-view contains eval annotation spans
- Snapshot tests: formatted output with eval annotations

## Acceptance Criteria

1. Pretty-print view shows `→ <value>` after each definition that evaluates successfully
2. Pretty-print view shows `→ <error>` in error styling for stuck evaluations
3. Pretty-print view shows nothing for Incomplete/ParseError (suppressed)
4. Structural tree view shows eval annotations on definition nodes
5. Annotations update incrementally on each keystroke
6. No performance regression: eval adds < 1ms for typical programs (< 50 definitions)
7. `moon check` and `moon test` pass across all modules
8. Web editor at `canopy-lambda-editor.pages.dev` displays eval results
