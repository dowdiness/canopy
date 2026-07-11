**Status:** Complete

# Structural Editing Actions — MoonBit Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement 16 structural editing actions in the MoonBit projection/ and editor/ packages, with context-sensitive action filtering, scope analysis, and post-edit cursor positioning.

**Architecture:** Each action is a `TreeEditOp` variant handled by `compute_text_edit` (projection/text_edit.mbt) which produces `SpanEdit[]` + `FocusHint`. The bridge (editor/tree_edit_bridge.mbt) applies edits through the text CRDT. New utilities for free-variable analysis and scope resolution live in projection/. JSON parsing in editor/ enables the web FFI.

**Tech Stack:** MoonBit, moon test (snapshot-based via `inspect`), whitebox tests (`*_wbtest.mbt`)

**Spec:** `docs/plans/2026-03-21-structural-editing-actions-design.md`

**Scope:** MoonBit backend only. TypeScript UI (which-key overlay, action sheet, keybindings) is a separate plan.

### Implementation Notes (from plan review)

These issues apply across multiple tasks — implementers must keep them in mind:

1. **`@immut/hashset` API:** Use `@immut/hashset.HashSet[String]` (not `.T[String]`). Verify `union()` exists — if not, use a `hashset_union` helper that iterates `.each()` with `.add()`. Use `@immut/hashset.new().add("x")` instead of `@immut/hashset.new().add("x")`.
2. **`@ast.print_term` wraps in parentheses:** `Bop`, `App`, `Lam`, `If` print with surrounding `()`. All test expectations must account for this (e.g., `SwapChildren` on `"1 + 2"` produces `"(2 + 1)"`, not `"2 + 1"`). `MoveCursor` placeholder positions must be computed from the actual wrapped output string, not estimated.
3. **`FlatProj::from_proj_node` vs `to_flat_proj`:** `from_proj_node` stores `init_child.start` (init expression start) as the 3rd tuple element, while `to_flat_proj` stores `child.start()` (LetDef syntax node start = `let` keyword). Tests using `from_proj_node` will have wrong `def.2` values for DeleteBinding/DuplicateBinding/MoveBinding. Use position-based range computation from SourceMap instead, or construct FlatProj via `to_flat_proj` in tests.
4. **Token spans for Rename:** `parse_to_proj_node` does NOT populate SourceMap token_spans. Rename tests must parse the CST/syntax tree separately and call `source_map.collect_token_spans_source_file(syntax_root, proj_root)` or equivalent. See `projection/source_map_token_spans_wbtest.mbt` for the pattern.
5. **Incremental compilation:** Each new `TreeEditOp` variant (Tasks 6-14) makes `TreeEditorState::apply_edit` non-exhaustive. Add a wildcard `_ => self` catch-all to `apply_edit` in Task 6, then replace it with proper handling in Task 16.
6. **Action filtering exclusions:** Bop nodes should NOT get `wrap_bop` (no self-wrapping). If nodes should NOT get `wrap_if`. The `add_wrap_actions` helper must be split into per-kind wrap lists.
7. **`find_usages` shadowing bug:** After breaking the def loop due to a later def shadowing the name, body search must also be suppressed. Track a `shadowed` flag.

---

## File Map

| File | Responsibility | Action |
|------|----------------|--------|
| `projection/types.mbt` | FocusHint enum | Modify |
| `projection/text_edit.mbt` | compute_text_edit — return type change + new action cases | Modify |
| `projection/text_edit_wbtest.mbt` | Whitebox tests for compute_text_edit | Modify |
| `projection/tree_lens.mbt` | TreeEditOp enum — new variants | Modify |
| `projection/free_vars.mbt` | free_vars(term, env) utility | Create |
| `projection/free_vars_wbtest.mbt` | Whitebox tests for free_vars | Create |
| `projection/scope.mbt` | resolve_binder, find_usages, collect_lam_env | Create |
| `projection/scope_wbtest.mbt` | Whitebox tests for scope utilities | Create |
| `projection/actions.mbt` | get_actions_for_node, NodeContext, Action, ActionGroup | Create |
| `projection/actions_wbtest.mbt` | Whitebox tests for action filtering | Create |
| `projection/tree_editor.mbt` | TreeEditorState::apply_edit — new variant handling | Modify |
| `projection/tree_editor_wbtest.mbt` | Whitebox tests for tree editor state | Modify |
| `editor/tree_edit_bridge.mbt` | apply_tree_edit — FocusHint cursor remapping | Modify |
| `editor/tree_edit_json.mbt` | parse_tree_edit_op — new JSON variants | Modify |
| `editor/tree_edit_bridge_test.mbt` | Integration tests | Modify |

---

### Task 1: FocusHint Type + compute_text_edit Signature

**Files:**
- Modify: `projection/types.mbt`
- Modify: `projection/text_edit.mbt`
- Modify: `projection/text_edit_wbtest.mbt`

- [ ] **Step 1: Add FocusHint enum to types.mbt**

Add after the `DropPosition` enum:

```moonbit
///|
/// Hint for where to place the cursor after a structural edit.
pub(all) enum FocusHint {
  RestoreCursor
  MoveCursor(position~ : Int)
} derive(Show, Eq)
```

- [ ] **Step 2: Update compute_text_edit return type**

In `projection/text_edit.mbt`, change the signature from:

```moonbit
pub fn compute_text_edit(...) -> Result[Array[SpanEdit]?, String]
```

to:

```moonbit
pub fn compute_text_edit(...) -> Result[(Array[SpanEdit], FocusHint)?, String]
```

Update every existing return path:
- `Ok(Some([]))` → `Ok(Some(([], RestoreCursor)))`
- `Ok(Some([edit]))` → `Ok(Some(([edit], RestoreCursor)))`
- `Ok(Some([edit1, edit2]))` → `Ok(Some(([edit1, edit2], RestoreCursor)))`

- [ ] **Step 3: Update all existing tests**

In `projection/text_edit_wbtest.mbt`, update every test that pattern-matches on `Ok(Some(edits))` to `Ok(Some((edits, _)))`. The `_` discards FocusHint since existing ops all use `RestoreCursor`.

- [ ] **Step 4: Run tests to verify backward compatibility**

Run: `moon test -p dowdiness/crdt/projection`
Expected: All existing tests pass.

- [ ] **Step 5: Commit**

```bash
git add projection/types.mbt projection/text_edit.mbt projection/text_edit_wbtest.mbt
git commit -m "feat(projection): add FocusHint type, update compute_text_edit signature"
```

---

### Task 2: Update apply_tree_edit to Use FocusHint

**Files:**
- Modify: `editor/tree_edit_bridge.mbt`

- [ ] **Step 1: Update apply_tree_edit to destructure FocusHint**

Replace the match body in `SyncEditor::apply_tree_edit`:

```moonbit
match @proj.compute_text_edit(op, old_text, source_map, registry, flat_proj) {
  Ok(Some((edits, focus_hint))) => {
    if edits.is_empty() {
      return Ok(())
    }
    edits.sort_by((a, b) => b.start.compare(a.start))
    for edit in edits {
      self.apply_text_edit_internal(
        edit.start,
        edit.delete_len,
        edit.inserted,
        timestamp_ms,
        true,
        false,
      )
    }
    match focus_hint {
      @proj.FocusHint::RestoreCursor => self.move_cursor(old_cursor)
      @proj.FocusHint::MoveCursor(position~) => {
        let mut adjusted = position
        for edit in edits {
          if edit.start <= position {
            if position < edit.start + edit.delete_len {
              adjusted = edit.start
            } else {
              adjusted = adjusted + edit.inserted.length() - edit.delete_len
            }
          }
        }
        self.move_cursor(adjusted)
      }
    }
    Ok(())
  }
  Ok(None) => Err("Unhandled tree edit op: " + op.to_string())
  Err(msg) => Err(msg)
}
```

