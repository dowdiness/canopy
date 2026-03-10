# Memo-Derived ProjNode & CanonicalModel Retirement — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace CanonicalModel with Memo-derived ProjNode/registry/source_map on SyncEditor, making all projection state reactive and eliminating dual-state synchronization.

**Architecture:** SyncEditor gains three Memos (proj_memo, registry_memo, source_map_memo) that derive ProjNode from ReactiveParser's cached CST. Tree edits become functional (ProjNode in → ProjNode out). CanonicalModel is deleted.

**Tech Stack:** MoonBit, loom (Signal/Memo incremental computation), eg-walker CRDT, projection package (ProjNode, SourceMap, reconciliation)

**Spec:** [docs/design/2026-03-10-memo-derived-projnode-design.md](../../design/2026-03-10-memo-derived-projnode-design.md)

---

## Chunk 1: Prerequisites

### Task 1: Expose ReactiveParser Runtime

The new Memos must join ReactiveParser's reactive graph. Currently `ReactiveParser::new` creates a `Runtime` internally and never exposes it.

**Files:**
- Modify: `loom/loom/src/pipeline/reactive_parser.mbt:18-22` (struct), `:59` (constructor)
- Test: `loom/loom/src/pipeline/reactive_parser_test.mbt` (new test)

- [ ] **Step 1: Write failing test**

```moonbit
// In loom/loom/src/pipeline/ — whitebox test file (same package, no prefix needed)
test "ReactiveParser::runtime returns the internal Runtime" {
  let parser = ReactiveParser::new("hello", test_lang())
  let rt = parser.runtime()
  // Create a downstream Memo on the same Runtime
  let downstream = @incr.Memo::new(rt, fn() { parser.get_source().length() })
  inspect(downstream.get(), content="5")
  parser.set_source("hi")
  inspect(downstream.get(), content="2")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd loom && moon test -p loom/src/pipeline`
Expected: FAIL — `runtime` method not found

- [ ] **Step 3: Add `rt` field and `runtime()` accessor**

In `loom/loom/src/pipeline/reactive_parser.mbt`:

Add `rt` to struct (line 18-22):
```moonbit
pub struct ReactiveParser[Ast] {
  priv rt : @incr.Runtime
  priv source_text : @incr.Signal[String]
  priv cst_memo : @incr.Memo[CstStage]
  priv term_memo : @incr.Memo[Ast]
}
```

Update constructor return (line 59):
```moonbit
  { rt, source_text, cst_memo, term_memo }
```

Add accessor after constructor:
```moonbit
///|
/// Return the internal Runtime for creating downstream Memos.
pub fn[Ast] ReactiveParser::runtime(self : ReactiveParser[Ast]) -> @incr.Runtime {
  self.rt
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd loom && moon test -p loom/src/pipeline`
Expected: PASS

- [ ] **Step 5: Run all loom tests**

Run: `cd loom && moon check && moon test`
Expected: All pass

- [ ] **Step 6: Format and update interfaces**

Run: `cd loom && moon info && moon fmt`

- [ ] **Step 7: Commit**

```bash
cd loom
git add loom/src/pipeline/reactive_parser.mbt loom/src/pipeline/reactive_parser_test.mbt
git commit -m "feat: expose ReactiveParser::runtime() for downstream Memos"
```

---

### Task 2: Add derive(Eq) to ProjNode

`Memo::new` requires `T : Eq`. ProjNode only derives `Show`.

**Files:**
- Modify: `projection/proj_node.mbt:15`
- Test: `projection/proj_node_wbtest.mbt` (add Eq test or verify in existing tests)

- [ ] **Step 1: Write failing test**

```moonbit
// In projection/ — whitebox test
test "ProjNode structural equality" {
  let a = ProjNode::new(@ast.Int(42), 0, 2, 1, [])
  let b = ProjNode::new(@ast.Int(42), 0, 2, 1, [])
  let c = ProjNode::new(@ast.Int(99), 0, 2, 1, [])
  assert_true(a == b)
  assert_true(a != c)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `moon test -p projection`
Expected: FAIL — ProjNode does not support `==`

- [ ] **Step 3: Add derive(Eq) to ProjNode**

In `projection/proj_node.mbt:15`, change:
```moonbit
} derive(Show)
```
to:
```moonbit
} derive(Show, Eq)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `moon test -p projection`
Expected: PASS (all existing projection tests also pass)

- [ ] **Step 5: Format and update interfaces**

Run: `moon info && moon fmt`

- [ ] **Step 6: Commit**

```bash
git add projection/proj_node.mbt projection/pkg.generated.mbti
git commit -m "feat: add derive(Eq) to ProjNode for Memo compatibility"
```

---

## Chunk 2: Refactor Reconciliation to be CanonicalModel-Free

### Task 3: Refactor reconcile_ast, reconcile_children, assign_fresh_ids

Replace `CanonicalModel` parameter with `Ref[Int]` counter. Remove `unregister_node_tree_from_model` calls (registry will be derived).

**Files:**
- Modify: `projection/text_lens.mbt:112-313`
- Modify: `projection/tree_lens.mbt` (update `assign_fresh_ids` calls)
- Test: existing tests in `projection/` (no test file changes needed — `text_lens_put` signature unchanged)

- [ ] **Step 1: Change `assign_fresh_ids` signature**

In `projection/text_lens.mbt:306-313`, change:
```moonbit
fn assign_fresh_ids(node : ProjNode, model : CanonicalModel) -> ProjNode {
  let new_id = model.new_node_id()
```
to:
```moonbit
pub fn assign_fresh_ids(node : ProjNode, counter : Ref[Int]) -> ProjNode {
  let new_id = next_proj_node_id(counter)
```

And update the recursive call:
```moonbit
    new_children.push(assign_fresh_ids(child, counter))
```

Note: `new_id` changes from `NodeId` (returned by `model.new_node_id()`) to `Int` (returned by `next_proj_node_id(counter)`). Remove the `.0` accessor in the return:
```moonbit
  // Was: ProjNode::new(node.kind, node.start, node.end, new_id.0, new_children)
  ProjNode::new(node.kind, node.start, node.end, new_id, new_children)
```

- [ ] **Step 2: Change `reconcile_children` signature**

In `projection/text_lens.mbt:227-302`, change:
```moonbit
fn reconcile_children(
  old_children : Array[ProjNode],
  new_children : Array[ProjNode],
  model : CanonicalModel,
) -> Array[ProjNode] {
```
to:
```moonbit
fn reconcile_children(
  old_children : Array[ProjNode],
  new_children : Array[ProjNode],
  counter : Ref[Int],
) -> Array[ProjNode] {
```

