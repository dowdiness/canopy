# Projectional Editor Framework Extraction

**Date:** 2026-03-18
**Status:** Approved
**Prerequisite:** Text-delta tree edit design (`loom/docs/plans/2026-03-18-projectional-edit-text-delta-design.md`)

## Goal

Extract a general-purpose projectional editor framework from the current lambda calculus CRDT editor. The framework supports any grammar that provides a parser + AST structure. Target consumers: MoonBit library authors (primary) and web developers via JS FFI (secondary).

## Key Architectural Premise: Read-Only Projection

After the text-delta design is implemented, the ProjNode tree becomes **read-only** — a projection derived from text, never mutated directly. All edits (text and structural) converge at `TextDelta → CRDT → reparse`:

```
Text edit:  keystroke → TextDelta → CRDT → reparse → projection updates
Tree edit:  TreeEditOp → compute_text_delta(op, source_map, text) → TextDelta → CRDT → reparse
```

This eliminates the need for `rebuild` / `apply_edit_to_proj` / `from_proj_node` and the FlatProj unparse roundtrip. The projection is purely a catamorphism from text → CST → T → ProjNode[T]. It is never written to.

## Architecture

The framework is the catamorphism side of the incremental hylomorphism pipeline (see `docs/architecture/Incremental-Hylomorphism.md`). The anamorphism side (loom parser, CstNode) is already generic. The extraction parameterizes everything from the CST→AST boundary onward over a type `T` representing the AST node type.

```
CRDT Ops →(fold)→ Text →(ana/loom)→ CstNode →(cata)→ T →(cata)→ ProjNode[T] →(cata)→ Screen
                                               ↑                    ↑
                                          already generic      extraction scope
```

### Two-Layer Architecture (from Hylomorphism document)

- **Layer 1 (Concrete):** CstNode — position-independent, lossless, already generic via loom
- **Layer 2 (Abstract):** T → ProjNode[T] — parameterized over grammar, uses capability traits

The boundary between layers is `cst_to_ast: SyntaxNode → T?`, a grammar-specific catamorphism provided by each language package. Spans flow from Layer 1 (CstNode positions via SyntaxNode) into ProjNode during the CST→ProjNode conversion in the memo chain. This is the existing pipeline — no "patch later" step needed.

## Capability Traits

Two core traits following MoonBit's Self-based pattern (see `moonbit-traits` patterns):

```moonbit
///| Tree structure (Pattern 1: Self-closed algebra)
pub trait TreeNode {
  children(Self) -> Array[Self]
  same_kind(Self, Self) -> Bool
}

///| Rendering + text (Pattern 2: Fixed projection)
pub trait Renderable {
  kind_tag(Self) -> String
  label(Self) -> String
  placeholder(Self) -> String
  unparse(Self) -> String
}
```

**`rebuild` is removed.** ProjNode is read-only after the text-delta design. The framework never reconstructs AST nodes — all edits go through text deltas. `unparse` moves to `Renderable` because it's a projection from `Self` to `String` (Pattern 2: fixed-type projection).

**`Parseable` is removed as a framework trait.** Parsing is handled by loom's `ImperativeParser` which is already generic over the AST type. The `cst_to_ast` function parameter on `SyncEditor::new` provides the grammar-specific CST→T catamorphism. There is no need for a `parse(String) -> Self?` method on the AST type itself — the parser framework handles that.

**`same_kind`** matches the current `same_kind_tag` behavior: constructor-tag comparison only, ignoring leaf data. `same_kind(Lam("x", _), Lam("y", _))` returns `true` — parameter renames preserve node IDs.

Lambda implementation:
```moonbit
impl TreeNode for Term with children(self) {
  match self { Lam(_, body) => [body]; App(f, a) => [f, a]; Let(_, i, b) => [i, b]; _ => [] }
}
impl TreeNode for Term with same_kind(self, other) {
  match (self, other) { (Lam(_, _), Lam(_, _)) => true; (App(_, _), App(_, _)) => true; ... }
}
impl Renderable for Term with kind_tag(self) { ... }
impl Renderable for Term with label(self) { ... }
impl Renderable for Term with placeholder(self) { ... }
impl Renderable for Term with unparse(self) { @ast.print_term(self) }
```

## Generic ProjNode[T] (Read-Only)

```moonbit
pub struct ProjNode[T] {
  node_id : Int
  kind : T
  children : Array[ProjNode[T]]
  start : Int
  end : Int
}
```

ProjNode is **read-only** — derived from text via the parsing pipeline, never mutated by edits. All structural edits produce text deltas instead.

`T` propagates through: `ProjNode[T]`, `InteractiveTreeNode[T]`, `SyncEditor[T]`.

`SourceMap` does NOT gain `T` — it stores only `NodeId` and `Range` (where `Range` stays in loom as an external dep). `NodeId` moves to `framework/core/`.

