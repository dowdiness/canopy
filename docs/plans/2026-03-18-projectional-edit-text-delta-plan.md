# Projectional Edit via Text Delta — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Structural edits produce text span replacements directly via the source map, eliminating the ProjNode → FlatProj → text roundtrip.

**Architecture:** New `compute_text_edit` function translates each `TreeEditOp` into `(start, delete_len, inserted_text)` using the source map. `tree_edit_bridge.mbt` tries the new path first, falls back to the old path for unhandled ops during migration. Once all ops are migrated, the old path is removed.

**Spec:** [docs/plans/2026-03-18-projectional-edit-text-delta-design.md](../plans/2026-03-18-projectional-edit-text-delta-design.md) (in loom repo)

**Worktree:** `/home/antisatori/ghq/github.com/dowdiness/crdt/.worktrees/projectional-edit`

---

## Preflight

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/.worktrees/projectional-edit
moon check && moon test
```

All 232 tests must pass.

---

## File Structure

| File | Role |
|------|------|
| `projection/text_edit.mbt` | **Create.** `SpanEdit` struct + `compute_text_edit` function |
| `projection/text_edit_wbtest.mbt` | **Create.** Whitebox tests for compute_text_edit (needs package-private ProjNode fields) |
| `editor/tree_edit_bridge.mbt` | **Modify.** Dual-path: try compute_text_edit, fall back to old path |
| `projection/tree_lens.mbt` | **Modify (Phase 6).** Remove `apply_edit_to_proj` and helpers |
| `projection/flat_proj.mbt` | **Modify (Phase 6).** Remove `from_proj_node` |

---

## Chunk 1: Foundation + CommitEdit

### Task 1: Create `compute_text_edit` with CommitEdit

**Files:**
- Create: `projection/text_edit.mbt`
- Create: `projection/text_edit_wbtest.mbt` (whitebox — ProjNode fields and NodeId constructor are package-private)

- [ ] **Step 1: Define SpanEdit struct**

Create `projection/text_edit.mbt`:

```moonbit
///|
/// A text span replacement: replace source_text[start : start+delete_len] with inserted.
pub(all) struct SpanEdit {
  start : Int
  delete_len : Int
  inserted : String
} derive(Show, Eq)
```

- [ ] **Step 2: Implement compute_text_edit with CommitEdit case**

In the same file, add:

```moonbit
///|
/// Translate a TreeEditOp into text span edits using the source map.
/// Returns None for unhandled ops (fall back to old path during migration).
/// Returns Some([]) for no-op ops (Select, Collapse, etc.).
pub fn compute_text_edit(
  op : TreeEditOp,
  source_text : String,
  source_map : SourceMap,
  registry : Map[NodeId, ProjNode],
  flat_proj : FlatProj,
) -> Result[Array[SpanEdit]?, String] {
  match op {
    // No-op operations
    Select(_) | SelectRange(_, _) | StartEdit(_) | CancelEdit |
    StartDrag(_) | DragOver(_, _) | Collapse(_) | Expand(_) =>
      Ok(Some([]))
    // CommitEdit: replace node span with new user-provided text
    CommitEdit(node_id~, new_value~) =>
      match source_map.get_range(node_id) {
        None => Err("Node not found: " + node_id.to_string())
        Some(range) =>
          Ok(Some([{ start: range.start, delete_len: range.end - range.start, inserted: new_value }]))
      }
    // Unhandled — fall back to old path
    _ => Ok(None)
  }
}
```

- [ ] **Step 3: Write tests**

Create `projection/text_edit_wbtest.mbt`:

```moonbit
///|
/// Build test state from source text. Returns (proj, source_map, registry, flat_proj).
/// All IDs are consistent — the ProjNode returned is the same one the source map was built from.
fn setup_test_state(text : String) -> (ProjNode, SourceMap, Map[NodeId, ProjNode], FlatProj) {
  let (cst, _) = @parser.parse_cst(text) catch { _ => abort("parse failed") }
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let counter = Ref::new(0)
  let fp = to_flat_proj(syntax, counter)
  let proj = fp.to_proj_node(counter)
  let source_map = SourceMap::from_ast(proj)
  let registry : Map[NodeId, ProjNode] = {}
  fn register(node : ProjNode) {
    registry[NodeId(node.node_id)] = node
    for child in node.children {
      register(child)
    }
  }
  register(proj)
  (proj, source_map, registry, fp)
}

