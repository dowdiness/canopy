# Scope-Colored Compact Tree View — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a compact inline tree view to the ideal editor with full binder coloring, def/use font weight, and selection-driven highlighting.

**Architecture:** Rabbita (Elm-architecture) view function reads `InteractiveTreeNode[Term]` + a Rabbita-local `scope_map` built from existing scope resolution. Persistent ProjNode rose tree zipper for O(1) keyboard navigation. All logic in MoonBit; TypeScript limited to CSS variables.

**Tech Stack:** MoonBit, Rabbita (moonbit-community/rabbita), existing `resolve_binder`/`find_usages` from `lang/lambda/edits/scope.mbt`

**Design spec:** `docs/plans/2026-04-04-scope-colored-tree-view-design.md`

---

## File Structure

### New files
| File | Responsibility |
|------|---------------|
| `examples/ideal/main/rose_zipper.mbt` | Generic `RoseCtx[T]`, `RoseZipper[T]`, navigation functions |
| `examples/ideal/main/rose_zipper_wbtest.mbt` | Zipper unit tests |
| `examples/ideal/main/scope_annotation.mbt` | `ScopeAnnotation` struct, `build_scope_map`, `compute_highlight_set` |
| `examples/ideal/main/scope_annotation_wbtest.mbt` | Scope map + highlight set tests |
| `examples/ideal/main/view_compact.mbt` | `view_compact_tree` Rabbita view function |

### Modified files
| File | Change |
|------|--------|
| `examples/ideal/main/model.mbt` | Add `scope_map`, `outline_mode`, `highlight_set`, `zipper` fields |
| `examples/ideal/main/msg.mbt` | Add `OutlineMode` enum, `SetOutlineMode`, `ClearSelection` messages |
| `examples/ideal/main/main.mbt` | Extend `refresh()` and `update()` with scope_map building, zipper lifecycle, selection logic |
| `examples/ideal/main/view_outline.mbt` | Mode toggle in panel header, dispatch to compact view |
| `examples/ideal/main/moon.pkg` | Add `@lambda_proj` and `@canopy_core` imports |
| `examples/ideal/web/index.html` | Binder palette CSS, selection state CSS, def-site weight |

---

## Task 1: ProjNode Rose Tree Zipper

**Files:**
- Create: `examples/ideal/main/rose_zipper.mbt`
- Create: `examples/ideal/main/rose_zipper_wbtest.mbt`

- [ ] **Step 1: Write failing tests for zipper navigation**

```moonbit
// examples/ideal/main/rose_zipper_wbtest.mbt

///|
test "go_down focuses first child" {
  // Tree: Node(0, [Node(1, []), Node(2, [])])
  let child0 : @canopy_core.ProjNode[@ast.Term] = @canopy_core.ProjNode::new(
    @ast.Int(10), 0, 1, 1, [],
  )
  let child1 : @canopy_core.ProjNode[@ast.Term] = @canopy_core.ProjNode::new(
    @ast.Int(20), 2, 3, 2, [],
  )
  let root : @canopy_core.ProjNode[@ast.Term] = @canopy_core.ProjNode::new(
    @ast.Module([], @ast.Unit), 0, 3, 0, [child0, child1],
  )
  let z = RoseZipper::from_root(root)
  let down = z.go_down(0)
  inspect(down is None, content="false")
  inspect(down.unwrap().focus.node_id, content="1")
}

///|
test "go_down then go_up is identity" {
  let child0 : @canopy_core.ProjNode[@ast.Term] = @canopy_core.ProjNode::new(
    @ast.Int(10), 0, 1, 1, [],
  )
  let root : @canopy_core.ProjNode[@ast.Term] = @canopy_core.ProjNode::new(
    @ast.Module([], @ast.Unit), 0, 1, 0, [child0],
  )
  let z = RoseZipper::from_root(root)
  let down = z.go_down(0).unwrap()
  let up = down.go_up().unwrap()
  inspect(up.focus.node_id, content="0")
}

///|
test "go_right moves to next sibling" {
  let child0 : @canopy_core.ProjNode[@ast.Term] = @canopy_core.ProjNode::new(
    @ast.Int(10), 0, 1, 1, [],
  )
  let child1 : @canopy_core.ProjNode[@ast.Term] = @canopy_core.ProjNode::new(
    @ast.Int(20), 2, 3, 2, [],
  )
  let root : @canopy_core.ProjNode[@ast.Term] = @canopy_core.ProjNode::new(
    @ast.Module([], @ast.Unit), 0, 3, 0, [child0, child1],
  )
  let z = RoseZipper::from_root(root)
  let down = z.go_down(0).unwrap()
  let right = down.go_right()
  inspect(right is None, content="false")
  inspect(right.unwrap().focus.node_id, content="2")
}

///|
test "go_left moves to previous sibling" {
  let child0 : @canopy_core.ProjNode[@ast.Term] = @canopy_core.ProjNode::new(
    @ast.Int(10), 0, 1, 1, [],
  )
  let child1 : @canopy_core.ProjNode[@ast.Term] = @canopy_core.ProjNode::new(
    @ast.Int(20), 2, 3, 2, [],
  )
  let root : @canopy_core.ProjNode[@ast.Term] = @canopy_core.ProjNode::new(
    @ast.Module([], @ast.Unit), 0, 3, 0, [child0, child1],
  )
  let z = RoseZipper::from_root(root)
  let at1 = z.go_down(0).unwrap().go_right().unwrap()
  let left = at1.go_left()
  inspect(left is None, content="false")
  inspect(left.unwrap().focus.node_id, content="1")
}

///|
test "go_right at last sibling returns None" {
  let child0 : @canopy_core.ProjNode[@ast.Term] = @canopy_core.ProjNode::new(
    @ast.Int(10), 0, 1, 1, [],
  )
  let root : @canopy_core.ProjNode[@ast.Term] = @canopy_core.ProjNode::new(
    @ast.Module([], @ast.Unit), 0, 1, 0, [child0],
  )
  let z = RoseZipper::from_root(root)
  let down = z.go_down(0).unwrap()
  inspect(down.go_right() is None, content="true")
}

///|
test "go_down on leaf returns None" {
  let leaf : @canopy_core.ProjNode[@ast.Term] = @canopy_core.ProjNode::new(
    @ast.Int(42), 0, 1, 0, [],
  )
  let z = RoseZipper::from_root(leaf)
  inspect(z.go_down(0) is None, content="true")
}

///|
test "path_indices round-trips via focus_at" {
  let gc0 : @canopy_core.ProjNode[@ast.Term] = @canopy_core.ProjNode::new(
    @ast.Var("x"), 0, 1, 10, [],
  )
  let child0 : @canopy_core.ProjNode[@ast.Term] = @canopy_core.ProjNode::new(
    @ast.Lam("x", @ast.Var("x")), 0, 3, 1, [gc0],
  )
  let child1 : @canopy_core.ProjNode[@ast.Term] = @canopy_core.ProjNode::new(
    @ast.Int(20), 4, 5, 2, [],
  )
  let root : @canopy_core.ProjNode[@ast.Term] = @canopy_core.ProjNode::new(
    @ast.Module([], @ast.Unit), 0, 5, 0, [child0, child1],
  )
  // Navigate to grandchild
  let z = RoseZipper::from_root(root).go_down(0).unwrap().go_down(0).unwrap()
  inspect(z.focus.node_id, content="10")
  let indices = z.path_indices()
  inspect(indices, content="[0, 0]")
  // Rebuild from indices
  let z2 = RoseZipper::focus_at(root, indices)
  inspect(z2.focus.node_id, content="10")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test --file main/rose_zipper_wbtest.mbt 2>&1 | head -20`