### The kind-children invariant

`ProjNode[T]` stores `kind: T` and `children: Array[ProjNode[T]]`. For recursive AST types like `App(t1, t2)`, the children exist in TWO places: embedded in `kind` (as sub-Terms) and in `ProjNode.children` (as child ProjNodes). These must agree. The invariant is maintained by the CST→ProjNode conversion (the only code that creates ProjNodes), not by edit operations (which never mutate ProjNodes).

### FlatProj is language-specific

`FlatProj` is NOT part of the generic framework. It is a concept specific to "module-shaped" grammars (languages with top-level definitions). Building `FlatProj` requires language-specific knowledge of binding names, def boundaries, and body positions that cannot be derived from `TreeNode + Renderable` alone.

Languages that have a module structure (like lambda calculus with `let` defs) implement `FlatProj[T]` in their language package (`lang/lambda/`). Languages without a module structure (single-expression calculators, JSON editors) skip it entirely.

The framework's projection pipeline produces `ProjNode[T]` directly. Language packages optionally wrap it with flattening logic.

### Generic Incremental Pipeline

The current pipeline goes through FlatProj:
```
SyntaxNode → to_flat_proj (with CstNode physical_equal skip) → reconcile_flat_proj → to_proj_node → ProjNode
```

The generic framework pipeline bypasses FlatProj:
```
SyntaxNode → cst_to_ast (inside ImperativeParser) → T → build_proj_node[T] → reconcile[T] → ProjNode[T]
```

**Incremental reuse** is preserved at two levels:

1. **Layer 1 (CstNode level):** loom's `ImperativeParser` already does incremental reparsing — only damaged CstNode subtrees are rebuilt. Unchanged subtrees are reused via `physical_equal`. This is generic and stays in loom.

2. **Layer 2 (ProjNode level):** `reconcile[T]` preserves node IDs across reparses by matching via `T::same_kind`. This is generic and stays in the framework.

The FlatProj-level incremental reuse (`to_flat_proj_incremental` using CstNode `physical_equal` to skip unchanged defs) is **language-specific** — it depends on "module-shaped" grammars with named top-level definitions. It moves to `lang/lambda/flat/` as a language-specific optimization. Languages without a module structure get the two generic levels above, which are sufficient.

For lambda, the full pipeline with FlatProj optimization is:
```
ImperativeParser[Term] → Term → lang/lambda/flat/to_flat_proj_incremental → reconcile_flat_proj → to_proj_node → ProjNode[Term]
```

For a simple language (no module structure):
```
ImperativeParser[T] → T → framework/build_proj_node[T] → reconcile[T] → ProjNode[T]
```

### Reconciliation

Uses `T::same_kind` for node matching:

```moonbit
fn[T : TreeNode + Renderable] reconcile(
  old : ProjNode[T], new : ProjNode[T], counter : Ref[Int]
) -> ProjNode[T] {
  if T::same_kind(old.kind, new.kind) {
    // Preserve node_id, reconcile children via LCS
  } else {
    // Different kind — assign new ID
  }
}
```

## Three-Tier Tree Edit API

### Tier 1: UI State (no pipeline, O(1))

Methods on `TreeEditorState`, no type parameter:

```moonbit
pub fn TreeEditorState::select(self, NodeId) -> TreeEditorState
pub fn TreeEditorState::collapse(self, NodeId) -> TreeEditorState
pub fn TreeEditorState::expand(self, NodeId) -> TreeEditorState
pub fn TreeEditorState::start_edit(self, NodeId) -> TreeEditorState
pub fn TreeEditorState::cancel_edit(self) -> TreeEditorState
```

`TreeEditorState` is immutable — each method returns a new state. UI calls these directly without going through `SyncEditor`. This is Phase 3 (UI state separation).

### Tier 2: Generic Text-Delta Edits (framework, triggers pipeline)

All structural edits are **text span replacements** via `compute_text_delta`. The framework provides:

```moonbit
pub fn[T : TreeNode + Renderable] SyncEditor::delete_node(
  self, node_id : NodeId, timestamp_ms : Int
) -> Result[Unit, String]

pub fn[T : TreeNode + Renderable] SyncEditor::commit_edit(
  self, node_id : NodeId, new_text : String, timestamp_ms : Int
) -> Result[Unit, String]

pub fn[T : TreeNode + Renderable] SyncEditor::move_node(
  self, source : NodeId, target : NodeId, position : DropPosition, timestamp_ms : Int
) -> Result[Unit, String]
```

Internally, each method:
1. Looks up the node's span from `SourceMap`
2. Computes replacement text (using `T::placeholder()` for delete, `T::unparse()` for move, user text for commit)
3. Produces a `TextDelta`
4. Applies the delta via CRDT (`apply_text_edit`)
5. The reparse → reconcile → projection update happens automatically via the memo chain

