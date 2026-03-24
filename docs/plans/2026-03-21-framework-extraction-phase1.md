# Framework Extraction Phase 1: Parameterize ProjNode[T]

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Parameterize ProjNode, reconciliation, and the projection pipeline over a generic AST type `T`, constrained by `TreeNode + Renderable` traits. All 507 existing tests pass after every task.

**Architecture:** Add two capability traits (`TreeNode`, `Renderable`) to `projection/`. Parameterize `ProjNode[T]`, `InteractiveTreeNode[T]`, reconciliation, and the projection pipeline. Lambda's `@ast.Term` implements both traits. `SyncEditor` becomes `SyncEditor[T]` accepting a parser factory. FlatProj stays lambda-specific (not parameterized).

**Tech Stack:** MoonBit, moon test/check/info/fmt

**Spec:** `docs/plans/2026-03-18-framework-extraction-design.md`

**Scope note:** This plan covers in-place parameterization only (Steps 1-5 of the extraction design). Package extraction (Step 7: moving to `framework/` and `lang/lambda/`) is a separate follow-up plan. FlatProj stays in `projection/` as a lambda-specific type.

**Required trait bounds:** The full set of bounds for `T` across the pipeline is `T : Show + Eq + TreeNode + Renderable`. `Show` is needed for `derive(Show)` on `ProjNode[T]` and `InteractiveTreeNode[T]`. `Eq` is needed for stamp comparison in refresh and for `derive(Eq)` on `ProjNode[T]`.

**Behavioral changes from current code:**
1. **`same_kind` for Bop:** Current `same_kind_tag` treats all `Bop` variants as same kind. The new `TreeNode::same_kind` for Term compares operators: `Bop(Plus, _, _)` and `Bop(Minus, _, _)` are different kinds. This means changing `+` to `*` now gets a fresh node ID instead of preserving it. This is more correct behavior.
2. **`reconcile` no longer calls `rebuild_kind`:** Current `reconcile_ast` rebuilds the `@ast.Term` embedded children after reconciling ProjNode children. The generic `reconcile[T]` uses `new.kind` directly since ProjNode is read-only (all edits go through text deltas). `rebuild_kind` remains in `proj_node.mbt` for use by lambda-specific code in `text_edit.mbt` and `tree_lens.mbt`.
3. **`InteractiveNodeShape` replaced by `T : Eq`:** Current stamp comparison uses a Term-specific shape enum. The generic version stores `kind: T` in the stamp and uses `T : Eq` for comparison, which detects both structural and leaf-value changes (e.g., `Int(4) != Int(5)`).

