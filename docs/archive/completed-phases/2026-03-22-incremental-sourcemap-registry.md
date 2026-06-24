**Status:** Complete

# Incremental SourceMap & Registry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the projection pipeline O(changed_subtree) instead of O(all_nodes) per keystroke, enabling 500+ def documents to stay under 16ms.

**Architecture:** FlatProj already knows which defs changed via CST pointer comparison. We thread that change set downstream so Registry and SourceMap can patch in place instead of rebuilding from scratch. A `changed_def_indices` side-channel (Ref) connects the proj_memo to downstream memos. Full rebuild fallback covers def count changes, first parse, and structural reordering.

**Tech Stack:** MoonBit, incr (Memo/Signal reactive system), projection package, editor package

**Key design assumptions:**
- Unchanged defs have stable positions when `physical_equal` holds (guaranteed by CST node interning)
- `reconcile_flat_proj` preserves array order (iterates new_defs in order)
- `SourceMap` struct fields are `pub` (readable cross-package), so no accessor needed for `node_to_range`

---

## File Structure

| File | Responsibility |
|------|---------------|
| `projection/flat_proj.mbt` | **Modify**: Add `changed_indices` output param to `to_flat_proj_incremental` |
| `projection/source_map.mbt` | **Modify**: Add `patch_subtree`, `remove_subtree`, `rebuild_ranges` (make pub), `populate_token_spans_for_indices` |
| `editor/projection_memo.mbt` | **Modify**: Wire change set through memo chain, add patch paths for registry and source_map |
| `projection/flat_proj_wbtest.mbt` | **Modify**: Add tests for changed_indices tracking |
| `projection/source_map_wbtest.mbt` | **Modify**: Add tests for incremental patch |
| `editor/sync_editor_test.mbt` | **Modify**: Add integration tests via SyncEditor (incremental parser gives proper CST sharing) |
| `editor/performance_benchmark.mbt` | **Modify**: Add 320-def and 500-def benchmarks, include `get_source_map()` in bench loop |

---

### Task 1: Track Changed Def Indices in FlatProj

**Files:**
- Modify: `projection/flat_proj.mbt:44-116`
- Test: `projection/flat_proj_wbtest.mbt`

**Important:** `parse_syntax` creates independent CST trees with no `physical_equal` sharing between calls. Tests that parse the same text twice will see ALL defs as changed (different CST objects). Unit tests here verify the parameter plumbing works; integration tests in Task 5 verify correct incremental behavior via SyncEditor.

- [ ] **Step 1: Write failing test for changed_indices parameter**

In `projection/flat_proj_wbtest.mbt`, add:

```moonbit
///|
test "to_flat_proj_incremental: changed_indices records all non-reused defs" {
  // Independent parses — no CST sharing, so ALL defs appear changed
  let counter = Ref::new(0)
  let old_root = parse_syntax("let x = 1\nlet y = 2\nx")
  let old_fp = to_flat_proj(old_root, counter)
  let new_root = parse_syntax("let x = 1\nlet y = 3\nx")
  let changed = Ref::new(([] : Array[Int]))
  let result = to_flat_proj_incremental(
    new_root, old_root, old_fp, counter, changed_indices=changed,
  )
  ignore(result)
  // Both defs fail physical_equal (independent parses), both recorded
  inspect(changed.val, content="[0, 1]")
}

///|
test "to_flat_proj_incremental: same root means zero changed" {
  let counter = Ref::new(0)
  let root = parse_syntax("let x = 1\nlet y = 2\nx")
  let fp = to_flat_proj(root, counter)
  // Same SyntaxNode — physical_equal succeeds for all children
  let changed = Ref::new(([] : Array[Int]))
  let result = to_flat_proj_incremental(
    root, root, fp, counter, changed_indices=changed,
  )
  ignore(result)
  inspect(changed.val.length(), content="0")
}

///|
test "to_flat_proj_incremental: final_expr change recorded as -1" {
  let counter = Ref::new(0)
  let old_root = parse_syntax("let x = 1\n42")
  let old_fp = to_flat_proj(old_root, counter)
  let new_root = parse_syntax("let x = 1\n99")
  let changed = Ref::new(([] : Array[Int]))
  let result = to_flat_proj_incremental(
    new_root, old_root, old_fp, counter, changed_indices=changed,
  )
  ignore(result)
  // x def changed (no CST sharing) + final_expr changed
  inspect(changed.val, content="[0, -1]")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt && moon test -p dowdiness/canopy/projection -f flat_proj_wbtest.mbt`