///|
/// Apply span edits to text (in reverse document order) and return the result.
fn apply_edits(text : String, edits : Array[SpanEdit]) -> String {
  let sorted = edits.copy()
  sorted.sort_by(fn(a, b) { b.start.compare(a.start) })
  let mut result = text
  for edit in sorted {
    result = result.substring(start=0, end=edit.start) +
      edit.inserted +
      result.substring(start=edit.start + edit.delete_len)
  }
  result
}

///|
test "compute_text_edit: CommitEdit replaces node span" {
  let text = "let x = 1\nx"
  let (proj, source_map, registry, fp) = setup_test_state(text)
  // proj.children[0] is the init of the first def (Int(1))
  let init_id = NodeId(proj.children[0].node_id)
  let result = compute_text_edit(
    CommitEdit(node_id=init_id, new_value="42"),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some(edits)) => {
      inspect(edits.length(), content="1")
      inspect(apply_edits(text, edits), content="let x = 42\nx")
    }
    _ => abort("expected Some edits")
  }
}

///|
test "compute_text_edit: no-op ops return empty array" {
  let text = "42"
  let (_, source_map, registry, fp) = setup_test_state(text)
  let result = compute_text_edit(
    Select(node_id=NodeId(0)),
    text,
    source_map,
    registry,
    fp,
  )
  inspect(result, content="Ok(Some([]))")
}

///|
test "compute_text_edit: unhandled ops return None" {
  let text = "42"
  let (_, source_map, registry, fp) = setup_test_state(text)
  let result = compute_text_edit(
    Delete(node_id=NodeId(0)),
    text,
    source_map,
    registry,
    fp,
  )
  inspect(result, content="Ok(None)")
}
```

- [ ] **Step 4: Verify tests**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/.worktrees/projectional-edit
moon check && moon test -p dowdiness/crdt/projection -f text_edit_wbtest.mbt
```

Fix compilation issues. The test setup may need adjustment based on actual ProjNode structure and source map behavior. Run `moon test --update` for snapshot strings if needed.

- [ ] **Step 5: Commit**

```bash
git add projection/text_edit.mbt projection/text_edit_wbtest.mbt
git commit -m "feat(projection): add compute_text_edit with CommitEdit case"
```

---

### Task 2: Wire dual-path in tree_edit_bridge

**Files:**
- Modify: `editor/tree_edit_bridge.mbt`

- [ ] **Step 1: Add new-path branch in apply_tree_edit**

Replace the body of `SyncEditor::apply_tree_edit` (lines 13-54) with dual-path logic:

```moonbit
pub fn SyncEditor::apply_tree_edit(
  self : SyncEditor,
  op : @proj.TreeEditOp,
  timestamp_ms : Int,
) -> Result[Unit, String] {
  let old_text = self.get_text()
  let old_cursor = self.get_cursor()

  // New path: try compute_text_edit first
  let source_map = self.get_source_map()
  let registry = self.registry_memo.get()
  let flat_proj = match self.get_flat_proj() {
    Some(fp) => fp
    None => return Err("No FlatProj available")
  }
  match @proj.compute_text_edit(op, old_text, source_map, registry, flat_proj) {
    Ok(Some(edits)) => {
      if edits.is_empty() {
        return Ok(()) // no-op
      }
      // Apply span edits in reverse document order to avoid position shifts.
      // IMPORTANT: use apply_text_edit_internal (not apply_replace_span)
      // because it calls apply_local_text_change to notify the incremental parser.
      let sorted = edits.copy()
      sorted.sort_by(fn(a, b) { b.start.compare(a.start) })
      for edit in sorted {
        self.apply_text_edit_internal(
          edit.start, edit.delete_len, edit.inserted, timestamp_ms,
          true,   // record_undo
          false,  // move_cursor_to_edit_end
        )
      }
      self.move_cursor(old_cursor)
      return Ok(())
    }
    Ok(None) => () // fall through to old path
    Err(msg) => return Err(msg)
  }

  // Old path: apply_edit_to_proj → from_proj_node → print_flat_proj
  let proj = match self.get_proj_node() {
    Some(p) => p
    None => return Err("No ProjNode available")
  }
  let new_proj = match
    @proj.apply_edit_to_proj(proj, op, registry, self.next_node_id) {
    Ok(updated) => updated
    Err(msg) => return Err(msg)
  }
  let new_fp = @proj.FlatProj::from_proj_node(new_proj)
  let new_text = @proj.print_flat_proj(new_fp)
  if old_text == new_text {
    return Ok(())
  }
  self.seed_flat_proj(Some(new_fp))
  self.set_text_and_record(new_text, timestamp_ms)
  self.move_cursor(old_cursor)
  Ok(())
}
```

