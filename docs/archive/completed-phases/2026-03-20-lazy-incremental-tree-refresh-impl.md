**Status:** Complete

# Lazy & Incremental Tree Refresh Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `TreeEditorState::refresh` O(changed_subtrees) for typing by deferring structural index computation to when tree operations actually need it.

**Architecture:** Phase 1 removes eager index building from `refresh()` and replaces it with lazy on-demand computation. Phase 2 adds subtree skip to avoid visiting unchanged ProjNode subtrees entirely. All changes are in `projection/tree_editor.mbt`.

**Tech Stack:** MoonBit, moon test/check/info/fmt

**Spec:** `docs/plans/2026-03-20-lazy-incremental-tree-refresh-design.md`

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `projection/tree_editor.mbt` | All implementation — struct fields, refresh algorithm, lazy builders, subtree skip |
| Modify | `projection/tree_editor_wbtest.mbt` | Update stale-pruning test, add lazy index + reuse tests |
| Update | `projection/pkg.generated.mbti` | `moon info` regeneration |

---

### Task 1: Add LazyPreorder struct and lazy builder functions

**Files:**
- Modify: `projection/tree_editor.mbt`
- Modify: `projection/tree_editor_wbtest.mbt`

Pure additions — no existing code changes. These functions will be used by later tasks.

- [ ] **Step 1: Write failing test for `build_parent_map_from_tree`**

In `projection/tree_editor_wbtest.mbt`, add:

```moonbit
///|
test "build_parent_map_from_tree matches eagerly-built parent_by_child" {
  let (_, _, state) = tree_editor_test_state("(1 + 2) + (3 + 4)")
  let tree = match state.tree {
    Some(tree) => tree
    None => abort("expected tree")
  }
  let lazy_map = build_parent_map_from_tree(Some(tree))
  let root_children = tree_editor_test_loaded_children(tree)
  let left_id = root_children[0].id
  let right_id = root_children[1].id
  let right_children = tree_editor_test_loaded_children(root_children[1])
  let right_leaf_id = right_children[1].id
  inspect(lazy_map.get(left_id) == Some(tree.id), content="true")
  inspect(lazy_map.get(right_leaf_id) == Some(right_id), content="true")
  inspect(lazy_map.get(tree.id) is None, content="true")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p dowdiness/canopy/projection -f tree_editor_wbtest.mbt`
Expected: FAIL (`build_parent_map_from_tree` not defined)

- [ ] **Step 3: Implement `LazyPreorder`, `build_parent_map_from_tree`, `build_preorder_from_tree`**

In `projection/tree_editor.mbt`, add after the `empty_tree_structure_indexes` function (around line 105):