**Lambda-specific methods on SyncEditor:** `get_ast()`, `get_ast_pretty()`, `get_resolution()`, `get_dot_resolved()` return `@ast.Term`-specific data and cannot be parameterized over `T`. They remain as-is for Phase 1 (extraction to `lang/lambda/` is Phase 2).

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `projection/traits.mbt` | TreeNode, Renderable trait definitions |
| Create | `projection/traits_term.mbt` | impl TreeNode + Renderable for @ast.Term |
| Modify | `projection/proj_node.mbt` | ProjNode → ProjNode[T], syntax_to_proj_node stays Term-specific |
| Modify | `projection/proj_node_json.mbt` | `impl[T : ToJson] ToJson for ProjNode[T]` |
| Modify | `projection/reconcile_ast.mbt` | reconcile_ast → reconcile[T], same_kind_tag → T::same_kind |
| Modify | `projection/tree_editor_model.mbt` | InteractiveTreeNode[T], TreeEditorState[T], get_node_label → T::label. **Note:** TreeEditorState struct is here (moved from tree_editor.mbt during refactoring) |
| Modify | `projection/tree_editor.mbt` | apply_edit[T] — edit operations only (no struct definition) |
| Modify | `projection/tree_editor_refresh.mbt` | Generic refresh functions, TreeEditorState::refresh[T], expand_node[T], hydrate_subtree[T] |
| Modify | `projection/source_map.mbt` | SourceMap::from_ast[T] |
| Modify | `projection/tree_lens.mbt` | TreeEditOp keeps @ast.Term for InsertChild, placeholder via T::placeholder |
| Modify | `projection/text_edit.mbt` | EditContext[T], core_dispatch[T], compute_text_edit stays Term-specific |
| Modify | `projection/text_edit_middleware.mbt` | EditMiddleware trait — parameterize with [T] |
| Modify | `projection/text_edit_binding.mbt` | Handler: parameterize with [T] where accessing registry |
| Modify | `projection/text_edit_commit.mbt` | Handler: parameterize with [T] where accessing registry |
| Modify | `projection/text_edit_delete.mbt` | Handler: parameterize with [T] where accessing registry |
| Modify | `projection/text_edit_drop.mbt` | Handler: parameterize with [T] where accessing registry |
| Modify | `projection/text_edit_refactor.mbt` | Handler: parameterize with [T] where accessing registry |
| Modify | `projection/text_edit_structural.mbt` | Handler: parameterize with [T] where accessing registry |
| Modify | `projection/text_edit_wrap.mbt` | Handler: parameterize with [T] where accessing registry |
| Modify | `projection/text_edit_rename.mbt` | Stays Term-specific (split from text_edit.mbt) |
| Modify | `projection/text_edit_utils.mbt` | Stays Term-specific (split from text_edit.mbt) |
| Modify | `projection/flat_proj.mbt` | FlatProj stays @ast.Term-specific, uses ProjNode[@ast.Term] |
| Keep   | `projection/actions.mbt` | **Lambda-specific** — `get_actions_for_node` pattern-matches on `@ast.Term`. Stays Term-specific for Phase 1 (extraction to `lang/lambda/` is Phase 2) |
| Keep   | `projection/scope.mbt` | **Lambda-specific** — `resolve_binder`, `find_usages` reference `@ast.Term`. Stays Term-specific |
| Keep   | `projection/free_vars.mbt` | **Lambda-specific** — `free_vars` pattern-matches on `@ast.Term`. Stays Term-specific |
| Modify | `editor/sync_editor.mbt` | SyncEditor[T] with parser factory |
| Modify | `editor/projection_memo.mbt` | Generic memo pipeline |
| Modify | `editor/tree_edit_bridge.mbt` | Generic tree edit roundtrip |
| Modify | `editor/sync_editor_parser.mbt` | Generic parser methods |
| Modify | `editor/sync_editor_text.mbt` | Generic text methods |
| Modify | `editor/sync_editor_undo.mbt` | Add [T] to all SyncEditor methods |
| Modify | `editor/sync_editor_sync.mbt` | Add [T] to all SyncEditor methods |
| Modify | `editor/sync_editor_ws.mbt` | Add [T] to all SyncEditor methods |
| Modify | `editor/tree_edit_json.mbt` | Keep Term-specific (InsertChild) |
| Modify | `crdt.mbt` + FFI files | Concrete type SyncEditor[@ast.Term] |
| Update | `projection/pkg.generated.mbti` | moon info |
| Update | `editor/pkg.generated.mbti` | moon info |

### Lambda-specific files (stay @ast.Term, move to lang/lambda/ in Phase 2)

These files were added by the structural editing actions implementation (2026-03-21) and pattern-match directly on `@ast.Term` variants. They stay Term-specific in Phase 1:

| File | Why Term-specific |
|------|-------------------|
| `projection/actions.mbt` | `get_actions_for_node` matches `@ast.Term::Int`, `Var`, `Lam`, etc. |
| `projection/scope.mbt` | `resolve_binder`, `find_usages` walk Term structure |
| `projection/free_vars.mbt` | `free_vars` matches `Lam`, `Module`, `Bop`, etc. |
| `projection/text_edit.mbt` | `compute_text_edit` uses `rebuild_kind`, FlatProj |
| `projection/text_edit_rename.mbt` | Rename logic uses token spans, Term-specific |
| `projection/text_edit_utils.mbt` | Helper functions for text editing |
| `projection/flat_proj.mbt` | FlatProj is lambda-specific |

### Test files (updated alongside their package)