Expected: FAIL — `to_flat_proj_incremental` doesn't accept `changed_indices` parameter

- [ ] **Step 3: Add changed_indices parameter to to_flat_proj_incremental**

In `projection/flat_proj.mbt`, modify `to_flat_proj_incremental` signature:

```moonbit
pub fn to_flat_proj_incremental(
  new_root : @seam.SyntaxNode,
  old_root : @seam.SyntaxNode,
  old_fp : FlatProj,
  counter : Ref[Int],
  changed_indices~ : Ref[Array[Int]] = Ref::new([]),
) -> FlatProj {
```

Inside the loop, where `any_changed = true` is set for a def (line ~84), also record the index:

```moonbit
      if not(reused) {
        any_changed = true
        changed_indices.val.push(defs.length())  // current new def index
        // ... existing rebuild code ...
      }
```

For `final_expr` change (line ~100), push `-1`:

```moonbit
        _ => {
          any_changed = true
          changed_indices.val.push(-1)
          final_proj = Some(syntax_to_proj_node(new_child, counter))
        }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt && moon test -p dowdiness/canopy/projection -f flat_proj_wbtest.mbt`
Expected: All tests pass including the new ones

- [ ] **Step 5: Run full projection test suite**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt && moon test -p dowdiness/canopy/projection`
Expected: All existing tests still pass (new parameter is optional with default)

- [ ] **Step 6: Commit**

```bash
git add projection/flat_proj.mbt projection/flat_proj_wbtest.mbt
git commit -m "feat(projection): track changed_indices in to_flat_proj_incremental"
```

---

### Task 2: Add SourceMap Patch Methods

**Files:**
- Modify: `projection/source_map.mbt`
- Test: `projection/source_map_wbtest.mbt`

- [ ] **Step 1: Write failing tests for remove_subtree, patch_subtree, and public rebuild_ranges**

In `projection/source_map_wbtest.mbt`, add:

```moonbit
///|
test "SourceMap::remove_subtree removes node and children" {
  let parent = ProjNode(
    App(Var("f"), Var("x")),
    0, 5, 1,
    [ProjNode(Var("f"), 0, 1, 2, []),
     ProjNode(Var("x"), 2, 5, 3, [])],
  )
  let sm = SourceMap::from_ast(parent)
  inspect(sm.node_count(), content="3")

  sm.remove_subtree(parent)
  inspect(sm.node_count(), content="0")
}

///|
test "SourceMap::patch_subtree adds new node entries" {
  let sm = SourceMap::new()
  let node = ProjNode(
    App(Var("f"), Var("x")),
    0, 5, 10,
    [ProjNode(Var("f"), 0, 1, 11, []),
     ProjNode(Var("x"), 2, 5, 12, [])],
  )
  sm.patch_subtree(node)
  inspect(sm.node_count(), content="3")
  inspect(sm.get_range(NodeId(10)).is_empty(), content="false")
  inspect(sm.get_range(NodeId(11)).is_empty(), content="false")
}