- [ ] **Step 2: Run all tests**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/.worktrees/projectional-edit
moon check && moon test
```

All 232+ tests must pass. CommitEdit now uses the new path; all other ops fall back.

- [ ] **Step 3: Commit**

```bash
git add editor/tree_edit_bridge.mbt
git commit -m "refactor(editor): dual-path tree edit bridge — new path for CommitEdit"
```

---

## Chunk 2: Remaining Operations

### Task 3: Add Delete case

**Files:**
- Modify: `projection/text_edit.mbt`
- Modify: `projection/text_edit_wbtest.mbt`

- [ ] **Step 1: Add Delete case to compute_text_edit**

In `projection/text_edit.mbt`, add before the `_ => Ok(None)` fallback.

Delete replaces a node's span with a placeholder. Special case: if the parent is an error node, delete the child entirely (no placeholder).

```moonbit
    Delete(node_id~) =>
      match source_map.get_range(node_id) {
        None => Err("Node not found: " + node_id.to_string())
        Some(range) => {
          // Check if parent is an error node — if so, remove entirely
          let is_error_child = registry.iter().any(fn(entry) {
            let (_, parent) = entry
            match parent.kind {
              @ast.Term::Error(_) =>
                parent.children.iter().any(fn(c) { NodeId(c.node_id) == node_id })
              _ => false
            }
          })
          if is_error_child {
            Ok(Some([{ start: range.start, delete_len: range.end - range.start, inserted: "" }]))
          } else {
            let placeholder = match registry.get(node_id) {
              Some(node) => placeholder_text_for_kind(node.kind)
              None => "a"
            }
            Ok(Some([{ start: range.start, delete_len: range.end - range.start, inserted: placeholder }]))
          }
        }
      }
```

- [ ] **Step 2: Write test**

```moonbit
///|
test "compute_text_edit: Delete replaces with placeholder" {
  let text = "let x = 1\nx"
  let (proj, source_map, registry, fp) = setup_test_state(text)
  let init_id = NodeId(proj.children[0].node_id)
  let result = compute_text_edit(
    Delete(node_id=init_id),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some(edits)) => {
      inspect(apply_edits(text, edits), content="let x = 0\nx")
    }
    _ => abort("expected Some edits")
  }
}
```

- [ ] **Step 3: Run tests**

```bash
moon check && moon test -p dowdiness/crdt/projection -f text_edit_wbtest.mbt
```

- [ ] **Step 4: Commit**

```bash
git add projection/text_edit.mbt projection/text_edit_wbtest.mbt
git commit -m "feat(projection): add Delete case to compute_text_edit"
```

---

### Task 4: Add WrapInLambda + WrapInApp cases

**Files:**
- Modify: `projection/text_edit.mbt`
- Modify: `projection/text_edit_wbtest.mbt`

- [ ] **Step 1: Add WrapInLambda case**

```moonbit
    WrapInLambda(node_id~, var_name~) =>
      match source_map.get_range(node_id) {
        None => Err("Node not found: " + node_id.to_string())
        Some(range) => {
          let existing = match registry.get(node_id) {
            Some(node) => @ast.print_term(node.kind)
            None => return Err("Node not found in registry")
          }
          let wrapped = "(λ" + var_name + ". " + existing + ")"
          Ok(Some([{ start: range.start, delete_len: range.end - range.start, inserted: wrapped }]))
        }
      }