| File | Notes |
|------|-------|
| `projection/proj_node_test.mbt` | Blackbox — may infer ProjNode[@ast.Term] |
| `projection/proj_node_json_test.mbt` | Blackbox — ToJson test |
| `projection/flat_proj_wbtest.mbt` | Whitebox — references ProjNode directly |
| `projection/tree_editor_wbtest.mbt` | Whitebox — references InteractiveTreeNode, stamps, refresh |
| `projection/text_edit_wbtest.mbt` | Whitebox — builds Map[NodeId, ProjNode] |
| `projection/text_lens_regression_wbtest.mbt` | Whitebox — calls reconcile_ast |
| `projection/source_map_wbtest.mbt` | Whitebox — uses SourceMap |
| `projection/source_map_token_spans_wbtest.mbt` | Whitebox — uses ProjNode |
| `projection/lens_test.mbt` | Blackbox — uses ProjNode, reconcile_ast |
| `projection/tree_refresh_benchmark.mbt` | Benchmark — uses ProjNode, TreeEditorState |
| `projection/actions_wbtest.mbt` | Whitebox — Term-specific, stays as-is |
| `projection/scope_wbtest.mbt` | Whitebox — Term-specific, stays as-is |
| `projection/free_vars_wbtest.mbt` | Whitebox — Term-specific, stays as-is |
| `editor/sync_editor_test.mbt` | Blackbox — SyncEditor::new |
| `editor/tree_edit_bridge_test.mbt` | Blackbox — SyncEditor::new |
| `editor/tree_edit_json_test.mbt` | Blackbox — parse_tree_edit_op |
| `editor/sync_editor_text_wbtest.mbt` | Whitebox — SyncEditor methods |
| `editor/sync_editor_ws_wbtest.mbt` | Whitebox — SyncEditor methods |
| `editor/error_path_wbtest.mbt` | Whitebox — SyncEditor, wire protocol |
| `editor/ephemeral_encoding_wbtest.mbt` | Whitebox — ephemeral encoding |

---

## MoonBit Generics Reference

MoonBit parameterized types and trait-constrained functions:
```moonbit
pub struct ProjNode[T] { kind : T; children : Array[ProjNode[T]]; ... }
pub fn[T : TreeNode + Renderable] reconcile(old : ProjNode[T], new : ProjNode[T], counter : Ref[Int]) -> ProjNode[T]
```

Trait implementations use one-method-per-impl-block:
```moonbit
pub impl TreeNode for @ast.Term with children(self) { ... }
pub impl TreeNode for @ast.Term with same_kind(self, other) { ... }
```

**Critical:** MoonBit packages compile as a unit. All files in `projection/` must be consistent before `moon check` passes. Tasks within a package may need to be done atomically.

---

### Task 1: Add TreeNode and Renderable traits

**Files:**
- Create: `projection/traits.mbt`
- Create: `projection/traits_term.mbt`

These are pure additions. Existing code is untouched, so all tests pass after this task.

- [ ] **Step 1: Write TreeNode trait**

In `projection/traits.mbt`:

```moonbit
///|
/// Tree structure capability — provides structural access for reconciliation and traversal.
pub trait TreeNode {
  children(Self) -> Array[Self]
  same_kind(Self, Self) -> Bool
}

///|
/// Rendering + text capability — provides display and serialization for projections.
pub trait Renderable {
  kind_tag(Self) -> String
  label(Self) -> String
  placeholder(Self) -> String
  unparse(Self) -> String
}
```

- [ ] **Step 2: Implement TreeNode for @ast.Term**

In `projection/traits_term.mbt`:

```moonbit
///|
pub impl TreeNode for @ast.Term with children(self) {
  match self {
    Lam(_, body) => [body]
    App(f, a) => [f, a]
    Bop(_, l, r) => [l, r]
    If(c, t, e) => [c, t, e]
    Module(defs, body) => {
      let result : Array[@ast.Term] = []
      for def in defs {
        result.push(def.1)
      }
      result.push(body)
      result
    }
    _ => []
  }
}

///|
pub impl TreeNode for @ast.Term with same_kind(self, other) {
  match (self, other) {
    (Int(_), Int(_)) => true
    (Var(_), Var(_)) => true
    (Lam(_, _), Lam(_, _)) => true
    (App(_, _), App(_, _)) => true
    (Bop(op1, _, _), Bop(op2, _, _)) => op1 == op2
    (If(_, _, _), If(_, _, _)) => true
    (Module(_, _), Module(_, _)) => true
    (Unit, Unit) => true
    (Unbound(_), Unbound(_)) => true
    (Error(_), Error(_)) => true
    _ => false
  }
}
```