Expected: Compilation error — `RoseZipper` not defined

- [ ] **Step 3: Implement rose tree zipper**

```moonbit
// examples/ideal/main/rose_zipper.mbt

///|
/// One-hole context for a rose tree (ProjNode[T]).
/// Stores parent's node data and the sibling ProjNodes on each side.
/// Derivative of T * List(X) = T * List(X) * List(X).
struct RoseCtx[T] {
  parent_node_id : Int
  parent_kind : T
  parent_start : Int
  parent_end : Int
  left : Array[@canopy_core.ProjNode[T]]
  right : Array[@canopy_core.ProjNode[T]]
}

///|
/// Persistent zipper over ProjNode[T].
/// Focus + path of contexts from focus to root.
struct RoseZipper[T] {
  focus : @canopy_core.ProjNode[T]
  path : Array[RoseCtx[T]]
}

///|
/// Create a zipper focused on the root.
fn[T] RoseZipper::from_root(root : @canopy_core.ProjNode[T]) -> RoseZipper[T] {
  { focus: root, path: [] }
}

///|
/// Move focus to child at index i. Returns None if no such child.
fn[T] RoseZipper::go_down(self : RoseZipper[T], i : Int) -> RoseZipper[T]? {
  let children = self.focus.children
  if i < 0 || i >= children.length() {
    return None
  }
  let left = children[0:i].iter().collect()
  let right = children[i + 1:].iter().collect()
  let ctx : RoseCtx[T] = {
    parent_node_id: self.focus.node_id,
    parent_kind: self.focus.kind,
    parent_start: self.focus.start,
    parent_end: self.focus.end,
    left,
    right,
  }
  let mut new_path = self.path.copy()
  new_path.push(ctx)
  Some({ focus: children[i], path: new_path })
}

///|
/// Move focus to parent. Returns None at root.
fn[T] RoseZipper::go_up(self : RoseZipper[T]) -> RoseZipper[T]? {
  if self.path.is_empty() {
    return None
  }
  let ctx = self.path[self.path.length() - 1]
  let new_path = self.path[0:self.path.length() - 1].iter().collect()
  // Reconstruct parent's children: left + focus + right
  let children : Array[@canopy_core.ProjNode[T]] = []
  for node in ctx.left {
    children.push(node)
  }
  children.push(self.focus)
  for node in ctx.right {
    children.push(node)
  }
  let parent = @canopy_core.ProjNode::new(
    ctx.parent_kind,
    ctx.parent_start,
    ctx.parent_end,
    ctx.parent_node_id,
    children,
  )
  Some({ focus: parent, path: new_path })
}

///|
/// Move focus to right sibling. Returns None if at last sibling.
fn[T] RoseZipper::go_right(self : RoseZipper[T]) -> RoseZipper[T]? {
  if self.path.is_empty() {
    return None
  }
  let ctx = self.path[self.path.length() - 1]
  if ctx.right.is_empty() {
    return None
  }
  let new_focus = ctx.right[0]
  let new_left = ctx.left.copy()
  new_left.push(self.focus)
  let new_right = ctx.right[1:].iter().collect()
  let new_ctx : RoseCtx[T] = {
    parent_node_id: ctx.parent_node_id,
    parent_kind: ctx.parent_kind,
    parent_start: ctx.parent_start,
    parent_end: ctx.parent_end,
    left: new_left,
    right: new_right,
  }
  let new_path = self.path[0:self.path.length() - 1].iter().collect()
  new_path.push(new_ctx)
  Some({ focus: new_focus, path: new_path })
}

///|
/// Move focus to left sibling. Returns None if at first sibling.
fn[T] RoseZipper::go_left(self : RoseZipper[T]) -> RoseZipper[T]? {
  if self.path.is_empty() {
    return None
  }
  let ctx = self.path[self.path.length() - 1]
  if ctx.left.is_empty() {
    return None
  }
  let new_focus = ctx.left[ctx.left.length() - 1]
  let new_left = ctx.left[0:ctx.left.length() - 1].iter().collect()
  let new_right : Array[@canopy_core.ProjNode[T]] = [self.focus]
  for node in ctx.right {
    new_right.push(node)
  }
  let new_ctx : RoseCtx[T] = {
    parent_node_id: ctx.parent_node_id,
    parent_kind: ctx.parent_kind,
    parent_start: ctx.parent_start,
    parent_end: ctx.parent_end,
    left: new_left,
    right: new_right,
  }
  let new_path = self.path[0:self.path.length() - 1].iter().collect()
  new_path.push(new_ctx)
  Some({ focus: new_focus, path: new_path })
}

///|
/// Extract path from root as array of child indices.
fn[T] RoseZipper::path_indices(self : RoseZipper[T]) -> Array[Int] {
  let indices : Array[Int] = []
  for ctx in self.path {
    indices.push(ctx.left.length())
  }
  indices
}

///|
/// Build a zipper focused at the node reached by following child indices.
/// Stops at the deepest reachable node if indices go out of range.
fn[T] RoseZipper::focus_at(
  root : @canopy_core.ProjNode[T],
  indices : Array[Int],
) -> RoseZipper[T] {
  let mut z = RoseZipper::from_root(root)
  for idx in indices {
    match z.go_down(idx) {
      Some(z2) => z = z2
      None => break
    }
  }
  z
}

///|
/// Build a zipper focused on the node with the given node_id.
/// Returns None if node_id is not found in the tree.
fn[T] RoseZipper::from_node_id(
  root : @canopy_core.ProjNode[T],
  target_node_id : Int,
) -> RoseZipper[T]? {
  match find_path_to_node(root, target_node_id) {
    Some(indices) => Some(RoseZipper::focus_at(root, indices))
    None => None
  }
}

///|
/// DFS to find path indices to a node with the given node_id.
fn[T] find_path_to_node(
  node : @canopy_core.ProjNode[T],
  target : Int,
) -> Array[Int]? {
  if node.node_id == target {
    return Some([])
  }
  for i, child in node.children {
    match find_path_to_node(child, target) {
      Some(sub_path) => {
        let path : Array[Int] = [i]
        for idx in sub_path {
          path.push(idx)
        }
        return Some(path)
      }
      None => ()
    }
  }
  None
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test --file main/rose_zipper_wbtest.mbt -v 2>&1 | tail -20`
Expected: All 7 tests pass