No `rebuild`, no ProjNode mutation, no FlatProj roundtrip.

### Tier 3: Language-Specific Text-Delta Transforms (closure-based)

```moonbit
pub fn[T : TreeNode + Renderable] SyncEditor::apply_text_transform(
  self,
  target : NodeId,
  compute_replacement : (String, Int, Int) -> Result[String, String],
    // (source_text, span_start, span_end) -> replacement_text
  timestamp_ms : Int,
) -> Result[Unit, String]
```

The language provides a closure that computes replacement text given the current source text and the target node's span. The framework handles: span lookup → call closure → TextDelta → CRDT → reparse.

Example — wrap in lambda:
```moonbit
editor.apply_text_transform(node_id, fn(source, start, end) {
  let existing = source.substring(start, end)
  Ok("(λx. " + existing + ")")
}, timestamp)
```

**UI discovery:**

```moonbit
pub struct EditAction[T] {
  label : String
  shortcut : String?
  applicable : (ProjNode[T], NodeId) -> Bool
  compute_replacement : (String, Int, Int) -> Result[String, String]
}
```

Language packages export edit actions as data. UI renders as context menus.

### TreeEditOp migration

| Current variant | New location |
|----------------|-------------|
| Select, Collapse, Expand | Tier 1: TreeEditorState methods |
| StartEdit, CancelEdit | Tier 1: TreeEditorState methods |
| CommitEdit | Tier 2: SyncEditor::commit_edit |
| Delete | Tier 2: SyncEditor::delete_node |
| InsertChild | Tier 3: language-specific (computes insertion text + position) |
| DragOver, Drop | Tier 2: SyncEditor::move_node |
| WrapInLambda, WrapInApp | Tier 3: lang/lambda EditAction[Term] |

## Generic SyncEditor[T]

```moonbit
pub struct SyncEditor[T] {
  // CRDT layer (unchanged)
  priv doc : @text.TextDoc
  priv undo_mgr : @undo.UndoManager

  // Parser layer (parameterized — ImperativeParser[T] hides Grammar type params)
  priv parser : @loom.ImperativeParser[T]

  // Reactive pipeline (read-only projection, generic over T)
  priv cached_proj_node : @incr.Memo[ProjNode[T]?]
  priv registry_memo : @incr.Memo[Map[NodeId, ProjNode[T]]]
  priv source_map_memo : @incr.Memo[SourceMap]

  // UI state (no T — Phase 3 separation)
  priv mut editor_state : TreeEditorState

  // Collaboration (not parameterized by T)
  priv ephemeral : EphemeralStore
  priv cursor_view : PeerCursorView
  priv peer_id : String
}
```

Note: `proj_memo : Memo[FlatProj[T]?]` is removed from the framework. Language packages that need FlatProj implement it as an additional memo in their wrapper.

### Construction

```moonbit
pub fn[T : TreeNode + Renderable] SyncEditor::new(
  agent_id : String,
  make_parser : (String) -> @loom.ImperativeParser[T],
) -> SyncEditor[T]
```

`make_parser` is a factory closure that creates an `ImperativeParser[T]` from initial source text. This hides loom's `Grammar[T, K, Ast]` type parameters (`T` = token kind, `K` = syntax kind) from the framework — the framework only sees `ImperativeParser[T]` where `T` is the AST type.

The `cst_to_ast` catamorphism (the hylomorphism boundary from Layer 1 to Layer 2) is embedded inside the `ImperativeParser[T]` via loom's `Grammar.fold_node`. Language packages configure this when constructing the grammar:

```moonbit
// Lambda language package provides:
fn make_lambda_parser(source : String) -> @loom.ImperativeParser[Term] {
  @loom.new_imperative_parser(source, @parser.lambda_grammar)
  // lambda_grammar already contains fold_node: SyntaxNode → Term
}

// Usage:
let editor = SyncEditor::new("alice", make_lambda_parser)
```

This matches the existing pattern where `@parser.lambda_grammar` is used internally by `new_imperative_parser`, never exposed to the editor layer.

### Refresh boundary (Phase 4)

```moonbit
pub fn[T] SyncEditor::is_dirty(self) -> Bool
pub fn[T] SyncEditor::refresh(self) -> Unit
pub fn[T] SyncEditor::get_proj_node(self) -> ProjNode[T]?  // reads cached, does NOT refresh
```

Consumers call `refresh()` when ready to re-render. Multiple edits between refreshes accumulate as a single dirty flag.

## Package Structure