- [ ] **Step 3: Implement Renderable for @ast.Term**

In `projection/traits_term.mbt` (append):

```moonbit
///|
pub impl Renderable for @ast.Term with kind_tag(self) {
  match self {
    Int(_) => "Int"
    Var(_) => "Var"
    Lam(_, _) => "Lam"
    App(_, _) => "App"
    Bop(_, _, _) => "Bop"
    If(_, _, _) => "If"
    Module(_, _) => "Module"
    Unit => "Unit"
    Unbound(_) => "Unbound"
    Error(_) => "Error"
  }
}

///|
pub impl Renderable for @ast.Term with label(self) {
  match self {
    Int(n) => n.to_string()
    Var(name) => name
    Lam(param, _) => "λ" + param
    App(_, _) => "App"
    Bop(op, _, _) => op.to_string()
    If(_, _, _) => "if"
    Module(defs, _) => {
      let names = defs.map(fn(d) { d.0 })
      "module [" + names.join(", ") + "]"
    }
    Unit => "()"
    Unbound(name) => "?" + name
    Error(msg) => "Error: " + msg
  }
}

///|
pub impl Renderable for @ast.Term with placeholder(self) {
  match self {
    Int(_) => "0"
    Var(_) | Unbound(_) => "a"
    Lam(_, _) => "(λx. a)"
    App(_, _) => "(a a)"
    Bop(op, _, _) => "(a " + op.to_string() + " a)"
    If(_, _, _) => "if a then a else a"
    Module(_, _) => "let x = 0\nx"
    Unit => "()"
    Error(_) => "0"
  }
}

///|
pub impl Renderable for @ast.Term with unparse(self) {
  @ast.print_term(self)
}
```

- [ ] **Step 4: Run moon check**

Run: `moon check`
Expected: No errors. Traits are defined but not yet used.

- [ ] **Step 5: Commit**

```bash
git add projection/traits.mbt projection/traits_term.mbt
git commit -m "feat(projection): add TreeNode and Renderable traits with Term impl"
```

---

### Task 2: Parameterize ProjNode[T]

**Files:**
- Modify: `projection/proj_node.mbt`

**WARNING:** This task changes the core type. Every file in `projection/` that references `ProjNode` will fail to compile until updated. Tasks 2-5 must be completed atomically before `moon check` passes. Plan accordingly — read all tasks, then execute as a batch.

- [ ] **Step 1: Change ProjNode struct to ProjNode[T]**

In `projection/proj_node.mbt`, change:
```moonbit
// OLD:
pub struct ProjNode {
  node_id : Int
  kind : @ast.Term
  children : Array[ProjNode]
  start : Int
  end : Int
}

// NEW:
pub struct ProjNode[T] {
  node_id : Int
  kind : T
  children : Array[ProjNode[T]]
  start : Int
  end : Int
}
```

- [ ] **Step 2: Update ProjNode methods**

Update `ProjNode::new` and `ProjNode::id`:
```moonbit
///|
pub fn ProjNode::new[T](
  kind : T,
  start : Int,
  end : Int,
  node_id : Int,
  children : Array[ProjNode[T]],
) -> ProjNode[T] {
  { node_id, kind, children, start, end }
}

///|
pub fn ProjNode::id[T](self : ProjNode[T]) -> NodeId {
  NodeId(self.node_id)
}
```

- [ ] **Step 3: Keep syntax_to_proj_node as Term-specific**

`syntax_to_proj_node` and `to_proj_node` remain `ProjNode[@ast.Term]` — they are lambda-specific CST→AST converters. Update their return types:

```moonbit
pub fn syntax_to_proj_node(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> ProjNode[@ast.Term]

pub fn to_proj_node(
  root : @seam.SyntaxNode,
  counter : Ref[Int],
) -> ProjNode[@ast.Term]

fn error_node_for_syntax(
  msg : String,
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> ProjNode[@ast.Term]
```

- [ ] **Step 4: Update same_kind_tag to use TreeNode trait**

Replace the existing `same_kind_tag` function:
```moonbit
// OLD: fn same_kind_tag(a : @ast.Term, b : @ast.Term) -> Bool
// NEW: use T::same_kind from TreeNode trait (used by reconcile_ast)
// Remove same_kind_tag — reconcile will call T::same_kind directly
```

