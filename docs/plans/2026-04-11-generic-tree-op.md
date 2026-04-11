# Generic Tree Op: Decouple projection/ from lang/lambda/edits

## Problem

`projection/tree_editor.mbt` imports `TreeEditOp` from `lang/lambda/edits`. This is a dependency inversion: a language-agnostic package (projection) depends on a language-specific package (lambda). Adding tree editing for a new language would require either routing through lambda's type or modifying projection.

Of TreeEditOp's 27 variants, projection meaningfully handles only 11 generic ones. The remaining 16 lambda-specific variants (WrapInLambda, WrapInBop, ExtractToLet, InlineDefinition, Rename, DeleteBinding, etc.) share a single catch-all behavior: clear editing state.

## Goal

- Remove `projection/moon.pkg` dependency on `lang/lambda/edits`
- Define a language-agnostic op type in `core/` that projection uses
- Lambda (and future languages) map their domain-specific ops to the generic type
- Near-zero behavior change (one minor tightening — see Design Notes)

## Design

### New type in core/

```moonbit
pub enum GenericTreeOp {
  // Selection
  Select(node_id~ : NodeId)
  SelectRange(start~ : NodeId, end~ : NodeId)

  // Inline editing
  StartEdit(node_id~ : NodeId)
  CommitEdit(node_id~ : NodeId, new_value~ : String)
  CancelEdit

  // Structural (generic)
  Delete(node_id~ : NodeId)
  StructuralEdit(node_id~ : NodeId)
  InsertChild(parent~ : NodeId, index~ : Int)

  // Drag and drop
  StartDrag(node_id~ : NodeId)
  DragOver(target~ : NodeId, position~ : DropPosition)
  Drop(source~ : NodeId, target~ : NodeId, position~ : DropPosition)

  // Navigation
  Collapse(node_id~ : NodeId)
  Expand(node_id~ : NodeId)
}
```

Design notes:

- **StructuralEdit(node_id~)** replaces all lambda-specific variants (WrapInLambda, Unwrap, SwapChildren, WrapInIf, WrapInBop, ChangeOperator, ExtractToLet, InlineDefinition, Rename) plus all binding-level ops (DeleteBinding, DuplicateBinding, MoveBindingUp, MoveBindingDown, AddBinding, InlineAllUsages). Projection's only behavior for all of these is `{ ..self, editing_node: None, edit_value: "" }` — clear editing state.
- **InsertChild** drops the `kind~ : @ast.Term` field. Projection ignores it today (line 106: `let _ = (index, kind)`). If a future language needs kind-aware insertion in projection state, add a `data~ : String?` field then.
- **WrapInLambda and WrapInApp** currently do `{ ..self, selection: [node_id] }` — keep the wrapped node selected, but do NOT clear editing state. `StructuralEditKeepSelected` will both select the node AND clear editing state (`editing_node: None, edit_value: ""`). This is a minor behavior tightening: wrapping while editing is not a supported workflow, and the extra clear is strictly safer (prevents stale editing state from leaking through structural operations).

Revised:

```moonbit
pub enum GenericTreeOp {
  Select(node_id~ : NodeId)
  SelectRange(start~ : NodeId, end~ : NodeId)
  StartEdit(node_id~ : NodeId)
  CommitEdit(node_id~ : NodeId, new_value~ : String)
  CancelEdit
  Delete(node_id~ : NodeId)
  StructuralEdit(node_id~ : NodeId)          // clears editing state
  StructuralEditKeepSelected(node_id~ : NodeId) // clears editing + selects node_id
  InsertChild(parent~ : NodeId, index~ : Int)   // selects parent
  StartDrag(node_id~ : NodeId)
  DragOver(target~ : NodeId, position~ : DropPosition)
  Drop(source~ : NodeId, target~ : NodeId, position~ : DropPosition)
  Collapse(node_id~ : NodeId)
  Expand(node_id~ : NodeId)
}
```

### Mapping in lang/lambda/edits

Add a function that maps TreeEditOp → GenericTreeOp:

```moonbit
pub fn TreeEditOp::to_generic(self : TreeEditOp) -> GenericTreeOp
```

This is a pure match that:
- Select → Select, SelectRange → SelectRange, etc. (11 pass-through)
- WrapInLambda, WrapInApp → StructuralEditKeepSelected(node_id~)
- InsertChild → InsertChild(parent~, index~) (drops `kind`)
- All remaining structural/binding ops → StructuralEdit(node_id~)

### Changes to projection/tree_editor.mbt

`TreeEditorState::apply_edit` changes signature from `TreeEditOp` to `GenericTreeOp`. The match body is simplified — no more catch-all for 16+ lambda variants.

### Callsite migration

There are 4 callsite categories:

1. **projection/tree_editor_refresh.mbt** (lines 747, 749): Internal calls using `Expand(node_id~)`. These construct `TreeEditOp::Expand` today. Will construct `GenericTreeOp::Expand` directly — same syntax.

2. **projection/tree_editor_wbtest.mbt** (~40 calls): Tests construct TreeEditOp variants directly (Select, Collapse, Expand, Delete, StartDrag, DragOver, WrapInLambda, StartEdit, SelectRange). After migration, these construct GenericTreeOp variants. For `WrapInLambda`, tests use `StructuralEditKeepSelected`.

3. **examples/ideal/main/main.mbt** (lines 472-601): App code constructs `@lambda_edits.Select`, `@lambda_edits.Expand`, `@lambda_edits.Collapse`, `@lambda_edits.Select`. After migration, these construct `@core.GenericTreeOp::Select`, etc. directly.