- [ ] **Step 5: Run moon check**

Run: `moon check 2>&1 | tail -5`
Expected: No errors

- [ ] **Step 6: Commit**

```bash
git add examples/ideal/main/rose_zipper.mbt examples/ideal/main/rose_zipper_wbtest.mbt
git commit -m "feat(ideal): add ProjNode rose tree zipper for compact view navigation"
```

---

## Task 2: ScopeAnnotation and scope_map builder

**Files:**
- Create: `examples/ideal/main/scope_annotation.mbt`
- Create: `examples/ideal/main/scope_annotation_wbtest.mbt`
- Modify: `examples/ideal/main/moon.pkg` (add `@lambda_proj` import)

- [ ] **Step 1: Add `@lambda_proj` import to moon.pkg**

Add to `examples/ideal/main/moon.pkg` imports:

```
"dowdiness/canopy/lang/lambda/proj" @lambda_proj,
"dowdiness/canopy/core" @canopy_core,
```

- [ ] **Step 2: Write failing tests for scope_map building**

```moonbit
// examples/ideal/main/scope_annotation_wbtest.mbt

///|
test "color_index is stable across calls" {
  let idx1 = binder_color_index("x")
  let idx2 = binder_color_index("x")
  inspect(idx1 == idx2, content="true")
  // Different names may differ
  let idx3 = binder_color_index("add")
  // Both in range 0..7
  inspect(idx1 >= 0 && idx1 < 8, content="true")
  inspect(idx3 >= 0 && idx3 < 8, content="true")
}

///|
test "compute_highlight_set for variable returns binder + usages" {
  // Simulate: scope_map has a Var node pointing to binder with usages
  let scope_map : Map[@proj.NodeId, ScopeAnnotation] = {}
  let var_id = @proj.NodeId::from_int(10)
  let binder_id = @proj.NodeId::from_int(1)
  let usage1 = @proj.NodeId::from_int(10)
  let usage2 = @proj.NodeId::from_int(20)
  scope_map[var_id] = {
    binder_id: Some(binder_id),
    is_definition: false,
    color_index: 0,
    usage_ids: [],
  }
  scope_map[binder_id] = {
    binder_id: Some(binder_id),
    is_definition: true,
    color_index: 0,
    usage_ids: [usage1, usage2],
  }
  let hs = compute_highlight_set(var_id, scope_map)
  inspect(hs.contains(binder_id), content="true")
  inspect(hs.contains(usage1), content="true")
  inspect(hs.contains(usage2), content="true")
}

///|
test "compute_highlight_set for non-identifier returns empty set" {
  let scope_map : Map[@proj.NodeId, ScopeAnnotation] = {}
  let unknown_id = @proj.NodeId::from_int(99)
  let hs = compute_highlight_set(unknown_id, scope_map)
  inspect(hs.length(), content="0")
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `moon test --file main/scope_annotation_wbtest.mbt 2>&1 | head -10`
Expected: Compilation error — `ScopeAnnotation` not defined

- [ ] **Step 4: Implement ScopeAnnotation, build_scope_map, compute_highlight_set**

```moonbit
// examples/ideal/main/scope_annotation.mbt