---

### Task 3: Parameterize reconciliation

**Files:**
- Modify: `projection/reconcile_ast.mbt`

- [ ] **Step 1: Parameterize reconcile_ast**

```moonbit
///|
pub fn reconcile[T : TreeNode + Eq](
  old : ProjNode[T],
  new : ProjNode[T],
  counter : Ref[Int],
) -> ProjNode[T] {
  if T::same_kind(old.kind, new.kind) {
    let reconciled_children = reconcile_children(
      old.children, new.children, counter,
    )
    ProjNode::new(
      new.kind, new.start, new.end, old.node_id, reconciled_children,
    )
  } else {
    assign_fresh_ids(new, counter)
  }
}
```

- [ ] **Step 2: Parameterize reconcile_children**

```moonbit
fn reconcile_children[T : TreeNode + Eq](
  old_children : Array[ProjNode[T]],
  new_children : Array[ProjNode[T]],
  counter : Ref[Int],
) -> Array[ProjNode[T]]
```

Keep the LCS matching logic identical, just parameterize the types.

- [ ] **Step 3: Parameterize assign_fresh_ids and next_proj_node_id**

```moonbit
pub fn assign_fresh_ids[T](node : ProjNode[T], counter : Ref[Int]) -> ProjNode[T]
pub fn next_proj_node_id(counter : Ref[Int]) -> Int  // unchanged, no T needed
```

- [ ] **Step 4: Keep reconcile_ast as a Term-specific alias (temporary)**

For backward compat during migration, keep:
```moonbit
///|
pub fn reconcile_ast(
  old : ProjNode[@ast.Term],
  new : ProjNode[@ast.Term],
  counter : Ref[Int],
) -> ProjNode[@ast.Term] {
  reconcile(old, new, counter)
}
```

This lets callers migrate incrementally. Remove after all callers switch.

---

### Task 4: Update tree_editor_model.mbt

**Files:**
- Modify: `projection/tree_editor_model.mbt`

- [ ] **Step 1: Parameterize InteractiveTreeNode[T]**

```moonbit
pub struct InteractiveTreeNode[T] {
  id : NodeId
  kind : T
  label : String
  children : InteractiveChildren[T]
  selected : Bool
  editing : Bool
  collapsed : Bool
  drop_target : Bool
  text_range : Range
}
```

- [ ] **Step 2: Parameterize InteractiveChildren[T]**

```moonbit
pub enum InteractiveChildren[T] {
  Loaded(Array[InteractiveTreeNode[T]])
  Elided(Int)
}
```

- [ ] **Step 3: Update InteractiveNodeShape — remove it**

`InteractiveNodeShape` duplicates what `T::same_kind` does. Replace stamp comparison:

```moonbit
// OLD: shape: interactive_node_shape(node.kind)
// NEW: use T::same_kind for comparisons, store kind: T directly in stamp

priv struct InteractiveNodeStamp[T : Eq] {
  id : NodeId
  kind : T
  label : String
  child_ids : Array[NodeId]
  elided_descendant_count : Int?
  selected : Bool
  editing : Bool
  collapsed : Bool
  drop_target : Bool
  text_range : Range
}
```

- [ ] **Step 4: Replace get_node_label with T::label**

Remove `get_node_label` function. All call sites use `Renderable::label(node.kind)` instead.

- [ ] **Step 5: Update from_term_node_impl to use traits**

```moonbit
fn from_term_node_impl[T : TreeNode + Renderable](
  node : ProjNode[T],
  source_map : SourceMap,
  ui_state : TreeUIState,
) -> InteractiveTreeNode[T]
```

Replace `get_node_label(node.kind)` with `Renderable::label(node.kind)`.

- [ ] **Step 6: Update is_leaf_node to use TreeNode**

```moonbit
pub fn is_leaf_node[T : TreeNode](kind : T) -> Bool {
  T::children(kind).is_empty()
}
```

---

### Task 5: Update remaining projection/ files

**Files:**
- Modify: `projection/source_map.mbt`
- Modify: `projection/tree_lens.mbt`
- Modify: `projection/text_edit.mbt`
- Modify: `projection/tree_editor.mbt`
- Modify: `projection/tree_editor_refresh.mbt`
- Modify: `projection/flat_proj.mbt`