```moonbit
///|
/// Lazy preorder index, built on demand.
priv struct LazyPreorder {
  ids : Array[NodeId]
  range_by_root : Map[NodeId, (Int, Int)]
}

///|
/// Build parent map by walking the InteractiveTreeNode tree.
fn build_parent_map_from_tree(
  tree : InteractiveTreeNode?,
) -> Map[NodeId, NodeId] {
  let map : Map[NodeId, NodeId] = {}
  match tree {
    Some(root) => build_parent_map_walk(root, map)
    None => ()
  }
  map
}

///|
fn build_parent_map_walk(
  node : InteractiveTreeNode,
  map : Map[NodeId, NodeId],
) -> Unit {
  match node.children {
    Loaded(children) =>
      for child in children {
        map[child.id] = node.id
        build_parent_map_walk(child, map)
      }
    Elided(_) => ()
  }
}

///|
/// Build preorder index by walking the InteractiveTreeNode tree.
fn build_preorder_from_tree(tree : InteractiveTreeNode?) -> LazyPreorder {
  let ids : Array[NodeId] = []
  let range_by_root : Map[NodeId, (Int, Int)] = {}
  match tree {
    Some(root) => build_preorder_walk(root, ids, range_by_root)
    None => ()
  }
  { ids, range_by_root }
}

///|
fn build_preorder_walk(
  node : InteractiveTreeNode,
  ids : Array[NodeId],
  range_by_root : Map[NodeId, (Int, Int)],
) -> Unit {
  let start = ids.length()
  ids.push(node.id)
  match node.children {
    Loaded(children) =>
      for child in children {
        build_preorder_walk(child, ids, range_by_root)
      }
    Elided(_) => ()
  }
  range_by_root[node.id] = (start, ids.length() - 1)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `moon test -p dowdiness/canopy/projection -f tree_editor_wbtest.mbt`
Expected: PASS

- [ ] **Step 5: Write test for `build_preorder_from_tree`**

In `projection/tree_editor_wbtest.mbt`, add:

```moonbit
///|
test "build_preorder_from_tree matches eagerly-built indexes" {
  let (_, _, state) = tree_editor_test_state("(1 + 2) + (3 + 4)")
  let tree = match state.tree {
    Some(tree) => tree
    None => abort("expected tree")
  }
  let lazy_preorder = build_preorder_from_tree(Some(tree))
  let root_children = tree_editor_test_loaded_children(tree)
  let right_id = root_children[1].id
  inspect(lazy_preorder.ids.length(), content="7")
  inspect(lazy_preorder.ids[0] == tree.id, content="true")
  inspect(
    lazy_preorder.range_by_root.get(right_id) == Some((4, 6)),
    content="true",
  )
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `moon test -p dowdiness/canopy/projection -f tree_editor_wbtest.mbt`
Expected: PASS

- [ ] **Step 7: Run moon check**

Run: `moon check`
Expected: No errors

- [ ] **Step 8: Commit**

```bash
git add projection/tree_editor.mbt projection/tree_editor_wbtest.mbt
git commit -m "feat(projection): add lazy structural index builders"
```

---

### Task 2: Migrate index consumers to lazy computation

**Files:**
- Modify: `projection/tree_editor.mbt`

Switch `collect_subtree_ids`, `is_descendant_of`, `collect_nodes_in_range`, and `hydrate_subtree` from using eager fields to computing indexes on demand. Use Strategy A (inline computation) per the spec.

- [ ] **Step 1: Update `collect_subtree_ids` to use lazy preorder**

Replace the function body:

```moonbit
///|
fn collect_subtree_ids(
  state : TreeEditorState,
  root_id : NodeId,
) -> Array[NodeId] {
  let preorder = build_preorder_from_tree(state.tree)
  match preorder.range_by_root.get(root_id) {
    Some((start_idx, end_idx)) =>
      collect_preorder_slice(preorder.ids, start_idx, end_idx)
    None => []
  }
}
```

- [ ] **Step 2: Update `is_descendant_of` to use lazy parent map**

Replace the function body:

```moonbit
///|
fn is_descendant_of(
  state : TreeEditorState,
  node_id : NodeId,
  ancestor_id : NodeId,
) -> Bool {
  if node_id == ancestor_id {
    false
  } else {
    let parent_map = build_parent_map_from_tree(state.tree)
    is_descendant_in_parent_links(parent_map, node_id, ancestor_id)
  }
}
```

- [ ] **Step 3: Update `collect_nodes_in_range` to use lazy preorder**

Replace the function body:

```moonbit
///|
fn collect_nodes_in_range(
  state : TreeEditorState,
  start : NodeId,
  end : NodeId,
) -> Array[NodeId] {
  let preorder = build_preorder_from_tree(state.tree)
  match (preorder.range_by_root.get(start), preorder.range_by_root.get(end)) {
    (Some((start_idx, _)), Some((end_idx, _))) => {
      let min_idx = if start_idx < end_idx { start_idx } else { end_idx }
      let max_idx = if start_idx > end_idx { start_idx } else { end_idx }
      collect_preorder_slice(preorder.ids, min_idx, max_idx)
    }
    _ => []
  }
}
```

- [ ] **Step 4: Update `hydrate_subtree` to use lazy parent map**

In `hydrate_subtree` (line 759), replace `self.parent_by_child.get(node_id)` with an inline lazy parent map lookup. The full updated call site:

```moonbit
              let parent_map = build_parent_map_from_tree(self.tree)
              let subtree_valid_ids : Array[NodeId] = []
              let subtree_indexes = empty_tree_structure_indexes()
              let hydrated = refresh_node_with_reuse_impl(
                proj_node,
                source_map,
                ui_state,
                subtree_valid_ids,
                self.loaded_nodes,
                parent_map.get(node_id),
                subtree_indexes,
              )
```

The `collect_subtree_ids(self, node_id)` call at line 796 already works via lazy preorder (updated in Step 1). No change needed there.

- [ ] **Step 5: Run all tests**

Run: `moon test -p dowdiness/canopy/projection`
Expected: All tests pass — same behavior, different index source

- [ ] **Step 6: Commit**

```bash
git add projection/tree_editor.mbt
git commit -m "refactor(projection): migrate index consumers to lazy computation"
```

---

### Task 3: Simplify refresh — remove eager index building

**Files:**
- Modify: `projection/tree_editor.mbt`
- Modify: `projection/tree_editor_wbtest.mbt`

This is the core refactor. Simplify `refresh_node_with_reuse_impl` and `refresh()` to stop building structural indexes eagerly. Remove the `build_loaded_node_index` call. Change stale pruning to use `loaded_nodes.get` checks.

- [ ] **Step 1: Create simplified refresh function**

Add a new function `refresh_node_minimal` that replaces `refresh_node_with_reuse_impl` without `valid_ids`, `indexes`, or `parent_id` parameters. It outputs only an `InteractiveTreeNode` and populates a `loaded_nodes` map:

```moonbit
///|
fn refresh_node_minimal(
  node : ProjNode,
  source_map : SourceMap,
  ui_state : TreeUIState,
  previous_nodes : Map[NodeId, InteractiveTreeNode],
  new_loaded_nodes : Map[NodeId, InteractiveTreeNode],
) -> RefreshedInteractiveNode {
  let node_id = NodeId(node.node_id)
  let text_range = match source_map.get_range(node_id) {
    Some(range) => range
    None => Range::new(node.start, node.end)
  }
  let collapsed = ui_state.collapsed_nodes.contains(node_id)
  let selected = ui_state.selection.contains(node_id)
  let editing = match ui_state.editing_node {
    Some(id) => id == node_id
    None => false
  }
  let drop_target = match ui_state.drop_target {
    Some(id) => id == node_id
    None => false
  }
  let label = get_node_label(node.kind)
  let previous_node = previous_nodes.get(node_id)
  if collapsed {
    let mut descendant_count = 0
    for child in node.children {
      descendant_count += count_projection_descendants(child)
    }
    let stamp : InteractiveNodeStamp = {
      id: node_id,
      shape: interactive_node_shape(node.kind),
      label,
      child_ids: [],
      elided_descendant_count: Some(descendant_count),
      selected,
      editing,
      collapsed,
      drop_target,
      text_range,
    }
    let result = match previous_node {
      Some(previous) =>
        if interactive_node_stamp(previous) == stamp {
          { node: previous, reused_previous: true }
        } else {
          {
            node: {
              id: node_id,
              kind: node.kind,
              label,
              children: Elided(descendant_count),
              selected,
              editing,
              collapsed,
              drop_target,
              text_range,
            },
            reused_previous: false,
          }
        }
      None => {
        {
          node: {
            id: node_id,
            kind: node.kind,
            label,
            children: Elided(descendant_count),
            selected,
            editing,
            collapsed,
            drop_target,
            text_range,
          },
          reused_previous: false,
        }
      }
    }
    new_loaded_nodes[node_id] = result.node
    result
  } else {
    let children : Array[InteractiveTreeNode] = []
    let child_ids : Array[NodeId] = []
    let previous_loaded_children = match previous_node {
      Some(previous) =>
        match previous.children {
          Loaded(previous_children) => Some(previous_children)
          Elided(_) => None
        }
      None => None
    }
    let mut children_reused = match previous_loaded_children {
      Some(_) => true
      None => false
    }
    for child_index, child in node.children {
      let child_result = refresh_node_minimal(
        child,
        source_map,
        ui_state,
        previous_nodes,
        new_loaded_nodes,
      )
      child_ids.push(child_result.node.id)
      children.push(child_result.node)
      match previous_loaded_children {
        Some(previous_children) =>
          if child_index >= previous_children.length() ||
            previous_children[child_index].id != child_result.node.id ||
            not(child_result.reused_previous) {
            children_reused = false
          }
        None => ()
      }
    }
    match previous_loaded_children {
      Some(previous_children) =>
        if previous_children.length() != children.length() {
          children_reused = false
        }
      None => ()
    }
    let stamp : InteractiveNodeStamp = {
      id: node_id,
      shape: interactive_node_shape(node.kind),
      label,
      child_ids,
      elided_descendant_count: None,
      selected,
      editing,
      collapsed,
      drop_target,
      text_range,
    }
    let result = match previous_node {
      Some(previous) =>
        if children_reused && interactive_node_stamp(previous) == stamp {
          { node: previous, reused_previous: true }
        } else {
          {
            node: {
              id: node_id,
              kind: node.kind,
              label,
              children: Loaded(children),
              selected,
              editing,
              collapsed,
              drop_target,
              text_range,
            },
            reused_previous: false,
          }
        }
      None => {
        {
          node: {
            id: node_id,
            kind: node.kind,
            label,
            children: Loaded(children),
            selected,
            editing,
            collapsed,
            drop_target,
            text_range,
          },
          reused_previous: false,
        }
      }
    }
    new_loaded_nodes[node_id] = result.node
    result
  }
}

///|
/// Count projection descendants without collecting IDs or building indexes.
fn count_projection_descendants(node : ProjNode) -> Int {
  let mut count = 1
  for child in node.children {
    count += count_projection_descendants(child)
  }
  count
}
```

- [ ] **Step 2: Rewrite `refresh()` to use `refresh_node_minimal`**

Replace the `refresh()` method body:

```moonbit
pub fn TreeEditorState::refresh(
  self : TreeEditorState,
  proj : ProjNode?,
  source_map : SourceMap,
) -> TreeEditorState {
  match proj {
    Some(ast) => {
      // Use existing loaded_nodes as previous — no rebuild needed
      let selection_set = @immut/hashset.from_iter(self.selection.iter())
      let ui_state : TreeUIState = {
        collapsed_nodes: self.collapsed_nodes,
        selection: selection_set,
        editing_node: self.editing_node,
        drop_target: self.drop_target,
      }
      let new_loaded_nodes : Map[NodeId, InteractiveTreeNode] = {}
      let tree = Some(
        refresh_node_minimal(
          ast,
          source_map,
          ui_state,
          self.loaded_nodes,
          new_loaded_nodes,
        ).node,
      )
      // Prune selection, editing_node, dragging, drop_target via loaded_nodes checks
      // Skip pruning for collapsed_nodes (stale entries are harmless)
      let selection = self.selection.filter(fn(id) {
        new_loaded_nodes.get(id) is Some(_)
      })
      let editing_node = match self.editing_node {
        Some(id) =>
          if new_loaded_nodes.get(id) is Some(_) { Some(id) } else { None }
        None => None
      }
      let edit_value = if editing_node is None && self.editing_node is Some(_) {
        ""
      } else {
        self.edit_value
      }
      let dragging = match self.dragging {
        Some(id) =>
          if new_loaded_nodes.get(id) is Some(_) { Some(id) } else { None }
        None => None
      }
      let drop_target = match self.drop_target {
        Some(id) =>
          if new_loaded_nodes.get(id) is Some(_) { Some(id) } else { None }
        None => None
      }
      let drop_position = if drop_target is None {
        None
      } else {
        self.drop_position
      }
      {
        tree,
        selection,
        editing_node,
        edit_value,
        dragging,
        drop_target,
        drop_position,
        collapsed_nodes: self.collapsed_nodes,
        preorder_ids: [],
        preorder_range_by_root: {},
        parent_by_child: {},
        loaded_nodes: new_loaded_nodes,
      }
    }
    None => {
      {
        ..self,
        tree: None,
        preorder_ids: [],
        preorder_range_by_root: {},
        parent_by_child: {},
        loaded_nodes: {},
      }
    }
  }
}
```

- [ ] **Step 3: Update stale-pruning test expectation**

In `projection/tree_editor_wbtest.mbt`, in test `"refresh prunes stale ids from UI state"`, change line 423:

```moonbit
  // OLD:
  inspect(refreshed.collapsed_nodes.contains(stale_id), content="false")
  // NEW:
  inspect(refreshed.collapsed_nodes.contains(stale_id), content="true")
```

- [ ] **Step 4: Update test helper `tree_editor_test_refresh_with_reuse`**

The existing helper calls `refresh_node_with_reuse_impl` with `valid_ids` and `indexes`. Add a new helper that uses `refresh_node_minimal`:

```moonbit
///|
fn tree_editor_test_refresh_minimal(
  node : ProjNode,
  source_map : SourceMap,
  ui_state : TreeUIState,
  previous_nodes : Map[NodeId, InteractiveTreeNode],
) -> RefreshedInteractiveNode {
  let new_loaded_nodes : Map[NodeId, InteractiveTreeNode] = {}
  refresh_node_minimal(
    node,
    source_map,
    ui_state,
    previous_nodes,
    new_loaded_nodes,
  )
}
```

Update the three tests that use `tree_editor_test_refresh_with_reuse` to use the new helper instead:
- `"refresh builder reuses unchanged sibling subtree after unrelated leaf change"` (line 497)
- `"refresh builder reuses root when projection and UI state are unchanged"` (line 539)
- `"refresh builder limits UI-only selection invalidation to selected branch"` (line 558)

Also in these three tests, replace `build_loaded_node_index(state.tree)` with `state.loaded_nodes` — they hold the same data and `build_loaded_node_index` will be removed later. For example, change:
```moonbit
let previous_nodes = build_loaded_node_index(state.tree)
```
to:
```moonbit
let previous_nodes = state.loaded_nodes
```

The tests for `reused_previous` behavior should produce the same results.

- [ ] **Step 5: Update tests that access eager structural index fields**

Tests `"from_projection builds structural indexes"` (line 427) and `"refresh rebuilds structural indexes for updated projection"` (line 463) and `"refresh elides collapsed descendants while keeping structural indexes"` (line 128) access `state.preorder_ids`, `state.preorder_range_by_root`, `state.parent_by_child` directly. These fields are now empty. Update these tests to use the lazy builders instead:

For example, change:
```moonbit
inspect(state.preorder_ids == ids, content="true")
```
to:
```moonbit
let preorder = build_preorder_from_tree(state.tree)
inspect(preorder.ids == ids, content="true")
```

And change:
```moonbit
inspect(state.parent_by_child.get(left_id) == Some(root_id), content="true")
```
to:
```moonbit
let parent_map = build_parent_map_from_tree(state.tree)
inspect(parent_map.get(left_id) == Some(root_id), content="true")
```

- [ ] **Step 6: Run all tests**

Run: `moon test -p dowdiness/canopy/projection`
Expected: All tests pass

- [ ] **Step 7: Run moon check**

Run: `moon check`
Expected: No errors

- [ ] **Step 8: Commit**

```bash
git add projection/tree_editor.mbt projection/tree_editor_wbtest.mbt
git commit -m "refactor(projection): simplify refresh to skip eager index building"
```

---

### Task 4: Remove eager structural index fields

**Files:**
- Modify: `projection/tree_editor.mbt`
- Modify: `projection/tree_editor_wbtest.mbt`

Now that all consumers use lazy computation, remove the dead eager fields and related infrastructure.

- [ ] **Step 1: Remove eager fields from `TreeEditorState`**

Remove these fields from the struct:
- `priv preorder_ids : Array[NodeId]`
- `priv preorder_range_by_root : Map[NodeId, (Int, Int)]`
- `priv parent_by_child : Map[NodeId, NodeId]`

- [ ] **Step 2: Remove all references to removed fields**

Remove from `new()`, `from_projection()`, `refresh()` (both branches), and `hydrate_subtree`. Remove from any `{ ..self, ... }` spread sites that explicitly set these fields.

- [ ] **Step 3: Remove dead functions**

Remove or mark as dead:
- `TreeStructureIndexes` struct (if no longer used by `hydrate_subtree`)
- `empty_tree_structure_indexes()`
- `finish_refreshed_interactive_node()` (used only by old `refresh_node_with_reuse_impl`)
- `record_projection_subtree()` (replaced by `count_projection_descendants`)
- `build_tree_projection_snapshot()` (replaced by inline `refresh_node_minimal` call)
- `build_loaded_node_index()` / `index_loaded_nodes()` (if no longer called — check `apply_selection_edit` first, fixed in Task 5)
- Old `refresh_node_with_reuse_impl()` (replaced by `refresh_node_minimal`)

**Important:** Keep `refresh_node_with_reuse_impl` if `hydrate_subtree` still calls it. If so, update `hydrate_subtree` to call `refresh_node_minimal` instead, then remove the old function.

- [ ] **Step 4: Update `from_projection()` to use `refresh_node_minimal`**

```moonbit
pub fn TreeEditorState::from_projection(
  proj : ProjNode?,
  source_map : SourceMap,
) -> TreeEditorState {
  let collapsed_nodes : @immut/hashset.HashSet[NodeId] = @immut/hashset.new()
  let ui_state : TreeUIState = {
    collapsed_nodes,
    selection: @immut/hashset.new(),
    editing_node: None,
    drop_target: None,
  }
  let loaded_nodes : Map[NodeId, InteractiveTreeNode] = {}
  let tree = match proj {
    Some(ast) =>
      Some(
        refresh_node_minimal(ast, source_map, ui_state, {}, loaded_nodes).node,
      )
    None => None
  }
  {
    tree,
    selection: [],
    editing_node: None,
    edit_value: "",
    dragging: None,
    drop_target: None,
    drop_position: None,
    collapsed_nodes,
    loaded_nodes,
  }
}
```

- [ ] **Step 5: Update `hydrate_subtree` to use `refresh_node_minimal`**

Replace the `refresh_node_with_reuse_impl` call with `refresh_node_minimal`. The parent lookup is no longer needed for index building:

```moonbit
  let subtree_loaded_nodes : Map[NodeId, InteractiveTreeNode] = {}
  let hydrated = refresh_node_minimal(
    proj_node,
    source_map,
    ui_state,
    self.loaded_nodes,
    subtree_loaded_nodes,
  )
```

And update the `loaded_nodes` replacement to use `subtree_loaded_nodes` instead of `subtree_indexes.loaded_nodes`.

- [ ] **Step 6: Remove old test helper `tree_editor_test_refresh_with_reuse`**

If no tests use it anymore, remove it.

- [ ] **Step 7: Run all tests**

Run: `moon test -p dowdiness/canopy/projection`
Expected: All tests pass

- [ ] **Step 8: Run moon check**

Run: `moon check`
Expected: No errors (no references to removed fields/functions)

- [ ] **Step 9: Commit**

```bash
git add projection/tree_editor.mbt projection/tree_editor_wbtest.mbt
git commit -m "refactor(projection): remove eager structural index fields and dead code"
```

---

### Task 5: Fix `apply_selection_edit` O(n) rebuild

**Files:**
- Modify: `projection/tree_editor.mbt`

Change `apply_selection_to_node` to return a changed-path array, then use `update_loaded_nodes_for_path` instead of `build_loaded_node_index`.

- [ ] **Step 1: Update `apply_selection_to_node` return type**

Change signature from `(InteractiveTreeNode, Bool)` to `(InteractiveTreeNode, Bool, Array[InteractiveTreeNode])`, matching `update_node_collapsed`:

```moonbit
///|
fn apply_selection_to_node(
  node : InteractiveTreeNode,
  selection : @immut/hashset.HashSet[NodeId],
) -> (InteractiveTreeNode, Bool, Array[InteractiveTreeNode]) {
  let new_selected = selection.contains(node.id)
  match node.children {
    Loaded(existing_children) => {
      let updated_children : Array[InteractiveTreeNode] = []
      let child_path : Array[InteractiveTreeNode] = []
      let mut any_child_changed = false
      for child in existing_children {
        let (updated, changed, changed_nodes) = apply_selection_to_node(
          child, selection,
        )
        updated_children.push(updated)
        if changed {
          any_child_changed = true
          for cn in changed_nodes {
            child_path.push(cn)
          }
        }
      }
      if new_selected == node.selected && not(any_child_changed) {
        (node, false, [])
      } else {
        let children = if any_child_changed {
          Loaded(updated_children)
        } else {
          node.children
        }
        let updated = { ..node, selected: new_selected, children }
        let changed_path : Array[InteractiveTreeNode] = [updated]
        for cn in child_path {
          changed_path.push(cn)
        }
        (updated, true, changed_path)
      }
    }
    Elided(_) =>
      if new_selected == node.selected {
        (node, false, [])
      } else {
        let updated = { ..node, selected: new_selected }
        (updated, true, [updated])
      }
  }
}
```

- [ ] **Step 2: Update `apply_selection_edit` to use path patching**

```moonbit
fn apply_selection_edit(
  state : TreeEditorState,
  selection : Array[NodeId],
) -> TreeEditorState {
  let selection_set = @immut/hashset.from_iter(selection.iter())
  match state.tree {
    None => { ..state, selection }
    Some(root) => {
      let (updated, changed, changed_nodes) = apply_selection_to_node(
        root, selection_set,
      )
      if changed {
        let loaded_nodes = update_loaded_nodes_for_path(
          state.loaded_nodes,
          changed_nodes,
        )
        { ..state, selection, tree: Some(updated), loaded_nodes }
      } else {
        { ..state, selection }
      }
    }
  }
}
```

- [ ] **Step 3: Remove `build_loaded_node_index` and `index_loaded_nodes`**

If no other callers remain, delete both functions.

- [ ] **Step 4: Run all tests**

Run: `moon test -p dowdiness/canopy/projection`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add projection/tree_editor.mbt
git commit -m "perf(projection): patch loaded_nodes on selection instead of O(n) rebuild"
```

---

### Task 6: Phase 2 — Subtree skip during refresh

**Files:**
- Modify: `projection/tree_editor.mbt`
- Modify: `projection/tree_editor_wbtest.mbt`

Add top-down subtree skip to `refresh_node_minimal`. Before descending into children, check if the entire subtree can be reused.

- [ ] **Step 1: Write failing test for subtree skip**

In `projection/tree_editor_wbtest.mbt`, add:

```moonbit
///|
test "refresh_node_minimal skips unchanged subtrees" {
  let (old_root, _) = parse_to_proj_node("(1 + 2) + (3 + 4)")
  let old_source_map = SourceMap::from_ast(old_root)
  let state = TreeEditorState::from_projection(Some(old_root), old_source_map)
  let (new_root, _) = parse_to_proj_node("(1 + 2) + (3 + 5)")
  let reconciled = reconcile_ast(old_root, new_root, Ref::new(1000))
  let source_map = SourceMap::from_ast(reconciled)
  let ui_state : TreeUIState = {
    collapsed_nodes: @immut/hashset.new(),
    selection: @immut/hashset.new(),
    editing_node: None,
    drop_target: None,
  }
  let new_loaded_nodes : Map[NodeId, InteractiveTreeNode] = {}
  let left_result = refresh_node_minimal(
    reconciled.children[0],
    source_map,
    ui_state,
    state.loaded_nodes,
    new_loaded_nodes,
  )
  // Left subtree is unchanged — should be reused AND children not visited
  inspect(left_result.reused_previous, content="true")
  // All left subtree nodes should be carried over to new_loaded_nodes
  let old_tree = match state.tree {
    Some(tree) => tree
    None => abort("expected tree")
  }
  let left_children = tree_editor_test_loaded_children(
    tree_editor_test_loaded_children(old_tree)[0],
  )
  inspect(
    new_loaded_nodes.get(left_children[0].id) is Some(_),
    content="true",
  )
  inspect(
    new_loaded_nodes.get(left_children[1].id) is Some(_),
    content="true",
  )
}
```

- [ ] **Step 2: Run test to see current behavior**

Run: `moon test -p dowdiness/canopy/projection -f tree_editor_wbtest.mbt`
Expected: The `reused_previous` assertion passes (existing stamp reuse works), but the `loaded_nodes` carry-over assertions may fail since the current `refresh_node_minimal` doesn't carry over children's loaded_nodes when reusing.

- [ ] **Step 3: Add subtree skip with loaded_nodes carry-over**

In `refresh_node_minimal`, add a top-down check before the existing logic. After looking up `previous_node`, add:

```moonbit
  // Phase 2: subtree skip — check if entire subtree can be reused
  match previous_node {
    Some(previous) =>
      if can_skip_subtree(node, previous, source_map, ui_state) {
        // Carry over all loaded_nodes entries from reused subtree
        carry_over_loaded_nodes(previous, new_loaded_nodes)
        return { node: previous, reused_previous: true }
      }
    None => ()
  }
```

Add the helper functions:

```moonbit
///|
/// Check if a subtree can be completely skipped during refresh.
fn can_skip_subtree(
  proj_node : ProjNode,
  prev_node : InteractiveTreeNode,
  source_map : SourceMap,
  ui_state : TreeUIState,
) -> Bool {
  let node_id = prev_node.id
  // Check text_range — positions shift when text is inserted/deleted before this node
  let text_range = match source_map.get_range(node_id) {
    Some(range) => range
    None => Range::new(proj_node.start, proj_node.end)
  }
  if text_range != prev_node.text_range {
    return false
  }
  // Check UI state matches
  let collapsed = ui_state.collapsed_nodes.contains(node_id)
  if collapsed != prev_node.collapsed {
    return false
  }
  let selected = ui_state.selection.contains(node_id)
  if selected != prev_node.selected {
    return false
  }
  let editing = match ui_state.editing_node {
    Some(id) => id == node_id
    None => false
  }
  if editing != prev_node.editing {
    return false
  }
  let drop_target = match ui_state.drop_target {
    Some(id) => id == node_id
    None => false
  }
  if drop_target != prev_node.drop_target {
    return false
  }
  // Check shape matches
  if interactive_node_shape(proj_node.kind) != interactive_node_shape(prev_node.kind) {
    return false
  }
  if get_node_label(proj_node.kind) != prev_node.label {
    return false
  }
  // Check children IDs match
  match prev_node.children {
    Loaded(prev_children) => {
      if proj_node.children.length() != prev_children.length() {
        return false
      }
      for i, child in proj_node.children {
        if NodeId(child.node_id) != prev_children[i].id {
          return false
        }
      }
      true
    }
    Elided(_) => collapsed // Elided matches if still collapsed
  }
}

///|
/// Copy all loaded_nodes entries from a reused subtree.
fn carry_over_loaded_nodes(
  node : InteractiveTreeNode,
  target : Map[NodeId, InteractiveTreeNode],
) -> Unit {
  target[node.id] = node
  match node.children {
    Loaded(children) =>
      for child in children {
        carry_over_loaded_nodes(child, target)
      }
    Elided(_) => ()
  }
}
```

- [ ] **Step 4: Run all tests**

Run: `moon test -p dowdiness/canopy/projection`
Expected: All tests pass including the new subtree skip test

- [ ] **Step 5: Run moon check**

Run: `moon check`
Expected: No errors

- [ ] **Step 6: Commit**

```bash
git add projection/tree_editor.mbt projection/tree_editor_wbtest.mbt
git commit -m "perf(projection): Phase 2 — skip unchanged subtrees in refresh"
```

---

### Task 7: moon info + moon fmt + final verification

**Files:**
- Update: `projection/pkg.generated.mbti`

- [ ] **Step 1: Regenerate interfaces**

Run: `moon info && moon fmt`

- [ ] **Step 2: Review .mbti changes**

Run: `git diff projection/pkg.generated.mbti`

Expected changes: removal of `preorder_ids`, `preorder_range_by_root`, `parent_by_child` from the public interface (if they were public — they are `priv` so may not appear). Addition of `cached_parent_map` and `cached_preorder` fields (also `priv`, may not appear).

- [ ] **Step 3: Run full test suite**

Run: `moon test`
Expected: All tests pass across all packages

- [ ] **Step 4: Commit**

```bash
git add projection/
git commit -m "chore: moon info + moon fmt after lazy tree refresh refactor"
```

---

## Post-implementation notes

**Verification checklist:**
- All existing `tree_editor_wbtest.mbt` tests pass (one assertion changed: stale `collapsed_nodes` now persists)
- `refresh()` no longer calls `build_loaded_node_index`
- `refresh()` no longer builds `preorder_ids`, `parent_by_child`, `preorder_range_by_root`
- `refresh()` no longer builds `valid_ids` array or HashSet
- Structural indexes are built lazily only when tree operations call them
- `apply_selection_edit` patches `loaded_nodes` instead of O(n) rebuild
- Phase 2: unchanged subtrees are skipped during refresh traversal
