# TreeEditOp Handler Chain Design

## Goal

Refactor `compute_text_edit` (1,064 lines, 28-arm exhaustive match) into a composable handler chain with per-file decomposition and a middleware layer for cross-cutting concerns.

## Motivation

### Current pain

`projection/text_edit.mbt` is the largest file in `projection/`. Adding a new refactoring operation (e.g., `ExtractFunction`) requires editing 3 files across 2 packages:

1. `TreeEditOp` enum in `projection/tree_lens.mbt` — add variant
2. `compute_text_edit` in `projection/text_edit.mbt` — add match arm (in a 1,064-line function)
3. `parse_tree_edit_op` in `editor/tree_edit_json.mbt` — add JSON parsing arm
4. `TreeEditorState::apply_edit` in `projection/tree_editor.mbt` — add UI state arm

The blast radius is high, the file is hard to navigate, and there's no extension point for cross-cutting logic (validation, undo recording, logging).

### SuperOOP-inspired insight

Fan & Parreaux (ECOOP 2023) decompose interpreters into composable mixins where each mixin handles one case and delegates to `super` for the rest. We adapt this pattern to MoonBit's constraints:

- **Closed enum stays** — provides exhaustiveness checking (MoonBit has no constructor difference types)
- **Per-file handlers** — each semantic group is self-contained (SuperOOP's "one mixin per case")
- **Middleware chain** — wraps the core dispatch with composable cross-cutting logic (SuperOOP's `super` delegation)

### Design approach: Two-Layer

- **Layer 1 (enum):** `TreeEditOp` remains the public API and wire format. JSON parsing and UI state dispatch are unchanged.
- **Layer 2 (handler chain):** Text edit computation uses a thin exhaustive router that delegates to per-file handler functions. The router is wrapped with middleware for composability.

## Architecture

### EditContext

Bundle the 5 parameters of `compute_text_edit` into a shared context struct:

```moonbit
pub(all) struct EditContext {
  source_text : String
  source_map : SourceMap
  registry : Map[NodeId, ProjNode]
  flat_proj : FlatProj
}

pub type EditResult = Result[(Array[SpanEdit], FocusHint)?, String]
```

`EditContext` is `pub(all)` because `editor/tree_edit_bridge.mbt` constructs it directly via struct literal syntax. No factory function needed — `pub(all)` fields are sufficient. Handler functions and middleware stay package-private.

### Core router

The exhaustive match in `text_edit.mbt` shrinks to ~40 lines. Each arm is a one-line delegation to a handler function:

```moonbit
fn core_dispatch(op : TreeEditOp, ctx : EditContext) -> EditResult {
  match op {
    Select(_) | SelectRange(..) | StartEdit(_) | CancelEdit
    | StartDrag(_) | DragOver(..) | Collapse(_) | Expand(_) =>
      Ok(Some(([], RestoreCursor)))
    CommitEdit(node_id~, new_value~) =>
      compute_commit(ctx, node_id, new_value)
    Delete(node_id~) =>
      compute_delete(ctx, node_id)
    WrapInLambda(node_id~, var_name~) =>
      compute_wrap_lambda(ctx, node_id, var_name)
    WrapInApp(node_id~) =>
      compute_wrap_app(ctx, node_id)
    WrapInIf(node_id~) =>
      compute_wrap_if(ctx, node_id)
    WrapInBop(node_id~, op~) =>
      compute_wrap_bop(ctx, node_id, op)
    InsertChild(parent~, index~, kind~) =>
      compute_insert_child(ctx, parent, index, kind)
    Drop(source~, target~, position~) =>
      compute_drop(ctx, source, target, position)
    Unwrap(node_id~, keep_child_index~) =>
      compute_unwrap(ctx, node_id, keep_child_index)
    SwapChildren(node_id~) =>
      compute_swap_children(ctx, node_id)
    ChangeOperator(node_id~, new_op~) =>
      compute_change_operator(ctx, node_id, new_op)
    DeleteBinding(binding_node_id~) =>
      compute_delete_binding(ctx, binding_node_id)
    DuplicateBinding(binding_node_id~) =>
      compute_duplicate_binding(ctx, binding_node_id)
    MoveBindingUp(binding_node_id~) =>
      compute_move_binding_up(ctx, binding_node_id)
    MoveBindingDown(binding_node_id~) =>
      compute_move_binding_down(ctx, binding_node_id)
    AddBinding(module_node_id~) =>
      compute_add_binding(ctx, module_node_id)
    ExtractToLet(node_id~, var_name~) =>
      compute_extract_to_let(ctx, node_id, var_name)
    InlineDefinition(node_id~) =>
      compute_inline_definition(ctx, node_id)
    InlineAllUsages(binding_node_id~) =>
      compute_inline_all_usages(ctx, binding_node_id)
    Rename(node_id~, new_name~) =>
      compute_rename(ctx, node_id, new_name)
  }
}
```

### Handler functions

Each handler function is package-private, lives in its own file, and takes `EditContext` plus the operation-specific fields:

```moonbit
// text_edit_commit.mbt
fn compute_commit(ctx : EditContext, node_id : NodeId, new_value : String) -> EditResult { ... }

// text_edit_delete.mbt
fn compute_delete(ctx : EditContext, node_id : NodeId) -> EditResult { ... }

// text_edit_drop.mbt
fn compute_drop(ctx : EditContext, source : NodeId, target : NodeId, position : DropPosition) -> EditResult { ... }

// text_edit_wrap.mbt
fn compute_wrap_lambda(ctx : EditContext, node_id : NodeId, var_name : String) -> EditResult { ... }
fn compute_wrap_app(ctx : EditContext, node_id : NodeId) -> EditResult { ... }
fn compute_wrap_if(ctx : EditContext, node_id : NodeId) -> EditResult { ... }
fn compute_wrap_bop(ctx : EditContext, node_id : NodeId, op : @ast.Bop) -> EditResult { ... }
fn compute_insert_child(ctx : EditContext, parent : NodeId, index : Int, kind : @ast.Term) -> EditResult { ... }

// text_edit_structural.mbt
fn compute_unwrap(ctx : EditContext, node_id : NodeId, keep_child_index : Int) -> EditResult { ... }
fn compute_swap_children(ctx : EditContext, node_id : NodeId) -> EditResult { ... }
fn compute_change_operator(ctx : EditContext, node_id : NodeId, new_op : @ast.Bop) -> EditResult { ... }

// text_edit_binding.mbt
fn compute_delete_binding(ctx : EditContext, binding_node_id : NodeId) -> EditResult { ... }
fn compute_duplicate_binding(ctx : EditContext, binding_node_id : NodeId) -> EditResult { ... }
fn compute_move_binding_up(ctx : EditContext, binding_node_id : NodeId) -> EditResult { ... }
fn compute_move_binding_down(ctx : EditContext, binding_node_id : NodeId) -> EditResult { ... }
fn compute_add_binding(ctx : EditContext, module_node_id : NodeId) -> EditResult { ... }

// text_edit_refactor.mbt
fn compute_extract_to_let(ctx : EditContext, node_id : NodeId, var_name : String) -> EditResult { ... }
fn compute_inline_definition(ctx : EditContext, node_id : NodeId) -> EditResult { ... }
fn compute_inline_all_usages(ctx : EditContext, binding_node_id : NodeId) -> EditResult { ... }

// text_edit_rename.mbt (add wrapper, existing helpers updated in Phase 3)
fn compute_rename(ctx : EditContext, node_id : NodeId, new_name : String) -> EditResult { ... }
```

**`AddBinding` delegation:** Currently `AddBinding` recursively calls `compute_text_edit` with a constructed `InsertChild` op. After refactoring, `compute_add_binding` calls `compute_insert_child` directly. This is a safe behavioral equivalence since there is no middleware in Phase 2, and once middleware exists (Phase 4), `AddBinding` already passes through the middleware via `compute_text_edit` before reaching `compute_add_binding` — so re-entering the pipeline is unnecessary.

**`Rename` wrapper:** `text_edit_rename.mbt` gains a `compute_rename` entry-point function that dispatches to the existing `rename_from_var`, `rename_lam_param`, and `rename_binding_by_id` helpers. These helpers are updated to take `EditContext` in Phase 3.

### Middleware layer

The middleware trait uses MoonBit's Self-based pattern (Pattern 3: Capability Traits). Each middleware receives the `next` dispatch function — SuperOOP's `super`:

```moonbit
priv trait EditMiddleware {
  apply(Self, (TreeEditOp, EditContext) -> EditResult, TreeEditOp, EditContext) -> EditResult
}
```

Middleware is invoked directly — no `wrap` closure needed:

```moonbit
pub fn compute_text_edit(op : TreeEditOp, ctx : EditContext) -> EditResult {
  ValidateNodeExists::{}.apply(core_dispatch, op, ctx)
}
```

Example middleware — validate target node exists before dispatching:

```moonbit
priv struct ValidateNodeExists {}

impl EditMiddleware for ValidateNodeExists with apply(_self, next, op, ctx) {
  match extract_primary_node_id(op) {
    Some(id) =>
      if ctx.registry.contains(id) {
        next(op, ctx)
      } else {
        Err("Node not found: " + id.to_string())
      }
    None => next(op, ctx)
  }
}
```

`extract_primary_node_id` returns `None` for no-ops (Select, Collapse, etc.) so they bypass validation, and `Some(node_id)` for structural ops. It lives in `text_edit_middleware.mbt` alongside the trait, exhaustive over all 28 variants.

### Pipeline assembly

Middleware is called directly on the core dispatch — no closure wrapping needed:

```moonbit
pub fn compute_text_edit(op : TreeEditOp, ctx : EditContext) -> EditResult {
  ValidateNodeExists::{}.apply(core_dispatch, op, ctx)
}
```

Future middleware can be chained by nesting: `Outer::{}.apply(fn(op, ctx) { Inner::{}.apply(core_dispatch, op, ctx) }, op, ctx)`.

## File layout

```
projection/
  text_edit.mbt              — EditContext, EditResult, core_dispatch, compute_text_edit
  text_edit_commit.mbt        — compute_commit (~20 lines)
  text_edit_delete.mbt        — compute_delete (~120 lines)
  text_edit_drop.mbt          — compute_drop (~30 lines)
  text_edit_wrap.mbt          — compute_wrap_{lambda,app,if,bop}, compute_insert_child (~200 lines)
  text_edit_structural.mbt    — compute_unwrap, compute_swap_children, compute_change_operator (~150 lines)
  text_edit_binding.mbt       — compute_{delete,duplicate,move_up,move_down,add}_binding (~260 lines)
  text_edit_refactor.mbt      — compute_extract_to_let, compute_inline_{definition,all_usages} (~300 lines)
  text_edit_rename.mbt        — already exists; add compute_rename wrapper, update helpers in Phase 3
  text_edit_utils.mbt         — already exists; shared helpers (find_def_index, binding_delete_range, etc.)
  text_edit_middleware.mbt    — EditMiddleware trait, ValidateNodeExists, extract_primary_node_id
```

## Package boundary

| Symbol | Visibility | Notes |
|--------|-----------|-------|
| `EditContext` | `pub(all)` struct | Constructed via struct literal by `editor/tree_edit_bridge.mbt` |
| `EditResult` | `pub` type alias | Return type of `compute_text_edit` |
| `compute_text_edit` | `pub` fn | Only public entry point |
| `core_dispatch` | private fn | Internal router |
| `compute_delete`, etc. | private fn | Per-file handlers |
| `EditMiddleware` | private trait | Internal composability |
| `ValidateNodeExists` | private struct | Internal middleware |

The call site in `editor/tree_edit_bridge.mbt` changes from:

```moonbit
let result = @proj.compute_text_edit(op, source_text, source_map, registry, flat_proj)
```

to:

```moonbit
let ctx : @proj.EditContext = { source_text, source_map, registry, flat_proj }
let result = @proj.compute_text_edit(op, ctx)
```

## What does NOT change

- `TreeEditOp` enum — untouched
- `TreeEditorState::apply_edit` in `tree_editor.mbt` — untouched
- `parse_tree_edit_op` in `tree_edit_json.mbt` — untouched

## What changes minimally

- `editor/tree_edit_bridge.mbt` — single call site bundles params into `EditContext`
- `projection/text_edit_wbtest.mbt` — test calls updated to use `EditContext` (same values, different shape)
- `projection/pkg.generated.mbti` — regenerated via `moon info` (public signature change)

## Migration strategy

Phases 1-3 are a pure refactor — no behavior changes. Phase 4 is additive — it introduces new validation behavior via middleware.

### Phase 1: Introduce EditContext

1. Add `EditContext` struct and `EditResult` type alias to `text_edit.mbt`
2. Change `compute_text_edit` to take `(TreeEditOp, EditContext)`
3. Update call sites:
   - `editor/tree_edit_bridge.mbt` — construct `EditContext` via struct literal
   - `projection/text_edit_wbtest.mbt` — update all test calls to use `EditContext`
4. Run `moon info` to regenerate `projection/pkg.generated.mbti` (public signature changes)
5. Verify: `moon check && moon test`

### Phase 2: Extract handlers (mechanical, one file at a time)

Extract in order of ascending complexity:

1. `compute_commit` → `text_edit_commit.mbt` (~20 lines)
2. `compute_drop` → `text_edit_drop.mbt` (~30 lines)
3. `compute_unwrap`, `compute_swap_children`, `compute_change_operator` → `text_edit_structural.mbt` (~150 lines)
4. `compute_wrap_*`, `compute_insert_child` → `text_edit_wrap.mbt` (~200 lines)
5. `compute_*_binding` → `text_edit_binding.mbt` (~260 lines)
6. `compute_extract_to_let`, `compute_inline_*` → `text_edit_refactor.mbt` (~300 lines)
7. `compute_delete` → `text_edit_delete.mbt` (~120 lines)
8. `compute_rename` → `text_edit_rename.mbt` (~30-line wrapper that destructures `ctx` and calls existing `rename_from_var`, `rename_lam_param`, `rename_binding_by_id` with individual params)

After each extraction: `moon check && moon test`

### Phase 3: Update helpers

1. Shared helpers in `text_edit_utils.mbt` that take multiple context params (e.g., `get_binding_text_range(source_text, source_map, def)`, `find_let_start(source_text, from)`) keep their current signatures — they are small utilities and coupling them to `EditContext` would reduce reusability. Handler functions destructure `ctx` at their call sites.
2. Update rename helpers (`rename_from_var`, `rename_lam_param`, `rename_binding_by_id`) to accept `EditContext` instead of separate params — these are larger functions that benefit from the bundling. Simplifies the `compute_rename` wrapper from Phase 2.
3. Verify: `moon check && moon test`

### Phase 4: Add middleware layer (additive)

1. Add `text_edit_middleware.mbt` with `EditMiddleware` trait, `ValidateNodeExists`, `extract_primary_node_id`
2. Rename `compute_text_edit` → `core_dispatch` (private), new `compute_text_edit` calls middleware directly (no `wrap` closure — avoids per-call allocation)
3. Verify: `moon check && moon test`

### Phase 5: Simplify and fix bugs

1. Extract shared helpers to `text_edit_utils.mbt`: `find_def_index` (was duplicated 6x), `binding_delete_range` (was duplicated 3x)
2. Fix move-binding scoping: remove over-restrictive guards that blocked valid swaps
3. Fix InlineDefinition cursor: use post-edit coordinates when binding deletion precedes the var
4. Fix Unwrap cursor: use `range.start` (replacement start) instead of kept child's invalidated pre-edit position
5. Add defensive guards: `AddBinding` validates Module target, `InsertChild` rejects negative index, `Unwrap` checks lower bound on `keep_child_index`

## Cost of adding a future operation

After this refactor, adding e.g. `ExtractFunction`:

| Step | File | Change |
|------|------|--------|
| 1 | `projection/tree_lens.mbt` | Add variant to `TreeEditOp` enum |
| 2 | `projection/text_edit.mbt` | Add one line to router |
| 3 | `projection/text_edit_extract_fn.mbt` | **New file** — self-contained handler |
| 4 | `editor/tree_edit_json.mbt` | Add ~5-line JSON parsing arm |
| 5 | `projection/tree_editor.mbt` | Add to catchall group (one line) |

Steps 1, 2, 4, 5 are one-liners. The actual logic lives in one new file.

## Testing

- Phases 1-3: pure refactor. Whitebox tests in `text_edit_wbtest.mbt` require mechanical updates to use `EditContext` (Phase 1), but test logic and assertions are unchanged.
- Phase 4: 1 new test for `ValidateNodeExists` rejecting a missing node ID.
- Phase 5: 5 new tests for bug fixes and defensive guards (move-binding valid swaps, unwrap cursor, negative index, non-Module AddBinding).

## References

- Fan, A. & Parreaux, L. (2023). *super-Charging Object-Oriented Programming Through Precise Typing of Open Recursion.* ECOOP.
- Expression Problem skill — `~/.claude/skills/moonbit-expression-problem/`
- MoonBit trait patterns — `~/.claude/skills/moonbit-traits/`