Update the two call sites inside:
- Line ~287: `reconcile_ast(old_children[new_matched[j]], new_children[j], model)` → `reconcile_ast(old_children[new_matched[j]], new_children[j], counter)`
- Line ~289: `assign_fresh_ids(new_children[j], model)` → `assign_fresh_ids(new_children[j], counter)`

Remove the stale-ID cleanup loop (lines ~296-301):
```moonbit
  // DELETE THIS BLOCK:
  // Unregister removed old children that weren't matched
  for i = 0; i < old_len; i = i + 1 {
    if old_matched[i] < 0 {
      unregister_node_tree_from_model(old_children[i], model)
    }
  }
```

- [ ] **Step 3: Change `reconcile_ast` signature and make pub**

In `projection/text_lens.mbt:112-220`, change:
```moonbit
fn reconcile_ast(
  old : ProjNode,
  new : ProjNode,
  model : CanonicalModel,
) -> ProjNode {
```
to:
```moonbit
pub fn reconcile_ast(
  old : ProjNode,
  new : ProjNode,
  counter : Ref[Int],
) -> ProjNode {
```

Update all internal recursive calls from `reconcile_ast(o, n, model)` to `reconcile_ast(o, n, counter)`.
Update all `assign_fresh_ids(new, model)` calls to `assign_fresh_ids(new, counter)`.
Update all `reconcile_children(old.children, new.children, model)` calls to `reconcile_children(old.children, new.children, counter)`.

- [ ] **Step 4: Update `text_lens_put` to use Ref[Int] internally**

`text_lens_put` currently passes `model` to `reconcile_ast`. It needs to create a `Ref[Int]` from `model.next_node_id` and update it back:

```moonbit
pub fn text_lens_put(
  model : CanonicalModel,
  text : String,
) -> Result[CanonicalModel, String] {
  let (new_ast, _) = parse_to_proj_node(text)
  match model.get_ast() {
    Some(old_ast) => {
      let counter = Ref::new(model.next_node_id)
      let reconciled = reconcile_ast(old_ast, new_ast, counter)
      model.next_node_id = counter.val
      model.set_ast(reconciled)
      Ok(model)
    }
    None => {
      model.set_ast(new_ast)
      Ok(model)
    }
  }
}
```

Note: `next_node_id` is `priv mut` on CanonicalModel but this is a whitebox file (same package), so direct access works.

- [ ] **Step 5: Update `tree_lens_put` similarly**

In `projection/tree_lens.mbt:18-40`, update:
```moonbit
pub fn tree_lens_put(
  model : CanonicalModel,
  ast : ProjNode?,
) -> Result[CanonicalModel, String] {
  match ast {
    Some(new_ast) =>
      match model.get_ast() {
        Some(old_ast) => {
          let counter = Ref::new(model.next_node_id)
          let reconciled = reconcile_ast(old_ast, new_ast, counter)
          model.next_node_id = counter.val
          model.set_ast(reconciled)
          Ok(model)
        }
        None => {
          model.set_ast(new_ast)
          Ok(model)
        }
      }
    None => Err("Cannot set AST to None - model requires an AST")
  }
}
```

- [ ] **Step 6: Update `tree_lens_apply_edit` calls to `assign_fresh_ids`**

In `projection/tree_lens.mbt`, every call `assign_fresh_ids(parsed, model)` becomes:
```moonbit
let counter = Ref::new(model.next_node_id)
let new_node = assign_fresh_ids(parsed, counter)
model.next_node_id = counter.val
```

This applies to lines ~96, ~128, ~151, ~178 in `tree_lens.mbt`.

- [ ] **Step 7: Run all tests**

Run: `moon check && moon test`
Expected: All pass — behavior unchanged, only signature refactored

- [ ] **Step 8: Format and update interfaces**

Run: `moon info && moon fmt`

- [ ] **Step 9: Commit**

```bash
git add projection/text_lens.mbt projection/tree_lens.mbt projection/pkg.generated.mbti
git commit -m "refactor: reconcile_ast takes Ref[Int] instead of CanonicalModel"
```

---

### Task 4: Expose syntax_to_proj_node as pub

**Files:**
- Modify: `projection/proj_node.mbt:100`

- [ ] **Step 1: Change visibility**

In `projection/proj_node.mbt:100`, change:
```moonbit
fn syntax_to_proj_node(node : @seam.SyntaxNode, counter : Ref[Int]) -> ProjNode {
```
to:
```moonbit
pub fn syntax_to_proj_node(node : @seam.SyntaxNode, counter : Ref[Int]) -> ProjNode {
```

Also expose `unwrap_expression_root` (line 233):
```moonbit
pub fn unwrap_expression_root(node : @seam.SyntaxNode) -> @seam.SyntaxNode {
```

- [ ] **Step 2: Run tests**

Run: `moon check && moon test`
Expected: All pass

- [ ] **Step 3: Format and update interfaces**

Run: `moon info && moon fmt`

- [ ] **Step 4: Commit**

```bash
git add projection/proj_node.mbt projection/pkg.generated.mbti
git commit -m "feat: expose syntax_to_proj_node and unwrap_expression_root as pub"
```

---

## Chunk 3: Add Memo Fields to SyncEditor

> **Dependency:** Requires Chunk 1 (Task 1: ReactiveParser::runtime) and Chunk 2 (Task 3: reconcile_ast refactoring) to be completed first.

### Task 5: Add Memo fields and projection accessors to SyncEditor

**Files:**
- Modify: `moon.mod.json` (add `dowdiness/incr` dependency)
- Modify: `editor/sync_editor.mbt:5-23`
- Modify: `editor/moon.pkg` (add `dowdiness/incr` import)
- Create: `editor/projection_memo.mbt` (Memo setup + accessors — keeps sync_editor.mbt focused)
- Test: `editor/projection_memo_test.mbt`

- [ ] **Step 0: Add `dowdiness/incr` to `moon.mod.json` deps**

`dowdiness/incr` is currently only a transitive dependency via `dowdiness/loom`. MoonBit requires direct dependency declarations. In `moon.mod.json`, add to `"deps"`:
```json
"dowdiness/incr": { "path": "./loom/incr" }
```

- [ ] **Step 1: Add `dowdiness/incr` to editor imports**

In `editor/moon.pkg`, add the import:
```
"dowdiness/incr" @incr,
```

- [ ] **Step 2: Run `moon check` to verify import works**

Run: `moon check`
Expected: PASS

- [ ] **Step 3: Write failing tests**