- [ ] **Step 1: Update SourceMap::from_ast**

SourceMap stores `NodeId → Range` — no T needed in the struct. Only the builder function needs T:

```moonbit
pub fn SourceMap::from_ast[T](root : ProjNode[T]) -> SourceMap
fn build_from_node[T](node : ProjNode[T], source_map : SourceMap) -> Unit
```

- [ ] **Step 2: Update tree_lens.mbt**

TreeEditOp uses `NodeId` and `@ast.Term` for `InsertChild(kind)`. Keep `InsertChild` Term-specific for now — it's a Tier 3 language-specific operation:

```moonbit
pub enum TreeEditOp {
  // ... all existing variants stay the same
  // InsertChild keeps @ast.Term — this is lambda-specific
  InsertChild(parent~ : NodeId, index~ : Int, kind~ : @ast.Term)
}
```

Update `placeholder_text_for_kind` to use Renderable:
```moonbit
pub fn placeholder_text_for_kind[T : Renderable](kind : T) -> String {
  T::placeholder(kind)
}
```

Update `get_node_in_tree`:
```moonbit
pub fn get_node_in_tree[T](root : ProjNode[T], target : NodeId) -> ProjNode[T]?
```

- [ ] **Step 3: Update text_edit.mbt and EditContext**

**Note (2026-03-24 refresh):** The handler chain refactor (PR #54) split `text_edit.mbt` into a middleware pipeline. `EditContext` struct and `EditMiddleware` trait now exist. The per-handler files (`text_edit_binding.mbt`, `text_edit_commit.mbt`, `text_edit_delete.mbt`, `text_edit_drop.mbt`, `text_edit_refactor.mbt`, `text_edit_structural.mbt`, `text_edit_wrap.mbt`) also reference `ProjNode` and `EditContext`.

Parameterize `EditContext`:
```moonbit
pub(all) struct EditContext[T] {
  source_text : String
  source_map : SourceMap
  registry : Map[NodeId, ProjNode[T]]
  flat_proj : FlatProj
}
```

Parameterize `core_dispatch` and all handler functions in the per-handler files:
```moonbit
fn core_dispatch[T : TreeNode + Renderable](op : TreeEditOp, ctx : EditContext[T]) -> EditResult
```

Each `text_edit_*.mbt` handler file's functions must also be parameterized with `[T : TreeNode + Renderable]` where they access `ctx.registry` (which is now `Map[NodeId, ProjNode[T]]`).

Replace `@ast.print_term(kind)` calls with `Renderable::unparse(kind)`.
Replace `placeholder_text_for_kind(kind)` calls — already generic from Step 2.

- [ ] **Step 4: Update TreeEditorState[T]**

In `projection/tree_editor.mbt`:

```moonbit
pub struct TreeEditorState[T] {
  tree : InteractiveTreeNode[T]?
  selection : Array[NodeId]
  editing_node : NodeId?
  edit_value : String
  dragging : NodeId?
  drop_target : NodeId?
  drop_position : DropPosition?
  collapsed_nodes : @immut/hashset.HashSet[NodeId]
  priv loaded_nodes : Map[NodeId, InteractiveTreeNode[T]]
}
```

Parameterize all methods: `new`, `get_loaded_node`, `from_projection`, `refresh`, `expand_node`, `hydrate_subtree`, `apply_edit`.

- [ ] **Step 5: Update tree_editor_refresh.mbt**

Parameterize all functions with `[T : TreeNode + Renderable + Eq]`:
- `refresh_node_minimal[T]`
- `can_skip_subtree[T]`
- `carry_over_loaded_nodes[T]`
- `build_parent_map_from_tree[T]`
- `build_preorder_from_tree[T]`
- `collect_subtree_ids[T]`
- `is_descendant_of[T]`
- `apply_selection_edit[T]`
- etc.

- [ ] **Step 6: Update flat_proj.mbt — keep Term-specific**

FlatProj stays `@ast.Term`-specific per the design. Update type references only:

```moonbit
pub struct FlatProj {
  defs : Array[(String, ProjNode[@ast.Term], Int, NodeId)]
  final_expr : ProjNode[@ast.Term]?
}

pub fn to_flat_proj(root : @seam.SyntaxNode, counter : Ref[Int]) -> FlatProj
pub fn reconcile_flat_proj(old : FlatProj, new : FlatProj, counter : Ref[Int]) -> FlatProj
pub fn FlatProj::to_proj_node(self : FlatProj, counter : Ref[Int]) -> ProjNode[@ast.Term]
pub fn FlatProj::from_proj_node(root : ProjNode[@ast.Term]) -> FlatProj
pub fn print_flat_proj(fp : FlatProj) -> String
```

- [ ] **Step 7: Run moon check on projection/**

Run: `moon check`
Expected: Projection package compiles. Editor package may have errors (fixed in Task 6).

- [ ] **Step 8: Run projection tests**

Run: `moon test -p dowdiness/canopy/projection`
Expected: All 105 projection tests pass.

- [ ] **Step 9: Commit projection changes**

```bash
git add projection/
git commit -m "feat(projection): parameterize ProjNode[T] with TreeNode + Renderable traits"
```

---

### Task 6: Update editor/ package

**Files:**
- Modify: `editor/sync_editor.mbt`
- Modify: `editor/projection_memo.mbt`
- Modify: `editor/tree_edit_bridge.mbt`
- Modify: `editor/sync_editor_parser.mbt`
- Modify: `editor/sync_editor_text.mbt`

- [ ] **Step 1: Parameterize SyncEditor[T]**

```moonbit
pub struct SyncEditor[T] {
  priv doc : @text.TextDoc
  priv undo : @undo.UndoManager
  priv parser : @loom.ImperativeParser[T]
  priv parser_rt : @incr.Runtime
  priv source_text : @incr.Signal[String]
  priv syntax_tree : @incr.Signal[@seam.SyntaxNode?]
  priv mut cursor : Int
  priv prev_flat_proj : Ref[@proj.FlatProj?]
  priv next_node_id : Ref[Int]
  priv proj_memo : @incr.Memo[@proj.FlatProj?]
  priv cached_proj_node : @incr.Memo[@proj.ProjNode[T]?]
  priv registry_memo : @incr.Memo[Map[@proj.NodeId, @proj.ProjNode[T]]]
  priv source_map_memo : @incr.Memo[@proj.SourceMap]
  priv hub : EphemeralHub
  priv cursor_view : PeerCursorView
  priv peer_id : String
  priv mut ws : JsWebSocket?
  priv mut recovery : RecoveryContext?
  priv mut recovery_epoch : Int
}
```

- [ ] **Step 2: Add parser factory to constructor**

The generic constructor requires an explicit `make_parser`. A convenience `new_lambda` constructor preserves backward compat:

```moonbit
pub fn SyncEditor::new[T : @proj.TreeNode + @proj.Renderable + Eq + Show](
  agent_id : String,
  make_parser : (String) -> @loom.ImperativeParser[T],
  capture_timeout_ms~ : Int = 500,
) -> SyncEditor[T]

/// Convenience constructor for lambda calculus (existing behavior).
pub fn SyncEditor::new_lambda(
  agent_id : String,
  capture_timeout_ms~ : Int = 500,
) -> SyncEditor[@ast.Term] {
  SyncEditor::new(
    agent_id,
    fn(s) { @loom.new_imperative_parser(s, @parser.lambda_grammar) },
    capture_timeout_ms~,
  )
}
```

Note: A default `make_parser` parameter won't type-check because the default expression produces `ImperativeParser[@ast.Term]`, not `ImperativeParser[T]`. The `new_lambda` constructor avoids this.

- [ ] **Step 3: Update projection_memo.mbt**

```moonbit
fn build_projection_memos[T : @proj.TreeNode + @proj.Renderable + Eq](
  rt : @incr.Runtime,
  source_text : @incr.Signal[String],
  syntax_tree : @incr.Signal[@seam.SyntaxNode?],
  prev_flat_proj_ref : Ref[@proj.FlatProj?],
  next_id_ref : Ref[Int],
) -> (
  @incr.Memo[@proj.FlatProj?],
  @incr.Memo[@proj.ProjNode[T]?],
  @incr.Memo[Map[@proj.NodeId, @proj.ProjNode[T]]],
  @incr.Memo[@proj.SourceMap],
)
```

The `proj_memo` (FlatProj) stays lambda-specific. The `cached_proj_node` converts `FlatProj → ProjNode[@ast.Term]` — when T = @ast.Term this works directly. For generic T, the pipeline needs adaptation.

**Key decision:** For Phase 1, keep the FlatProj pipeline as-is. It means `SyncEditor[T]` only fully works when `T = @ast.Term`. A TODO comment marks where the generic pipeline path (`SyntaxNode → T → ProjNode[T]`) will be added in Phase 2.

- [ ] **Step 4: Update accessor methods**

```moonbit
pub fn SyncEditor::get_proj_node[T](self : SyncEditor[T]) -> @proj.ProjNode[T]?
pub fn SyncEditor::get_source_map[T](self : SyncEditor[T]) -> @proj.SourceMap
pub fn SyncEditor::get_registry[T](self : SyncEditor[T]) -> Map[@proj.NodeId, @proj.ProjNode[T]]
```

- [ ] **Step 5: Update tree_edit_bridge.mbt**

```moonbit
pub fn SyncEditor::apply_tree_edit[T : @proj.TreeNode + @proj.Renderable + Eq](
  self : SyncEditor[T],
  op : @proj.TreeEditOp,
  timestamp_ms : Int,
) -> Result[Unit, String]
```

- [ ] **Step 6: Update sync_editor_parser.mbt and sync_editor_text.mbt**

Add type parameter `[T]` to all `SyncEditor` methods in these files.

- [ ] **Step 7: Run moon check on editor/**

Run: `moon check`
Expected: Editor package compiles.

- [ ] **Step 8: Run editor tests**

Run: `moon test -p dowdiness/canopy/editor`
Expected: All editor tests pass.

- [ ] **Step 9: Commit editor changes**

```bash
git add editor/
git commit -m "feat(editor): parameterize SyncEditor[T] with parser factory"
```

---

### Task 7: Update root FFI layer

**Files:**
- Modify: `crdt.mbt`, `crdt_undo.mbt`, `crdt_ephemeral.mbt`, `crdt_projection.mbt`, `crdt_websocket.mbt`

- [ ] **Step 1: Concrete-type the editor map**

```moonbit
let editors : Map[Int, @editor.SyncEditor[@ast.Term]] = Map::new()
```

All FFI functions use concrete `@ast.Term` — no generics leak to JS.

- [ ] **Step 2: Update crdt.mbt create functions to use new_lambda**

```moonbit
pub fn create_editor(agent_id : String) -> Int {
  let handle = next_handle.val
  next_handle.val = handle + 1
  editors[handle] = @editor.SyncEditor::new_lambda(agent_id)
  last_created_handle.val = Some(handle)
  handle
}
```

Similarly update `create_editor_with_undo` in `crdt_undo.mbt`.

- [ ] **Step 3: Run moon check**

Run: `moon check`
Expected: Everything compiles.

- [ ] **Step 4: Run full test suite**

Run: `moon test`
Expected: All 507 tests pass.

- [ ] **Step 5: moon info + moon fmt**

Run: `moon info && moon fmt`
Review `git diff *.mbti` — verify new generic signatures appear.

- [ ] **Step 6: Commit FFI + interface changes**

```bash
git add crdt*.mbt pkg.generated.mbti projection/pkg.generated.mbti editor/pkg.generated.mbti
git commit -m "feat: complete Phase 1 framework extraction — generic ProjNode[T] + SyncEditor[T]"
```

---

## Post-implementation notes

**What this enables:**
- Any MoonBit type implementing `TreeNode + Renderable` can be used with the projection pipeline
- `SyncEditor::new(agent_id, make_parser=my_parser_factory)` creates an editor for any grammar
- Lambda calculus is the default, existing behavior unchanged

**Follow-up tasks (Phase 2):**
1. **Generic pipeline path** — bypass FlatProj for non-lambda grammars (`SyntaxNode → T → ProjNode[T]` directly)
2. **Package extraction** — move traits + core to `framework/`, lambda code to `lang/lambda/`
3. **loomgen integration** — code generator emits trait impls for new languages
4. **TestExpr test suite** — framework tests using minimal test expression type (proves framework works independently)
5. **Remove reconcile_ast alias** — once all callers use `reconcile[T]`