```
framework/
  framework/traits/     # TreeNode, Renderable (no deps)
  framework/core/       # ProjNode[T], SourceMap, NodeId, reconciliation
  framework/editor/     # SyncEditor[T], TreeEditorState, text-delta edits

lang/lambda/
  lang/lambda/ast/      # Term enum (from loom/examples/lambda/)
  lang/lambda/traits/   # impl TreeNode/Renderable for Term
  lang/lambda/flat/     # FlatProj[Term], to_flat_proj, reconcile_flat_proj (language-specific)
  lang/lambda/edits/    # EditAction[Term], compute_text_delta for lambda ops
  lang/lambda/bridge/   # cst_to_ast: SyntaxNode → Term

editor/                 # Application (framework + lang/lambda)
examples/web/           # Web frontend
```

**Dependency graph:**
```
framework/traits  →  framework/core  →  framework/editor
                                              ↓
                     lang/lambda  ────────→  editor/  →  examples/web/
```

**Acid test:** `framework/` compiles with zero imports from `lambda` or `@ast`.

## Extraction Approach: Bottom-Up

**Prerequisite:** Implement text-delta tree edit design first (eliminates FlatProj from edit path, makes ProjNode read-only).

Then extract incrementally — each step passes all tests:

1. Parameterize `ProjNode[T]` — replace `kind: @ast.Term` with generic `T`
2. Add capability traits (`TreeNode`, `Renderable`), implement for `Term`
3. Separate UI state from model pipeline (Phase 3)
4. Move FlatProj to language package (no longer framework-level)
5. Parameterize `SyncEditor[T]` — accept grammar + cst_to_ast
6. Add refresh boundary (Phase 4)
7. Extract framework packages, move lambda code to language package

## Testing Strategy

**Framework tests:** Use a minimal `TestExpr` enum (not lambda) to prove the framework works independently:
- ProjNode[TestExpr] construction and reconciliation
- TreeEditorState UI operations without pipeline
- SyncEditor[TestExpr] text edit → reparse → projection roundtrip
- Text-delta structural edits (delete, commit_edit, move)
- apply_text_transform with a test transform
- Refresh boundary protocol
- Incremental CST reuse (physical_equal) preserved after parameterization
- SourceMap span correctness after reconciliation

**TestExpr definition:**
```moonbit
enum TestExpr {
  Leaf(String)
  Node(String, Array[TestExpr])
}
impl TreeNode for TestExpr with children(self) {
  match self { Leaf(_) => []; Node(_, cs) => cs }
}
impl TreeNode for TestExpr with same_kind(self, other) {
  match (self, other) { (Leaf(_), Leaf(_)) => true; (Node(_, _), Node(_, _)) => true; _ => false }
}
impl Renderable for TestExpr with kind_tag(self) {
  match self { Leaf(_) => "Leaf"; Node(_, _) => "Node" }
}
impl Renderable for TestExpr with label(self) {
  match self { Leaf(s) => s; Node(tag, _) => tag }
}
impl Renderable for TestExpr with placeholder(self) {
  match self { Leaf(_) => "?"; Node(_, _) => "node(?)" }
}
impl Renderable for TestExpr with unparse(self) {
  match self { Leaf(s) => s; Node(tag, cs) => tag + "(" + cs.map(Renderable::unparse).join(", ") + ")" }
}
```

**Edge case tests:**
- Empty tree reconciliation (no children)
- Roundtrip: edit text → reparse → projection has correct structure and spans
- Error handling in text-delta edits (node not in source map, invalid span)

**Lambda tests:** Existing 232 tests continue to pass as a framework consumer.

**Lambda-specific SyncEditor methods** (`get_ast`, `get_resolution`, `get_dot_resolved`) move to `lang/lambda/` as extension functions or a thin wrapper around `SyncEditor[Term]`. They are NOT part of the framework API.

**Acid test:** `framework/` compiles with zero imports from `lambda` or `@ast`.

## JS FFI

JS consumers use a concrete wrapper type:

```moonbit
struct DynamicNode {
  tag : String
  text : String
  child_nodes : Array[DynamicNode]
  source : String
}

impl TreeNode for DynamicNode with children(self) { self.child_nodes }
impl TreeNode for DynamicNode with same_kind(self, other) { self.tag == other.tag }
impl Renderable for DynamicNode with kind_tag(self) { self.tag }
impl Renderable for DynamicNode with label(self) { self.text }
impl Renderable for DynamicNode with placeholder(self) { "?" }
impl Renderable for DynamicNode with unparse(self) { self.source }
```

JS consumers provide `cst_to_ast` as a callback that constructs `DynamicNode` from `SyntaxNode`. The framework's `SyncEditor[DynamicNode]` handles everything else — same code path as MoonBit consumers.

The intended JS model is **"MoonBit framework, JS UI only"**: parsing and projection happen in MoonBit (via loom), the JS layer handles rendering and user interaction. JS does NOT need to implement its own parser — it provides a `cst_to_ast` callback that maps loom's generic `SyntaxNode` to `DynamicNode`.