Create `editor/projection_memo_test.mbt`:
```moonbit
test "get_proj_node returns ProjNode for valid expression" {
  let editor = SyncEditor::new("test")
  editor.set_text("42")
  let proj = editor.get_proj_node()
  inspect(proj.is_empty(), content="false")
}

test "get_proj_node returns None for empty text" {
  let editor = SyncEditor::new("test")
  let proj = editor.get_proj_node()
  // Empty string parses to something (parser may produce error node or Unit)
  // Just verify it doesn't crash
  let _ = proj
}

test "get_proj_node caching - same node IDs without text change" {
  let editor = SyncEditor::new("test")
  editor.set_text("42")
  let proj1 = editor.get_proj_node()
  let proj2 = editor.get_proj_node()
  // Same object returned from Memo cache
  inspect(proj1 == proj2, content="true")
}

test "get_proj_node preserves node IDs after edit" {
  let editor = SyncEditor::new("test")
  editor.set_text("(λx. 42)")
  let proj1 = editor.get_proj_node()
  // Edit the body (42 -> 99) but keep lambda structure
  editor.set_text("(λx. 99)")
  let proj2 = editor.get_proj_node()
  // Lambda root should keep same node_id
  match (proj1, proj2) {
    (Some(p1), Some(p2)) => inspect(p1.node_id == p2.node_id, content="true")
    _ => abort("Expected Some for both")
  }
}

test "get_source_map returns valid SourceMap" {
  let editor = SyncEditor::new("test")
  editor.set_text("42")
  let sm = editor.get_source_map()
  let proj = editor.get_proj_node()
  match proj {
    Some(p) => {
      let range = sm.get_range(@proj.NodeId(p.node_id))
      inspect(range.is_empty(), content="false")
    }
    None => abort("Expected Some")
  }
}

test "get_node looks up by NodeId" {
  let editor = SyncEditor::new("test")
  editor.set_text("42")
  match editor.get_proj_node() {
    Some(p) => {
      let found = editor.get_node(@proj.NodeId(p.node_id))
      inspect(found.is_empty(), content="false")
    }
    None => abort("Expected Some")
  }
}

test "node_at_position finds innermost node" {
  let editor = SyncEditor::new("test")
  editor.set_text("42")
  let id = editor.node_at_position(0)
  inspect(id.is_empty(), content="false")
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `moon test -p editor`
Expected: FAIL — `get_proj_node` method not found

- [ ] **Step 5: Add Memo fields to SyncEditor struct**

In `editor/sync_editor.mbt:5-10`, change:
```moonbit
pub struct SyncEditor {
  priv doc : @text.TextDoc
  priv undo : @undo.UndoManager
  priv parser : @loom.ReactiveParser[@parser.SyntaxNode]
  priv mut cursor : Int
}
```
to:
```moonbit
pub struct SyncEditor {
  priv doc : @text.TextDoc
  priv undo : @undo.UndoManager
  priv parser : @loom.ReactiveParser[@parser.SyntaxNode]
  priv mut cursor : Int
  // Projection derivation (Memo chain from parser CST)
  priv proj_memo : @incr.Memo[@proj.ProjNode?]
  priv registry_memo : @incr.Memo[Map[@proj.NodeId, @proj.ProjNode]]
  priv source_map_memo : @incr.Memo[@proj.SourceMap]
  priv prev_proj_node : Ref[@proj.ProjNode?]    // Ref for closure capture
  priv next_node_id : Ref[Int]                   // Ref for closure capture
}
```

Note: `prev_proj_node` and `next_node_id` use `Ref` (not `mut`) because the Memo compute closures need to capture and mutate them. `Ref` boxes are shared between the closures and the struct.

- [ ] **Step 6: Create projection_memo.mbt with Memo setup helper and accessors**

Create `editor/projection_memo.mbt`:
```moonbit
// Projection Memo: Reactive derivation of ProjNode, registry, and source map
// from ReactiveParser's cached CST.

///|
/// Build the three projection Memos on the parser's Runtime.
/// Called once during SyncEditor::new().
fn build_projection_memos(
  parser : @loom.ReactiveParser[@parser.SyntaxNode],
  prev_proj_ref : Ref[@proj.ProjNode?],
  next_id_ref : Ref[Int],
) -> (@incr.Memo[@proj.ProjNode?], @incr.Memo[Map[@proj.NodeId, @proj.ProjNode]], @incr.Memo[@proj.SourceMap]) {
  let rt = parser.runtime()

  let proj_memo : @incr.Memo[@proj.ProjNode?] = @incr.Memo::new(
    rt,
    fn() -> @proj.ProjNode? {
      let cst_stage = parser.cst()
      let syntax = @seam.SyntaxNode::from_cst(cst_stage.cst)
      let root = @proj.unwrap_expression_root(syntax)
      let counter : Ref[Int] = Ref::new(next_id_ref.val)
      let new_proj = @proj.syntax_to_proj_node(root, counter)
      let reconciled = match prev_proj_ref.val {
        None => new_proj
        Some(prev) => @proj.reconcile_ast(prev, new_proj, counter)
      }
      next_id_ref.val = counter.val
      prev_proj_ref.val = Some(reconciled)
      Some(reconciled)
    },
    label="proj_node",
  )

  let registry_memo : @incr.Memo[Map[@proj.NodeId, @proj.ProjNode]] = @incr.Memo::new(
    rt,
    fn() -> Map[@proj.NodeId, @proj.ProjNode] {
      let registry : Map[@proj.NodeId, @proj.ProjNode] = {}
      match proj_memo.get() {
        Some(root) => register_node_tree(root, registry)
        None => ()
      }
      registry
    },
    label="registry",
  )

  let source_map_memo : @incr.Memo[@proj.SourceMap] = @incr.Memo::new(
    rt,
    fn() -> @proj.SourceMap {
      let sm = @proj.SourceMap::new()
      match proj_memo.get() {
        Some(root) => sm.rebuild(root)
        None => ()
      }
      sm
    },
    label="source_map",
  )

  (proj_memo, registry_memo, source_map_memo)
}

///|
/// Recursively register a node and its children into a registry map.
fn register_node_tree(
  node : @proj.ProjNode,
  registry : Map[@proj.NodeId, @proj.ProjNode],
) -> Unit {
  registry[@proj.NodeId(node.node_id)] = node
  for child in node.children {
    register_node_tree(child, registry)
  }
}

// --- Public projection accessors ---

///|
/// Get the current ProjNode tree (lazy — triggers Memo chain if stale).
pub fn SyncEditor::get_proj_node(self : SyncEditor) -> @proj.ProjNode? {
  self.proj_memo.get()
}

///|
/// Get the current SourceMap (lazy — derived from ProjNode).
pub fn SyncEditor::get_source_map(self : SyncEditor) -> @proj.SourceMap {
  self.source_map_memo.get()
}

///|
/// Look up a node by its ID.
pub fn SyncEditor::get_node(
  self : SyncEditor,
  id : @proj.NodeId,
) -> @proj.ProjNode? {
  self.registry_memo.get().get(id)
}

///|
/// Find the innermost node at a text position.
pub fn SyncEditor::node_at_position(
  self : SyncEditor,
  position : Int,
) -> @proj.NodeId? {
  self.source_map_memo.get().innermost_node_at(position)
}