///|
/// Scope annotation for a single node. Rabbita-local — does not modify ViewNode.
struct ScopeAnnotation {
  binder_id : @proj.NodeId?
  is_definition : Bool
  color_index : Int
  usage_ids : Array[@proj.NodeId]
}

///|
/// Deterministic color index from binder name. Stable across edits.
fn binder_color_index(name : String) -> Int {
  let mut h = 0
  for i = 0; i < name.length(); i = i + 1 {
    h = h * 31 + name[i].to_int()
  }
  if h < 0 {
    h = -h
  }
  h % 8
}

///|
/// Build scope_map for all identifier nodes in the projection tree.
fn build_scope_map(
  editor : @editor.SyncEditor[@ast.Term],
) -> Map[@proj.NodeId, ScopeAnnotation] {
  let scope_map : Map[@proj.NodeId, ScopeAnnotation] = {}
  let proj_root = match editor.get_proj_node() {
    Some(r) => r
    None => return scope_map
  }
  let source_map = editor.get_source_map()
  let flat_proj = @lambda_proj.FlatProj::from_proj_node(proj_root)
  let registry = build_registry(proj_root)
  // Annotate module def init expressions as definition sites
  for i, def in flat_proj.defs {
    let (name, _init_node, _start, node_id) = def
    let cidx = binder_color_index(name)
    let usages = @lambda_edits.find_usages(name, i + 1, flat_proj, registry)
    scope_map[node_id] = {
      binder_id: Some(node_id),
      is_definition: true,
      color_index: cidx,
      usage_ids: usages,
    }
  }
  // Walk tree to annotate Var and Lam nodes
  annotate_tree(proj_root, flat_proj, registry, source_map, scope_map)
  // Second pass: populate Lam binder usage_ids by collecting vars that point to them
  backfill_lam_usages(scope_map)
  scope_map
}

///|
/// Walk ProjNode tree and annotate Var and Lam nodes.
fn annotate_tree(
  node : @canopy_core.ProjNode[@ast.Term],
  flat_proj : @lambda_proj.FlatProj,
  registry : Map[@proj.NodeId, @canopy_core.ProjNode[@ast.Term]],
  source_map : @canopy_core.SourceMap,
  scope_map : Map[@proj.NodeId, ScopeAnnotation],
) -> Unit {
  let node_id = @proj.NodeId::from_int(node.node_id)
  match node.kind {
    Var(name) => {
      if !scope_map.contains(node_id) {
        let binding = @lambda_edits.resolve_binder(
          node_id, name, flat_proj, registry, source_map,
        )
        match binding {
          Some(site) => {
            let (binder_name, binder_nid) = match site {
              LamBinder(lam_id~) => {
                // Extract param name from the Lam term
                let lam_name = match registry.get(lam_id) {
                  Some(lam_node) =>
                    match lam_node.kind {
                      Lam(param_name, _) => param_name
                      _ => name
                    }
                  None => name
                }
                (lam_name, lam_id)
              }
              ModuleBinder(binding_node_id~, ..) => (name, binding_node_id)
            }
            scope_map[node_id] = {
              binder_id: Some(binder_nid),
              is_definition: false,
              color_index: binder_color_index(binder_name),
              usage_ids: [],
            }
          }
          None => () // Free variable — no annotation
        }
      }
    }
    Lam(param_name, _) => {
      if !scope_map.contains(node_id) {
        let cidx = binder_color_index(param_name)
        // Find usages of this param in the body
        // For lam params, we use find_usages starting from the body
        scope_map[node_id] = {
          binder_id: Some(node_id),
          is_definition: true,
          color_index: cidx,
          usage_ids: [], // Will be populated by cross-referencing var annotations
        }
      }
    }
    _ => ()
  }
  for child in node.children {
    annotate_tree(child, flat_proj, registry, source_map, scope_map)
  }
}

///|
/// Second pass: for each Var annotation that points to a Lam binder,
/// add the Var's NodeId to the binder's usage_ids.
fn backfill_lam_usages(
  scope_map : Map[@proj.NodeId, ScopeAnnotation],
) -> Unit {
  // Collect var → binder pairs first to avoid mutation during iteration
  let pairs : Array[(@proj.NodeId, @proj.NodeId)] = []
  for node_id, ann in scope_map {
    if !ann.is_definition {
      match ann.binder_id {
        Some(bid) => pairs.push((node_id, bid))
        None => ()
      }
    }
  }
  for pair in pairs {
    let (var_id, binder_id) = pair
    match scope_map.get(binder_id) {
      Some(binder_ann) =>
        if binder_ann.is_definition {
          binder_ann.usage_ids.push(var_id)
        }
      None => ()
    }
  }
}

///|
/// Build a NodeId → ProjNode registry for the tree.
fn build_registry(
  root : @canopy_core.ProjNode[@ast.Term],
) -> Map[@proj.NodeId, @canopy_core.ProjNode[@ast.Term]] {
  let registry : Map[@proj.NodeId, @canopy_core.ProjNode[@ast.Term]] = {}
  fn walk(node : @canopy_core.ProjNode[@ast.Term]) {
    registry[@proj.NodeId::from_int(node.node_id)] = node
    for child in node.children {
      walk(child)
    }
  }
  walk(root)
  registry
}