///|
test "SourceMap::remove_subtree then patch_subtree replaces entries" {
  let old_child = ProjNode(Int(1), 10, 11, 5, [])
  let old_root = ProjNode(
    Module([("x", Int(1))], Int(1)),
    0, 15, 1,
    [old_child, ProjNode(Int(1), 12, 15, 6, [])],
  )
  let sm = SourceMap::from_ast(old_root)
  inspect(sm.node_count(), content="3")

  // Remove old child subtree
  sm.remove_subtree(old_child)
  inspect(sm.node_count(), content="2")

  // Add new child subtree
  let new_child = ProjNode(Int(2), 10, 11, 7, [])
  sm.patch_subtree(new_child)
  sm.rebuild_ranges()  // must be callable cross-package
  inspect(sm.node_count(), content="3")

  // Old id gone, new id present
  inspect(sm.get_range(NodeId(5)), content="None")
  inspect(sm.get_range(NodeId(7)).is_empty(), content="false")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt && moon test -p dowdiness/canopy/projection -f source_map_wbtest.mbt`
Expected: FAIL — methods don't exist yet

- [ ] **Step 3: Implement remove_subtree, patch_subtree, and make rebuild_ranges public**

In `projection/source_map.mbt`:

1. Change `fn SourceMap::rebuild_ranges` (line 47) to `pub fn SourceMap::rebuild_ranges` — this is needed because `editor/projection_memo.mbt` calls it cross-package.

2. Add new methods:

```moonbit
///|
/// Remove all entries for a ProjNode subtree from the source map.
/// Does NOT rebuild the sorted ranges array — call rebuild_ranges() after
/// all patches are done.
pub fn SourceMap::remove_subtree(self : SourceMap, node : ProjNode) -> Unit {
  let node_id = NodeId(node.node_id)
  self.node_to_range.remove(node_id)
  self.token_spans.remove(node_id)
  for child in node.children {
    self.remove_subtree(child)
  }
}

///|
/// Add entries for a ProjNode subtree to the source map.
/// Does NOT rebuild the sorted ranges array — call rebuild_ranges() after
/// all patches are done.
pub fn SourceMap::patch_subtree(self : SourceMap, node : ProjNode) -> Unit {
  let node_id = NodeId(node.node_id)
  self.node_to_range[node_id] = Range::new(node.start, node.end)
  for child in node.children {
    self.patch_subtree(child)
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt && moon test -p dowdiness/canopy/projection -f source_map_wbtest.mbt`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add projection/source_map.mbt projection/source_map_wbtest.mbt
git commit -m "feat(projection): add SourceMap remove_subtree, patch_subtree, make rebuild_ranges pub"
```

---

### Task 3: Add Index-Scoped Token Spans to SourceMap

**Files:**
- Modify: `projection/source_map.mbt`
- Test: `projection/source_map_wbtest.mbt`

- [ ] **Step 1: Write failing test for populate_token_spans_for_indices**

In `projection/source_map_wbtest.mbt`:

```moonbit
///|
test "populate_token_spans_for_indices: only processes specified indices" {
  let text = "let x = 1\nlet y = 2\nx"
  let (cst, _) = @parser.parse_cst(text) catch { _ => abort("parse failed") }
  let syntax_root = @seam.SyntaxNode::from_cst(cst)
  let counter = Ref::new(0)
  let proj_root = to_proj_node(syntax_root, counter)
  let sm = SourceMap::from_ast(proj_root)
  // Clear token spans
  sm.token_spans.clear()
  // Only populate for index 1 (the y def)
  sm.populate_token_spans_for_indices(syntax_root, proj_root, [1])
  // Should have name:1 but not name:0
  inspect(sm.get_token_span(proj_root.id(), "name:1").is_empty(), content="false")
  inspect(sm.get_token_span(proj_root.id(), "name:0"), content="None")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt && moon test -p dowdiness/canopy/projection -f source_map_wbtest.mbt`
Expected: FAIL — method doesn't exist

- [ ] **Step 3: Implement populate_token_spans_for_indices**

In `projection/source_map.mbt`, add:

```moonbit
///|
/// Populate token-level spans for specific def indices only.
/// `indices` contains def indices that changed; -1 means final_expr.
/// More efficient than populate_token_spans when few defs changed.
pub fn SourceMap::populate_token_spans_for_indices(
  self : SourceMap,
  syntax_root : @seam.SyntaxNode,
  proj_root : ProjNode,
  indices : Array[Int],
) -> Unit {
  match proj_root.kind {
    Module(defs, _) => {
      let syntax_children = syntax_root.children()
      let let_def_nodes : Array[@seam.SyntaxNode] = []
      let mut final_syntax_node : @seam.SyntaxNode? = None
      for syn_child in syntax_children {
        if @parser.LetDefView::cast(syn_child) is Some(_) {
          let_def_nodes.push(syn_child)
        } else if final_syntax_node is None {
          final_syntax_node = Some(syn_child)
        }
      }
      for idx in indices {
        if idx == -1 {
          let body_idx = proj_root.children.length() - 1
          match final_syntax_node {
            Some(syn) if body_idx >= 0 =>
              self.collect_token_spans_expr(syn, proj_root.children[body_idx])
            _ => ()
          }
        } else if idx >= 0 && idx < defs.length() && idx < proj_root.children.length() {
          if idx < let_def_nodes.length() {
            let syn_child = let_def_nodes[idx]
            let ident_token = syn_child.find_token(@syntax.IdentToken.to_raw())
            match ident_token {
              Some(tok) => {
                let role = "name:" + idx.to_string()
                self.set_token_span(
                  proj_root.id(),
                  role,
                  Range::new(tok.start(), tok.end()),
                )
              }
              None => ()
            }
            if @parser.LetDefView::cast(syn_child) is Some(v) {
              match v.init() {
                Some(init_syn) =>
                  self.collect_token_spans_expr(
                    init_syn, proj_root.children[idx],
                  )
                None => ()
              }
            }
          }
        }
      }
    }
    _ => self.populate_token_spans(syntax_root, proj_root)
  }
}
```

- [ ] **Step 4: Run tests**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt && moon test -p dowdiness/canopy/projection`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add projection/source_map.mbt projection/source_map_wbtest.mbt
git commit -m "feat(projection): add populate_token_spans_for_indices for incremental token span updates"
```

---

### Task 4: Wire Change Set Through Memo Chain

**Files:**
- Modify: `editor/projection_memo.mbt`

This is the core task. We modify `build_projection_memos` to:
1. Pass `changed_indices` ref from `proj_memo` to downstream memos
2. Guard against def count changes (force full rebuild)
3. Track `prev_proj_children` in `cached_proj_node` (not in registry_memo) to avoid execution-order dependency
4. Add patch path to `registry_memo`
5. Add patch path to `source_map_memo`

- [ ] **Step 1: Add side-channel refs and modify proj_memo**

In `editor/projection_memo.mbt`, inside `build_projection_memos`:

Add new refs after existing refs:

```moonbit
  // Change tracking: indices of defs that changed in the last incremental update.
  // None = full rebuild needed. Some([]) = no change. Some([2, 5]) = defs 2 and 5 changed.
  // -1 in the array signals final_expr changed.
  let changed_def_indices_ref : Ref[Array[Int]?] = Ref::new(None)
```

In the `proj_memo` closure, for the `(Some(prev_fp), Some(prev_root))` match arm:

```moonbit
        (Some(prev_fp), Some(prev_root)) => {
          let changed = Ref::new(([] : Array[Int]))
          let result = @proj.to_flat_proj_incremental(
            syntax_root, prev_root, prev_fp, counter,
            changed_indices=changed,
          )
          // Guard: if def count changed, force full rebuild — indices are
          // not meaningful across different-length def arrays.
          if result.defs.length() != prev_fp.defs.length() {
            changed_def_indices_ref.val = None
          } else {
            changed_def_indices_ref.val = Some(changed.val)
          }
          result
        }
```

For all other paths (first parse, no prev root, empty source), set:
```moonbit
      changed_def_indices_ref.val = None  // full rebuild
```

- [ ] **Step 2: Track prev_proj_children in cached_proj_node (not registry_memo)**

This avoids an execution-order dependency between `registry_memo` and `source_map_memo` — both need the previous children, so the ref must be set in their shared upstream memo.

Add a ref before `cached_proj_node`:

```moonbit
  // Previous ProjNode children — set in cached_proj_node, read by registry_memo and source_map_memo.
  // Must be set here (not in a downstream memo) to avoid execution-order dependency.
  let prev_proj_children_ref : Ref[Array[@proj.ProjNode]?] = Ref::new(None)
```

At the end of the `cached_proj_node` closure, after computing `proj`:

```moonbit
          prev_proj_children_ref.val = Some(proj.children.copy())
          // ... existing prev_module_id_ref.val = Some(proj.node_id)
          Some(proj)
```

On the `None` path:
```moonbit
          prev_proj_children_ref.val = None
```

**Important:** The `copy()` must happen BEFORE returning the value, because after the memo caches it, the children array is the live reference that downstream memos will see as the "new" value. The copy captures the "old" state for the next cycle's patch path.

Wait — actually, we need the **previous cycle's** children, not the current one. So we should capture BEFORE recomputing. Restructure as:

```moonbit
  let prev_proj_children_ref : Ref[Array[@proj.ProjNode]?] = Ref::new(None)

  let cached_proj_node : @incr.Memo[@proj.ProjNode?] = @incr.Memo::new(
    rt,
    fn() -> @proj.ProjNode? {
      match proj_memo.get() {
        Some(fp) => {
          let counter = Ref::new(next_id_ref.val)
          let proj = fp.to_proj_node_with_prev_module_id(
            counter,
            prev_module_id_ref.val,
          )
          next_id_ref.val = counter.val
          prev_module_id_ref.val = Some(proj.node_id)
          // Capture children for downstream patch paths AFTER building new ProjNode.
          // prev_proj_children_ref still holds the PREVIOUS cycle's children at this point,
          // which is what registry_memo and source_map_memo need for remove_subtree.
          // We update it to the CURRENT children AFTER returning, so downstream memos
          // see the previous children during their execution in THIS cycle.
          // ... but we can't update after returning. Instead, registry/source_map read
          // prev_proj_children_ref (the previous cycle's value), then we update here.
          // This works because Memo::get() caches — downstream memos in the same cycle
          // that call cached_proj_node.get() get the cached value, not a recompute.
          // The update below prepares prev_proj_children_ref for the NEXT cycle.
          let result = Some(proj)
          // Schedule update for next cycle — defer to after downstream reads
          // Actually, simply update here. In this cycle, registry_memo and source_map_memo
          // will read prev_proj_children_ref BEFORE we update it, because they call
          // cached_proj_node.get() first (which returns the cached result, not recomputing).
          // No — the update happens during THIS recomputation. If registry_memo is evaluated
          // after cached_proj_node, it will see the UPDATED value.
          // Solution: use a two-ref swap pattern.
          result
        }
        None => {
          prev_proj_children_ref.val = None
          None
        }
      }
    },
    label="cached_proj_node",
  )
```

Actually, the simpler approach: give each downstream memo its OWN `prev_children` ref that it manages. This avoids all ordering issues.

```moonbit
  // Each downstream memo manages its own previous-children snapshot.
  let registry_prev_children_ref : Ref[Array[@proj.ProjNode]?] = Ref::new(None)
  let source_map_prev_children_ref : Ref[Array[@proj.ProjNode]?] = Ref::new(None)
```

Each memo reads its own ref, uses it for patching, then updates it with the new children. Since each memo manages its own state, there's no ordering dependency.

- [ ] **Step 3: Add patch path to registry_memo**

Replace the `registry_memo` closure:

```moonbit
  let prev_registry_ref : Ref[Map[@proj.NodeId, @proj.ProjNode]?] = Ref::new(None)
  let registry_prev_children_ref : Ref[Array[@proj.ProjNode]?] = Ref::new(None)

  let registry_memo : @incr.Memo[Map[@proj.NodeId, @proj.ProjNode]] = @incr.Memo::new(
    rt,
    fn() -> Map[@proj.NodeId, @proj.ProjNode] {
      match cached_proj_node.get() {
        Some(root) => {
          let registry = match (changed_def_indices_ref.val, prev_registry_ref.val, registry_prev_children_ref.val) {
            (Some(indices), Some(prev_reg), Some(prev_children))
              if indices.length() > 0 => {
              // Patch path: only update changed subtrees
              for idx in indices {
                if idx == -1 {
                  // final_expr changed — last child
                  let last = root.children.length() - 1
                  if last >= 0 && last < prev_children.length() {
                    unregister_subtree(prev_children[last], prev_reg)
                  }
                  if last >= 0 {
                    register_node_tree(root.children[last], prev_reg)
                  }
                } else if idx >= 0 && idx < root.children.length() {
                  if idx < prev_children.length() {
                    unregister_subtree(prev_children[idx], prev_reg)
                  }
                  register_node_tree(root.children[idx], prev_reg)
                }
              }
              // Update the Module node itself (positions may have changed)
              prev_reg[root.id()] = root
              prev_reg
            }
            (Some(indices), Some(prev_reg), _) if indices.length() == 0 => {
              // Nothing changed — reuse previous registry
              prev_reg
            }
            _ => {
              // Full rebuild
              let reg : Map[@proj.NodeId, @proj.ProjNode] = {}
              register_node_tree(root, reg)
              reg
            }
          }
          prev_registry_ref.val = Some(registry)
          registry_prev_children_ref.val = Some(root.children.copy())
          registry
        }
        None => {
          prev_registry_ref.val = None
          registry_prev_children_ref.val = None
          {}
        }
      }
    },
    label="proj_registry",
  )
```

Also add the helper `unregister_subtree`:

```moonbit
///|
fn unregister_subtree(
  node : @proj.ProjNode,
  registry : Map[@proj.NodeId, @proj.ProjNode],
) -> Unit {
  registry.remove(node.id())
  for child in node.children {
    unregister_subtree(child, registry)
  }
}
```

- [ ] **Step 4: Add patch path to source_map_memo**

Replace the `source_map_memo` closure:

```moonbit
  let prev_source_map_ref : Ref[@proj.SourceMap?] = Ref::new(None)
  let source_map_prev_children_ref : Ref[Array[@proj.ProjNode]?] = Ref::new(None)

  let source_map_memo : @incr.Memo[@proj.SourceMap] = @incr.Memo::new(
    rt,
    fn() -> @proj.SourceMap {
      match cached_proj_node.get() {
        Some(root) => {
          let sm = match (changed_def_indices_ref.val, prev_source_map_ref.val, source_map_prev_children_ref.val) {
            (Some(indices), Some(prev_sm), Some(prev_children))
              if indices.length() > 0 => {
              // Patch path: remove old subtrees, add new subtrees
              for idx in indices {
                if idx == -1 {
                  let last = root.children.length() - 1
                  if last >= 0 && last < prev_children.length() {
                    prev_sm.remove_subtree(prev_children[last])
                  }
                  if last >= 0 {
                    prev_sm.patch_subtree(root.children[last])
                  }
                } else if idx >= 0 {
                  if idx < prev_children.length() {
                    prev_sm.remove_subtree(prev_children[idx])
                  }
                  if idx < root.children.length() {
                    prev_sm.patch_subtree(root.children[idx])
                  }
                }
              }
              // Update Module node range (start/end may have shifted)
              prev_sm.node_to_range[@proj.NodeId(root.node_id)] = @proj.Range::new(root.start, root.end)
              prev_sm.rebuild_ranges()
              // Repopulate token_spans for changed defs only
              match syntax_tree.get() {
                Some(syntax_root) =>
                  prev_sm.populate_token_spans_for_indices(
                    syntax_root, root, indices,
                  )
                None => ()
              }
              prev_sm
            }
            (Some(indices), Some(prev_sm), _) if indices.length() == 0 => prev_sm
            _ => {
              // Full rebuild
              let sm = @proj.SourceMap::from_ast(root)
              match syntax_tree.get() {
                Some(syntax_root) => sm.populate_token_spans(syntax_root, root)
                None => ()
              }
              sm
            }
          }
          prev_source_map_ref.val = Some(sm)
          source_map_prev_children_ref.val = Some(root.children.copy())
          sm
        }
        None => {
          prev_source_map_ref.val = None
          source_map_prev_children_ref.val = None
          @proj.SourceMap::new()
        }
      }
    },
    label="source_map",
  )
```

- [ ] **Step 5: Run moon check**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt && moon check`
Expected: PASS — all types and methods exist from Tasks 1-3

- [ ] **Step 6: Commit**

```bash
git add editor/projection_memo.mbt
git commit -m "feat(editor): wire incremental patch paths for registry and source_map memos"
```

---

### Task 5: Integration Tests

**Files:**
- Test: `editor/sync_editor_test.mbt`

These tests use SyncEditor which has a real incremental parser, giving proper CST pointer sharing via `physical_equal`. This exercises the actual patch path (not the full rebuild fallback).

- [ ] **Step 1: Write integration tests**

In `editor/sync_editor_test.mbt`, add:

```moonbit
///|
fn count_nodes(node : @proj.ProjNode) -> Int {
  let mut count = 1
  for child in node.children {
    count = count + count_nodes(child)
  }
  count
}

///|
test "incremental patch: registry node count stable after tail edit" {
  let editor = SyncEditor::new("test")
  editor.set_text("let x = 1\nlet y = 2\nlet z = 0\nz")
  ignore(editor.get_proj_node())
  ignore(editor.get_source_map())
  let node_count_before = match editor.get_proj_node() {
    Some(r) => count_nodes(r)
    None => 0
  }
  // Edit tail def value: 0 → 9
  let text = editor.get_text()
  let pos = text.length() - 3 // position of '0' in "z = 0"
  editor.move_cursor(pos)
  ignore(editor.backspace())
  editor.insert("9") catch { _ => () }
  let node_count_after = match editor.get_proj_node() {
    Some(r) => count_nodes(r)
    None => 0
  }
  // Same structure — same node count
  inspect(node_count_before == node_count_after, content="true")
}

///|
test "incremental patch: source_map position queries work after edit" {
  let editor = SyncEditor::new("test")
  editor.set_text("let x = 1\nlet y = 2\ny")
  ignore(editor.get_source_map()) // warm up
  // Edit: y=2 → y=3
  let text = editor.get_text()
  let pos = text.length() - 3 // position of '2'
  editor.move_cursor(pos)
  ignore(editor.backspace())
  editor.insert("3") catch { _ => () }
  let sm = editor.get_source_map()
  // Position query should still find nodes
  inspect(sm.innermost_node_at(0).is_empty(), content="false") // 'l' in 'let'
  inspect(sm.innermost_node_at(pos).is_empty(), content="false") // the '3'
}

///|
test "incremental patch: get_node returns correct node after edit" {
  let editor = SyncEditor::new("test")
  editor.set_text("let x = 1\nlet y = 2\ny")
  let proj = editor.get_proj_node().unwrap()
  // Get node ID of x's init (Int(1)) — first child of Module
  let x_init_id = proj.children[0].id()
  // Edit y's init: 2 → 3
  let text = editor.get_text()
  let pos = text.length() - 3
  editor.move_cursor(pos)
  ignore(editor.backspace())
  editor.insert("3") catch { _ => () }
  // x's init should still be retrievable with same ID
  match editor.get_node(x_init_id) {
    Some(node) => inspect(node.kind, content="Int(1)")
    None => fail("x init node not found after y edit")
  }
}
```

- [ ] **Step 2: Run integration tests**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt && moon test -p dowdiness/canopy/editor -f sync_editor_test.mbt`
Expected: PASS

- [ ] **Step 3: Run full project test suite**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt && moon test`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add editor/sync_editor_test.mbt
git commit -m "test(editor): add integration tests for incremental registry and source_map patching"
```

---

### Task 6: Add Benchmarks and Measure

**Files:**
- Modify: `editor/performance_benchmark.mbt`

- [ ] **Step 1: Update bench helper to exercise full pipeline including source_map**

The existing `run_projection_incremental_bench` only calls `get_proj_node()`, which doesn't trigger `registry_memo` or `source_map_memo`. Add `get_source_map()` to the loop:

In `editor/performance_benchmark.mbt`, modify `run_projection_incremental_bench`:

```moonbit
fn run_projection_incremental_bench(b : @bench.T, let_count : Int) -> Unit {
  let source = parser_bench_source(let_count, "0")
  let editor = SyncEditor::new("bench")
  editor.set_text(source)
  ignore(editor.get_proj_node())
  ignore(editor.get_source_map()) // warm up source_map too
  let edit_pos = source.length() - 2
  editor.move_cursor(edit_pos)
  let mut inserted = false
  b.bench(() => {
    if inserted {
      ignore(editor.backspace())
    } else {
      editor.insert("1") catch {
        _ => ()
      }
    }
    b.keep(editor.get_proj_node())
    b.keep(editor.get_source_map()) // exercise the optimized path
    inserted = not(inserted)
  })
}
```

- [ ] **Step 2: Add 320-def and 500-def benchmarks**

```moonbit
///|
test "projection pipeline - incremental keystroke (320 defs)" (b : @bench.T) {
  run_projection_incremental_bench(b, 320)
}

///|
test "projection pipeline - incremental keystroke (500 defs)" (b : @bench.T) {
  run_projection_incremental_bench(b, 500)
}
```

- [ ] **Step 3: Run benchmarks**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/crdt && moon bench --release -p dowdiness/canopy/editor -f performance_benchmark.mbt`

Record numbers for 20, 80, 320, 500 defs. Expected gains:
- 20 defs: negligible (already fast)
- 80 defs: 10-20% faster
- 320 defs: 30-50% faster
- 500 defs: 40-60% faster

- [ ] **Step 4: Commit benchmarks**

```bash
git add editor/performance_benchmark.mbt
git commit -m "bench(editor): add 320/500-def benchmarks, include get_source_map in bench loop"
```

---

### Task 7: Write Performance Results Doc

**Files:**
- Create: `docs/performance/2026-03-22-incremental-sourcemap-registry.md`

- [ ] **Step 1: Write results doc**

Document:
- Before/after numbers for all def counts
- Explanation of the optimization (change set propagation, patch vs rebuild)
- Remaining bottleneck (SourceMap `rebuild_ranges` O(n log n) sort — still runs on every keystroke)
- Future work: interval tree or incremental sorted insert to eliminate the sort

- [ ] **Step 2: Update docs/README.md if needed**

Add a link to the new performance doc if the docs README has a performance section.

- [ ] **Step 3: Commit docs**

```bash
git add docs/performance/2026-03-22-incremental-sourcemap-registry.md
git commit -m "docs(performance): add incremental sourcemap/registry benchmark results"
```

---

## Edge Cases to Watch

1. **Def count changes** (addition/deletion): Falls back to full rebuild — `changed_def_indices_ref = None` (explicitly checked: `result.defs.length() != prev_fp.defs.length()`)
2. **First parse**: No previous state — full rebuild (`prev_registry_ref = None`)
3. **`reconcile_flat_proj` path**: Hash-based name matching preserves array order but modifies ProjNode IDs — still safe for patch because indices are stable
4. **Empty document**: Both registry and source_map produce empty results
5. **Single expression (no defs)**: ProjNode is not a Module — `cached_proj_node` returns non-Module, registry/source_map do full rebuild (no children to patch)
6. **Final_expr only change**: Tracked as index `-1` in the changed set
7. **Multiple defs change at once** (e.g., paste): Patch path handles any number of changed indices; if more than ~50% changed, patch overhead may exceed full rebuild — no threshold needed initially, profile later
8. **Execution order**: Each downstream memo manages its own `prev_children_ref`, so `registry_memo` and `source_map_memo` can be evaluated in any order

## Verification Checklist

- [ ] `moon test` — all project tests pass
- [ ] `moon check` — no warnings
- [ ] `moon bench --release` — performance numbers recorded
- [ ] `moon info && moon fmt` — interfaces and formatting clean
- [ ] `git diff *.mbti` — review any API surface changes (expect: `rebuild_ranges` becomes `pub`, new methods added)