- [ ] **Step 2: Run tests**

Run: `moon test -p dowdiness/crdt/editor`
Expected: All existing tests pass (all existing ops return `RestoreCursor`).

- [ ] **Step 3: Commit**

```bash
git add editor/tree_edit_bridge.mbt
git commit -m "feat(editor): apply_tree_edit uses FocusHint for cursor positioning"
```

---

### Task 3: Free Variable Analysis

**Files:**
- Create: `projection/free_vars.mbt`
- Create: `projection/free_vars_wbtest.mbt`

- [ ] **Step 1: Write tests for free_vars**

Create `projection/free_vars_wbtest.mbt`:

```moonbit
///|
test "free_vars: Var free when not in env" {
  let result = free_vars(@ast.Term::Var("x"), @immut/hashset.new())
  inspect(result.contains("x"), content="true")
}

///|
test "free_vars: Var bound when in env" {
  let env = @immut/hashset.new().add("x")
  let result = free_vars(@ast.Term::Var("x"), env)
  inspect(result.contains("x"), content="false")
}

///|
test "free_vars: Lam binds param" {
  // λx. x — x is bound, no free vars
  let term = @ast.Term::Lam("x", @ast.Term::Var("x"))
  let result = free_vars(term, @immut/hashset.new())
  inspect(result.size(), content="0")
}

///|
test "free_vars: Lam body references outer" {
  // λx. y — y is free
  let term = @ast.Term::Lam("x", @ast.Term::Var("y"))
  let result = free_vars(term, @immut/hashset.new())
  inspect(result.contains("y"), content="true")
  inspect(result.contains("x"), content="false")
}

///|
test "free_vars: Bop collects from both sides" {
  // x + y — both free
  let term = @ast.Term::Bop(@ast.Bop::Plus, @ast.Term::Var("x"), @ast.Term::Var("y"))
  let result = free_vars(term, @immut/hashset.new())
  inspect(result.contains("x"), content="true")
  inspect(result.contains("y"), content="true")
}

///|
test "free_vars: nested Lam shadowing" {
  // λx. λx. x — inner x shadows outer, no free vars
  let term = @ast.Term::Lam("x", @ast.Term::Lam("x", @ast.Term::Var("x")))
  let result = free_vars(term, @immut/hashset.new())
  inspect(result.size(), content="0")
}

///|
test "free_vars: Int has no free vars" {
  let result = free_vars(@ast.Term::Int(42), @immut/hashset.new())
  inspect(result.size(), content="0")
}

///|
test "free_vars: Module sequential scoping" {
  // let x = y; let z = x; x + z
  // y is free, x and z are bound by their let-defs
  let term = @ast.Term::Module(
    [
      ("x", @ast.Term::Var("y")),
      ("z", @ast.Term::Var("x")),
    ],
    @ast.Term::Bop(@ast.Bop::Plus, @ast.Term::Var("x"), @ast.Term::Var("z")),
  )
  let result = free_vars(term, @immut/hashset.new())
  inspect(result.contains("y"), content="true")
  inspect(result.contains("x"), content="false")
  inspect(result.contains("z"), content="false")
}

///|
test "free_vars: Module def not in scope for own init" {
  // let x = x — x in init is free (x not yet in scope)
  let term = @ast.Term::Module(
    [("x", @ast.Term::Var("x"))],
    @ast.Term::Unit,
  )
  let result = free_vars(term, @immut/hashset.new())
  inspect(result.contains("x"), content="true")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/crdt/projection -f free_vars_wbtest.mbt`
Expected: FAIL — `free_vars` not defined.

- [ ] **Step 3: Implement free_vars**

Create `projection/free_vars.mbt`:

```moonbit
///|
/// Compute the set of free variables in a Term, given a set of bound names.
/// Follows sequential scoping for Module bindings (matching resolve.mbt).
pub fn free_vars(
  term : @ast.Term,
  env : @immut/hashset.HashSet[String],
) -> @immut/hashset.HashSet[String] {
  match term {
    @ast.Term::Var(x) =>
      if env.contains(x) {
        @immut/hashset.new()
      } else {
        @immut/hashset.of([x])
      }
    @ast.Term::Lam(x, body) => free_vars(body, env.add(x))
    @ast.Term::App(f, a) => free_vars(f, env).union(free_vars(a, env))
    @ast.Term::Bop(_, l, r) => free_vars(l, env).union(free_vars(r, env))
    @ast.Term::If(c, t, e) =>
      free_vars(c, env).union(free_vars(t, env)).union(free_vars(e, env))
    @ast.Term::Module(defs, body) => {
      let mut result : @immut/hashset.HashSet[String] = @immut/hashset.new()
      let mut cur_env = env
      for def in defs {
        result = result.union(free_vars(def.1, cur_env))
        cur_env = cur_env.add(def.0)
      }
      result = result.union(free_vars(body, cur_env))
      result
    }
    _ => @immut/hashset.new() // Int, Unit, Error, Unbound
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/crdt/projection -f free_vars_wbtest.mbt`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add projection/free_vars.mbt projection/free_vars_wbtest.mbt
git commit -m "feat(projection): add free_vars utility for scope analysis"
```

---

### Task 4: Scope Resolution Utilities

**Files:**
- Create: `projection/scope.mbt`
- Create: `projection/scope_wbtest.mbt`

- [ ] **Step 1: Write tests for scope utilities**

Create `projection/scope_wbtest.mbt`:

```moonbit
///|
test "resolve_binder: Var bound by Module let-def" {
  // let x = 0\nx
  let text = "let x = 0\nx"
  let (proj, _) = parse_to_proj_node(text)
  let fp = FlatProj::from_proj_node(proj)
  let source_map = SourceMap::from_ast(proj)
  let registry = scope_test_registry(proj)
  // Find the body Var("x") node
  let body_id = proj.children[proj.children.length() - 1].id()
  match resolve_binder(body_id, "x", fp, registry, source_map) {
    Some(ModuleBinder(_, def_index~)) => inspect(def_index, content="0")
    _ => fail("expected ModuleBinder")
  }
}

///|
test "resolve_binder: Var bound by Lam" {
  // λx. x
  let text = "λx. x"
  let (proj, _) = parse_to_proj_node(text)
  let fp = FlatProj::from_proj_node(proj)
  let source_map = SourceMap::from_ast(proj)
  let registry = scope_test_registry(proj)
  // body is Var("x"), child of Lam
  let var_node = proj.children[0]
  match resolve_binder(var_node.id(), "x", fp, registry, source_map) {
    Some(LamBinder(lam_id~)) => inspect(lam_id == proj.id(), content="true")
    _ => fail("expected LamBinder")
  }
}

///|
test "find_usages: finds Var references in Module body" {
  // let x = 0\nx + x
  let text = "let x = 0\nx + x"
  let (proj, _) = parse_to_proj_node(text)
  let fp = FlatProj::from_proj_node(proj)
  let registry = scope_test_registry(proj)
  let usages = find_usages("x", 0, fp, registry)
  inspect(usages.length(), content="2")
}