4. **ffi/ and lang/lambda/companion/**: These construct `TreeEditOp` for lambda's text-edit pipeline, not for projection's apply_edit. **No change needed** — they continue using `TreeEditOp` for `compute_text_edit`. The `apply_edit` call in examples is separate from the text-edit pipeline.

## Steps

### Step 1: Add GenericTreeOp to core/

- Create `core/generic_tree_op.mbt`
- Define `pub enum GenericTreeOp` with 14 variants
- Add `derive(Debug)` and `Show` impl
- **Compile break**: None — additive change

**Verify**: `moon check` in root

### Step 2: Add TreeEditOp::to_generic in lang/lambda/edits

- Add `core/generic_tree_op.mbt` mapping function in `lang/lambda/edits/tree_lens.mbt`
- Pure mapping, no logic change

**Compile break**: None — additive change

**Verify**: `moon check` in root

### Step 3: Migrate projection/tree_editor.mbt

- Remove `using @lambda_edits {type TreeEditOp}` import
- Change `apply_edit` signature: `TreeEditOp` → `GenericTreeOp`
- Rewrite match body using GenericTreeOp variants
- Remove `@lambda_edits` from `projection/moon.pkg`

**Compile break**: Yes — all callers of `TreeEditorState::apply_edit` break because the parameter type changed. This includes:
  - `projection/tree_editor_refresh.mbt` (2 calls)
  - `projection/tree_editor_wbtest.mbt` (~40 calls)
  - `examples/ideal/main/main.mbt` (5 calls)

**Fix**: Steps 4-6 fix these.

**Verify**: `moon check` will fail until Steps 4-6 complete.

### Step 4: Fix projection internal callsites

- `projection/tree_editor_refresh.mbt` lines 747, 749: Change `Expand(node_id~)` — no prefix change needed since GenericTreeOp is now in scope via core.
- Import `using @core {type GenericTreeOp}` at top of file if bare constructors don't resolve.

**Verify**: `moon check` — projection should compile (wbtest may still fail)

### Step 5: Fix projection tests

- `projection/tree_editor_wbtest.mbt`: Replace all `TreeEditOp::*` / bare `Select(...)` etc. with `GenericTreeOp::*` variants.
- `WrapInLambda(node_id=root_id, var_name="y")` → `StructuralEditKeepSelected(node_id=root_id)` (test on line 431 checks that selection is preserved — behavior unchanged)

**Verify**: `moon check && moon test` in projection/

### Step 6: Fix examples/ideal callsite

- `examples/ideal/main/main.mbt`: Replace `@lambda_edits.Select(...)`, `@lambda_edits.Expand(...)`, `@lambda_edits.Collapse(...)` with `@core.GenericTreeOp::Select(...)`, etc.
- `examples/ideal/main/view_outline.mbt`: Constructs `@lambda_edits.Expand`/`Collapse` at lines 58, 60, and 219-221. Under option (b) these stay as-is since the message still carries `TreeEditOp`. No code change needed, but audit to confirm.
- Remove `@lambda_edits` import if it's no longer used for TreeEdited messages. (Check: the `TreeEdited(op)` message type carries `TreeEditOp` — this may still need `@lambda_edits` for the message enum definition. If so, the callsite calls `.to_generic()` before passing to `apply_edit`.)

**Compile break**: The `TreeEdited(op)` message likely carries `TreeEditOp` from the outline view. Two options:
  a. Change the message to carry `GenericTreeOp` (cleanest — outline only sends generic ops)
  b. Keep `TreeEditOp` in message, call `op.to_generic()` before `apply_edit` (minimal change)

Option (b) is safer for this PR. Option (a) can follow if the message type is revisited.

**Verify**: `moon check && moon test` in root

### Step 7: Clean up projection/moon.pkg

- Verify `dowdiness/canopy/lang/lambda/edits` is no longer in import list
- Verify wbtest imports for lambda are still present (tests use lambda AST for test data)

**Verify**: `grep 'lambda/edits' projection/moon.pkg` returns only test imports

### Step 8: Run full verification

- `moon check` — full project
- `moon test` — all tests pass
- `moon info && moon fmt` — interfaces updated
- `git diff *.mbti` — verify only expected API changes:
  - `core/pkg.generated.mbti` gains `GenericTreeOp`
  - `projection/pkg.generated.mbti` changes `apply_edit(TreeEditOp)` → `apply_edit(GenericTreeOp)`
  - `lang/lambda/edits/pkg.generated.mbti` gains `TreeEditOp::to_generic`
- No other `.mbti` files change

## Invariants

- `TreeEditorState::apply_edit` behavior is identical for all generic variants except one minor tightening: `StructuralEditKeepSelected` now also clears editing state, where `WrapInLambda`/`WrapInApp` previously did not
- Lambda's text-edit pipeline (`compute_text_edit`) is completely untouched — it still uses `TreeEditOp`
- No FFI surface changes (ffi/ doesn't call `apply_edit` directly)
- projection/moon.pkg has zero lang/* dependencies in production imports

## Test Plan

- Existing projection tests (tree_editor_wbtest.mbt) migrated to GenericTreeOp — same assertions
- Add one new test: `StructuralEdit` clears editing state (replaces implicit coverage from lambda-specific variant tests)
- `moon test` across root + submodules
- Manual: web dev server, lambda editor — outline tree operations (select, collapse, expand, drag) still work

## Risk

**Low.** Type-system-guided migration — the compiler catches every broken callsite. One minor behavior tightening (StructuralEditKeepSelected clears editing state — benign, prevents stale state). No FFI surface change. Reversible with a single revert.