///|
/// Get the text range for a node.
pub fn SyncEditor::get_node_range(
  self : SyncEditor,
  id : @proj.NodeId,
) -> @loom_core.Range? {
  self.source_map_memo.get().get_range(id)
}
```

- [ ] **Step 7: Update SyncEditor::new() to initialize Memos**

In `editor/sync_editor.mbt:13-23`, change constructor:
```moonbit
pub fn SyncEditor::new(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
) -> SyncEditor {
  let parser = @loom.new_reactive_parser("", @parser.lambda_grammar)
  let prev_proj_ref : Ref[@proj.ProjNode?] = Ref::new(None)
  let next_id_ref : Ref[Int] = Ref::new(0)
  let (proj_memo, registry_memo, source_map_memo) = build_projection_memos(
    parser, prev_proj_ref, next_id_ref,
  )
  {
    doc: @text.TextDoc::new(agent_id),
    undo: @undo.UndoManager::new(agent_id, capture_timeout_ms~),
    parser,
    cursor: 0,
    proj_memo,
    registry_memo,
    source_map_memo,
    prev_proj_node: None,
    next_node_id: 0,
  }
}
```

Constructor:
```moonbit
pub fn SyncEditor::new(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
) -> SyncEditor {
  let parser = @loom.new_reactive_parser("", @parser.lambda_grammar)
  let prev_proj_node : Ref[@proj.ProjNode?] = Ref::new(None)
  let next_node_id : Ref[Int] = Ref::new(0)
  let (proj_memo, registry_memo, source_map_memo) = build_projection_memos(
    parser, prev_proj_node, next_node_id,
  )
  {
    doc: @text.TextDoc::new(agent_id),
    undo: @undo.UndoManager::new(agent_id, capture_timeout_ms~),
    parser,
    cursor: 0,
    proj_memo,
    registry_memo,
    source_map_memo,
    prev_proj_node,
    next_node_id,
  }
}
```

- [ ] **Step 8: Run tests**

Run: `moon check && moon test`
Expected: All pass including new projection_memo tests

- [ ] **Step 9: Format and update interfaces**

Run: `moon info && moon fmt`

- [ ] **Step 10: Commit**

```bash
git add editor/sync_editor.mbt editor/projection_memo.mbt editor/projection_memo_test.mbt editor/moon.pkg editor/pkg.generated.mbti
git commit -m "feat: add Memo-derived ProjNode, registry, source_map to SyncEditor"
```

---

## Chunk 4: Functional Tree Edit API

### Task 6: Move helper functions from canonical_model.mbt to tree_lens.mbt

These pure helper functions need to be available after CanonicalModel is deleted. They must be **moved** (not copied) to avoid duplicate function definitions within the same package.

**Files:**
- Modify: `projection/tree_lens.mbt` (add helper functions)
- Modify: `projection/canonical_model.mbt` (remove moved functions — `apply_operation` will call them from their new location since they're package-private)

- [ ] **Step 1: Copy pure helper functions to tree_lens.mbt**

Add to `projection/tree_lens.mbt` (before `tree_lens_apply_edit`):

```moonbit
///|
/// Update a node in the tree by its ID (returns new tree root).
fn update_node_in_tree(
  root : ProjNode,
  target_id : NodeId,
  new_node : ProjNode,
) -> ProjNode {
  if NodeId(root.node_id) == target_id {
    new_node
  } else {
    let new_children : Array[ProjNode] = []
    for child in root.children {
      new_children.push(update_node_in_tree(child, target_id, new_node))
    }
    ProjNode::new(
      rebuild_kind(root.kind, new_children),
      root.start,
      root.end,
      root.node_id,
      new_children,
    )
  }
}

///|
/// Remove a child from a node's children by index.
fn remove_child_at(node : ProjNode, index : Int) -> ProjNode {
  let new_children : Array[ProjNode] = []
  for i, child in node.children {
    if i != index {
      new_children.push(child)
    }
  }
  ProjNode::new(
    rebuild_kind(node.kind, new_children),
    node.start,
    node.end,
    node.node_id,
    new_children,
  )
}

///|
/// Insert a child into a node's children at index.
fn insert_child_at(node : ProjNode, index : Int, child : ProjNode) -> ProjNode {
  let new_children : Array[ProjNode] = []
  for i, c in node.children {
    if i == index {
      new_children.push(child)
    }
    new_children.push(c)
  }
  if index >= node.children.length() {
    new_children.push(child)
  }
  ProjNode::new(
    rebuild_kind(node.kind, new_children),
    node.start,
    node.end,
    node.node_id,
    new_children,
  )
}

///|
/// Find a node in a tree by ID.
fn get_node_in_tree(root : ProjNode, target_id : NodeId) -> ProjNode? {
  if NodeId(root.node_id) == target_id {
    Some(root)
  } else {
    for child in root.children {
      match get_node_in_tree(child, target_id) {
        Some(found) => return Some(found)
        None => continue
      }
    }
    None
  }
}

///|
/// Find the parent of a node by its ID.
/// Returns (parent_node, index_in_parent) or None if node is root or not found.
fn find_parent_in_tree(
  root : ProjNode,
  target_id : NodeId,
) -> (ProjNode, Int)? {
  for i, child in root.children {
    if NodeId(child.node_id) == target_id {
      return Some((root, i))
    }
    match find_parent_in_tree(child, target_id) {
      Some(result) => return Some(result)
      None => continue
    }
  }
  None
}
```

- [ ] **Step 1b: Remove moved functions from canonical_model.mbt**

Delete `update_node_in_tree`, `remove_child_at`, `insert_child_at`, `get_node_in_tree` from `projection/canonical_model.mbt` (lines 221-266, 454-466). These are package-private free functions (not methods), so `apply_operation` in the same package can still call them from their new location in `tree_lens.mbt`.

Note: `find_parent_recursive` stays in `canonical_model.mbt` (different name from `find_parent_in_tree` in tree_lens.mbt — no conflict).

- [ ] **Step 2: Run tests to verify no regressions**

Run: `moon check && moon test -p projection`
Expected: PASS — functions are package-private, same-package access works from either file

- [ ] **Step 3: Commit**

```bash
git add projection/tree_lens.mbt
git commit -m "refactor: add standalone tree helper functions to tree_lens.mbt"
```

---

### Task 7: Add apply_edit_to_proj functional API

**Files:**
- Modify: `projection/tree_lens.mbt` (add new function)
- Test: `projection/tree_lens_wbtest.mbt` (new test file)

- [ ] **Step 1: Write failing tests**

Create `projection/tree_lens_wbtest.mbt`:
```moonbit
test "apply_edit_to_proj - CommitEdit" {
  let (root, _) = parse_to_proj_node("42")
  let registry : Map[NodeId, ProjNode] = {}
  register_all(root, registry)
  let counter : Ref[Int] = Ref::new(100)
  let result = apply_edit_to_proj(
    root,
    TreeEditOp::CommitEdit(node_id=NodeId(root.node_id), new_value="99"),
    registry,
    counter,
  )
  match result {
    Ok(new_root) => inspect(@ast.print_term(new_root.kind), content="99")
    Err(msg) => abort("Unexpected error: " + msg)
  }
}