///|
test "find_usages: respects shadowing by inner Lam" {
  // let x = 0\nλx. x
  let text = "let x = 0\nλx. x"
  let (proj, _) = parse_to_proj_node(text)
  let fp = FlatProj::from_proj_node(proj)
  let registry = scope_test_registry(proj)
  // x inside λx. x is bound by the Lam, not the Module def
  let usages = find_usages("x", 0, fp, registry)
  inspect(usages.length(), content="0")
}

///|
fn scope_test_registry(root : ProjNode) -> Map[NodeId, ProjNode] {
  let registry : Map[NodeId, ProjNode] = {}
  fn register(node : ProjNode) {
    registry[node.id()] = node
    for child in node.children {
      register(child)
    }
  }
  register(root)
  registry
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/crdt/projection -f scope_wbtest.mbt`
Expected: FAIL — functions not defined.

- [ ] **Step 3: Implement scope utilities**

Create `projection/scope.mbt`:

```moonbit
///|
/// The kind of binding site a variable resolves to.
pub(all) enum BindingSite {
  LamBinder(lam_id~ : NodeId)
  ModuleBinder(binding_node_id~ : NodeId, def_index~ : Int)
} derive(Show, Eq)

///|
/// Resolve which binding site a Var node refers to.
/// Walks up from the Var's position to find the nearest Lam or Module def.
pub fn resolve_binder(
  var_node_id : NodeId,
  var_name : String,
  flat_proj : FlatProj,
  registry : Map[NodeId, ProjNode],
  source_map : SourceMap,
) -> BindingSite? {
  // Check if it's inside a Lam that binds this name (walk up)
  let lam_binder = find_enclosing_lam_binder(
    var_node_id, var_name, registry,
  )
  if lam_binder is Some(_) {
    return lam_binder
  }
  // Check Module defs — find which def/body contains this var
  let var_range = source_map.get_range(var_node_id)
  let var_pos = match var_range {
    Some(r) => r.start
    None => return None
  }
  // Find which def index (or body) this var is in
  let mut containing_def_index = flat_proj.defs.length() // body
  for i, def in flat_proj.defs {
    let init_range = source_map.get_range(def.1.id())
    match init_range {
      Some(r) =>
        if var_pos >= r.start && var_pos < r.end {
          containing_def_index = i
          break
        }
      None => ()
    }
  }
  // Walk backwards from containing_def_index to find matching def
  // (sequential scope: def i is in scope for defs i+1..n and body)
  let search_end = if containing_def_index < flat_proj.defs.length() {
    containing_def_index
  } else {
    flat_proj.defs.length()
  }
  for i = search_end - 1; i >= 0; i = i - 1 {
    if flat_proj.defs[i].0 == var_name {
      return Some(ModuleBinder(binding_node_id=flat_proj.defs[i].3, def_index=i))
    }
  }
  None
}

///|
/// Walk up the tree to find an enclosing Lam that binds the given name.
fn find_enclosing_lam_binder(
  node_id : NodeId,
  name : String,
  registry : Map[NodeId, ProjNode],
) -> BindingSite? {
  // Find parent of node_id
  for pid, pnode in registry {
    for child in pnode.children {
      if NodeId(child.node_id) == node_id {
        match pnode.kind {
          @ast.Term::Lam(param, _) =>
            if param == name {
              return Some(LamBinder(lam_id=pid))
            } else {
              return find_enclosing_lam_binder(pid, name, registry)
            }
          _ => return find_enclosing_lam_binder(pid, name, registry)
        }
      }
    }
  }
  None
}

///|
/// Find all Var nodes that reference the given name from scope_start_index onward
/// in the Module defs + body, respecting shadowing by later defs or inner Lam params.
pub fn find_usages(
  var_name : String,
  scope_start_index : Int,
  flat_proj : FlatProj,
  registry : Map[NodeId, ProjNode],
) -> Array[NodeId] {
  let results : Array[NodeId] = []
  let mut shadowed = false
  // Check defs from scope_start_index onward
  for i = scope_start_index; i < flat_proj.defs.length(); i = i + 1 {
    let def = flat_proj.defs[i]
    // If this def shadows the name, stop looking in subsequent defs and body
    if def.0 == var_name && i > scope_start_index {
      shadowed = true
      break
    }
    collect_var_usages(def.1, var_name, results)
  }
  // Check body only if name was not shadowed by a later def
  if not(shadowed) {
    match flat_proj.final_expr {
      Some(body) => collect_var_usages(body, var_name, results)
      None => ()
    }
  }
  results
}

///|
/// Recursively collect Var nodes matching the given name, stopping at shadowing Lam params.
fn collect_var_usages(
  node : ProjNode,
  name : String,
  results : Array[NodeId],
) -> Unit {
  match node.kind {
    @ast.Term::Var(x) =>
      if x == name {
        results.push(node.id())
      }
    @ast.Term::Lam(param, _) =>
      // If Lam shadows the name, don't recurse into body
      if param != name {
        for child in node.children {
          collect_var_usages(child, name, results)
        }
      }
    _ =>
      for child in node.children {
        collect_var_usages(child, name, results)
      }
  }
}

///|
/// Collect Lam parameter names in scope at a node position (walking up the tree).
pub fn collect_lam_env(
  node_id : NodeId,
  registry : Map[NodeId, ProjNode],
) -> @immut/hashset.HashSet[String] {
  let mut env : @immut/hashset.HashSet[String] = @immut/hashset.new()
  fn walk_up(nid : NodeId) {
    for pid, pnode in registry {
      for child in pnode.children {
        if NodeId(child.node_id) == nid {
          match pnode.kind {
            @ast.Term::Lam(param, _) => env = env.add(param)
            _ => ()
          }
          walk_up(pid)
          return
        }
      }
    }
  }
  walk_up(node_id)
  env
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/crdt/projection -f scope_wbtest.mbt`
Expected: All PASS.

- [ ] **Step 5: Run full projection test suite**

Run: `moon test -p dowdiness/crdt/projection`
Expected: All PASS.

- [ ] **Step 6: Commit**

```bash
git add projection/scope.mbt projection/scope_wbtest.mbt
git commit -m "feat(projection): add scope resolution utilities (resolve_binder, find_usages)"
```

---

### Task 5: Action Filtering (get_actions_for_node)

**Files:**
- Create: `projection/actions.mbt`
- Create: `projection/actions_wbtest.mbt`

- [ ] **Step 1: Write tests for action filtering**

Create `projection/actions_wbtest.mbt`:

```moonbit
///|
test "actions for Int node" {
  let ctx = NodeContext::new()
  let actions = get_actions_for_node(@ast.Term::Int(0), ctx)
  let ids = actions.map(fn(a) { a.id })
  inspect(ids.contains("extract_to_let"), content="true")
  inspect(ids.contains("delete"), content="true")
  inspect(ids.contains("wrap_lambda"), content="true")
  inspect(ids.contains("wrap_if"), content="true")
  inspect(ids.contains("wrap_bop"), content="true")
  inspect(ids.contains("wrap_app"), content="true")
  // Should NOT have inline, rename, unwrap, swap, change_op
  inspect(ids.contains("inline"), content="false")
  inspect(ids.contains("rename"), content="false")
  inspect(ids.contains("unwrap"), content="false")
}

///|
test "actions for Var node" {
  let ctx = NodeContext::new()
  let actions = get_actions_for_node(@ast.Term::Var("x"), ctx)
  let ids = actions.map(fn(a) { a.id })
  inspect(ids.contains("inline"), content="true")
  inspect(ids.contains("rename"), content="true")
}

///|
test "actions for Bop node" {
  let ctx = NodeContext::new()
  let actions = get_actions_for_node(
    @ast.Term::Bop(@ast.Bop::Plus, @ast.Term::Int(0), @ast.Term::Int(0)),
    ctx,
  )
  let ids = actions.map(fn(a) { a.id })
  inspect(ids.contains("swap"), content="true")
  inspect(ids.contains("change_op"), content="true")
  inspect(ids.contains("unwrap"), content="true")
}

///|
test "actions for Error node — only delete" {
  let ctx = NodeContext::new()
  let actions = get_actions_for_node(@ast.Term::Error("bad"), ctx)
  let ids = actions.map(fn(a) { a.id })
  inspect(ids.length(), content="1")
  inspect(ids[0], content="delete")
}

///|
test "binding context adds binding actions" {
  let ctx = NodeContext::new_binding(
    binding_node_id=NodeId(99), binding_def_index=0, module_node_id=NodeId(1),
  )
  let actions = get_actions_for_node(@ast.Term::Int(0), ctx)
  let ids = actions.map(fn(a) { a.id })
  // Should have both expression actions and binding actions
  inspect(ids.contains("extract_to_let"), content="true")
  inspect(ids.contains("binding_rename"), content="true")
  inspect(ids.contains("binding_duplicate"), content="true")
  inspect(ids.contains("binding_delete"), content="true")
  inspect(ids.contains("binding_inline_all"), content="true")
  inspect(ids.contains("binding_move_up"), content="true")
  inspect(ids.contains("binding_move_down"), content="true")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/crdt/projection -f actions_wbtest.mbt`
Expected: FAIL.

- [ ] **Step 3: Implement action filtering**

Create `projection/actions.mbt`:

```moonbit
///|
pub(all) enum ActionGroup {
  Core
  Wrap
  Binding
  Module
} derive(Show, Eq)

///|
pub(all) struct Action {
  id : String
  label : String
  mnemonic : Char
  group : ActionGroup
  needs_input : Bool
} derive(Show, Eq)

///|
pub(all) struct NodeContext {
  is_let_binding : Bool
  binding_node_id : NodeId?
  binding_def_index : Int?
  module_node_id : NodeId?
} derive(Show, Eq)

///|
pub fn NodeContext::new() -> NodeContext {
  {
    is_let_binding: false,
    binding_node_id: None,
    binding_def_index: None,
    module_node_id: None,
  }
}

///|
pub fn NodeContext::new_binding(
  binding_node_id~ : NodeId,
  binding_def_index~ : Int,
  module_node_id~ : NodeId,
) -> NodeContext {
  {
    is_let_binding: true,
    binding_node_id: Some(binding_node_id),
    binding_def_index: Some(binding_def_index),
    module_node_id: Some(module_node_id),
  }
}

///|
pub fn get_actions_for_node(
  kind : @ast.Term,
  context : NodeContext,
) -> Array[Action] {
  let actions : Array[Action] = []
  // Expression-level actions based on node kind
  match kind {
    @ast.Term::Int(_) => {
      actions.push(action_extract())
      add_wrap_actions(actions)
      actions.push(action_delete())
    }
    @ast.Term::Var(_) => {
      actions.push(action_extract())
      actions.push(action_inline())
      actions.push(action_rename())
      add_wrap_actions(actions)
      actions.push(action_delete())
    }
    @ast.Term::Lam(_, _) => {
      actions.push(action_extract())
      actions.push(action_rename())
      actions.push(action_unwrap())
      add_wrap_actions(actions)
      actions.push(action_delete())
    }
    @ast.Term::App(_, _) => {
      actions.push(action_extract())
      actions.push(action_unwrap())
      add_wrap_actions(actions)
      actions.push(action_delete())
    }
    @ast.Term::Bop(_, _, _) => {
      actions.push(action_extract())
      actions.push(action_unwrap())
      actions.push(action_swap())
      actions.push(action_change_op())
      // No wrap_bop for Bop (no self-wrapping)
      actions.push(action_wrap_lambda())
      actions.push(action_wrap_if())
      actions.push(action_wrap_app())
      actions.push(action_delete())
    }
    @ast.Term::If(_, _, _) => {
      actions.push(action_extract())
      actions.push(action_unwrap())
      actions.push(action_swap())
      // No wrap_if for If (no self-wrapping)
      actions.push(action_wrap_lambda())
      actions.push(action_wrap_bop())
      actions.push(action_wrap_app())
      actions.push(action_delete())
    }
    @ast.Term::Module(_, _) => {
      actions.push(action_add_binding())
    }
    @ast.Term::Unit => {
      add_wrap_actions(actions)
      actions.push(action_delete())
    }
    @ast.Term::Error(_) => {
      actions.push(action_delete())
    }
    @ast.Term::Unbound(_) => {
      actions.push(action_delete())
    }
  }
  // Binding-level actions
  if context.is_let_binding {
    actions.push(
      { id: "binding_rename", label: "Rename binding", mnemonic: 'r', group: Binding, needs_input: true },
    )
    actions.push(
      { id: "binding_duplicate", label: "Duplicate", mnemonic: 'd', group: Binding, needs_input: false },
    )
    actions.push(
      { id: "binding_move_up", label: "Move up", mnemonic: 'k', group: Binding, needs_input: false },
    )
    actions.push(
      { id: "binding_move_down", label: "Move down", mnemonic: 'j', group: Binding, needs_input: false },
    )
    actions.push(
      { id: "binding_inline_all", label: "Inline all", mnemonic: 'i', group: Binding, needs_input: false },
    )
    actions.push(
      { id: "binding_delete", label: "Delete binding", mnemonic: 'x', group: Binding, needs_input: false },
    )
  }
  actions
}

///|
fn add_wrap_actions(actions : Array[Action]) -> Unit {
  actions.push(action_wrap_lambda())
  actions.push(action_wrap_if())
  actions.push(action_wrap_bop())
  actions.push(action_wrap_app())
}

///|
fn action_extract() -> Action {
  { id: "extract_to_let", label: "Extract to let", mnemonic: 'e', group: Core, needs_input: true }
}

///|
fn action_inline() -> Action {
  { id: "inline", label: "Inline", mnemonic: 'i', group: Core, needs_input: false }
}

///|
fn action_rename() -> Action {
  { id: "rename", label: "Rename", mnemonic: 'r', group: Core, needs_input: true }
}

///|
fn action_unwrap() -> Action {
  { id: "unwrap", label: "Unwrap", mnemonic: 'u', group: Core, needs_input: false }
}

///|
fn action_swap() -> Action {
  { id: "swap", label: "Swap", mnemonic: 's', group: Core, needs_input: false }
}

///|
fn action_change_op() -> Action {
  { id: "change_op", label: "Change op", mnemonic: 'c', group: Core, needs_input: false }
}

///|
fn action_delete() -> Action {
  { id: "delete", label: "Delete", mnemonic: 'd', group: Core, needs_input: false }
}

///|
fn action_wrap_lambda() -> Action {
  { id: "wrap_lambda", label: "Wrap λ", mnemonic: 'l', group: Wrap, needs_input: true }
}

///|
fn action_wrap_if() -> Action {
  { id: "wrap_if", label: "Wrap if", mnemonic: 'i', group: Wrap, needs_input: false }
}

///|
fn action_wrap_bop() -> Action {
  { id: "wrap_bop", label: "Wrap +/-", mnemonic: 'b', group: Wrap, needs_input: false }
}

///|
fn action_wrap_app() -> Action {
  { id: "wrap_app", label: "Wrap app", mnemonic: 'a', group: Wrap, needs_input: false }
}

///|
fn action_add_binding() -> Action {
  { id: "add_binding", label: "Add binding", mnemonic: 'a', group: Module, needs_input: false }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `moon test -p dowdiness/crdt/projection -f actions_wbtest.mbt`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add projection/actions.mbt projection/actions_wbtest.mbt
git commit -m "feat(projection): add context-sensitive action filtering"
```

---

### Task 6: Unwrap Action

**Files:**
- Modify: `projection/tree_lens.mbt` (add TreeEditOp variant)
- Modify: `projection/text_edit.mbt` (add compute_text_edit case)
- Modify: `projection/text_edit_wbtest.mbt` (add tests)

- [ ] **Step 1: Add TreeEditOp variant**

In `projection/tree_lens.mbt`, add to the `TreeEditOp` enum:

```moonbit
Unwrap(node_id~ : NodeId, keep_child_index~ : Int)
```

- [ ] **Step 2: Write test**

In `projection/text_edit_wbtest.mbt`:

```moonbit
///|
test "compute_text_edit: Unwrap Lam keeps body" {
  let text = "(λx. 42)"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  // The Lam node is the root
  let lam_id = proj.id()
  let result = compute_text_edit(
    Unwrap(node_id=lam_id, keep_child_index=0),
    text, source_map, registry, fp,
  )
  match result {
    Ok(Some((edits, hint))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="42")
      inspect(hint != FocusHint::RestoreCursor, content="true")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: Unwrap Bop keeps left" {
  let text = "1 + 2"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let bop_id = proj.id()
  let result = compute_text_edit(
    Unwrap(node_id=bop_id, keep_child_index=0),
    text, source_map, registry, fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      inspect(apply_edits(text, edits), content="1")
    }
    _ => fail("expected Some edits")
  }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `moon test -p dowdiness/crdt/projection -f text_edit_wbtest.mbt`
Expected: FAIL on new tests (Unwrap not handled in compute_text_edit).

- [ ] **Step 4: Implement Unwrap in compute_text_edit**

Add case to the match in `projection/text_edit.mbt`:

```moonbit
Unwrap(node_id~, keep_child_index~) =>
  match source_map.get_range(node_id) {
    None => Err("Node not found: " + node_id.to_string())
    Some(range) =>
      match registry.get(node_id) {
        None => Err("Node not in registry")
        Some(node) =>
          if keep_child_index >= node.children.length() {
            Err("Child index out of range")
          } else {
            let kept = node.children[keep_child_index]
            let kept_text = @ast.print_term(kept.kind)
            let kept_range = source_map.get_range(kept.id())
            let focus_pos = match kept_range {
              Some(r) => r.start
              None => range.start
            }
            Ok(Some(([{
              start: range.start,
              delete_len: range.end - range.start,
              inserted: kept_text,
            }], MoveCursor(position=focus_pos))))
          }
      }
  }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `moon test -p dowdiness/crdt/projection -f text_edit_wbtest.mbt`
Expected: All PASS.

- [ ] **Step 6: Commit**

```bash
git add projection/tree_lens.mbt projection/text_edit.mbt projection/text_edit_wbtest.mbt
git commit -m "feat(projection): add Unwrap structural editing action"
```

---

### Task 7: SwapChildren Action

**Files:**
- Modify: `projection/tree_lens.mbt`
- Modify: `projection/text_edit.mbt`
- Modify: `projection/text_edit_wbtest.mbt`

- [ ] **Step 1: Add TreeEditOp variant**

```moonbit
SwapChildren(node_id~ : NodeId)
```

- [ ] **Step 2: Write test**

```moonbit
///|
test "compute_text_edit: SwapChildren on Bop" {
  let text = "1 + 2"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let result = compute_text_edit(
    SwapChildren(node_id=proj.id()),
    text, source_map, registry, fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      // Note: print_term wraps Bop in parens
      inspect(apply_edits(text, edits), content="(2 + 1)")
    }
    _ => fail("expected Some edits")
  }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `moon test -p dowdiness/crdt/projection -f text_edit_wbtest.mbt`

- [ ] **Step 4: Implement SwapChildren**

```moonbit
SwapChildren(node_id~) =>
  match (source_map.get_range(node_id), registry.get(node_id)) {
    (Some(range), Some(node)) => {
      let swapped_kind = match node.kind {
        @ast.Term::Bop(op, l, r) => @ast.Term::Bop(op, r, l)
        @ast.Term::If(c, t, e) => @ast.Term::If(c, e, t)
        _ => return Err("SwapChildren only applies to Bop and If")
      }
      let new_text = @ast.print_term(swapped_kind)
      Ok(Some(([{
        start: range.start,
        delete_len: range.end - range.start,
        inserted: new_text,
      }], RestoreCursor)))
    }
    _ => Err("Node not found")
  }
```

- [ ] **Step 5: Run tests, verify pass**

- [ ] **Step 6: Commit**

```bash
git add projection/tree_lens.mbt projection/text_edit.mbt projection/text_edit_wbtest.mbt
git commit -m "feat(projection): add SwapChildren action"
```

---

### Task 8: WrapInIf Action

**Files:**
- Modify: `projection/tree_lens.mbt`
- Modify: `projection/text_edit.mbt`
- Modify: `projection/text_edit_wbtest.mbt`

- [ ] **Step 1: Add TreeEditOp variant**

```moonbit
WrapInIf(node_id~ : NodeId)
```

- [ ] **Step 2: Write test**

```moonbit
///|
test "compute_text_edit: WrapInIf" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let result = compute_text_edit(
    WrapInIf(node_id=proj.id()),
    text, source_map, registry, fp,
  )
  match result {
    Ok(Some((edits, hint))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="if 0 then 42 else 0")
      // Focus should move to the condition placeholder
      inspect(hint != FocusHint::RestoreCursor, content="true")
    }
    _ => fail("expected Some edits")
  }
}
```

- [ ] **Step 3: Run test to verify it fails**

- [ ] **Step 4: Implement WrapInIf**

```moonbit
WrapInIf(node_id~) =>
  match (source_map.get_range(node_id), registry.get(node_id)) {
    (Some(range), Some(node)) => {
      let existing = @ast.print_term(node.kind)
      let wrapped = "if 0 then " + existing + " else 0"
      Ok(Some(([{
        start: range.start,
        delete_len: range.end - range.start,
        inserted: wrapped,
      }], MoveCursor(position=range.start + 3)))) // "if " = 3 chars, position at condition placeholder
    }
    _ => Err("Node not found")
  }
```

- [ ] **Step 5: Run tests, verify pass**

- [ ] **Step 6: Commit**

```bash
git add projection/tree_lens.mbt projection/text_edit.mbt projection/text_edit_wbtest.mbt
git commit -m "feat(projection): add WrapInIf action"
```

---

### Task 9: WrapInBop + ChangeOperator Actions

**Files:**
- Modify: `projection/tree_lens.mbt`
- Modify: `projection/text_edit.mbt`
- Modify: `projection/text_edit_wbtest.mbt`

- [ ] **Step 1: Add TreeEditOp variants**

```moonbit
WrapInBop(node_id~ : NodeId, op~ : @ast.Bop)
ChangeOperator(node_id~ : NodeId, new_op~ : @ast.Bop)
```

- [ ] **Step 2: Write tests**

```moonbit
///|
test "compute_text_edit: WrapInBop Plus" {
  let text = "42"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let result = compute_text_edit(
    WrapInBop(node_id=proj.id(), op=@ast.Bop::Plus),
    text, source_map, registry, fp,
  )
  match result {
    Ok(Some((edits, _))) => inspect(apply_edits(text, edits), content="(42 + 0)")
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: ChangeOperator Plus to Minus" {
  let text = "1 + 2"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let result = compute_text_edit(
    ChangeOperator(node_id=proj.id(), new_op=@ast.Bop::Minus),
    text, source_map, registry, fp,
  )
  match result {
    Ok(Some((edits, _))) => inspect(apply_edits(text, edits), content="(1 - 2)")
    _ => fail("expected Some edits")
  }
}
```

- [ ] **Step 3: Run tests to verify they fail**

- [ ] **Step 4: Implement both actions**

```moonbit
WrapInBop(node_id~, op~) =>
  match (source_map.get_range(node_id), registry.get(node_id)) {
    (Some(range), Some(node)) => {
      let existing = @ast.print_term(node.kind)
      let wrapped = @ast.print_term(@ast.Term::Bop(op, node.kind, @ast.Term::Int(0)))
      let placeholder_pos = range.start + existing.length() + 3 // "x + " = existing + " op "
      Ok(Some(([{
        start: range.start,
        delete_len: range.end - range.start,
        inserted: wrapped,
      }], MoveCursor(position=placeholder_pos))))
    }
    _ => Err("Node not found")
  }
ChangeOperator(node_id~, new_op~) =>
  match (source_map.get_range(node_id), registry.get(node_id)) {
    (Some(range), Some(node)) => {
      let new_kind = match node.kind {
        @ast.Term::Bop(_, l, r) => @ast.Term::Bop(new_op, l, r)
        _ => return Err("ChangeOperator only applies to Bop")
      }
      let new_text = @ast.print_term(new_kind)
      Ok(Some(([{
        start: range.start,
        delete_len: range.end - range.start,
        inserted: new_text,
      }], RestoreCursor)))
    }
    _ => Err("Node not found")
  }
```

- [ ] **Step 5: Run tests, verify pass**

- [ ] **Step 6: Commit**

```bash
git add projection/tree_lens.mbt projection/text_edit.mbt projection/text_edit_wbtest.mbt
git commit -m "feat(projection): add WrapInBop and ChangeOperator actions"
```

---

### Task 10: DeleteBinding Action

**Files:**
- Modify: `projection/tree_lens.mbt`
- Modify: `projection/text_edit.mbt`
- Modify: `projection/text_edit_wbtest.mbt`

- [ ] **Step 1: Add TreeEditOp variant**

```moonbit
DeleteBinding(binding_node_id~ : NodeId)
```

- [ ] **Step 2: Write test**

```moonbit
///|
test "compute_text_edit: DeleteBinding removes let line" {
  let text = "let x = 0\nlet y = 1\nx + y"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  // Delete first binding (x = 0)
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    DeleteBinding(binding_node_id=binding_id),
    text, source_map, registry, fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let y = 1\nx + y")
    }
    _ => fail("expected Some edits")
  }
}
```

- [ ] **Step 3: Run test to verify it fails**

- [ ] **Step 4: Implement DeleteBinding**

In `compute_text_edit`, find the binding by its NodeId in `flat_proj.defs`, compute the text range for the entire `let name = expr\n` line, and delete it:

```moonbit
DeleteBinding(binding_node_id~) => {
  // Find the def entry by binding NodeId
  let mut found : (Int, String, ProjNode, Int)? = None
  for i, def in flat_proj.defs {
    if def.3 == binding_node_id {
      found = Some((i, def.0, def.1, def.2))
      break
    }
  }
  match found {
    None => Err("Binding not found: " + binding_node_id.to_string())
    Some((def_index, _, _, def_start)) => {
      // Compute end: start of next def, or start of body, or end of text
      let def_end = if def_index + 1 < flat_proj.defs.length() {
        flat_proj.defs[def_index + 1].2 // start of next def
      } else {
        match flat_proj.final_expr {
          Some(body) =>
            match source_map.get_range(body.id()) {
              Some(r) => r.start
              None => source_text.length()
            }
          None => source_text.length()
        }
      }
      Ok(Some(([{
        start: def_start,
        delete_len: def_end - def_start,
        inserted: "",
      }], RestoreCursor)))
    }
  }
}
```

- [ ] **Step 5: Run tests, verify pass**

- [ ] **Step 6: Commit**

```bash
git add projection/tree_lens.mbt projection/text_edit.mbt projection/text_edit_wbtest.mbt
git commit -m "feat(projection): add DeleteBinding action"
```

---

### Task 11: DuplicateBinding + MoveBinding Actions

**Files:**
- Modify: `projection/tree_lens.mbt`
- Modify: `projection/text_edit.mbt`
- Modify: `projection/text_edit_wbtest.mbt`

- [ ] **Step 1: Add TreeEditOp variants**

```moonbit
DuplicateBinding(binding_node_id~ : NodeId)
MoveBindingUp(binding_node_id~ : NodeId)
MoveBindingDown(binding_node_id~ : NodeId)
AddBinding(module_node_id~ : NodeId)
```

- [ ] **Step 2: Write tests**

```moonbit
///|
test "compute_text_edit: DuplicateBinding" {
  let text = "let x = 0\nx"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    DuplicateBinding(binding_node_id=binding_id),
    text, source_map, registry, fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let x = 0\nlet x_copy = 0\nx")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: MoveBindingDown" {
  let text = "let x = 0\nlet y = 1\nx"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    MoveBindingDown(binding_node_id=binding_id),
    text, source_map, registry, fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let y = 1\nlet x = 0\nx")
    }
    _ => fail("expected Some edits")
  }
}
```

- [ ] **Step 3: Run tests to verify they fail**

- [ ] **Step 4: Implement DuplicateBinding, MoveBindingUp, MoveBindingDown, AddBinding**

These are module-level text operations: extract the binding's text slice, insert/swap at the target position. `MoveBinding` must validate scoping guards using `free_vars` before proceeding (reject if either binding's name is free in the other's init, or if names match). `AddBinding` delegates to the existing `InsertChild` path.

Implementation details in `compute_text_edit`:
- `DuplicateBinding`: read binding text from source, insert copy below with `_copy` suffix
- `MoveBindingUp/Down`: find adjacent def, validate scoping, swap text ranges
- `AddBinding`: reuse `InsertChild(parent=module_node_id, index=defs.length(), kind=Int(0))`

- [ ] **Step 5: Run tests, verify pass**

- [ ] **Step 6: Run full test suite**

Run: `moon test -p dowdiness/crdt/projection`

- [ ] **Step 7: Commit**

```bash
git add projection/tree_lens.mbt projection/text_edit.mbt projection/text_edit_wbtest.mbt
git commit -m "feat(projection): add DuplicateBinding, MoveBinding, AddBinding actions"
```

---

### Task 12: ExtractToLet Action

**Files:**
- Modify: `projection/tree_lens.mbt`
- Modify: `projection/text_edit.mbt`
- Modify: `projection/text_edit_wbtest.mbt`

- [ ] **Step 1: Add TreeEditOp variant**

```moonbit
ExtractToLet(node_id~ : NodeId, var_name~ : String)
```

- [ ] **Step 2: Write tests**

```moonbit
///|
test "compute_text_edit: ExtractToLet from body" {
  let text = "let x = 0\nx + 1"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  // Extract the "1" literal from the body "x + 1"
  // Body is last child of Module, which is Bop(+, Var(x), Int(1))
  let body = proj.children[proj.children.length() - 1]
  let int_node = body.children[1] // Int(1)
  let result = compute_text_edit(
    ExtractToLet(node_id=int_node.id(), var_name="y"),
    text, source_map, registry, fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="let x = 0\nlet y = 1\nx + y")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: ExtractToLet rejects lambda-captured var" {
  let text = "λx. x + 1"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  // Try to extract "x + 1" which captures lambda-bound x
  let body = proj.children[0] // Bop
  let result = compute_text_edit(
    ExtractToLet(node_id=body.id(), var_name="y"),
    text, source_map, registry, fp,
  )
  inspect(result.is_err(), content="true")
}
```

- [ ] **Step 3: Run tests to verify they fail**

- [ ] **Step 4: Implement ExtractToLet**

Two `SpanEdit` entries:
1. Insert `let <name> = <expr_text>\n` before the Module body (or at end of defs)
2. Replace the selected expression with `Var(name)`

Validation: compute `free_vars(node.kind, module_env)` and check if any result is in `lam_env`. If so, reject.

If no root Module exists (bare expression), create one by wrapping: `let <name> = <expr_text>\n<original_body_with_replacement>`.

- [ ] **Step 5: Run tests, verify pass**

- [ ] **Step 6: Commit**

```bash
git add projection/tree_lens.mbt projection/text_edit.mbt projection/text_edit_wbtest.mbt
git commit -m "feat(projection): add ExtractToLet action with free-var validation"
```

---

### Task 13: InlineDefinition + InlineAllUsages Actions

**Files:**
- Modify: `projection/tree_lens.mbt`
- Modify: `projection/text_edit.mbt`
- Modify: `projection/text_edit_wbtest.mbt`

- [ ] **Step 1: Add TreeEditOp variants**

```moonbit
InlineDefinition(node_id~ : NodeId)
InlineAllUsages(binding_node_id~ : NodeId)
```

- [ ] **Step 2: Write tests**

```moonbit
///|
test "compute_text_edit: InlineDefinition replaces Var with init" {
  let text = "let x = 42\nx"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  // Find the body Var("x") node
  let body = proj.children[proj.children.length() - 1]
  let result = compute_text_edit(
    InlineDefinition(node_id=body.id()),
    text, source_map, registry, fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      // Should inline 42 and remove the let since sole usage
      inspect(new_text, content="42")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: InlineAllUsages replaces all refs" {
  let text = "let x = 42\nx + x"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast(proj)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let binding_id = fp.defs[0].3
  let result = compute_text_edit(
    InlineAllUsages(binding_node_id=binding_id),
    text, source_map, registry, fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="42 + 42")
    }
    _ => fail("expected Some edits")
  }
}
```

- [ ] **Step 3: Run tests to verify they fail**

- [ ] **Step 4: Implement InlineDefinition and InlineAllUsages**

`InlineDefinition`: resolve the Var's binding via `resolve_binder`, get the init expression text via `@ast.print_term`, replace the Var span. If sole usage (checked via `find_usages`), also delete the binding (emit second SpanEdit for the `let` line).

`InlineAllUsages`: find all usages via `find_usages`, replace each with init text, then delete the binding. Produces N+1 SpanEdits.

- [ ] **Step 5: Run tests, verify pass**

- [ ] **Step 6: Commit**

```bash
git add projection/tree_lens.mbt projection/text_edit.mbt projection/text_edit_wbtest.mbt
git commit -m "feat(projection): add InlineDefinition and InlineAllUsages actions"
```

---

### Task 14: Rename Action

**Files:**
- Modify: `projection/tree_lens.mbt`
- Modify: `projection/text_edit.mbt`
- Modify: `projection/text_edit_wbtest.mbt`

- [ ] **Step 1: Add TreeEditOp variant**

```moonbit
Rename(node_id~ : NodeId, new_name~ : String)
```

- [ ] **Step 2: Write tests**

```moonbit
///|
test "compute_text_edit: Rename Lam param" {
  let text = "λx. x"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast_with_syntax(proj, text)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  let result = compute_text_edit(
    Rename(node_id=proj.id(), new_name="y"),
    text, source_map, registry, fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      inspect(new_text, content="λy. y")
    }
    _ => fail("expected Some edits")
  }
}

///|
test "compute_text_edit: Rename respects shadowing" {
  let text = "λx. λx. x"
  let (proj, _) = parse_to_proj_node(text)
  let source_map = SourceMap::from_ast_with_syntax(proj, text)
  let registry = text_edit_test_registry(proj)
  let fp = FlatProj::from_proj_node(proj)
  // Rename the outer Lam's x to y
  let result = compute_text_edit(
    Rename(node_id=proj.id(), new_name="y"),
    text, source_map, registry, fp,
  )
  match result {
    Ok(Some((edits, _))) => {
      let new_text = apply_edits(text, edits)
      // Inner λx. x should be untouched
      inspect(new_text, content="λy. λx. x")
    }
    _ => fail("expected Some edits")
  }
}
```

- [ ] **Step 3: Run tests to verify they fail**

- [ ] **Step 4: Implement Rename**

Determine binding type from node kind:
- If `Lam(param, _)`: rename the param token (via `source_map.get_token_span(node_id, "param")`), then find and rename all bound `Var` occurrences using `collect_var_usages`.
- If `Var(name)`: resolve to binder via `resolve_binder`, then apply rename from that binder.
- For Module let-def: use `source_map.get_token_span(module_node_id, "name:" + def_index)` for the binder span, and `find_usages` for the usage spans.

Produces multiple SpanEdits (binder + all usages).

**Important:** `SourceMap::from_ast_with_syntax` may need to be used in tests to populate token_spans. Check if `parse_to_proj_node` already populates them. If not, the test helper must call the syntax-aware source map builder.

- [ ] **Step 5: Run tests, verify pass**

- [ ] **Step 6: Commit**

```bash
git add projection/tree_lens.mbt projection/text_edit.mbt projection/text_edit_wbtest.mbt
git commit -m "feat(projection): add Rename action with scope-aware renaming"
```

---

### Task 15: JSON Parsing for All New Variants

**Files:**
- Modify: `editor/tree_edit_json.mbt`
- Modify: `editor/tree_edit_bridge_test.mbt`

- [ ] **Step 1: Write tests for JSON parsing**

Add to test file:

```moonbit
///|
test "parse_tree_edit_op: Unwrap" {
  let json = @json.parse!("{\"type\": \"Unwrap\", \"node_id\": 5, \"keep_child_index\": 0}")
  let result = parse_tree_edit_op(json)
  inspect(result.is_ok(), content="true")
}

///|
test "parse_tree_edit_op: ExtractToLet" {
  let json = @json.parse!("{\"type\": \"ExtractToLet\", \"node_id\": 5, \"var_name\": \"x\"}")
  let result = parse_tree_edit_op(json)
  inspect(result.is_ok(), content="true")
}

///|
test "parse_tree_edit_op: DeleteBinding" {
  let json = @json.parse!("{\"type\": \"DeleteBinding\", \"binding_node_id\": 5}")
  let result = parse_tree_edit_op(json)
  inspect(result.is_ok(), content="true")
}

///|
test "parse_tree_edit_op: ChangeOperator" {
  let json = @json.parse!("{\"type\": \"ChangeOperator\", \"node_id\": 5, \"new_op\": \"Minus\"}")
  let result = parse_tree_edit_op(json)
  inspect(result.is_ok(), content="true")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/crdt/editor`

- [ ] **Step 3: Extend parse_tree_edit_op**

Add cases for each new variant. Helper for binding_node_id:

```moonbit
// After existing node_id helper, add:
fn get_binding_node_id(m : Map[String, Json]) -> Result[@proj.NodeId, String] {
  match m.get("binding_node_id") {
    Some(Json::Number(n, ..)) => Ok(@proj.NodeId::from_int(n.to_int()))
    _ => Err("missing binding_node_id field")
  }
}
```

Add match cases:

```moonbit
"Unwrap" => {
  let keep_child_index = match m.get("keep_child_index") {
    Some(Json::Number(n, ..)) => n.to_int()
    _ => return Err("missing keep_child_index")
  }
  Ok(@proj.TreeEditOp::Unwrap(node_id~, keep_child_index~))
}
"SwapChildren" => Ok(@proj.TreeEditOp::SwapChildren(node_id~))
"WrapInIf" => Ok(@proj.TreeEditOp::WrapInIf(node_id~))
"WrapInBop" => {
  let op = match m.get("op") {
    Some(Json::String("Plus")) => @ast.Bop::Plus
    Some(Json::String("Minus")) => @ast.Bop::Minus
    _ => return Err("missing or invalid op")
  }
  Ok(@proj.TreeEditOp::WrapInBop(node_id~, op~))
}
"ChangeOperator" => {
  let new_op = match m.get("new_op") {
    Some(Json::String("Plus")) => @ast.Bop::Plus
    Some(Json::String("Minus")) => @ast.Bop::Minus
    _ => return Err("missing or invalid new_op")
  }
  Ok(@proj.TreeEditOp::ChangeOperator(node_id~, new_op~))
}
"ExtractToLet" => {
  let var_name = match m.get("var_name") {
    Some(Json::String(s)) => s
    _ => return Err("missing var_name")
  }
  Ok(@proj.TreeEditOp::ExtractToLet(node_id~, var_name~))
}
"InlineDefinition" => Ok(@proj.TreeEditOp::InlineDefinition(node_id~))
"Rename" => {
  let new_name = match m.get("new_name") {
    Some(Json::String(s)) => s
    _ => return Err("missing new_name")
  }
  Ok(@proj.TreeEditOp::Rename(node_id~, new_name~))
}
"InlineAllUsages" => {
  let binding_node_id = get_binding_node_id(m)!
  Ok(@proj.TreeEditOp::InlineAllUsages(binding_node_id~))
}
"DeleteBinding" => {
  let binding_node_id = get_binding_node_id(m)!
  Ok(@proj.TreeEditOp::DeleteBinding(binding_node_id~))
}
"DuplicateBinding" => {
  let binding_node_id = get_binding_node_id(m)!
  Ok(@proj.TreeEditOp::DuplicateBinding(binding_node_id~))
}
"MoveBindingUp" => {
  let binding_node_id = get_binding_node_id(m)!
  Ok(@proj.TreeEditOp::MoveBindingUp(binding_node_id~))
}
"MoveBindingDown" => {
  let binding_node_id = get_binding_node_id(m)!
  Ok(@proj.TreeEditOp::MoveBindingDown(binding_node_id~))
}
"AddBinding" => {
  let module_node_id = match m.get("module_node_id") {
    Some(Json::Number(n, ..)) => @proj.NodeId::from_int(n.to_int())
    _ => return Err("missing module_node_id")
  }
  Ok(@proj.TreeEditOp::AddBinding(module_node_id~))
}
```

- [ ] **Step 4: Run tests, verify pass**

Run: `moon test -p dowdiness/crdt/editor`

- [ ] **Step 5: Commit**

```bash
git add editor/tree_edit_json.mbt editor/tree_edit_bridge_test.mbt
git commit -m "feat(editor): extend JSON parsing for all new TreeEditOp variants"
```

---

### Task 16: TreeEditorState::apply_edit for New Variants

**Files:**
- Modify: `projection/tree_editor.mbt`
- Modify: `projection/tree_editor_wbtest.mbt`

- [ ] **Step 1: Add match arms for all new variants**

Most new structural ops (Unwrap, SwapChildren, WrapInIf, etc.) don't change TreeEditorState beyond what happens through the reparse/reconcile cycle. They can share the same UI-state handling as Delete: clear editing state, preserve selection.

```moonbit
// In TreeEditorState::apply_edit, add:
Unwrap(node_id~, ..) | SwapChildren(node_id~) | WrapInIf(node_id~) |
WrapInBop(node_id~, ..) | ChangeOperator(node_id~, ..) |
ExtractToLet(node_id~, ..) | InlineDefinition(node_id~) |
Rename(node_id~, ..) => {
  let _ = node_id
  { ..self, editing_node: None, edit_value: "" }
}
DeleteBinding(..) | InlineAllUsages(..) | DuplicateBinding(..) |
MoveBindingUp(..) | MoveBindingDown(..) | AddBinding(..) => {
  { ..self, editing_node: None, edit_value: "" }
}
```

- [ ] **Step 2: Run tests**

Run: `moon test -p dowdiness/crdt/projection`
Expected: All PASS (no compilation errors from exhaustive match).

- [ ] **Step 3: Commit**

```bash
git add projection/tree_editor.mbt
git commit -m "feat(projection): handle new TreeEditOp variants in TreeEditorState"
```

---

### Task 17: Update Interfaces + Format

**Files:**
- All modified `.mbt` files

- [ ] **Step 1: Run moon info to update .mbti interfaces**

Run: `moon info`

- [ ] **Step 2: Check interface changes**

Run: `git diff *.mbti`
Verify: New public types (FocusHint, Action, NodeContext, ActionGroup, BindingSite) and new functions appear.

- [ ] **Step 3: Run moon fmt**

Run: `moon fmt`

- [ ] **Step 4: Run full test suite**

Run: `moon test`
Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: update interfaces and format after structural editing actions"
```

---

## Dependency Graph

```
Task 1 (FocusHint) ──→ Task 2 (apply_tree_edit)
                   ──→ Task 6-9 (simple actions)
                   ──→ Task 10-11 (module actions)

Task 3 (free_vars) ──→ Task 11 (MoveBinding guards)
                   ──→ Task 12 (ExtractToLet validation)

Task 4 (scope)     ──→ Task 12 (ExtractToLet)
                   ──→ Task 13 (Inline)
                   ──→ Task 14 (Rename)

Task 5 (actions)   ── independent, can run after Task 1

Tasks 6-14         ──→ Task 15 (JSON parsing)
                   ──→ Task 16 (TreeEditorState)
                   ──→ Task 17 (interfaces)
```

Tasks 1, 3, 4, 5 can be implemented in parallel.
Tasks 6-9 can be implemented in parallel (all simple expression actions).
Tasks 10-11 can be implemented in parallel.
Tasks 12-14 should be sequential (increasing complexity, shared scope utilities).
Tasks 15-17 are sequential and come last.