```

- [ ] **Step 2: Add WrapInApp case**

```moonbit
    WrapInApp(node_id~) =>
      match source_map.get_range(node_id) {
        None => Err("Node not found: " + node_id.to_string())
        Some(range) => {
          let existing = match registry.get(node_id) {
            Some(node) => @ast.print_term(node.kind)
            None => return Err("Node not found in registry")
          }
          let wrapped = "(" + existing + ") a"
          Ok(Some([{ start: range.start, delete_len: range.end - range.start, inserted: wrapped }]))
        }
      }
```

- [ ] **Step 3: Write tests**

```moonbit
///|
test "compute_text_edit: WrapInLambda wraps node in lambda" {
  let text = "42"
  let (proj, source_map, registry, fp) = setup_test_state(text)
  let root_id = NodeId(proj.node_id)
  let result = compute_text_edit(
    WrapInLambda(node_id=root_id, var_name="x"),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some(edits)) => {
      inspect(apply_edits(text, edits), content="(λx. 42)")
    }
    _ => abort("expected Some edits")
  }
}
```

- [ ] **Step 4: Run tests**

```bash
moon check && moon test -p dowdiness/crdt/projection -f text_edit_wbtest.mbt
```

- [ ] **Step 5: Commit**

```bash
git add projection/text_edit.mbt projection/text_edit_wbtest.mbt
git commit -m "feat(projection): add WrapInLambda and WrapInApp to compute_text_edit"
```

---

### Task 5: Add InsertChild case

**Files:**
- Modify: `projection/text_edit.mbt`
- Modify: `projection/text_edit_wbtest.mbt`

- [ ] **Step 1: Add InsertChild case**

InsertChild needs to determine the insertion position within the parent. For Module parents (flat defs), use FlatProj def positions. For other parents, re-render the whole parent with the new child inserted.

```moonbit
    InsertChild(parent~, index~, kind~) => {
      let placeholder = placeholder_text_for_kind(kind)
      match registry.get(parent) {
        None => Err("Parent not found: " + parent.to_string())
        Some(parent_node) =>
          match source_map.get_range(parent) {
            None => Err("Parent not in source map")
            Some(parent_range) =>
              match parent_node.kind {
                @ast.Term::Module(_, _) => {
                  // Flat defs: insert between defs using FlatProj positions
                  let insert_text = "\nlet x = " + placeholder
                  let insert_pos = if index >= parent_node.children.length() {
                    // Insert at end (before body)
                    let body = parent_node.children[parent_node.children.length() - 1]
                    match source_map.get_range(NodeId(body.node_id)) {
                      Some(r) => r.start
                      None => parent_range.end
                    }
                  } else {
                    match source_map.get_range(NodeId(parent_node.children[index].node_id)) {
                      Some(r) => r.start
                      None => parent_range.start
                    }
                  }
                  Ok(Some([{ start: insert_pos, delete_len: 0, inserted: insert_text }]))
                }
                _ => {
                  // Non-Module parent: re-render whole parent with child inserted
                  let new_child_node = ProjNode::new(kind, 0, 0, 0, [])
                  let new_parent = insert_child_at(parent_node, index, new_child_node)
                  let new_text = @ast.print_term(new_parent.kind)
                  Ok(Some([{ start: parent_range.start, delete_len: parent_range.end - parent_range.start, inserted: new_text }]))
                }
              }
          }
      }
    }