test "apply_edit_to_proj - WrapInLambda" {
  let (root, _) = parse_to_proj_node("42")
  let registry : Map[NodeId, ProjNode] = {}
  register_all(root, registry)
  let counter : Ref[Int] = Ref::new(100)
  let result = apply_edit_to_proj(
    root,
    TreeEditOp::WrapInLambda(node_id=NodeId(root.node_id), var_name="x"),
    registry,
    counter,
  )
  match result {
    Ok(new_root) => inspect(@ast.print_term(new_root.kind), content="(λx. 42)")
    Err(msg) => abort("Unexpected error: " + msg)
  }
}

test "apply_edit_to_proj - WrapInApp" {
  let (root, _) = parse_to_proj_node("42")
  let registry : Map[NodeId, ProjNode] = {}
  register_all(root, registry)
  let counter : Ref[Int] = Ref::new(100)
  let result = apply_edit_to_proj(
    root,
    TreeEditOp::WrapInApp(node_id=NodeId(root.node_id)),
    registry,
    counter,
  )
  match result {
    Ok(new_root) => inspect(@ast.print_term(new_root.kind), content="(42 a)")
    Err(msg) => abort("Unexpected error: " + msg)
  }
}

test "apply_edit_to_proj - Select preserves tree" {
  let (root, _) = parse_to_proj_node("42")
  let registry : Map[NodeId, ProjNode] = {}
  register_all(root, registry)
  let counter : Ref[Int] = Ref::new(100)
  let result = apply_edit_to_proj(
    root,
    TreeEditOp::Select(node_id=NodeId(root.node_id)),
    registry,
    counter,
  )
  match result {
    Ok(new_root) => inspect(new_root == root, content="true")
    Err(msg) => abort("Unexpected error: " + msg)
  }
}

