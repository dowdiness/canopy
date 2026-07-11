# AST Zipper for Tree Pane Navigation and Structural Editing

**Date:** 2026-03-28
**Revised:** 2026-03-29
**Status:** Approved

**Prerequisites (in order):**

1. **Two-layer architecture (TermSym)** — ✅ Complete (archived). Adding `Hole(Int)` to `Term` triggers only `replay` and `TermSym` impls; all `TermSym` consumers get compile errors that self-document what to fix.

2. **Framework Extraction Phase 1** — ✅ Complete. Tier-2 methods (`delete_node`, `commit_edit`, `apply_text_transform`, `move_node`) are in place on `SyncEditor[T]`.

3. **Framework Extraction Phase 2** — ✅ Complete. `FlatProj` moved to `lang/lambda/flat/`. Zipper files land directly in their final location.

**References:**
- Huet, "Functional Pearl: The Zipper" (1997) — core data structure
- McBride, "The Derivative of a Regular Type is its Type of One-Hole Contexts" (2001) — Zipper as type derivative
- Omar et al., "Hazelnut: a bidirectionally typed structure editor calculus" (POPL 2017) — edit action semantics, typed holes
- Adams et al., "Grove: A Bidirectionally Typed Collaborative Structure Editor Calculus" (POPL 2025) — structural identity, future collaborative editing (see `docs/architecture/grove-and-structural-identity.md`)
- [tylr paper (TyDe 2022)](https://hazel.org/papers/tiny-tylr-tyde2022.pdf) — tile-based editing (reviewed, deferred)

**Architecture docs:**
- `docs/architecture/zipper-roundtrip-invariants.md` — transient Zipper principle, cursor relocation, projection isomorphism
- `docs/architecture/grove-and-structural-identity.md` — text-first vs structure-first, incremental adoption path
- `docs/architecture/edit-action-progression.md` — deferred operations and promotion path

## Goal

Add a Huet Zipper over `Term` to Canopy's tree pane with four properties:

1. **NodeId-primary cursor** — the cursor is a stable node identity; the Zipper is a transient computation constructed on demand for navigation and context
2. **Edit actions as data** — structural operations are reified values mapping to the existing `TreeEditOp` backend, enabling undo/redo, operation logging, and future collaborative structural editing
3. **Bidirectional text ↔ tree cursor sync** — text cursor position and tree cursor (NodeId) stay synchronized via SourceMap
4. **Hole-ready AST** — a dedicated `Hole` variant (not `Var("_")`) that reserves space for future type-aware editing

The design does not force a choice between text editing fluidity and structural editing semantics. Both coexist.

## Key Architectural Premise: NodeId Is the Cursor, Zipper Is a Lens

Text CRDT remains ground truth. The cursor is a **NodeId** — stable across reparses via reconciliation. The Zipper is a **transient lens** constructed from the NodeId when structural navigation or context information is needed, then discarded.

```
Text edit:
  keystroke → CRDT op → loom reparse → new Term
  → NodeId survives automatically (reconcile preserves it)

Structural edit:
  EditAction → resolve cursor NodeId → map to TreeEditOp → apply_tree_edit
  → CRDT op → loom reparse → new Term
  → relocate cursor (follow text cursor via FocusHint, NodeId fallback)

Navigation:
  Direction → construct Zipper from cursor NodeId → navigate → extract new NodeId

Cursor sync:
  Text cursor at offset N → source_map.innermost_node_at(N) → NodeId
  Tree cursor NodeId → source_map.get_range(NodeId) → highlight text span
```

The Zipper is never persisted. There is no `sync_after_roundtrip`.

## The Actual AST

```moonbit
pub(all) enum Bop { Plus; Minus }

pub(all) enum Term {
  Int(Int)
  Var(VarName)
  Lam(VarName, Term)
  App(Term, Term)
  Bop(Bop, Term, Term)
  If(Term, Term, Term)
  Module(Array[(VarName, Term)], Term)
  Unit
  Unbound(VarName)
  Error(String)
  Hole(Int)             // NEW — dedicated hole with unique ID
}
```

**`Hole(Int)` replaces `Var("_")` as placeholder.** The `Int` is a hole ID, unique within a single edit session. Holes are **ephemeral** — they do not survive the text round-trip. `print_term` outputs `_` for all holes regardless of ID. After reparse, the parser reads `_` as a fresh `Hole` with a new ID (recommendation: always use 0 — the parser has no global counter). Hole metadata is managed via NodeId after reconciliation, not via hole IDs embedded in Term. See "Hole Lifecycle" for details.

---

## Data Types

### Context Type (the Derivative)

```moonbit
pub(all) enum TermCtx {
  CtxLamBody(VarName)

  CtxAppFunc(Term)
  CtxAppArg(Term)

  CtxBopLeft(Bop, Term)
  CtxBopRight(Bop, Term)

  CtxIfCond(Term, Term)
  CtxIfThen(Term, Term)
  CtxIfElse(Term, Term)

  CtxModuleDef(
    Array[(VarName, Term)],  // defs before hole
    VarName,                 // name at hole position
    Array[(VarName, Term)],  // defs after hole
    Term                     // body
  )
  CtxModuleBody(Array[(VarName, Term)])
}
```

### Zipper

```moonbit
pub(all) struct Zipper {
  focus : Term
  path : @immut/list.T[TermCtx]
}
```

### Position Role

Derived from the top of the Zipper path. Tells the UI and future tools **what kind of position** the cursor occupies.

```moonbit
pub(all) enum PositionRole {
  Root                    // path = Nil
  FunctionPosition        // App(□, _)
  ArgumentPosition        // App(_, □)
  BinderBody(VarName)     // Lam(x, □)
  Condition               // If(□, _, _)
  ThenBranch              // If(_, □, _)
  ElseBranch              // If(_, _, □)
  OperandLeft(Bop)        // Bop(op, □, _)
  OperandRight(Bop)       // Bop(op, _, □)
  LetDefinition(VarName)  // Module def value
  LetBody                 // Module body
}

pub fn position_role(z : Zipper) -> PositionRole {
  match z.path {
    Nil => Root
    Cons(ctx, _) =>
      match ctx {
        CtxLamBody(param) => BinderBody(param)
        CtxAppFunc(_) => FunctionPosition
        CtxAppArg(_) => ArgumentPosition
        CtxBopLeft(op, _) => OperandLeft(op)
        CtxBopRight(op, _) => OperandRight(op)
        CtxIfCond(..) => Condition
        CtxIfThen(..) => ThenBranch
        CtxIfElse(..) => ElseBranch
        CtxModuleDef(_, name, ..) => LetDefinition(name)
        CtxModuleBody(_) => LetBody
      }
  }
}
```

**Uses:**
- UI: context menu filters available actions by role
- Future type checker: `PositionRole` → expected type constraint for the focused hole
- Accessibility: screen reader can announce "you are in the else branch of an if expression"

### Edit Action (Cursor-Relative Frontend for TreeEditOp)

Structural operations are **data**, not just functions. Each EditAction maps trivially to a `TreeEditOp` by resolving the cursor NodeId. Navigation is a separate function, not an EditAction.

```moonbit
pub(all) enum EditAction {
  // Core structural
  Delete
  WrapLam(VarName)
  WrapApp
  WrapIf
  WrapBop(Bop)
  Unwrap(Int)            // child index to keep (0 = first child)
  SwapChildren
  ChangeOperator(Bop)

  // Leaf editing
  CommitEdit(String)     // new text for focused leaf
}

pub(all) enum Direction {
  Up
  Down
  Left
  Right
}
```

**`Unwrap(Int)` instead of plain `Unwrap`:** Plain unwrap silently discards siblings. `Unwrap(0)` on `App(f, arg)` keeps `f` and discards `arg`. `Unwrap(1)` keeps `arg` and discards `f`. The UI presents a choice when the node has multiple non-trivial children. If the non-kept children are all `Hole`s or trivial literals, no confirmation is needed.

**Why data, not functions:**

| Capability | Functions (`wrap_in_lambda(id, "x")`) | Data (`WrapLam("x")`) |
|---|---|---|
| Structural undo | ✗ must diff text | ✓ invert the action |
| Operation log | ✗ "some function was called" | ✓ `[Delete, WrapLam("f")]` |
| Collaborative conflict detection | ✗ compare text diffs | ✓ "A wrapped in λ, B deleted same node" |
| Serialization (eg-walker TransformOp) | ✗ | ✓ `EditAction` is serializable |
| Context menu rendering | redundant labels | `EditAction` → label + shortcut |

**Deferred operations** (stay TreeEditOp-only for now):
- Module binding operations (Add, Delete, Duplicate, MoveUp/Down) — need FlatProj access
- Refactoring (ExtractToLet, Inline, InlineAll, Rename) — need scope analysis
- Drop/Relocate — needs two-cursor model (cut/paste)
- InsertChild (non-Module) — fixed-arity constructors

See `docs/architecture/edit-action-progression.md` for the promotion path for each.

### Action Record

Each structural edit is logged with cursor context:

```moonbit
pub(all) struct ActionRecord {
  action : EditAction
  cursor_before : NodeId
  cursor_after : NodeId
  role : PositionRole       // position context at time of edit
}
```

---

## Hole Lifecycle

Holes are ephemeral markers. Their lifecycle is:

```
1. User performs Delete → TreeEditOp::Delete(cursor) → text becomes "_"
   Hole metadata stored in HoleRegistry keyed by the hole's NodeId (assigned by reconcile)

2. print_term(Hole(_)) → outputs `_`

3. CRDT op → loom reparse → parser reads `_` → produces Hole(0)

4. reconcile matches old ProjNode[Hole(_)] with new ProjNode[Hole(_)]
   via same_kind (both are Hole) → preserves NodeId

5. HoleRegistry is keyed by NodeId, not hole ID → metadata survives round-trip
```

**Key invariant:** Hole metadata lives in the projection layer (keyed by `NodeId`), not in `Term`. The `Int` inside `Hole(Int)` is only used for local identity between creation and the next reconcile pass.

```moonbit
pub(all) struct HoleInfo {
  created_by : EditAction
  role : PositionRole
  // Future: expected_type : Type?
}

/// HoleRegistry is keyed by NodeId (stable across round-trips),
/// not by the Int inside Hole(Int) (ephemeral).
pub(all) struct HoleRegistry {
  priv next_id : Ref[Int]
  priv holes : Map[NodeId, HoleInfo]
}

pub fn HoleRegistry::new() -> HoleRegistry {
  { next_id: Ref::new(0), holes: {} }
}

pub fn HoleRegistry::fresh_hole_id(self : HoleRegistry) -> Int {
  let id = self.next_id.val
  self.next_id.val = id + 1
  id
}

/// Register metadata after reconcile assigns a stable NodeId.
pub fn HoleRegistry::register(
  self : HoleRegistry,
  node_id : NodeId,
  info : HoleInfo,
) -> Unit {
  self.holes[node_id] = info
}

pub fn HoleRegistry::get(self : HoleRegistry, node_id : NodeId) -> HoleInfo? {
  self.holes.get(node_id)
}

/// Remove entries for NodeIds no longer in the tree.
pub fn HoleRegistry::prune(self : HoleRegistry, live_ids : @immut/hashset.HashSet[NodeId]) -> Unit {
  let stale : Array[NodeId] = []
  for id in self.holes.keys() {
    if not(live_ids.contains(id)) { stale.push(id) }
  }
  for id in stale { self.holes.remove(id) }
}
```

`HoleRegistry::prune` is called during `TreeEditorState::refresh`, alongside the existing stale-ID pruning for selection, editing\_node, and drag state. (Note: `collapsed_nodes` is not pruned — stale entries are harmless.)

---

## Navigation

Four directions. All return `Zipper?` — `None` means movement not possible. Navigation is a **separate function**, not an EditAction.

### plug

```moonbit
fn plug(ctx : TermCtx, child : Term) -> Term {
  match ctx {
    CtxLamBody(param) => Lam(param, child)
    CtxAppFunc(arg) => App(child, arg)
    CtxAppArg(func) => App(func, child)
    CtxBopLeft(op, right) => Bop(op, child, right)
    CtxBopRight(op, left) => Bop(op, left, child)
    CtxIfCond(then_, else_) => If(child, then_, else_)
    CtxIfThen(cond, else_) => If(cond, child, else_)
    CtxIfElse(cond, then_) => If(cond, then_, child)
    CtxModuleDef(before, name, after, body) => {
      let defs = Array::new()
      for def in before { defs.push(def) }
      defs.push((name, child))
      for def in after { defs.push(def) }
      Module(defs, body)
    }
    CtxModuleBody(defs) => Module(defs, child)
  }
}
```

### go_down, go_up, go_left, go_right

```moonbit
pub fn go_down(z : Zipper) -> Zipper?
pub fn go_up(z : Zipper) -> Zipper?
pub fn go_right(z : Zipper) -> Zipper?
pub fn go_left(z : Zipper) -> Zipper?
```

Each function pattern-matches on `z.focus` (for `go_down`) or `z.path` (for `go_up`, `go_left`, `go_right`) and swaps the focus with the appropriate sibling/parent.

**Module navigation:** `go_right` from `CtxModuleDef` advances to next def or (if last) to body. `go_left` from `CtxModuleBody` moves to last def.

**Leaf nodes:** `go_down` on `Int`, `Var`, `Unit`, `Unbound`, `Error`, `Hole` returns `None`.

### navigate (NodeId-level)

Constructs a transient Zipper, navigates, extracts the new NodeId:

```moonbit
pub fn navigate(
  cursor : NodeId,
  direction : Direction,
  term : Term,
  proj_root : ProjNode[Term],
) -> NodeId? {
  let z = zipper_from_node_id(cursor, term, proj_root)?
  let z2 = match direction {
    Up => go_up(z)?
    Down => go_down(z)?
    Left => go_left(z)?
    Right => go_right(z)?
  }
  let proj = find_proj_node_for_focus(z2, proj_root)?
  Some(proj.node_id)
}
```

### Helpers

```moonbit
pub fn to_root(z : Zipper) -> Term
pub fn from_root(term : Term) -> Zipper
pub fn depth(z : Zipper) -> Int
```

### ctx_to_child_index

Maps a context frame to the child index of the hole within the reconstructed parent.

```moonbit
fn ctx_to_child_index(ctx : TermCtx) -> Int {
  match ctx {
    CtxLamBody(_)          => 0
    CtxAppFunc(_)          => 0
    CtxAppArg(_)           => 1
    CtxBopLeft(..)         => 0
    CtxBopRight(..)        => 1
    CtxIfCond(..)          => 0
    CtxIfThen(..)          => 1
    CtxIfElse(..)          => 2
    CtxModuleDef(before, ..) => before.length()
    CtxModuleBody(defs)    => defs.length()
  }
}
```

### children_of

```moonbit
fn children_of(term : Term) -> Array[Term] {
  match term {
    Lam(_, body) => [body]
    App(f, a) => [f, a]
    Bop(_, l, r) => [l, r]
    If(c, t, e) => [c, t, e]
    Module(defs, body) => {
      let result : Array[Term] = []
      for def in defs { result.push(def.1) }
      result.push(body)
      result
    }
    _ => []
  }
}
```

---

## Edit Dispatch

EditAction maps trivially to TreeEditOp by resolving the cursor NodeId. The existing `compute_*` handlers in `projection/text_edit_*.mbt` do the text computation. No new text computation code.

```moonbit
fn to_tree_edit_op(cursor : NodeId, action : EditAction) -> @edits.TreeEditOp {
  match action {
    Delete => @edits.TreeEditOp::Delete(node_id=cursor)
    WrapLam(name) => @edits.TreeEditOp::WrapInLambda(node_id=cursor, var_name=name)
    WrapApp => @edits.TreeEditOp::WrapInApp(node_id=cursor)
    WrapIf => @edits.TreeEditOp::WrapInIf(node_id=cursor)
    WrapBop(op) => @edits.TreeEditOp::WrapInBop(node_id=cursor, op=op)
    Unwrap(idx) => @edits.TreeEditOp::Unwrap(node_id=cursor, keep_child_index=idx)
    SwapChildren => @edits.TreeEditOp::SwapChildren(node_id=cursor)
    ChangeOperator(op) => @edits.TreeEditOp::ChangeOperator(node_id=cursor, new_op=op)
    CommitEdit(text) => @edits.TreeEditOp::CommitEdit(node_id=cursor, new_value=text)
  }
}
```

---

## Cursor Relocation After Structural Edits

When a structural edit changes the constructor at the cursor position (wrap, unwrap, delete), reconciliation assigns a fresh NodeId. The cursor must be relocated.

`apply_tree_edit` already applies `FocusHint` internally — it moves the text cursor to the appropriate position (e.g., after `WrapIf`, the text cursor lands on the condition hole). The tree cursor should follow the text cursor to stay synchronized.

```moonbit
fn relocate_cursor(
  old_cursor : NodeId,
  editor : SyncEditor[Term],
) -> NodeId? {
  // Primary strategy: follow the text cursor.
  // apply_tree_edit already applied FocusHint (e.g., MoveCursor to the
  // condition hole after WrapIf). Use the text cursor position to derive
  // the tree cursor, ensuring text and tree cursors stay synchronized.
  let source_map = editor.get_source_map()?
  let text_cursor = editor.get_cursor()
  match source_map.innermost_node_at(text_cursor) {
    Some(id) => Some(id)
    None => {
      // Fallback: FocusHint didn't land on a node (e.g., whitespace).
      // Check if old NodeId survived reconcile.
      let proj_root = editor.get_proj_node()?
      if node_exists_in_tree(proj_root, old_cursor) {
        Some(old_cursor)
      } else {
        None
      }
    }
  }
}
```

```moonbit
fn node_exists_in_tree(proj_root : ProjNode[Term], target : NodeId) -> Bool {
  if proj_root.node_id == target.to_int() { return true }
  for child in proj_root.children {
    if node_exists_in_tree(child, target) { return true }
  }
  false
}
```

This approach is simpler and more correct than path-index replay because:
- It respects the existing `FocusHint` logic in each `compute_*` handler
- Text and tree cursors always agree (no divergence after wraps)
- No path indices to save/replay, no ancestor-walk needed for relocation

### focus_at (with ancestor-walk fallback)

```moonbit
pub fn focus_at(term : Term, indices : Array[Int]) -> Zipper {
  let mut z = from_root(term)
  for idx in indices {
    match navigate_to_child(z, idx) {
      Some(z2) => z = z2
      None => break  // stop at deepest reachable ancestor
    }
  }
  z  // always succeeds — returns at least root
}

fn navigate_to_child(z : Zipper, child_idx : Int) -> Zipper? {
  let first = go_down(z)?
  var current = first
  for _ in 0..<child_idx {
    current = go_right(current)?
  }
  Some(current)
}
```

**Why ancestor-walk, not `None`:** With Hole support, structural edits always produce parseable text, so path indices match the new tree in practice. The ancestor walk is cheap insurance for edge cases (error recovery during user-typed leaf edits, concurrent remote edits). See `docs/architecture/zipper-roundtrip-invariants.md`.

---

## Zipper ↔ NodeId Bridge

### zipper_from_node_id

Constructs a transient Zipper from a NodeId:

```moonbit
pub fn zipper_from_node_id(
  node_id : NodeId,
  term : Term,
  proj_root : ProjNode[Term],
) -> Zipper? {
  let indices = path_indices_to_node(proj_root, node_id)?
  Some(focus_at(term, indices))
}
```

### find_proj_node_for_focus

Extracts a ProjNode (and its NodeId) from a Zipper position. Uses direct child indexing — safe because ProjNode[Term] is structurally isomorphic to Term by construction (see `docs/architecture/zipper-roundtrip-invariants.md`).

```moonbit
pub fn find_proj_node_for_focus(
  z : Zipper,
  proj_root : ProjNode[Term],
) -> ProjNode[Term]? {
  let trail = zipper_to_trail(z)
  walk_proj(proj_root, trail, 0)
}

fn zipper_to_trail(z : Zipper) -> Array[Int] {
  let indices = Array::new()
  let mut current = z
  while true {
    match current.path {
      Nil => break
      Cons(ctx, _) => {
        indices.push(ctx_to_child_index(ctx))
        match go_up(current) {
          Some(parent) => current = parent
          None => break
        }
      }
    }
  }
  indices.reverse()
  indices
}

fn walk_proj(
  node : ProjNode[Term],
  trail : Array[Int],
  depth : Int,
) -> ProjNode[Term]? {
  if depth >= trail.length() {
    return Some(node)
  }
  let child_idx = trail[depth]
  if child_idx < node.children.length() {
    walk_proj(node.children[child_idx], trail, depth + 1)
  } else {
    None
  }
}
```

### path_indices_to_node

```moonbit
fn path_indices_to_node(
  root : ProjNode[Term],
  target : NodeId,
) -> Array[Int]? {
  fn go(node : ProjNode[Term], acc : Array[Int]) -> Array[Int]? {
    if node.node_id == target { return Some(acc) }
    for i, child in node.children {
      let next = acc.copy()
      next.push(i)
      match go(child, next) {
        Some(path) => return Some(path)
        None => ()
      }
    }
    None
  }
  go(root, [])
}
```

### Text ↔ NodeId sync

```moonbit
// Text cursor → tree cursor
pub fn node_id_at_offset(
  source_map : SourceMap,
  offset : Int,
) -> NodeId? {
  source_map.innermost_node_at(offset)
}

// Tree cursor → text highlight
pub fn text_range_from_node_id(
  source_map : SourceMap,
  node_id : NodeId,
) -> (Int, Int)? {
  source_map.get_range(node_id)
}
```

---

## Path Indices

```moonbit
pub fn to_path_indices(z : Zipper) -> Array[Int]
pub fn focus_at(term : Term, indices : Array[Int]) -> Zipper  // with ancestor-walk
```

Index mapping per context:

| Context | Index |
|---------|-------|
| `CtxLamBody` | 0 |
| `CtxAppFunc` | 0 |
| `CtxAppArg` | 1 |
| `CtxBopLeft` | 0 |
| `CtxBopRight` | 1 |
| `CtxIfCond` | 0 |
| `CtxIfThen` | 1 |
| `CtxIfElse` | 2 |
| `CtxModuleDef(before, ..)` | `before.length()` |
| `CtxModuleBody(defs)` | `defs.length()` |

---

## Framework Boundary: Zipper is Language-Specific

The Zipper is **not** part of the generic framework (`framework/`). It lives in the language package (`lang/lambda/`). Reasons:

1. `TermCtx` is the derivative of `Term` — a different AST enum has a different derivative.
2. `TreeEditorState[T]` is framework-level and must not depend on lambda-specific types.
3. `EditAction` variants like `WrapLam(VarName)` are lambda-specific.

```moonbit
/// Lambda-specific editor state that adds hole management and action logging
/// on top of the generic tree editor.
/// Lives in lang/lambda/, not in framework/.
pub struct LambdaEditorState {
  tree_state : TreeEditorState[Term]
  hole_registry : HoleRegistry
  action_log : Array[ActionRecord]
  // NO zipper: Zipper? — the Zipper is transient
}
```

The cursor IS `tree_state.selection[0]`. No separate cursor field.

**Acid test:** `framework/` compiles with zero imports from `zipper.mbt` or `TermCtx`.

---

## Integration with Existing Architecture

### Edit Dispatch

```moonbit
fn on_tree_key(
  state : LambdaEditorState,
  action : EditAction,
  sync_editor : SyncEditor[Term],
  timestamp_ms : Int,
) -> LambdaEditorState {
  let cursor = match state.tree_state.selection.get(0) {
    Some(id) => id
    None => return state
  }

  let proj_root = match sync_editor.get_proj_node() {
    Some(r) => r
    None => return state
  }

  // 1. Compute context before edit (transient Zipper)
  let role = match zipper_from_node_id(cursor, sync_editor.get_ast(), proj_root) {
    Some(z) => position_role(z)
    None => Root
  }

  // 2. Map EditAction to TreeEditOp and dispatch via existing pipeline
  //    apply_tree_edit handles FocusHint internally (moves text cursor)
  let tree_op = to_tree_edit_op(cursor, action)
  match sync_editor.apply_tree_edit(tree_op, timestamp_ms) {
    Err(_) => return state
    Ok(_) => ()
  }

  // 3. Relocate tree cursor to follow text cursor (FocusHint already applied)
  let new_cursor = match relocate_cursor(cursor, sync_editor) {
    Some(id) => id
    None => return state
  }

  // 4. Update selection
  let new_tree_state = { ..state.tree_state, selection: [new_cursor] }

  // 5. Log the action
  let log = state.action_log.copy()
  log.push({
    action,
    cursor_before: cursor,
    cursor_after: new_cursor,
    role,
  })

  // 6. Register hole metadata for newly created holes
  match action {
    Delete | WrapApp | WrapIf | WrapBop(_) =>
      register_new_holes(state.hole_registry, sync_editor, action)
    _ => ()
  }

  { ..state, tree_state: new_tree_state, action_log: log }
}
```

### on_tree_navigate

```moonbit
fn on_tree_navigate(
  state : LambdaEditorState,
  direction : Direction,
  sync_editor : SyncEditor[Term],
) -> LambdaEditorState {
  let cursor = match state.tree_state.selection.get(0) {
    Some(id) => id
    None => return state
  }

  let proj_root = match sync_editor.get_proj_node() {
    Some(r) => r
    None => return state
  }

  // Expand collapsed node on Down navigation
  let tree_state = match direction {
    Down =>
      if state.tree_state.collapsed_nodes.contains(cursor) {
        state.tree_state.expand_node(cursor, proj_root, sync_editor.get_source_map())
      } else {
        state.tree_state
      }
    _ => state.tree_state
  }

  match navigate(cursor, direction, sync_editor.get_ast(), proj_root) {
    Some(new_cursor) =>
      { ..state, tree_state: { ..tree_state, selection: [new_cursor] } }
    None => state
  }
}
```

### register_new_holes

After the text round-trip, scan the ProjNode tree for holes not yet in the registry.
Each hole gets its role from its **position in the post-edit tree**, not from the pre-edit
cursor role. This matters for wraps that create multiple holes: `WrapIf` creates holes at
Condition and ElseBranch positions, and each should get the correct role.

```moonbit
fn register_new_holes(
  registry : HoleRegistry,
  sync_editor : SyncEditor[Term],
  action : EditAction,
) -> Unit {
  let proj_root = match sync_editor.get_proj_node() {
    Some(r) => r
    None => return
  }
  let term = sync_editor.get_ast()
  collect_new_holes(proj_root, term, registry, action)
}

fn collect_new_holes(
  proj_root : ProjNode[Term],
  term : Term,
  registry : HoleRegistry,
  action : EditAction,
) -> Unit {
  fn go(node : ProjNode[Term]) {
    match node.kind {
      Hole(_) =>
        if registry.get(node.node_id).is_empty() {
          // Derive role from this hole's position in the post-edit tree
          let role = match zipper_from_node_id(node.node_id, term, proj_root) {
            Some(z) => position_role(z)
            None => Root
          }
          registry.register(node.node_id, { created_by: action, role })
        }
      _ => ()
    }
    for child in node.children {
      go(child)
    }
  }
  go(proj_root)
}
```

### Context Menu (available_actions)

```moonbit
fn available_actions(
  cursor : NodeId,
  term : Term,
  proj_root : ProjNode[Term],
) -> Array[EditAction] {
  let z = match zipper_from_node_id(cursor, term, proj_root) {
    Some(z) => z
    None => return []
  }
  let focus = z.focus
  let actions : Array[EditAction] = []

  // Hole is already a placeholder — Delete is a no-op
  // Module uses dedicated binding actions, not generic Delete/Wrap/Unwrap
  match focus {
    Hole(_) | Module(_, _) => ()
    _ => actions.push(Delete)
  }

  // Wrap and Unwrap not offered for Module or Hole
  match focus {
    Module(_, _) => ()
    _ => {
      actions.push(WrapLam("x"))
      actions.push(WrapApp)
      actions.push(WrapIf)
      actions.push(WrapBop(Plus))
      actions.push(WrapBop(Minus))

      // Unwrap: one per child (non-leaf only)
      let n = children_count(focus)
      for i in 0..<n {
        actions.push(Unwrap(i))
      }
    }
  }

  // SwapChildren: Bop and If only (backend only supports these)
  match focus {
    Bop(..) | If(..) => actions.push(SwapChildren)
    _ => ()
  }

  // ChangeOperator: Bop focus only
  match focus {
    Bop(Plus, _, _) => actions.push(ChangeOperator(Minus))
    Bop(Minus, _, _) => actions.push(ChangeOperator(Plus))
    _ => ()
  }

  actions
}
```

### Keyboard Mapping

```
↑  →  on_tree_navigate(Up)
↓  →  on_tree_navigate(Down)       — expand if collapsed
←  →  on_tree_navigate(Left)
→  →  on_tree_navigate(Right)

Enter       →  start inline editing (TreeEditorState)
Delete/Bksp →  on_tree_key(Delete)
Escape      →  clear selection
```

Context menu items are generated from `available_actions`.

---

## What Changes

### Prerequisite change to Term

With TermSym already landed, adding `Hole(Int)` requires updating only the TermSym boundary.

| File | Change |
|------|--------|
| `loom/examples/lambda/src/ast/term.mbt` | Add `Hole(Int)` variant to `Term` enum |
| `loom/examples/lambda/src/ast/sym.mbt` | Add `hole(Int) -> Self` to `TermSym` trait |
| `loom/examples/lambda/src/ast/sym.mbt` | Add `hole` arm to `replay` (one new match arm) |
| `loom/examples/lambda/src/ast/sym.mbt` | Add `Pretty::hole` impl: `{ repr: "_" }` |
| `loom/examples/lambda/src/ast/sym.mbt` | Add `Term::hole` impl: `Hole(n)` |
| `loom/examples/lambda/src/parser/` | Parser recognizes `_` as `Hole` token (always ID 0) |
| `loom/examples/lambda/src/cst_parser.mbt` | Add `@token.Hole` to `token_starts_expression`, `token_starts_application_atom`, `parse_atom`, and `parse_application` |
| `loom/examples/lambda/src/lambda_spec.mbt` | Add `HoleToken => Some(@token.Hole)` to `syntax_kind_to_token_kind` (required for incremental subtree reuse) |
| `loom/examples/lambda/src/ast/proj_traits.mbt` | Add `Hole` cases to `TreeNode` (`children`, `same_kind`) and `Renderable` impls |
| `lang/lambda/proj/proj_node.mbt` | Add `HoleLiteral => Hole(0)` to `syntax_to_proj_node` |

### New files

All zipper files land directly in `lang/lambda/zipper/`.

**`lang/lambda/zipper/moon.pkg`:**
```
import {
  "dowdiness/canopy/framework/core" @core,
  "dowdiness/canopy/lang/lambda/edits" @edits,
  "dowdiness/lambda/ast" @ast,
  "moonbitlang/core/immut/hashset" @immut/hashset,
  "moonbitlang/core/list" @list,
}

import {
  "dowdiness/canopy/lang/lambda/proj" @proj,
} for "wbtest"
```

Note: Implementation uses `@list.List` (from `moonbitlang/core/list`) instead of `@immut/list.T` — the immutable list API changed in recent MoonBit versions. List constructors are `Empty`/`More(head, tail=rest)`, constructed via `@list.cons()` / `@list.new()`.

| File | Purpose |
|------|---------|
| `lang/lambda/zipper/zipper.mbt` | `Zipper`, `TermCtx`, `plug`, navigation, `children_of`, `ctx_to_child_index`, path indices, `to_root`, `from_root`, `focus_at` (with ancestor-walk) |
| `lang/lambda/zipper/zipper_action.mbt` | `EditAction`, `Direction`, `ActionRecord`, `to_tree_edit_op` |
| `lang/lambda/zipper/zipper_role.mbt` | `PositionRole`, `position_role`, `available_actions` |
| `lang/lambda/zipper/zipper_hole.mbt` | `HoleInfo`, `HoleRegistry` (keyed by NodeId) |
| `lang/lambda/zipper/zipper_bridge.mbt` | `zipper_from_node_id`, `find_proj_node_for_focus`, `path_indices_to_node`, `node_id_at_offset`, `text_range_from_node_id` |
| `lang/lambda/zipper/zipper_wbtest.mbt` | White-box tests |
| `lang/lambda/lambda_editor_state.mbt` | `LambdaEditorState`, `on_tree_key`, `on_tree_navigate`, `relocate_cursor`, `register_new_holes` |

### Modified files

| File | Change |
|------|--------|
| (none in `TreeEditorState`) | Cursor is `TreeEditorState.selection[0]`, no new fields |

### Unchanged

- `framework/editor/tree_editor_model.mbt` — `TreeEditorState[T]` unchanged
- `framework/editor/sync_editor*.mbt` — Zipper goes through existing `apply_tree_edit` path
- `editor/tree_edit_bridge.mbt` — existing round-trip unchanged
- `framework/core/reconcile.mbt` — reconciliation unchanged
- `projection/text_edit_*.mbt` — existing `compute_*` handlers reused, not reimplemented
- `lang/lambda/flat/flat_proj.mbt` — FlatProj unchanged
- `event-graph-walker/` — CRDT untouched
- `loom/loom/` — parser framework untouched

### Dependencies

```
lang/lambda/zipper/zipper.mbt        → @ast.Term, @ast.Bop, @ast.VarName (only)
lang/lambda/zipper/zipper_action.mbt → zipper.mbt, @edits.TreeEditOp
lang/lambda/zipper/zipper_role.mbt   → zipper.mbt
lang/lambda/zipper/zipper_hole.mbt   → @framework_core.NodeId
lang/lambda/zipper/zipper_bridge.mbt → zipper.mbt, @framework_core.ProjNode[Term], @framework_core.SourceMap
lang/lambda/lambda_editor_state.mbt  → all of the above + @framework_editor.TreeEditorState[Term], SyncEditor[Term]
```

No dependency on `SyncEditor`, CRDT, or loom internals from zipper files. `LambdaEditorState` depends on `SyncEditor[Term]` for integration dispatch only.

---

## Testing Strategy

### Navigation round-trips

```moonbit
test "go_down then go_up is identity" { ... }
test "go_right then go_left is identity" { ... }
test "traverse all children of If" { ... }
test "go_down on leaf returns None" { ... }
test "go_down on Hole returns None" { ... }
test "Module navigation: defs then body" { ... }
test "Module with empty defs: go_down focuses body" { ... }
```

### Position roles

```moonbit
test "root position" {
  let z = from_root(Int(42))
  inspect!(position_role(z), content="Root")
}

test "function position in App" {
  let z = from_root(App(Var("f"), Int(1)))
    |> go_down() |> Option::unwrap()
  inspect!(position_role(z), content="FunctionPosition")
}

test "else branch in If" {
  let z = from_root(If(Int(1), Int(2), Int(3)))
    |> go_down() |> Option::unwrap()
    |> go_right() |> Option::unwrap()
    |> go_right() |> Option::unwrap()
  inspect!(position_role(z), content="ElseBranch")
}

test "let definition role carries name" {
  let z = from_root(Module([("x", Int(1))], Var("x")))
    |> go_down() |> Option::unwrap()
  inspect!(position_role(z), content="LetDefinition(\"x\")")
}
```

### Edit action dispatch

```moonbit
test "to_tree_edit_op maps Delete" {
  let op = to_tree_edit_op(NodeId::from_int(5), Delete)
  inspect!(op, content="Delete(NodeId(5))")
}

test "to_tree_edit_op maps WrapLam" {
  let op = to_tree_edit_op(NodeId::from_int(5), WrapLam("x"))
  inspect!(op, content="WrapInLambda(NodeId(5), \"x\")")
}

test "to_tree_edit_op maps Unwrap" {
  let op = to_tree_edit_op(NodeId::from_int(5), Unwrap(1))
  inspect!(op, content="Unwrap(NodeId(5), 1)")
}
```

### Cursor relocation

```moonbit
test "relocate_cursor: follows text cursor after FocusHint" { ... }
test "relocate_cursor: falls back to old NodeId when text cursor lands on whitespace" { ... }
test "focus_at ancestor-walk: stops at deepest reachable" {
  let term = App(Var("f"), Int(1))
  let z = focus_at(term, [0, 0, 0])  // too deep
  inspect!(depth(z), content="1")     // stops at Var("f"), depth 1
}
```

### Bridge functions

```moonbit
test "zipper_from_node_id round-trips" { ... }
test "find_proj_node_for_focus uses direct child indexing" { ... }
test "path_indices_to_node finds target" { ... }
```

### Hole lifecycle

```moonbit
test "hole metadata survives round-trip via NodeId" {
  // 1. Create hole via Delete → TreeEditOp::Delete
  // 2. print_term → "_"
  // 3. Simulate reparse → new Hole(0)
  // 4. reconcile preserves NodeId (same_kind(Hole, Hole) = true)
  // 5. HoleRegistry.get(node_id) returns original metadata
}
```

### Edge cases

- `navigate` at root with `Up` → `None`
- `Unwrap(5)` with only 2 children → `Err` from TreeEditOp handler
- `focus_at` with out-of-bounds indices → ancestor-walk stops early
- `node_id_at_offset` at whitespace → nearest enclosing node
- `available_actions` on Hole → all wraps (fill the hole)

---

## What's NOT in Scope

- **Tile/shard decomposition** — no text-like input in tree pane (reviewed tylr, deferred)
- **Structural undo implementation** — `EditAction` as data enables it, but the undo manager integration is a separate plan
- **Collaborative structural conflict resolution** — `EditAction` + `PositionRole` provide the data, but eg-walker TransformOp integration is a separate plan. See `docs/architecture/grove-and-structural-identity.md` for the Grove-informed adoption path.
- **Type checker** — `HoleRegistry` reserves space for expected types, but type inference is not part of this plan
- **Deferred EditAction operations** — module binding ops, refactoring, cut/paste, InsertChild. See `docs/architecture/edit-action-progression.md` for the promotion path.
- **Generic Zipper[T]** — the Zipper is defined on `Term`. Each grammar needs its own context type. Generalization via codegen is a future concern.
- **Cached Zipper for rapid navigation** — constructing a transient Zipper per keystroke is O(depth), negligible for interactive use. Caching during navigation bursts is a future optimization if profiling shows a need.

## Resolved Questions

1. **Hole in parser:** Parser always uses ID 0. The parser has no global counter. The actual ID is irrelevant — `reconcile` assigns stable `NodeId` via `same_kind(Hole, Hole) = true`.

2. **EditAction serialization format:** Deferred. Define `ToJson`/`FromJson` when the sync protocol needs it.

3. **SourceMap inverse lookup:** Already exists as `SourceMap::innermost_node_at(position: Int) -> NodeId?` in `framework/core/source_map.mbt`. No additional work needed.

4. **Hole rendering in tree pane:** Use role-specific placeholder from `HoleInfo.role` for tree pane (e.g. `<body>`, `<condition>`), plain `_` for text pane.

5. **LambdaEditorState location:** Files land directly in `lang/lambda/zipper/` and `lang/lambda/`. No intermediate placement.

6. **ProjNode-Term isomorphism:** Verified. ProjNode[Term] mirrors Term exactly — no synthetic wrappers from error recovery. Direct child indexing is safe. `same_kind` guards are belt-and-suspenders.

7. **Cursor representation:** NodeId is primary. Zipper is transient. No `sync_after_roundtrip` needed.

8. **EditAction vs TreeEditOp:** EditAction is a cursor-relative frontend. Dispatch is a trivial mapping. Existing compute_* handlers do the work.

## Implementation Order

1. **Add `Hole(Int)` to Term** — add variant + `TermSym::hole`, update `replay`, `Pretty`, parser, trait impls, `same_kind`
2. **`lang/lambda/zipper/zipper.mbt`** — `Zipper`, `TermCtx`, `plug`, navigation, `ctx_to_child_index`, `children_of`, path indices, `to_root`, `from_root`, `focus_at` (with ancestor-walk)
3. **`lang/lambda/zipper/zipper_role.mbt`** — `PositionRole`, `position_role`
4. **`lang/lambda/zipper/zipper_action.mbt`** — `EditAction`, `Direction`, `ActionRecord`, `to_tree_edit_op` (must come before HoleRegistry because `HoleInfo` depends on `EditAction`)
5. **`lang/lambda/zipper/zipper_hole.mbt`** — `HoleInfo`, `HoleRegistry` (with `new()`, `fresh_hole_id`, `register`, `get`, `prune`)
6. **`lang/lambda/zipper/zipper_bridge.mbt`** — `zipper_from_node_id`, `find_proj_node_for_focus`, `path_indices_to_node`, `node_id_at_offset`, `text_range_from_node_id`
7. **`lang/lambda/zipper/zipper_wbtest.mbt`** — all tests
8. **`lang/lambda/lambda_editor_state.mbt`** — `LambdaEditorState`, `on_tree_key`, `on_tree_navigate`, `relocate_cursor`, `register_new_holes`, `available_actions`
9. **Integration** — keyboard dispatch, collapsed-node interception, `HoleRegistry::prune` in refresh

Steps 1-8 are additive — no existing code modified except `Term` (step 1). Step 9 wires everything together.