```

- [ ] **Step 2: Write test**

```moonbit
///|
test "compute_text_edit: InsertChild into Module inserts def" {
  let text = "let x = 1\nx"
  let (proj, source_map, registry, fp) = setup_test_state(text)
  let module_id = NodeId(proj.node_id)
  let result = compute_text_edit(
    InsertChild(parent=module_id, index=1, kind=@ast.Term::Int(0)),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some(edits)) => {
      inspect(edits.length(), content="1")
      inspect(edits[0].delete_len, content="0") // pure insertion
    }
    _ => abort("expected Some edits")
  }
}
```

- [ ] **Step 3: Run tests**

```bash
moon check && moon test -p dowdiness/crdt/projection -f text_edit_wbtest.mbt
```

- [ ] **Step 4: Commit**

```bash
git add projection/text_edit.mbt projection/text_edit_wbtest.mbt
git commit -m "feat(projection): add InsertChild to compute_text_edit"
```

---

### Task 6: Add Drop case

**Files:**
- Modify: `projection/text_edit.mbt`
- Modify: `projection/text_edit_wbtest.mbt`

- [ ] **Step 1: Add Drop case**

Drop is a move: delete at source, insert at target. Two span edits applied in reverse document order.

```moonbit
    Drop(source~, target~, position~) => {
      let source_range = match source_map.get_range(source) {
        Some(r) => r
        None => return Err("Source node not found")
      }
      let target_range = match source_map.get_range(target) {
        Some(r) => r
        None => return Err("Target node not found")
      }
      let source_text_slice = source_text.substring(
        start=source_range.start,
        end=source_range.end,
      )
      let insert_pos = match position {
        Before => target_range.start
        After => target_range.end
        Inside => target_range.start // insert as first child
      }
      // Two edits: delete source, insert at target
      // Will be sorted by reverse document order in tree_edit_bridge
      Ok(Some([
        { start: source_range.start, delete_len: source_range.end - source_range.start, inserted: "" },
        { start: insert_pos, delete_len: 0, inserted: source_text_slice },
      ]))
    }
```

**Note:** The bridge applies edits in reverse document order (highest start first), so position arithmetic is correct regardless of whether source is before or after target.

- [ ] **Step 2: Write test**

```moonbit
///|
test "compute_text_edit: Drop produces delete + insert" {
  let text = "let x = 1\nlet y = 2\nx + y"
  let (proj, source_map, registry, fp) = setup_test_state(text)
  let first_init = proj.children[0]
  let second_init = proj.children[1]
  let result = compute_text_edit(
    Drop(source=NodeId(first_init.node_id), target=NodeId(second_init.node_id), position=After),
    text,
    source_map,
    registry,
    fp,
  )
  match result {
    Ok(Some(edits)) => {
      inspect(edits.length(), content="2")
      // Verify result text after applying both edits
      let new_text = apply_edits(text, edits)
      // Source (first init "1") deleted, inserted after target (second init "2")
      // Exact result depends on source map spans — verify in test
      inspect(new_text.length() > 0, content="true")
    }
    _ => abort("expected Some edits")
  }
}
```

- [ ] **Step 3: Run tests**

```bash
moon check && moon test -p dowdiness/crdt/projection -f text_edit_wbtest.mbt
```

- [ ] **Step 4: Run full test suite**

```bash
moon test
```

All tests must pass. All ops now use the new path — no fallback to old path should occur.

- [ ] **Step 5: Commit**

```bash
git add projection/text_edit.mbt projection/text_edit_wbtest.mbt
git commit -m "feat(projection): add Drop to compute_text_edit — all ops migrated"
```

---

## Chunk 3: Cleanup + Verification

### Task 7: Remove old path

**Files:**
- Modify: `editor/tree_edit_bridge.mbt`
- Modify: `projection/tree_lens.mbt`
- Modify: `projection/flat_proj.mbt`

- [ ] **Step 1: Remove fallback in tree_edit_bridge**

Remove the entire old-path section (the `apply_edit_to_proj → from_proj_node → print_flat_proj` block) from `tree_edit_bridge.mbt`. Change the `Ok(None)` case to return an error:

```moonbit
    Ok(None) => return Err("Unhandled tree edit op: " + op.to_string())
