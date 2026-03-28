# Framework Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract a generic projectional editor framework (`framework/`) from the lambda-specific code, with `lang/lambda/` as the first consumer. Acid test: `framework/` compiles with zero `@ast` or `@lambda` imports.

**Design reference:** `docs/plans/2026-03-18-framework-extraction-design.md`

**Current state:** Phase 2 complete (2026-03-28). `lang/lambda/flat/` created with `VersionedFlatProj`.
`FlatProj` stays in `projection/` until Phase 4 (circular dep: `text_edit.mbt` uses `FlatProj`).
Phase 3 (extract `framework/`) is next.

**Phase 1 summary:** `EditAction[T]`, Tier-2 edit methods (`delete_node`, `commit_edit`, `apply_text_transform`, `move_node`), and `is_dirty`/`refresh` boundary live in `projection/` and `editor/`. Package structure not yet extracted. FlatProj still in `projection/`.

**Module:** `dowdiness/canopy` (root `moon.mod.json`)

---

## Phase overview

| Phase | Tasks | Risk | PR | Status |
|-------|-------|------|----|----|
| 1 — Additive API | 1–3 | Low | [#60](https://github.com/dowdiness/canopy/pull/60) | ✅ Done |
| 2 — Create lang/lambda/flat/ | 4 | Low | 2 | ✅ Done |
| 3 — Extract framework/ | 5–7 | High | 3 | Not started |
| 4 — Extract lang/lambda/ | 8 | High | 4 | Blocked on TermSym |
| 5 — Verification | 9 | Low | 5 | Not started |

Each phase must pass `moon test` before moving to the next.

---

## Phase 1 — Additive API

No file moves. All tasks are purely additive. Can be done in a single PR.

---

### Task 1: Add `EditAction[T]` struct

**File:** `projection/traits.mbt` (append after existing trait definitions)

- [x] **Step 1: Add `EditAction[T]` to `projection/traits.mbt`**

```moonbit
///|
/// A language-specific structural edit action for UI discovery (context menus, palette).
/// Language packages export these as data; the UI renders them without knowing their semantics.
pub struct EditAction[T] {
  /// Display label for the action
  label : String
  /// Optional keyboard shortcut (e.g., "Ctrl+D")
  shortcut : String?
  /// Predicate: is this action applicable to the given node?
  applicable : (@proj.ProjNode[T], NodeId) -> Bool
  /// Compute replacement text given (source_text, span_start, span_end).
  /// Returns Ok(replacement) or Err(reason).
  compute_replacement : (String, Int, Int) -> Result[String, String]
}
```

- [x] **Step 2: Verify compilation**

```bash
cd /path/to/canopy && moon check
```

Expected: no errors.

- [x] **Step 3: Commit**

```bash
git add projection/traits.mbt
git commit -m "feat(projection): add EditAction[T] struct for UI-discoverable structural edits"
```

---

### Task 2: Add generic Tier-2 edit methods to `SyncEditor[T]`

These methods work purely from `SourceMap` span lookups + `apply_text_edit_internal`.
They do **not** use `FlatProj`, `TreeEditOp`, or any lambda-specific code.

**New file:** `editor/sync_editor_tree_edit.mbt`

- [x] **Step 1: Create `editor/sync_editor_tree_edit.mbt`**

```moonbit
// Generic Tier-2 structural edit methods for SyncEditor[T].
// All edits reduce to: span lookup → compute replacement text → apply_text_edit_internal.
// No FlatProj, no TreeEditOp, no lambda-specific logic.

///|
/// Delete a node by replacing its source span with the node's placeholder text.
/// Uses T::placeholder(node.kind) so deletion leaves a parseable hole.
///
/// Example: deleting `(f x)` in lambda → leaves `?`
pub fn[T : @proj.TreeNode + @proj.Renderable] SyncEditor::delete_node(
  self : SyncEditor[T],
  node_id : @proj.NodeId,
  timestamp_ms : Int,
) -> Result[Unit, String] {
  let range = match self.get_node_range(node_id) {
    None => return Err("delete_node: node \{node_id} not in source map")
    Some(r) => r
  }
  let node = match self.get_node(node_id) {
    None => return Err("delete_node: node \{node_id} not in registry")
    Some(n) => n
  }
  let placeholder = @proj.Renderable::placeholder(node.kind)
  let delete_len = range.end_ - range.start
  self.apply_text_edit_internal(
    range.start, delete_len, placeholder, timestamp_ms,
    record_undo=true, move_cursor_to_edit_end=false,
  )
  Ok(())
}

///|
/// Replace a node's source span with `new_text`.
/// The new text is inserted verbatim — the caller is responsible for
/// providing syntactically valid replacement text.
///
/// Example: committing an inline rename edit.
pub fn[T : @proj.TreeNode + @proj.Renderable] SyncEditor::commit_edit(
  self : SyncEditor[T],
  node_id : @proj.NodeId,
  new_text : String,
  timestamp_ms : Int,
) -> Result[Unit, String] {
  let range = match self.get_node_range(node_id) {
    None => return Err("commit_edit: node \{node_id} not in source map")
    Some(r) => r
  }
  let delete_len = range.end_ - range.start
  self.apply_text_edit_internal(
    range.start, delete_len, new_text, timestamp_ms,
    record_undo=true, move_cursor_to_edit_end=true,
  )
  Ok(())
}

///|
/// Apply a language-provided text transform to a node's source span.
/// The closure receives (source_text, span_start, span_end) and returns
/// the replacement text. The framework handles span lookup → apply.
///
/// Example:
///   editor.apply_text_transform(node_id, fn(src, s, e) {
///     Ok("(λx. " + src.substring(s, e) + ")")
///   }, timestamp)
pub fn[T : @proj.TreeNode + @proj.Renderable] SyncEditor::apply_text_transform(
  self : SyncEditor[T],
  node_id : @proj.NodeId,
  compute_replacement : (String, Int, Int) -> Result[String, String],
  timestamp_ms : Int,
) -> Result[Unit, String] {
  let range = match self.get_node_range(node_id) {
    None => return Err("apply_text_transform: node \{node_id} not in source map")
    Some(r) => r
  }
  let source = self.get_text()
  let replacement = match compute_replacement(source, range.start, range.end_) {
    Err(msg) => return Err("apply_text_transform: \{msg}")
    Ok(r) => r
  }
  let delete_len = range.end_ - range.start
  self.apply_text_edit_internal(
    range.start, delete_len, replacement, timestamp_ms,
    record_undo=true, move_cursor_to_edit_end=false,
  )
  Ok(())
}

///|
/// Move a node to a new position in the tree by:
///   1. Unparsing the source node via T::unparse
///   2. Deleting the source span (replace with placeholder)
///   3. Inserting the unparsed text adjacent to the target span
///
/// CAUTION: Insert position must be adjusted when source precedes target
/// in the document (deletion shifts subsequent offsets backward by
/// `source_len - placeholder_len`). This method handles the adjustment.
pub fn[T : @proj.TreeNode + @proj.Renderable] SyncEditor::move_node(
  self : SyncEditor[T],
  source_id : @proj.NodeId,
  target_id : @proj.NodeId,
  position : @proj.DropPosition,
  timestamp_ms : Int,
) -> Result[Unit, String] {
  // Resolve source
  let src_range = match self.get_node_range(source_id) {
    None => return Err("move_node: source \{source_id} not in source map")
    Some(r) => r
  }
  let src_node = match self.get_node(source_id) {
    None => return Err("move_node: source \{source_id} not in registry")
    Some(n) => n
  }
  // Resolve target
  let tgt_range = match self.get_node_range(target_id) {
    None => return Err("move_node: target \{target_id} not in source map")
    Some(r) => r
  }
  let src_text = @proj.Renderable::unparse(src_node.kind)
  let placeholder = @proj.Renderable::placeholder(src_node.kind)
  let src_len = src_range.end_ - src_range.start
  let shift = placeholder.length() - src_len // negative if placeholder is shorter

  // Step 1: delete source span (replace with placeholder)
  self.apply_text_edit_internal(
    src_range.start, src_len, placeholder, timestamp_ms,
    record_undo=true, move_cursor_to_edit_end=false,
  )

  // Step 2: compute insert position, adjusting for source deletion if source < target
  let tgt_insert = match position {
    Before => tgt_range.start
    After  => tgt_range.end_
    Inside => tgt_range.end_ // insert after opening — language-specific; best effort
  }
  let adjusted_insert = if src_range.start < tgt_insert {
    tgt_insert + shift
  } else {
    tgt_insert
  }

  // Step 3: insert src_text + separator at adjusted position
  // Separator is a space — language-specific grammars may need wrapping.
  // Use apply_text_transform with a custom closure for precise control.
  self.apply_text_edit_internal(
    adjusted_insert, 0, src_text + " ", timestamp_ms,
    record_undo=true, move_cursor_to_edit_end=false,
  )
  Ok(())
}
```

> **Note on `apply_text_edit_internal` named args:** Check the actual signature in
> `editor/sync_editor_text.mbt` — it uses positional args, not labelled args.
> Adjust the call sites above to match the real signature.

- [x] **Step 2: Verify compilation**

```bash
moon check
```

Expected: no errors. If `apply_text_edit_internal` uses positional args, fix the calls.

- [x] **Step 3: Add tests in `editor/sync_editor_tree_edit_wbtest.mbt`**

```moonbit
// Whitebox tests for generic Tier-2 tree edit methods.
// Uses SyncEditor[@ast.Term] via the lambda convenience constructor.

///|
test "delete_node replaces span with placeholder" {
  let editor = @editor.SyncEditor::new_lambda("")
  editor.set_text("(λx. x)")
  editor.mark_dirty()
  // Force memo evaluation
  let _ = editor.get_proj_node()
  let _ = editor.get_source_map()
  // Find the root node id
  match editor.get_proj_node() {
    None => fail("no proj node")
    Some(root) => {
      let result = editor.delete_node(root.node_id, 0)
      inspect(result is Ok(_), content="true")
      // Text should now be the placeholder for a Term node
      // (exact placeholder depends on Term::placeholder impl)
    }
  }
}

///|
test "commit_edit replaces span with new text" {
  let editor = @editor.SyncEditor::new_lambda("x")
  editor.mark_dirty()
  let _ = editor.get_proj_node()
  let _ = editor.get_source_map()
  match editor.get_proj_node() {
    None => fail("no proj node")
    Some(root) => {
      let result = editor.commit_edit(root.node_id, "y", 0)
      inspect(result is Ok(_), content="true")
      inspect(editor.get_text(), content="y")
    }
  }
}

///|
test "apply_text_transform wraps node in lambda" {
  let editor = @editor.SyncEditor::new_lambda("x")
  editor.mark_dirty()
  let _ = editor.get_proj_node()
  let _ = editor.get_source_map()
  match editor.get_proj_node() {
    None => fail("no proj node")
    Some(root) => {
      let result = editor.apply_text_transform(root.node_id, fn(src, s, e) {
        Ok("(λy. " + src.substring(s, e) + ")")
      }, 0)
      inspect(result is Ok(_), content="true")
      inspect(editor.get_text(), content="(λy. x)")
    }
  }
}
```

- [x] **Step 4: Run tests**

```bash
moon test -p dowdiness/canopy/editor
```

Expected: new tests pass. Fix any `apply_text_edit_internal` signature mismatches.

- [x] **Step 5: Commit**

```bash
git add editor/sync_editor_tree_edit.mbt editor/sync_editor_tree_edit_wbtest.mbt
git commit -m "feat(editor): add generic Tier-2 tree edit methods (delete_node, commit_edit, apply_text_transform, move_node)"
```

---

### Task 3: Add `is_dirty` / `refresh` boundary to `SyncEditor[T]`

Currently memos are lazily evaluated on first access after an edit. Adding an explicit
`is_dirty` / `refresh` enables consumers to batch edits and refresh on their own schedule.

**Files to modify:**
- `editor/sync_editor.mbt` — add `projection_dirty` field
- `editor/sync_editor_text.mbt` — set dirty flag after text edits

- [x] **Step 1: Add `projection_dirty` field to `SyncEditor[T]` struct** (`editor/sync_editor.mbt`)

Find the struct definition and add:
```moonbit
  priv mut projection_dirty : Bool
```

Initialize to `false` in `SyncEditor::new`.

- [x] **Step 2: Add `is_dirty`, `refresh`, `get_proj_node_if_dirty` to `editor/sync_editor_tree_edit.mbt`**

```moonbit
///|
/// Returns true if any text edit has been applied since the last refresh().
/// Does not force memo evaluation.
pub fn[T] SyncEditor::is_dirty(self : SyncEditor[T]) -> Bool {
  self.projection_dirty
}

///|
/// Forces evaluation of all projection memos and clears the dirty flag.
/// Call this when ready to re-render (e.g., on animation frame).
/// Multiple edits between refresh() calls are processed as a single update.
pub fn[T] SyncEditor::refresh(self : SyncEditor[T]) -> Unit {
  self.projection_dirty = false
  // Force memo evaluation by reading the root memo
  let _ = self.cached_proj_node.get()
  ()
}
```

- [x] **Step 3: Set `projection_dirty = true` after text edits**

In `editor/sync_editor_text.mbt`, find `apply_text_edit_internal` and add
`self.projection_dirty = true` at the end of the function body.

- [x] **Step 4: Run tests**

```bash
moon test
```

Expected: all tests pass.

- [x] **Step 5: Commit**

```bash
git add editor/sync_editor.mbt editor/sync_editor_text.mbt editor/sync_editor_tree_edit.mbt
git commit -m "feat(editor): add is_dirty/refresh projection boundary to SyncEditor[T]"
```

---

## Phase 2 — Create `lang/lambda/flat/` package

**Goal:** Create the `lang/lambda/flat/` package and migrate `VersionedFlatProj` out
of `editor/`. `FlatProj` itself moves in Phase 4 (see architectural note below).

**Architectural note — why FlatProj stays in `projection/` until Phase 4:**
Moving `FlatProj` to `lang/lambda/flat/` creates a circular dependency:
- `lang/lambda/flat/` → `projection/` (needs `ProjNode`, `syntax_to_proj_node`, `reconcile_ast`, etc.)
- `projection/` → `lang/lambda/flat/` (`text_edit.mbt`'s `EditContext.flat_proj : FlatProj`)

The cycle breaks naturally in Phase 4 when `text_edit*`, `scope`, and other
lambda-specific files in `projection/` all move to `lang/lambda/`. At that point,
`projection/` no longer depends on `lang/lambda/flat/` so the dependency is one-way.

**Phase 3 prerequisite:** Extracting `framework/` in Phase 3 also clears the path:
after Phase 3, `lang/lambda/flat/` can import `framework/core/` (for `ProjNode`, etc.)
instead of `projection/`, so `projection/` can safely import `lang/lambda/flat/`.
However, Phase 3 alone is not sufficient — `flat_proj.mbt` also calls package-private
helpers in `projection/` (`next_proj_node_id`, `error_node_for_syntax` from `proj_node.mbt`;
`assign_fresh_ids` from `reconcile_ast.mbt`). These will need to be made public or
co-located before the move is mechanically possible.

---

### Task 4: Create `lang/lambda/flat/` and move `VersionedFlatProj` ✅ Done (PR #62)

**Files created:**
- `lang/lambda/flat/moon.pkg` — imports `@proj` and `@incr`
- `lang/lambda/flat/versioned_flat_proj.mbt` — `pub(all) struct VersionedFlatProj` + impls

**Files modified:**
- `editor/moon.pkg` — added `"dowdiness/canopy/lang/lambda/flat" @lambda_flat`
- `editor/projection_memo.mbt` — replaced local `priv struct VersionedFlatProj` with `@lambda_flat.VersionedFlatProj`
- `editor/sync_editor.mbt` — updated `proj_memo` field and `build_memos` closure type to use `@lambda_flat.VersionedFlatProj`

**Deferred to Phase 4:**
- Moving `projection/flat_proj.mbt` → `lang/lambda/flat/flat_proj.mbt`
- Moving `projection/text_edit*.mbt`, `projection/scope.mbt`, etc. → `lang/lambda/`
- Removing lambda-specific files from `projection/`

- [x] **Step 1: Create `lang/lambda/flat/moon.pkg`**

- [x] **Step 2: Create `lang/lambda/flat/versioned_flat_proj.mbt`** (extracted from `editor/projection_memo.mbt`)

- [x] **Step 3: Update `editor/projection_memo.mbt`** (removed local struct, uses `@lambda_flat.VersionedFlatProj`)

- [x] **Step 4: Run full test suite** (508 tests pass)

- [x] **Step 5: Commit** (`refactor: create lang/lambda/flat/ and move VersionedFlatProj there`)

---

## Phase 3 — Extract `framework/` packages

**Goal:** Extract the purely generic code from `projection/` and `editor/` into three
framework packages. After this phase, framework code has no `@ast` dependency.

The generic files to extract from `projection/` (verified by the Explore agent):
- `projection/types.mbt` — NodeId, DropPosition, FocusHint, Range alias
- `projection/traits.mbt` — TreeNode, Renderable, EditAction[T]
- `projection/proj_node.mbt` — ProjNode[T] (generic parts)
- `projection/reconcile_ast.mbt` — reconcile[T] using same_kind
- `projection/source_map.mbt` — SourceMap (generic parts)
- `projection/proj_node_json.mbt` — JSON serialization
- `projection/tree_editor_model.mbt` — TreeEditorState[T]
- `projection/tree_editor.mbt` — tree editor operations
- `projection/tree_editor_refresh.mbt` — refresh algorithm

> **Before starting:** Grep each file for `@ast` to confirm it is truly generic.
> Any `@ast` references must be resolved (either the file moves to lang/lambda/, or the
> lambda-specific parts are split out) before the file can move to framework/.

---

### Task 5: Create `framework/traits/`

**Files:** `framework/traits/traits.mbt` (from `projection/traits.mbt`)

- [ ] **Step 1: Create `framework/traits/moon.pkg`**

```json
{
  "import": []
}
```

No dependencies — traits are pure abstractions.

- [ ] **Step 2: Move `projection/traits.mbt` → `framework/traits/traits.mbt`**

The file content is already generic. Update any package-qualified references if needed.

- [ ] **Step 3: Update `projection/moon.pkg`**

Replace the `traits.mbt` definitions with an import:
```
"dowdiness/canopy/framework/traits" @framework_traits,
```

Then audit all files in `projection/` that use `TreeNode` or `Renderable` — replace
`@proj.TreeNode` / `@proj.Renderable` with `@framework_traits.TreeNode` etc.

- [ ] **Step 4: Update `editor/moon.pkg`**

Add `"dowdiness/canopy/framework/traits" @framework_traits`.
Replace all `@proj.TreeNode` / `@proj.Renderable` in `editor/` files.

- [ ] **Step 5: Run `moon check` and `moon test`**

Expected: all pass. Fix any import path issues.

- [ ] **Step 6: Commit**

```bash
git commit -m "refactor: extract framework/traits/ package (TreeNode, Renderable, EditAction)"
```

---

### Task 6: Create `framework/core/`

**Files to move:**
- `projection/types.mbt` → `framework/core/types.mbt`
- `projection/proj_node.mbt` → `framework/core/proj_node.mbt`
- `projection/reconcile_ast.mbt` → `framework/core/reconcile.mbt`
- `projection/source_map.mbt` → `framework/core/source_map.mbt` (generic parts only)
- `projection/proj_node_json.mbt` → `framework/core/proj_node_json.mbt`

> **Pre-check:** Run `grep -n "@ast" projection/proj_node.mbt projection/source_map.mbt`
> before moving. If any `@ast` references exist, split them out first.

- [ ] **Step 1: Create `framework/core/moon.pkg`**

```json
{
  "import": [
    "dowdiness/loom/core",
    "dowdiness/canopy/framework/traits",
    "moonbitlang/core/json"
  ]
}
```

- [ ] **Step 2: Move the five files listed above**

For each file:
1. `git mv projection/<file>.mbt framework/core/<new_name>.mbt`
2. Update any internal `@proj.*` self-references to use local names
3. Run `moon check` — fix import errors one file at a time

- [ ] **Step 3: Update `projection/moon.pkg`**

Add `"dowdiness/canopy/framework/core" @framework_core`.
Replace remaining `ProjNode`, `NodeId`, `SourceMap`, `Range` usages in `projection/`
with `@framework_core.*`.

- [ ] **Step 4: Update `editor/moon.pkg`**

Add `"dowdiness/canopy/framework/core" @framework_core`.
Replace `@proj.ProjNode`, `@proj.NodeId`, `@proj.SourceMap` in all `editor/` files.

- [ ] **Step 5: Update root `moon.pkg`** (the JS FFI layer)

Replace `@proj.*` types in `crdt_projection.mbt` with `@framework_core.*` as needed.

- [ ] **Step 6: Run full test suite**

```bash
moon test
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git commit -m "refactor: extract framework/core/ package (ProjNode, NodeId, SourceMap, reconcile)"
```

---

### Task 7: Create `framework/editor/`

**Files to move:**
- `projection/tree_editor_model.mbt` → `framework/editor/tree_editor_model.mbt`
- `projection/tree_editor.mbt` → `framework/editor/tree_editor.mbt`
- `projection/tree_editor_refresh.mbt` → `framework/editor/tree_editor_refresh.mbt`
- `editor/sync_editor.mbt` → `framework/editor/sync_editor.mbt`
- `editor/sync_editor_text.mbt` → `framework/editor/sync_editor_text.mbt`
- `editor/sync_editor_sync.mbt` → `framework/editor/sync_editor_sync.mbt`
- `editor/sync_editor_undo.mbt` → `framework/editor/sync_editor_undo.mbt`
- `editor/sync_editor_tree_edit.mbt` → `framework/editor/sync_editor_tree_edit.mbt`

> **Pre-check:** Lambda-specific files stay in `editor/`:
> - `sync_editor_parser.mbt` — references `@ast.Term` via `get_ast`, `get_resolution`, etc.
> - `projection_memo.mbt` — lambda-specific memo builder
> - `tree_edit_bridge.mbt` — routes `TreeEditOp` to lambda edit handlers

- [ ] **Step 1: Create `framework/editor/moon.pkg`**

```json
{
  "import": [
    "dowdiness/event-graph-walker/text",
    "dowdiness/event-graph-walker/undo",
    "dowdiness/incr",
    "dowdiness/loom",
    "dowdiness/text_change",
    "dowdiness/canopy/framework/traits",
    "dowdiness/canopy/framework/core",
    "moonbitlang/core/immut/hashset"
  ]
}
```

- [ ] **Step 2: Move the files listed above one at a time**

For each file, move it and fix imports. The key changes:
- `@proj.ProjNode` → `@framework_core.ProjNode`
- `@proj.TreeNode` → `@framework_traits.TreeNode`
- `@proj.Renderable` → `@framework_traits.Renderable`

Run `moon check` after each file.

- [ ] **Step 3: Update `editor/moon.pkg`**

Remove entries now in `framework/editor/`.
Add `"dowdiness/canopy/framework/editor" @framework_editor`.

- [ ] **Step 4: Update root `moon.pkg` (JS FFI layer)**

Replace `"dowdiness/canopy/editor"` import with `"dowdiness/canopy/framework/editor"` where appropriate.

- [ ] **Step 5: Run full test suite**

```bash
moon test && moon build --target js
```

Expected: all pass, JS build succeeds.

- [ ] **Step 6: Commit**

```bash
git commit -m "refactor: extract framework/editor/ package (SyncEditor[T], TreeEditorState)"
```

---

## Phase 4 — Extract `lang/lambda/` packages

**Goal:** Move all remaining `@ast`-dependent code out of `projection/` into dedicated
`lang/lambda/` packages. After this phase, `projection/` should be empty and removable,
with all code living in `framework/` or `lang/lambda/`.

---

### Task 8: Create `lang/lambda/` sub-packages

**Package plan:**

| New package | Source files |
|-------------|-------------|
| `lang/lambda/traits/` | `projection/traits_term.mbt` |
| `lang/lambda/bridge/` | `projection/scope.mbt`, `projection/free_vars.mbt`, `projection/reconcile_ast.mbt` (if lambda-specific) |
| `lang/lambda/edits/` | `projection/text_edit.mbt`, `projection/text_edit_*.mbt` (all handlers), `projection/actions.mbt` |

- [ ] **Step 1: Create `lang/lambda/traits/` package**

`moon.pkg` imports: `@ast`, `@framework_traits`, `@framework_core`.

Move `projection/traits_term.mbt` here. Run `moon check`.

- [ ] **Step 2: Create `lang/lambda/bridge/` package**

`moon.pkg` imports: `@ast`, `@framework_core`, `@seam`.

Move `projection/scope.mbt`, `projection/free_vars.mbt`. Run `moon check`.

- [ ] **Step 3: Create `lang/lambda/edits/` package**

`moon.pkg` imports: `@ast`, `@framework_core`, `@framework_traits`, `@lambda_flat`, `@lambda_bridge`.

Move all `projection/text_edit*.mbt` and `projection/actions.mbt`.

`EditContext[T]` currently includes `flat_proj : FlatProj`. After FlatProj moved to
`lang/lambda/flat/`, this reference becomes `@lambda_flat.FlatProj`. Verify the import.

- [ ] **Step 4: Update `editor/moon.pkg`**

Update `tree_edit_bridge.mbt` imports to reference new lang/lambda packages.

- [ ] **Step 5: Delete the now-empty `projection/` package (if empty)**

```bash
# Verify nothing remains
ls projection/*.mbt
# If only test files remain, move those to appropriate test dirs
git rm projection/*.mbt
```

- [ ] **Step 6: Run full test suite**

```bash
moon test && moon build --target js
```

Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git commit -m "refactor: extract lang/lambda/ packages (traits, bridge, edits), remove projection/"
```

---

## Phase 5 — Verification

---

### Task 9: `TestExpr` proof tests

Prove the framework compiles and works with a non-lambda AST type.

**New file:** `framework/editor/test_expr_wbtest.mbt` (or a dedicated `framework/test/` package)

- [ ] **Step 1: Define `TestExpr` and implement framework traits**

```moonbit
// Minimal AST type for framework independence testing.
// Deliberately not @ast.Term.

priv enum TestExpr {
  Leaf(String)
  Node(String, Array[TestExpr])
} derive(Show, Eq)

impl @framework_traits.TreeNode for TestExpr with children(self) -> Array[TestExpr] {
  match self { Leaf(_) => []; Node(_, cs) => cs }
}
impl @framework_traits.TreeNode for TestExpr with same_kind(self, other) -> Bool {
  match (self, other) {
    (Leaf(_), Leaf(_)) => true
    (Node(_, _), Node(_, _)) => true
    _ => false
  }
}
impl @framework_traits.Renderable for TestExpr with kind_tag(self) -> String {
  match self { Leaf(_) => "Leaf"; Node(_, _) => "Node" }
}
impl @framework_traits.Renderable for TestExpr with label(self) -> String {
  match self { Leaf(s) => s; Node(tag, _) => tag }
}
impl @framework_traits.Renderable for TestExpr with placeholder(self) -> String {
  "?"
}
impl @framework_traits.Renderable for TestExpr with unparse(self) -> String {
  match self {
    Leaf(s) => s
    Node(tag, cs) =>
      tag + "(" + cs.map(@framework_traits.Renderable::unparse).join(", ") + ")"
  }
}
```

- [ ] **Step 2: Add proof tests**

```moonbit
///|
test "TestExpr: TreeNode and Renderable compile without @ast" {
  let leaf = TestExpr::Leaf("x")
  inspect(@framework_traits.Renderable::label(leaf), content="x")
  inspect(@framework_traits.TreeNode::children(leaf).length(), content="0")
}

///|
test "TestExpr: same_kind is structural only" {
  let a = TestExpr::Leaf("x")
  let b = TestExpr::Leaf("y")
  inspect(@framework_traits.TreeNode::same_kind(a, b), content="true")
}
```

- [ ] **Step 3: Verify `framework/` package has no `@ast` import**

```bash
grep -r "@ast\|dowdiness/lambda" framework/
```

Expected: no matches. If any appear, the extraction is incomplete.

- [ ] **Step 4: Run tests**

```bash
moon test
```

Expected: all pass including new TestExpr tests.

- [ ] **Step 5: Commit**

```bash
git add framework/editor/test_expr_wbtest.mbt
git commit -m "test(framework): add TestExpr proof tests — framework compiles without @lambda"
```

---

## Notes

### Range field names

`Range` is imported from `@loomcore` (`dowdiness/loom/core`). Before implementing
`delete_node` / `commit_edit`, verify the field names:

```bash
grep -n "pub struct Range\|start\|end" loom/loom/src/core/*.mbt | head -20
```

Adjust `range.start` and `range.end_` in Task 2 to match the actual field names.

### `apply_text_edit_internal` signature

The method uses positional (not labelled) args. Check the current signature in
`editor/sync_editor_text.mbt` lines 102–143 before writing the Task 2 call sites.

### Package naming convention

New `moon.pkg` files use string import paths. The alias (`@lambda_flat`, `@framework_core`)
is set in each file's `import` block. Keep aliases short and unambiguous.

### Test count

The current test count is ~311 (in loom) + ~232 (in canopy). All must pass after each
phase. Run `moon test` at the end of every task, not just every phase.

### `projection/` deprecation

`projection/` becomes obsolete after Phase 4. Before deleting it, ensure nothing in
the root `crdt*.mbt` FFI layer imports `@proj` directly. Grep:

```bash
grep -r '"dowdiness/canopy/projection"' .
```