///|
fn register_all(node : ProjNode, registry : Map[NodeId, ProjNode]) -> Unit {
  registry[NodeId(node.node_id)] = node
  for child in node.children {
    register_all(child, registry)
  }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -p projection -f tree_lens_wbtest.mbt`
Expected: FAIL — `apply_edit_to_proj` not found

- [ ] **Step 3: Implement apply_edit_to_proj**

Add to `projection/tree_lens.mbt`:

```moonbit
///|
/// Apply a tree edit operation to a ProjNode tree (functional — no mutation).
/// Returns a new ProjNode root or error.
pub fn apply_edit_to_proj(
  root : ProjNode,
  edit : TreeEditOp,
  registry : Map[NodeId, ProjNode],
  counter : Ref[Int],
) -> Result[ProjNode, String] {
  match edit {
    // UI-only operations return tree unchanged
    Select(..) | SelectRange(..) | StartEdit(..) | CancelEdit |
    StartDrag(..) | DragOver(..) | Collapse(..) | Expand(..) =>
      Ok(root)

    CommitEdit(node_id~, new_value~) => {
      let (parsed, _) = parse_to_proj_node(new_value)
      let new_node = assign_fresh_ids(parsed, counter)
      let replacement = ProjNode::new(
        new_node.kind, new_node.start, new_node.end,
        node_id.0, new_node.children,
      )
      Ok(update_node_in_tree(root, node_id, replacement))
    }

    Delete(node_id~) =>
      match find_parent_in_tree(root, node_id) {
        None => Err("Cannot delete root or node not found")
        Some((parent_node, index)) => {
          let new_parent = remove_child_at(parent_node, index)
          Ok(update_node_in_tree(root, NodeId(parent_node.node_id), new_parent))
        }
      }

    WrapInLambda(node_id~, var_name~) =>
      match registry.get(node_id) {
        None => Err("Node not found: " + node_id.to_string())
        Some(existing) => {
          let existing_text = @ast.print_term(existing.kind)
          let lambda_text = "λ" + var_name + "." + existing_text
          let (parsed, diagnostics) = parse_to_proj_node(lambda_text)
          if diagnostics.length() > 0 {
            return Err("Failed to parse wrapped lambda: " + diagnostics[0])
          }
          let new_node = assign_fresh_ids(parsed, counter)
          Ok(update_node_in_tree(root, node_id, new_node))
        }
      }

    WrapInApp(node_id~) =>
      match registry.get(node_id) {
        None => Err("Node not found: " + node_id.to_string())
        Some(existing) => {
          let existing_text = @ast.print_term(existing.kind)
          let app_text = "(" + existing_text + ") a"
          let (parsed, diagnostics) = parse_to_proj_node(app_text)
          if diagnostics.length() > 0 {
            return Err("Failed to parse wrapped application: " + diagnostics[0])
          }
          let new_node = assign_fresh_ids(parsed, counter)
          Ok(update_node_in_tree(root, node_id, new_node))
        }
      }

    InsertChild(parent~, index~, kind~) => {
      let placeholder_text = match kind {
        @ast.Term::Int(_) => "0"
        @ast.Term::Var(_) => "a"
        @ast.Term::Lam(_, _) => "λx.x"
        @ast.Term::App(_, _) => "f x"
        @ast.Term::Bop(_, _, _) => "0 + 0"
        @ast.Term::If(_, _, _) => "if 0 then 0 else 0"
        @ast.Term::Let(_, _, _) => "let x = 0 in x"
        @ast.Term::Unit => "()"
        @ast.Term::Error(_) => "a"
      }
      let (parsed, diagnostics) = parse_to_proj_node(placeholder_text)
      if diagnostics.length() > 0 {
        return Err("Failed to parse placeholder: " + diagnostics[0])
      }
      let new_node = assign_fresh_ids(parsed, counter)
      match get_node_in_tree(root, parent) {
        None => Err("Parent not found: " + parent.to_string())
        Some(parent_node) => {
          let new_parent = insert_child_at(parent_node, index, new_node)
          Ok(update_node_in_tree(root, parent, new_parent))
        }
      }
    }

    Drop(source~, target~, position~) =>
      match find_parent_in_tree(root, target) {
        None => Err("Cannot drop on root node")
        Some((parent_node, target_index)) => {
          let new_index = match position {
            Before => target_index
            After => target_index + 1
            Inside => 0
          }
          let new_parent = match position {
            Before | After => NodeId(parent_node.node_id)
            Inside => target
          }
          // Remove source from old location
          match find_parent_in_tree(root, source) {
            None => Err("Cannot move root node")
            Some((old_parent, old_index)) => {
              let old_parent_id = NodeId(old_parent.node_id)
              match get_node_in_tree(root, source) {
                None => Err("Source not found")
                Some(source_node) => {
                  let parent_after_remove = remove_child_at(old_parent, old_index)
                  let root_after_remove = update_node_in_tree(root, old_parent_id, parent_after_remove)
                  let adjusted_index = if old_parent_id == new_parent && old_index < new_index {
                    new_index - 1
                  } else {
                    new_index
                  }
                  match get_node_in_tree(root_after_remove, new_parent) {
                    None => Err("New parent not found: " + new_parent.to_string())
                    Some(new_parent_node) => {
                      let parent_after_insert = insert_child_at(new_parent_node, adjusted_index, source_node)
                      Ok(update_node_in_tree(root_after_remove, new_parent, parent_after_insert))
                    }
                  }
                }
              }
            }
          }
        }
      }
  }
}
```

- [ ] **Step 4: Run tests**

Run: `moon check && moon test -p projection`
Expected: All pass

- [ ] **Step 5: Format and update interfaces**

Run: `moon info && moon fmt`

- [ ] **Step 6: Commit**

```bash
git add projection/tree_lens.mbt projection/tree_lens_wbtest.mbt projection/pkg.generated.mbti
git commit -m "feat: add apply_edit_to_proj functional tree edit API"
```

---

## Chunk 5: Breaking Changes — apply_tree_edit & TreeEditorState

> **Dependency:** Requires Chunk 3 (Task 5: SyncEditor Memo fields) and Chunk 4 (Task 7: apply_edit_to_proj) to be completed first.

### Task 8: Update apply_tree_edit to use internal Memos

**Files:**
- Modify: `editor/tree_edit_bridge.mbt` (rewrite)
- Modify: `editor/tree_edit_bridge_test.mbt` (simplify setup)

- [ ] **Step 1: Rewrite tree_edit_bridge.mbt**

Replace entire contents of `editor/tree_edit_bridge.mbt`:
```moonbit
// Tree Edit Bridge: Apply structural AST edits through the text CRDT
// TreeEditOp → functional ProjNode edit → unparse → set_text → Memo auto-reconciles

///|
/// Apply a tree edit using SyncEditor's internal projection state.
///
/// 1. Get current ProjNode from Memo
/// 2. Apply edit functionally (ProjNode → ProjNode)
/// 3. Unparse to text
/// 4. Set CRDT text (generates broadcastable ops)
/// 5. Memo chain auto-reconciles on next get_proj_node() access
pub fn SyncEditor::apply_tree_edit(
  self : SyncEditor,
  op : @proj.TreeEditOp,
) -> Result[Unit, String] {
  let old_text = self.get_text()
  let old_cursor = self.get_cursor()

  // 1. Get current ProjNode tree
  let proj = match self.get_proj_node() {
    Some(p) => p
    None => return Err("No ProjNode available")
  }

  // 2. Apply edit functionally
  let registry = self.registry_memo.get()
  let new_proj = match @proj.apply_edit_to_proj(proj, op, registry, self.next_node_id) {
    // next_node_id is Ref[Int] — apply_edit_to_proj mutates it via the Ref
    Ok(p) => p
    Err(msg) => return Err(msg)
  }

  // 3. Unparse to text
  let new_text = @ast.print_term(new_proj.kind)

  // 4. Skip CRDT ops if text unchanged (UI-only ops: Select, Collapse, etc.)
  if old_text == new_text {
    return Ok(())
  }

  // 5. Apply text change to CRDT
  self.set_text(new_text)
  self.move_cursor(old_cursor)

  Ok(())
}
```

- [ ] **Step 2: Rewrite tree_edit_bridge_test.mbt**

Replace entire contents of `editor/tree_edit_bridge_test.mbt`:
```moonbit
// Tests for the tree edit bridge roundtrip:
// TreeEditOp -> ProjNode (structural) -> unparse -> set_text -> Memo reconcile

///|
/// Helper: create a SyncEditor initialized with text
fn setup_bridge(text : String) -> SyncEditor {
  let editor = SyncEditor::new("test")
  editor.set_text(text)
  editor
}

///|
/// Helper: get root NodeId from editor's ProjNode
fn get_root_id(editor : SyncEditor) -> @proj.NodeId {
  match editor.get_proj_node() {
    Some(p) => @proj.NodeId(p.node_id)
    None => abort("No ProjNode available")
  }
}

///|
test "apply_tree_edit - Select preserves text" {
  let editor = setup_bridge("42")
  let id = get_root_id(editor)
  let result = editor.apply_tree_edit(@proj.TreeEditOp::Select(node_id=id))
  inspect(result, content="Ok(())")
  inspect(editor.get_text(), content="42")
}

///|
test "apply_tree_edit - Collapse preserves text" {
  let editor = setup_bridge("42")
  let id = get_root_id(editor)
  let result = editor.apply_tree_edit(@proj.TreeEditOp::Collapse(node_id=id))
  inspect(result, content="Ok(())")
  inspect(editor.get_text(), content="42")
}

///|
test "apply_tree_edit - WrapInLambda" {
  let editor = setup_bridge("42")
  let id = get_root_id(editor)
  let result = editor.apply_tree_edit(
    @proj.TreeEditOp::WrapInLambda(node_id=id, var_name="x"),
  )
  inspect(result, content="Ok(())")
  inspect(editor.get_text(), content="(λx. 42)")
}

///|
test "apply_tree_edit - WrapInApp" {
  let editor = setup_bridge("42")
  let id = get_root_id(editor)
  let result = editor.apply_tree_edit(@proj.TreeEditOp::WrapInApp(node_id=id))
  inspect(result, content="Ok(())")
  inspect(editor.get_text(), content="(42 a)")
}

///|
test "apply_tree_edit - CommitEdit replaces value" {
  let editor = setup_bridge("42")
  let id = get_root_id(editor)
  let result = editor.apply_tree_edit(
    @proj.TreeEditOp::CommitEdit(node_id=id, new_value="99"),
  )
  inspect(result, content="Ok(())")
  inspect(editor.get_text(), content="99")
}

///|
test "apply_tree_edit - preserves cursor for follow-up text edits" {
  let editor = setup_bridge("42")
  editor.move_cursor(1)
  let id = get_root_id(editor)
  let result = editor.apply_tree_edit(
    @proj.TreeEditOp::CommitEdit(node_id=id, new_value="99"),
  )
  inspect(result, content="Ok(())")
  inspect(editor.get_cursor(), content="1")
  try! editor.insert("x")
  inspect(editor.get_text(), content="9x9")
}

///|
test "apply_tree_edit - CommitEdit with expression" {
  let editor = setup_bridge("42")
  let id = get_root_id(editor)
  let result = editor.apply_tree_edit(
    @proj.TreeEditOp::CommitEdit(node_id=id, new_value="λz.z"),
  )
  inspect(result, content="Ok(())")
  inspect(editor.get_text(), content="(λz. z)")
}

///|
test "apply_tree_edit - CRDT text and ProjNode converge after WrapInLambda" {
  let editor = setup_bridge("42")
  let id = get_root_id(editor)
  let result = editor.apply_tree_edit(
    @proj.TreeEditOp::WrapInLambda(node_id=id, var_name="y"),
  )
  inspect(result, content="Ok(())")
  // Verify ProjNode text matches CRDT text
  match editor.get_proj_node() {
    Some(p) => inspect(@ast.print_term(p.kind), content="(λy. 42)")
    None => abort("Expected ProjNode")
  }
  inspect(editor.get_text(), content="(λy. 42)")
}

///|
test "apply_tree_edit - CRDT text and ProjNode converge after CommitEdit" {
  let editor = setup_bridge("42")
  let id = get_root_id(editor)
  let result = editor.apply_tree_edit(
    @proj.TreeEditOp::CommitEdit(node_id=id, new_value="λz.z"),
  )
  inspect(result, content="Ok(())")
  match editor.get_proj_node() {
    Some(p) => inspect(@ast.print_term(p.kind), content="(λz. z)")
    None => abort("Expected ProjNode")
  }
  inspect(editor.get_text(), content="(λz. z)")
}

///|
test "apply_tree_edit - sequential edits" {
  let editor = setup_bridge("42")
  // First: wrap in lambda
  let id1 = get_root_id(editor)
  let result1 = editor.apply_tree_edit(
    @proj.TreeEditOp::WrapInLambda(node_id=id1, var_name="x"),
  )
  inspect(result1, content="Ok(())")
  inspect(editor.get_text(), content="(λx. 42)")
  // Second: wrap the whole thing in an application
  let id2 = get_root_id(editor)
  let result2 = editor.apply_tree_edit(
    @proj.TreeEditOp::WrapInApp(node_id=id2),
  )
  inspect(result2, content="Ok(())")
  inspect(editor.get_text(), content="((λx. 42) a)")
  // Verify convergence
  match editor.get_proj_node() {
    Some(p) => inspect(@ast.print_term(p.kind), content="((λx. 42) a)")
    None => abort("Expected ProjNode")
  }
}
```

- [ ] **Step 3: Run tests**

Run: `moon check && moon test -p editor`
Expected: All pass

- [ ] **Step 4: Format and update interfaces**

Run: `moon info && moon fmt`

- [ ] **Step 5: Commit**

```bash
git add editor/tree_edit_bridge.mbt editor/tree_edit_bridge_test.mbt editor/pkg.generated.mbti
git commit -m "feat: apply_tree_edit uses internal Memos, no CanonicalModel parameter"
```

---

### Task 9: Update TreeEditorState API

**Files:**
- Modify: `projection/tree_editor.mbt:155-246`
- Modify: `projection/tree_editor_wbtest.mbt`

- [ ] **Step 1: Add new from_projection and refresh methods**

In `projection/tree_editor.mbt`, add after `refresh_from_model`:

```moonbit
///|
/// Create tree editor state from a ProjNode and SourceMap.
pub fn TreeEditorState::from_projection(
  proj : ProjNode?,
  source_map : SourceMap,
) -> TreeEditorState {
  let collapsed_nodes : @immut/hashset.HashSet[NodeId] = @immut/hashset.new()
  let tree = match proj {
    Some(ast) =>
      Some(
        InteractiveTreeNode::from_term_node_with_state(
          ast,
          source_map,
          collapsed_nodes,
        ),
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
  }
}

///|
/// Refresh tree from projection data while preserving UI state.
pub fn TreeEditorState::refresh(
  self : TreeEditorState,
  proj : ProjNode?,
  source_map : SourceMap,
) -> TreeEditorState {
  match proj {
    Some(ast) => {
      let valid_ids = collect_all_ids_from_ast(ast)
      let collapsed_nodes = self.collapsed_nodes.intersection(valid_ids)
      let selection = self.selection.filter(fn(id) { valid_ids.contains(id) })
      let editing_node = match self.editing_node {
        Some(id) => if valid_ids.contains(id) { Some(id) } else { None }
        None => None
      }
      let edit_value = if editing_node is None && self.editing_node is Some(_) {
        ""
      } else {
        self.edit_value
      }
      let dragging = match self.dragging {
        Some(id) => if valid_ids.contains(id) { Some(id) } else { None }
        None => None
      }
      let drop_target = match self.drop_target {
        Some(id) => if valid_ids.contains(id) { Some(id) } else { None }
        None => None
      }
      let drop_position = if drop_target is None {
        None
      } else {
        self.drop_position
      }
      let selection_set = @immut/hashset.from_iter(selection.iter())
      let ui_state : TreeUIState = {
        collapsed_nodes,
        selection: selection_set,
        editing_node,
        drop_target,
      }
      let tree = Some(from_term_node_with_full_state(ast, source_map, ui_state))
      {
        tree,
        selection,
        editing_node,
        edit_value,
        dragging,
        drop_target,
        drop_position,
        collapsed_nodes,
      }
    }
    None => { ..self, tree: None }
  }
}
```

- [ ] **Step 2: Update tree_editor_wbtest.mbt to use from_projection**

Replace all `TreeEditorState::from_model(model)` calls with:
```moonbit
TreeEditorState::from_projection(model.get_ast(), model.get_source_map())
```

And `state.refresh_from_model(model)` with:
```moonbit
state.refresh(model.get_ast(), model.get_source_map())
```

(Keep CanonicalModel in tests for now — it still exists. The old methods remain temporarily.)

- [ ] **Step 3: Run tests**

Run: `moon check && moon test -p projection`
Expected: All pass

- [ ] **Step 4: Format and update interfaces**

Run: `moon info && moon fmt`

- [ ] **Step 5: Commit**

```bash
git add projection/tree_editor.mbt projection/tree_editor_wbtest.mbt projection/pkg.generated.mbti
git commit -m "feat: add TreeEditorState::from_projection and refresh methods"
```

---

## Chunk 6: Caller Migration & Cleanup

> **Dependency:** Requires all previous chunks (1-5) to be completed first. Task 11 specifically depends on Task 3 (reconcile_ast refactored) so that `text_lens.mbt` no longer references CanonicalModel.

### Task 10: Update Rabbita example

**Files:**
- Modify: `examples/rabbita/main/main.mbt`

- [ ] **Step 1: Remove CanonicalModel from Model struct**

In `main.mbt`, remove `canonical : @proj.CanonicalModel` from the `Model` struct.

- [ ] **Step 2: Update init_model**

Remove `CanonicalModel::new()` and `text_lens_put` calls. Use `editor.set_text(init_text)` only. Create TreeEditorState from editor's projection:

```moonbit
let tree_state = @proj.TreeEditorState::from_projection(
  editor.get_proj_node(),
  editor.get_source_map(),
)
```

- [ ] **Step 3: Update TextInput handler**

Remove `text_lens_put(model.canonical, new_text)`. Replace `refresh_from_model(model.canonical)` with:
```moonbit
let tree_state = model.tree_state.refresh(
  model.editor.get_proj_node(),
  model.editor.get_source_map(),
)
```

- [ ] **Step 4: Update TreeEdited handler**

Replace `model.editor.apply_tree_edit(model.canonical, op)` with:
```moonbit
model.editor.apply_tree_edit(op)
```

Update tree_state refresh similarly.

- [ ] **Step 5: Update the `refresh()` helper function**

The `refresh()` function (around line 95-100) uses `model.canonical` for tree state refresh. Update:
```moonbit
fn refresh(model : Model) -> Model {
  let text_view = model.editor.get_text()
  let tree_state = model.tree_state.refresh(
    model.editor.get_proj_node(),
    model.editor.get_source_map(),
  )
  { ..model, text_view, tree_state }
}
```

- [ ] **Step 6: Update diagnostics**

Replace `model.canonical.get_errors()` with `model.editor.get_errors()`.

- [ ] **Step 7: Remove all remaining `model.canonical` references**

Search for any remaining `model.canonical` references and remove/replace them.

- [ ] **Step 8: Run the Rabbita example**

Run: `moon check && moon test`
Expected: Compiles and tests pass

- [ ] **Step 9: Commit**

```bash
git add examples/rabbita/main/main.mbt
git commit -m "refactor: Rabbita uses SyncEditor projection accessors, no CanonicalModel"
```

---

### Task 11: Delete CanonicalModel and related files

**Files:**
- Delete: `projection/canonical_model.mbt`
- Delete: `projection/canonical_model_wbtest.mbt`
- Delete: `projection/lens.mbt`
- Modify: `projection/text_lens.mbt` (remove text_lens_put, text_lens_get, text_lens, text_lens_with_diff, text_lens_diff)
- Modify: `projection/tree_lens.mbt` (remove tree_lens_get, tree_lens_put, tree_lens, tree_lens_apply_edit)
- Modify: `projection/tree_editor.mbt` (remove from_model, refresh_from_model)
- Modify: `projection/types.mbt` (remove ProjectionId, ModelOperation, LeafValue if unused)
- Modify: `projection/lens_test.mbt` (remove CanonicalModel-dependent tests)
- Modify: `projection/text_lens_regression_wbtest.mbt` (update to functional API)

- [ ] **Step 1: Delete canonical_model.mbt and canonical_model_wbtest.mbt**

```bash
rm projection/canonical_model.mbt projection/canonical_model_wbtest.mbt
```

- [ ] **Step 2: Delete lens.mbt**

```bash
rm projection/lens.mbt
```

- [ ] **Step 3: Remove old CanonicalModel-based functions from text_lens.mbt**

Remove `text_lens()`, `text_lens_with_diff()`, `text_lens_get()`, `text_lens_put()`, `text_lens_diff()` — the functions that take CanonicalModel.

Keep: `reconcile_ast` (pub), `reconcile_children`, `assign_fresh_ids` (pub), and helper functions.

- [ ] **Step 4: Remove old CanonicalModel-based functions from tree_lens.mbt**

Remove `tree_lens()`, `tree_lens_get()`, `tree_lens_put()`, `tree_lens_apply_edit()`.

Keep: `apply_edit_to_proj` (pub), helper functions (`update_node_in_tree`, `remove_child_at`, etc.), `TreeEditOp` enum.

- [ ] **Step 5: Remove from_model and refresh_from_model from tree_editor.mbt**

Remove the old methods that take CanonicalModel. Keep `from_projection` and `refresh`.

- [ ] **Step 6: Clean up types.mbt and ProjectionEdit**

Remove `ProjectionId` (only used by CanonicalModel's dirty_projections).
Remove `ModelOperation` (only used by CanonicalModel's apply_operation).
Remove `LeafValue` (only used by ModelOperation::UpdateLeaf).
Check if `ProjectionEdit` (used by `text_lens_diff`) has remaining consumers — if not, remove it too.
Keep: `NodeId`, `DropPosition`, `ValidationLevel`.

- [ ] **Step 7: Update lens_test.mbt**

Remove tests that depend on CanonicalModel or Lens types. Keep tests for SourceMap, functional APIs.

- [ ] **Step 8: Update text_lens_regression_wbtest.mbt**

Replace CanonicalModel usage with direct `reconcile_ast` calls:
```moonbit
test "regression - reconcile preserves IDs on value change" {
  let (old, _) = parse_to_proj_node("42")
  let (new_ast, _) = parse_to_proj_node("99")
  let counter : Ref[Int] = Ref::new(100)
  let reconciled = reconcile_ast(old, new_ast, counter)
  // Root node ID should be preserved
  inspect(reconciled.node_id == old.node_id, content="true")
}
```

- [ ] **Step 9: Remove CanonicalModel from editor imports if needed**

Check if `editor/tree_edit_bridge.mbt` still references `@proj.CanonicalModel`. It should not after Task 8.

- [ ] **Step 10: Run all tests**

Run: `moon check && moon test`
Expected: All pass

- [ ] **Step 11: Format and update interfaces**

Run: `moon info && moon fmt`

- [ ] **Step 12: Commit**

```bash
git add -A projection/ editor/
git commit -m "refactor: delete CanonicalModel, Lens types, and CanonicalModel-based APIs"
```

---

### Task 12: Update design docs

**Files:**
- Modify: `docs/design/GRAND_DESIGN.md`
- Modify: `docs/design/03-unified-editor.md`
- Modify: `docs/design/05-tree-edit-roundtrip.md`
- Modify: `docs/TODO.md`

- [ ] **Step 1: Update GRAND_DESIGN.md**

- Move `CanonicalModel` to "Retired" table
- Update §3 status to "Phase 2 done"
- Update §5 status to "Done"
- Update "Still to build" table

- [ ] **Step 2: Update 03-unified-editor.md**

- Mark Phase 2 as complete
- Update SyncEditor struct to show Memo fields
- Remove "CanonicalModel -> Derived Computation" section (it's done)

- [ ] **Step 3: Update 05-tree-edit-roundtrip.md**

- Mark as complete
- Update `apply_tree_edit` signature
- Remove "needs §3 Memo integration" notes

- [ ] **Step 4: Update TODO.md**

- Mark §6 items about dual-state and double parse as resolved
- Update status for encapsulating CanonicalModel

- [ ] **Step 5: Commit**

```bash
git add docs/
git commit -m "docs: update design docs — CanonicalModel retired, §3 Phase 2 complete"
```