```

Remove the comment about "Old path" and the seed_flat_proj call.

- [ ] **Step 2: Remove apply_edit_to_proj and helpers from tree_lens.mbt**

Remove these functions from `projection/tree_lens.mbt`:
- `apply_edit_to_proj` (lines 33-247)
- `find_parent_recursive` (lines 250-264)
- `update_node_in_tree` (lines 267-287)
- `remove_child_at` (lines 290-304)
- `deleted_placeholder` (lines 307-327)
- `insert_child_at` (lines 346-364)
- `get_node_in_tree` (lines 367-379)

Keep:
- `TreeEditOp` enum (lines 5-29)
- `placeholder_text_for_kind` (lines 330-343) — still used by compute_text_edit
- `DropPosition` enum (if it exists)

**Note:** `insert_child_at` is used by `compute_text_edit` for the non-Module InsertChild fallback. Either keep it, move it to `text_edit.mbt`, or inline it. Check before deleting.

- [ ] **Step 3: Remove from_proj_node from flat_proj.mbt**

Remove `FlatProj::from_proj_node` (lines 237-264). It's no longer called in production code.

- [ ] **Step 3b: Update test files that reference removed functions**

**`projection/tree_lens_wbtest.mbt`:** All 8 tests call `apply_edit_to_proj`. Remove or rewrite them as tests for `compute_text_edit` instead. The new tests in `text_edit_wbtest.mbt` already cover the same operations.

**`projection/flat_proj_wbtest.mbt`:** Remove 3 tests that reference `from_proj_node`:
- `"FlatProj::from_proj_node: extracts Module defs"`
- `"FlatProj::from_proj_node: single expression (no Module)"`
- `"FlatProj roundtrip: from_proj_node -> to_proj_node preserves text"`

- [ ] **Step 4: Remove seed_flat_proj usage**

Check if `seed_flat_proj` is still needed. With the new path, tree edits go through `apply_replace_span` which updates the text CRDT directly. The memo chain re-derives FlatProj from the new text. If `seed_flat_proj` is only called from tree_edit_bridge, it can be removed.

Check call sites:
```bash
rg 'seed_flat_proj' --type-add 'mbt:*.mbt' --type mbt
```

- [ ] **Step 5: Run full test suite**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/.worktrees/projectional-edit
moon check && moon test
```

Fix any compilation errors from removed functions (exhaustive matches, unused imports, etc.).

- [ ] **Step 6: Update interfaces**

```bash
moon info && moon fmt
```

- [ ] **Step 7: Commit**

```bash
git add -u
git commit -m "refactor(projection): remove old tree edit path — ProjNode is now read-only"
```

---

### Task 8: Benchmark + final verification

- [ ] **Step 1: Run all tests**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt/.worktrees/projectional-edit
moon check && moon test
```

- [ ] **Step 2: Verify no from_proj_node or apply_edit_to_proj remnants**

```bash
rg 'apply_edit_to_proj|from_proj_node' --type-add 'mbt:*.mbt' --type mbt
```

Expected: no matches in production code. Test files and docs may reference them.

- [ ] **Step 3: Run benchmarks**

```bash
moon bench --release 2>&1 | head -30
```

- [ ] **Step 4: Commit benchmark results if applicable**

---

## Key Design Decisions

1. **`print_term` for wrapping ops** — WrapInLambda/WrapInApp use `print_term(existing.kind)` for the wrapped text, not source text slices. This normalizes formatting but ensures correct parenthesization. Can switch to source slices later for better formatting preservation.

2. **Reverse document order** — Multiple span edits (Drop) are applied in reverse document order (highest start first) to avoid position shifts. The bridge handles this sorting.

3. **InsertChild fallback** — For non-Module parents, InsertChild re-renders the whole parent via `print_term`. This is correct but lossy (normalizes formatting). Module parents use precise position insertion.

4. **`apply_text_edit_internal` over `set_text_and_record`** — The new path uses `apply_text_edit_internal` (precise span edit + parser notification) instead of `set_text_and_record` (full-text diff). This is more efficient — skips the `compute_text_change` diff computation — and correctly notifies the incremental parser via `apply_local_text_change`. Do NOT use `apply_replace_span` directly — it lacks the parser notification step.

5. **`insert_child_at` + `rebuild_kind` retention** — The non-Module InsertChild fallback re-renders the parent with a new child. This requires `insert_child_at` and `rebuild_kind` from `tree_lens.mbt`. Move these to `text_edit.mbt` during cleanup, or keep them in `tree_lens.mbt`.