///|
/// Compute the set of NodeIds to highlight when a node is selected.
/// Returns empty set for non-identifiers (clear highlights).
fn compute_highlight_set(
  selected_id : @proj.NodeId,
  scope_map : Map[@proj.NodeId, ScopeAnnotation],
) -> @immut/hashset.HashSet[@proj.NodeId] {
  let mut hs = @immut/hashset.HashSet::new()
  match scope_map.get(selected_id) {
    None => hs // Non-identifier: empty set → clear highlights
    Some(ann) => {
      // Include the binder
      match ann.binder_id {
        Some(bid) => {
          hs = hs.add(bid)
          // Get binder's usages
          match scope_map.get(bid) {
            Some(binder_ann) => {
              for uid in binder_ann.usage_ids {
                hs = hs.add(uid)
              }
            }
            None => ()
          }
        }
        None => ()
      }
      // If this IS a binder, include self + usages
      if ann.is_definition {
        hs = hs.add(selected_id)
        for uid in ann.usage_ids {
          hs = hs.add(uid)
        }
      }
      hs
    }
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `moon test --file main/scope_annotation_wbtest.mbt -v 2>&1 | tail -10`
Expected: All 3 tests pass

- [ ] **Step 6: Run moon check**

Run: `moon check 2>&1 | tail -5`
Expected: No errors

- [ ] **Step 7: Commit**

```bash
git add examples/ideal/main/scope_annotation.mbt examples/ideal/main/scope_annotation_wbtest.mbt examples/ideal/main/moon.pkg
git commit -m "feat(ideal): add ScopeAnnotation, build_scope_map, compute_highlight_set"
```

---

## Task 3: Model Extensions + Msg Additions

**Files:**
- Modify: `examples/ideal/main/model.mbt`
- Modify: `examples/ideal/main/msg.mbt`

- [ ] **Step 1: Add OutlineMode enum and new fields to Model**

In `examples/ideal/main/model.mbt`, add the `OutlineMode` enum before the `Model` struct:

```moonbit
///|
pub(all) enum OutlineMode {
  Tree
  Compact
} derive(Show, Eq)
```

Add four fields to the `Model` struct (after `overlay : OverlayState`):

```moonbit
  scope_map : Map[@proj.NodeId, ScopeAnnotation]
  outline_mode : OutlineMode
  highlight_set : @immut/hashset.HashSet[@proj.NodeId]
  zipper : RoseZipper[@ast.Term]?
```

- [ ] **Step 2: Update init_model() in main.mbt**

In `examples/ideal/main/main.mbt`, in `init_model()`, add the new fields to the model literal:

```moonbit
  scope_map: {},
  outline_mode: Tree,
  highlight_set: @immut/hashset.HashSet::new(),
  zipper: None,
```

- [ ] **Step 3: Add new Msg variants**

In `examples/ideal/main/msg.mbt`, add to the `Msg` enum:

```moonbit
  SetOutlineMode(OutlineMode)
  ClearSelection
  CompactNodeClicked(String)
```

- [ ] **Step 4: Add placeholder match arms in update() to avoid compile error**

In `examples/ideal/main/main.mbt`, add to the `update()` match (temporary — Task 6 will implement real logic):

```moonbit
    SetOutlineMode(_) => (@rabbita.none, model)
    ClearSelection => (@rabbita.none, model)
    CompactNodeClicked(_) => (@rabbita.none, model)
```

- [ ] **Step 5: Run moon check**

Run: `moon check 2>&1 | tail -10`
Expected: No errors.

- [ ] **Step 6: Commit**

```bash
git add examples/ideal/main/model.mbt examples/ideal/main/msg.mbt examples/ideal/main/main.mbt
git commit -m "feat(ideal): add OutlineMode, scope_map, highlight_set, zipper to Model"
```

---

## Task 4: Extend refresh() + Zipper Lifecycle

**Files:**
- Modify: `examples/ideal/main/main.mbt`

- [ ] **Step 1: Extend refresh() to build scope_map and manage zipper**

Replace the `refresh()` function in `examples/ideal/main/main.mbt` (lines 43-48):

```moonbit
///|
fn refresh(model : Model) -> Model {
  let outline_state = model.outline_state.refresh(
    model.editor.get_proj_node(),
    model.editor.get_source_map(),
  )
  // Build scope_map from current projection
  let scope_map = build_scope_map(model.editor)
  // Rebuild zipper if it existed
  let zipper : RoseZipper[@ast.Term]? = match model.zipper {
    Some(z) => {
      let saved_indices = z.path_indices()
      match model.editor.get_proj_node() {
        Some(proj_root) => {
          let new_z = RoseZipper::focus_at(proj_root, saved_indices)
          // Verify the node at the restored position is the same kind
          if new_z.focus.node_id == z.focus.node_id {
            Some(new_z)
          } else {
            // Path shifted — try to find the old node by id
            RoseZipper::from_node_id(proj_root, z.focus.node_id)
          }
        }
        None => None
      }
    }
    None => None
  }
  // Clear highlight_set if zipper was invalidated
  let highlight_set = match zipper {
    Some(_) => model.highlight_set
    None =>
      if model.zipper is None {
        model.highlight_set
      } else {
        @immut/hashset.HashSet::new()
      }
  }
  { ..model, outline_state, scope_map, zipper, highlight_set }
}
```

- [ ] **Step 2: Run moon check**

Run: `moon check 2>&1 | tail -10`
Expected: No errors (warnings about unmatched Msg ok)

- [ ] **Step 3: Commit**

```bash
git add examples/ideal/main/main.mbt
git commit -m "feat(ideal): extend refresh() with scope_map building and zipper lifecycle"
```

---

## Task 5: CSS — Binder Palette + Selection States

**Files:**
- Modify: `examples/ideal/web/index.html`

- [ ] **Step 1: Add binder palette and selection CSS**

Add inside the `<style>` tag in `examples/ideal/web/index.html`:

```css
/* Binder palette — 8 hues */
:root {
  --binder-0: #e06c75;
  --binder-1: #61afef;
  --binder-2: #c3e88d;
  --binder-3: #f78c6c;
  --binder-4: #dcdcaa;
  --binder-5: #c792ea;
  --binder-6: #89ddff;
  --binder-7: #ff5370;
}
.binder-0 { color: var(--binder-0); }
.binder-1 { color: var(--binder-1); }
.binder-2 { color: var(--binder-2); }
.binder-3 { color: var(--binder-3); }
.binder-4 { color: var(--binder-4); }
.binder-5 { color: var(--binder-5); }
.binder-6 { color: var(--binder-6); }
.binder-7 { color: var(--binder-7); }

/* Definition site weight */
.def-site { font-weight: 700; }

/* Selection states */
.scope-highlighted { opacity: 1; }
.scope-dimmed { opacity: 0.35; transition: opacity 0.15s ease; }

/* Compact view */
.compact-line {
  display: flex;
  align-items: baseline;
  gap: 6px;
  padding: 2px 8px;
  font-family: 'JetBrains Mono', monospace;
  font-size: 13px;
  line-height: 1.8;
  cursor: pointer;
}
.compact-line:hover { background: #2c2c2c; }
.compact-line.selected { background: #4ec9b022; outline: 1px solid #4ec9b0; }

.compact-block {
  padding-left: 16px;
}

/* Outline mode toggle */
.outline-mode-toggle {
  display: flex;
  gap: 2px;
  margin-left: auto;
}
.outline-mode-toggle button {
  background: none;
  border: 1px solid transparent;
  color: #888;
  font-size: 11px;
  padding: 1px 6px;
  cursor: pointer;
  border-radius: 3px;
}
.outline-mode-toggle button.active {
  color: #d4d4d4;
  border-color: #555;
}
.outline-mode-toggle button:hover {
  color: #d4d4d4;
}
```

- [ ] **Step 2: Commit**

```bash
git add examples/ideal/web/index.html
git commit -m "feat(ideal): add binder palette CSS, selection states, compact view styles"
```

---

## Task 6: Compact View Rendering + Mode Toggle

**Files:**
- Create: `examples/ideal/main/view_compact.mbt`
- Modify: `examples/ideal/main/view_outline.mbt`
- Modify: `examples/ideal/main/main.mbt`

- [ ] **Step 1: Implement view_compact_tree**

```moonbit
// examples/ideal/main/view_compact.mbt

///|
using @rabbita {type Dispatch, type Html}
using @html {div, span, text}

///|
/// Render the compact inline tree view.
fn view_compact_tree(dispatch : Dispatch[Msg], model : Model) -> Html {
  let proj_root = match model.editor.get_proj_node() {
    Some(r) => r
    None => return div(class="compact-tree", [text("No projection")])
  }
  let flat_proj = @lambda_proj.FlatProj::from_proj_node(proj_root)
  let source_map = model.editor.get_source_map()
  let children : Array[Html] = []
  for i, def in flat_proj.defs {
    let (name, _init_node, _start, node_id) = def
    children.push(
      view_compact_def_line(
        dispatch, model, name, node_id, proj_root.children[i], i, source_map,
      ),
    )
  }
  // Render final expression if present
  match flat_proj.final_expr {
    Some(expr) =>
      children.push(view_compact_expr(dispatch, model, expr))
    None => ()
  }
  div(class="compact-tree", children)
}

///|
/// Render one module definition line: name = expr
fn view_compact_def_line(
  dispatch : Dispatch[Msg],
  model : Model,
  name : String,
  node_id : @proj.NodeId,
  init_node : @canopy_core.ProjNode[@ast.Term],
  _def_index : Int,
  _source_map : @canopy_core.SourceMap,
) -> Html {
  let nid_str = node_id.0.to_string()
  let is_selected = model.selected_node == Some(nid_str)
  let ann = model.scope_map.get(node_id)
  let color_class = match ann {
    Some(a) => "binder-" + a.color_index.to_string()
    None => ""
  }
  let hl_class = highlight_class(node_id, model)
  let selected_suffix = if is_selected { " selected" } else { "" }
  let line_class = "compact-line\{selected_suffix} \{hl_class}"
  // Check if init is a nested Module (BlockExpr)
  let body_html : Array[Html] = match init_node.kind {
    Module(_, _) => {
      // Render as indented sub-block
      let inner_flat = @lambda_proj.FlatProj::from_proj_node(init_node)
      let inner_children : Array[Html] = []
      for j, inner_def in inner_flat.defs {
        let (inner_name, _inner_init, _inner_start, inner_nid) = inner_def
        inner_children.push(
          view_compact_def_line(
            dispatch,
            model,
            inner_name,
            inner_nid,
            init_node.children[j],
            j,
            _source_map,
          ),
        )
      }
      match inner_flat.final_expr {
        Some(expr) =>
          inner_children.push(view_compact_expr(dispatch, model, expr))
        None => ()
      }
      [
        div(
          class=line_class,
          on_click=dispatch(CompactNodeClicked(nid_str)),
          [
            span(class="def-site \{color_class}", [text(name)]),
            span(class="punctuation", [text(" = {")]),
          ],
        ),
        div(class="compact-block", inner_children),
        div(class="compact-line", [
          span(class="punctuation", [text("}")]),
        ]),
      ]
    }
    _ => [
      div(
        class=line_class,
        on_click=dispatch(CompactNodeClicked(nid_str)),
        [
          span(class="def-site \{color_class}", [text(name)]),
          span(class="punctuation", [text(" = ")]),
          view_compact_expr(dispatch, model, init_node),
        ],
      ),
    ]
  }
  match body_html {
    [single] => single
    multiple => div(class="", multiple)
  }
}

///|
/// Render an expression inline with binder coloring.
fn view_compact_expr(
  dispatch : Dispatch[Msg],
  model : Model,
  node : @canopy_core.ProjNode[@ast.Term],
) -> Html {
  let node_id = @proj.NodeId::from_int(node.node_id)
  let nid_str = node.node_id.to_string()
  let ann = model.scope_map.get(node_id)
  let color_class = match ann {
    Some(a) => "binder-" + a.color_index.to_string()
    None => ""
  }
  let def_class = match ann {
    Some(a) => if a.is_definition { " def-site" } else { "" }
    None => ""
  }
  let hl_class = highlight_class(node_id, model)
  let css = "\{color_class}\{def_class} \{hl_class}"
  match node.kind {
    Var(name) =>
      span(
        class=css,
        on_click=dispatch(CompactNodeClicked(nid_str)),
        [text(name)],
      )
    Int(n) => span(class="number \{hl_class}", [text(n.to_string())])
    Lam(param, _) => {
      let body = if node.children.length() > 0 {
        view_compact_expr(dispatch, model, node.children[0])
      } else {
        text("")
      }
      span(class=hl_class, [
        span(class="punctuation", [text("(")]),
        span(
          class="def-site \{color_class}",
          on_click=dispatch(CompactNodeClicked(nid_str)),
          [text(param)],
        ),
        span(class="punctuation", [text(") => ")]),
        body,
      ])
    }
    App(_, _) => {
      let children : Array[Html] = []
      for i, child in node.children {
        if i > 0 {
          children.push(text(" "))
        }
        children.push(view_compact_expr(dispatch, model, child))
      }
      span(class=hl_class, children)
    }
    Bop(op, _, _) => {
      let op_str = match op {
        Plus => "+"
        Minus => "-"
      }
      let left = if node.children.length() > 0 {
        view_compact_expr(dispatch, model, node.children[0])
      } else {
        text("?")
      }
      let right = if node.children.length() > 1 {
        view_compact_expr(dispatch, model, node.children[1])
      } else {
        text("?")
      }
      span(class=hl_class, [
        left,
        span(class="operator", [text(" \{op_str} ")]),
        right,
      ])
    }
    If(_, _, _) => {
      let children : Array[Html] = []
      children.push(span(class="keyword", [text("if ")]))
      if node.children.length() > 0 {
        children.push(view_compact_expr(dispatch, model, node.children[0]))
      }
      children.push(span(class="keyword", [text(" then ")]))
      if node.children.length() > 1 {
        children.push(view_compact_expr(dispatch, model, node.children[1]))
      }
      children.push(span(class="keyword", [text(" else ")]))
      if node.children.length() > 2 {
        children.push(view_compact_expr(dispatch, model, node.children[2]))
      }
      span(class=hl_class, children)
    }
    Unit => span(class=hl_class, [text("()")])
    Hole(_) => span(class="hole \{hl_class}", [text("_")])
    Module(_, _) => {
      // Nested module rendered as block — handled by view_compact_def_line
      text("{...}")
    }
    _ => span(class=hl_class, [text("?")])
  }
}

///|
/// Return the highlight CSS class for a node based on the current highlight set.
fn highlight_class(
  node_id : @proj.NodeId,
  model : Model,
) -> String {
  if model.highlight_set.length() == 0 {
    "" // No highlights active — calm state
  } else if model.highlight_set.contains(node_id) {
    "scope-highlighted"
  } else {
    "scope-dimmed"
  }
}
```

- [ ] **Step 2: Add mode toggle to outline panel header**

In `examples/ideal/main/view_outline.mbt`, modify `view_outline_content` to check `model.outline_mode` and dispatch to the appropriate view. Add at the top of `view_outline_content`:

```moonbit
  // Mode toggle buttons
  let tree_active = if model.outline_mode == Tree { " active" } else { "" }
  let compact_active = if model.outline_mode == Compact { " active" } else { "" }
  let mode_toggle = div(class="outline-mode-toggle", [
    @html.button(
      class="tree-btn\{tree_active}",
      on_click=dispatch(SetOutlineMode(Tree)),
      [text("Tree")],
    ),
    @html.button(
      class="compact-btn\{compact_active}",
      on_click=dispatch(SetOutlineMode(Compact)),
      [text("Compact")],
    ),
  ])
```

And switch the body based on mode:

```moonbit
  let body = match model.outline_mode {
    Tree => // existing tree view code
    Compact => view_compact_tree(dispatch, model)
  }
```

- [ ] **Step 3: Handle new Msg variants in update()**

In `examples/ideal/main/main.mbt`, add to the `update()` match:

```moonbit
    SetOutlineMode(mode) => (@rabbita.none, { ..model, outline_mode: mode })
    ClearSelection => (
      @rabbita.none,
      {
        ..model,
        selected_node: None,
        highlight_set: @immut/hashset.HashSet::new(),
        zipper: None,
      },
    )
    CompactNodeClicked(nid_str) => {
      // Build zipper from clicked node
      let zipper = match model.editor.get_proj_node() {
        Some(proj_root) => {
          let nid = @strconv.parse_int(nid_str) catch { _ => 0 }
          RoseZipper::from_node_id(proj_root, nid)
        }
        None => None
      }
      // Compute highlight set
      let nid = @strconv.parse_int(nid_str) catch { _ => 0 }
      let node_id = @proj.NodeId::from_int(nid)
      let highlight_set = compute_highlight_set(node_id, model.scope_map)
      // Sync selection with editor
      let cmd = @rabbita.effect(fn() { js_set_editor_selected_node(nid_str) })
      (cmd, { ..model, selected_node: Some(nid_str), highlight_set, zipper })
    }
```

- [ ] **Step 4: Run moon check**

Run: `moon check 2>&1 | tail -10`
Expected: No errors

- [ ] **Step 5: Run moon test**

Run: `moon test 2>&1 | tail -10`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add examples/ideal/main/view_compact.mbt examples/ideal/main/view_outline.mbt examples/ideal/main/main.mbt
git commit -m "feat(ideal): add compact tree view with binder coloring and mode toggle"
```

---

## Task 7: Keyboard Navigation

**Files:**
- Modify: `examples/ideal/main/view_compact.mbt`
- Modify: `examples/ideal/main/main.mbt`

- [ ] **Step 1: Add keyboard handler to compact view**

In `view_compact_tree`, add a keyboard handler to the root div:

```moonbit
  div(
    class="compact-tree",
    attrs=@html.Attrs::build().tabindex(0),
    on_keydown=fn(kb : @html.Keyboard) {
      match kb.key() {
        "ArrowLeft" => dispatch(CompactNavigate("left"))
        "ArrowRight" => dispatch(CompactNavigate("right"))
        "ArrowUp" => dispatch(CompactNavigate("up"))
        "ArrowDown" => dispatch(CompactNavigate("down"))
        "Escape" => dispatch(ClearSelection)
        _ => @rabbita.none
      }
    },
    children,
  )
```

- [ ] **Step 2: Add CompactNavigate Msg variant**

In `examples/ideal/main/msg.mbt`, add:

```moonbit
  CompactNavigate(String)
```

- [ ] **Step 3: Handle CompactNavigate in update()**

In `examples/ideal/main/main.mbt`, add to the `update()` match:

```moonbit
    CompactNavigate(direction) => {
      let proj_root = match model.editor.get_proj_node() {
        Some(r) => r
        None => return (@rabbita.none, model)
      }
      // Initialize zipper if needed
      let zipper = match model.zipper {
        Some(z) => z
        None =>
          match model.selected_node {
            Some(nid_str) => {
              let nid = @strconv.parse_int(nid_str) catch { _ => 0 }
              match RoseZipper::from_node_id(proj_root, nid) {
                Some(z) => z
                None => RoseZipper::from_root(proj_root)
              }
            }
            None => RoseZipper::from_root(proj_root)
          }
      }
      // Navigate
      let moved = match direction {
        "left" => zipper.go_left()
        "right" => zipper.go_right()
        "up" => zipper.go_up()
        "down" => zipper.go_down(0)
        _ => None
      }
      match moved {
        Some(new_zipper) => {
          let nid = new_zipper.focus.node_id
          let nid_str = nid.to_string()
          let node_id = @proj.NodeId::from_int(nid)
          let highlight_set = compute_highlight_set(node_id, model.scope_map)
          let cmd = @rabbita.effect(fn() { js_set_editor_selected_node(nid_str) })
          (
            cmd,
            {
              ..model,
              selected_node: Some(nid_str),
              highlight_set,
              zipper: Some(new_zipper),
            },
          )
        }
        None => (@rabbita.none, model) // Boundary — no-op
      }
    }
```

- [ ] **Step 4: Run moon check**

Run: `moon check 2>&1 | tail -5`
Expected: No errors

- [ ] **Step 5: Commit**

```bash
git add examples/ideal/main/view_compact.mbt examples/ideal/main/msg.mbt examples/ideal/main/main.mbt
git commit -m "feat(ideal): add keyboard navigation via persistent ProjNode zipper"
```

---

## Task 8: Visual Verification + Final Tests

**Files:**
- Run existing tests
- Manual browser verification

- [ ] **Step 1: Run all tests**

Run: `moon test 2>&1 | tail -20`
Expected: All tests pass

- [ ] **Step 2: Run moon check and moon fmt**

Run: `moon check && moon fmt 2>&1 | tail -5`
Expected: Clean

- [ ] **Step 3: Run moon info to update interfaces**

Run: `moon info 2>&1 | tail -5`
Expected: Updated .mbti files

- [ ] **Step 4: Check git diff for .mbti changes**

Run: `git diff *.mbti`
Expected: New exports visible (ScopeAnnotation, RoseZipper, OutlineMode, etc.)

- [ ] **Step 5: Start dev server for visual verification**

Run: `cd examples/ideal/web && npm run dev`
Expected: Server starts at localhost. Open browser and verify:
- Outline panel shows Tree/Compact toggle
- Compact mode renders inline definitions with binder colors
- Bold definition names, regular usages
- Clicking a variable highlights binder + usages, dims rest
- Clicking a non-identifier clears highlights
- Arrow keys navigate between nodes
- Escape clears selection

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "feat(ideal): scope-colored compact tree view — Phase 1 complete"
```

---

## Dependency Graph

```
Task 1 (Zipper) ─────────────────────────┐
                                          ├─→ Task 4 (refresh + lifecycle)
Task 2 (ScopeAnnotation) ────────────────┤
                                          │
Task 3 (Model + Msg) ────────────────────┤
                                          ├─→ Task 6 (Compact view + toggle)
Task 5 (CSS) ────────────────────────────┘         │
                                                    ├─→ Task 7 (Keyboard nav)
                                                    │
                                                    └─→ Task 8 (Verification)
```

Tasks 1, 2, 3, 5 can be done in parallel. Task 4 depends on 1+2+3. Task 6 depends on 4+5. Task 7 depends on 6. Task 8 depends on all.
