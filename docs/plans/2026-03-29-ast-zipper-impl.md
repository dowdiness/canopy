# AST Zipper Implementation Plan

**Status:** Complete (implemented on `feat/ast-zipper` branch, PR #89)

**Goal:** Add a Huet Zipper package over `Term` with navigation, context, EditAction dispatch, and Hole support. This plan covers the zipper library and Hole variant only — `LambdaEditorState`, `relocate_cursor`, and JS bridge integration are a separate follow-up plan.

**Implementation notes (discovered during execution):**
- MoonBit's `@immut/list` was replaced by `@list.List` (stdlib change). List constructors are `Empty`/`More(head, tail=rest)`.
- `HoleLiteral` was missing from `lang/lambda/proj/proj_node.mbt` (`syntax_to_proj_node`) — added post-review.
- `@token.Hole` was missing from `token_starts_application_atom` and `parse_application` — `f _` didn't parse as App. Fixed.
- `HoleToken` was missing from `syntax_kind_to_token_kind` in `lambda_spec.mbt` — broke incremental subtree reuse. Fixed.
- Delete/Wrap/Unwrap suppressed for Hole and Module nodes in `available_actions` — matches existing action policy.
- `@proj` import moved to `import { ... } for "wbtest"` to avoid CI warnings-as-errors.

**Architecture:** Cursor is a NodeId (stable via reconciliation). Zipper is a transient computation constructed on demand for navigation and context. EditAction maps trivially to TreeEditOp. All text computation reuses existing `compute_*` handlers. See `docs/plans/2026-03-28-ast-zipper-design.md` for the full design.

**Tech Stack:** MoonBit, loom parser framework, FugueMax CRDT (eg-walker)

**Reference files:**
- Design plan: `docs/plans/2026-03-28-ast-zipper-design.md`
- Architecture: `docs/architecture/zipper-roundtrip-invariants.md`
- Architecture: `docs/architecture/edit-action-progression.md`

---

## File Structure

### Submodule changes (loom)

| File | Action | Responsibility |
|------|--------|---------------|
| `loom/examples/lambda/src/token/token.mbt` | Modify | Add `Hole` token variant |
| `loom/examples/lambda/src/syntax/syntax_kind.mbt` | Modify | Add `HoleToken` + `HoleLiteral` syntax kinds |
| `loom/examples/lambda/src/lexer/lexer.mbt` | Modify | Recognize `_` as Hole token |
| `loom/examples/lambda/src/cst_parser.mbt` | Modify | Parse `_` as HoleLiteral atom |
| `loom/examples/lambda/src/term_convert.mbt` | Modify | Convert HoleLiteral → `Hole(0)` |
| `loom/examples/lambda/src/ast/ast.mbt` | Modify | Add `Hole(Int)` to Term enum |
| `loom/examples/lambda/src/ast/sym.mbt` | Modify | Add `hole` to TermSym trait + impls |
| `loom/examples/lambda/src/ast/proj_traits.mbt` | Modify | Add Hole to TreeNode + Renderable |

### Canopy changes

| File | Action | Responsibility |
|------|--------|---------------|
| `lang/lambda/zipper/moon.pkg` | Create | Package declaration + imports |
| `lang/lambda/zipper/zipper.mbt` | Create | Zipper, TermCtx, plug, navigation, focus_at |
| `lang/lambda/zipper/zipper_role.mbt` | Create | PositionRole, position_role |
| `lang/lambda/zipper/zipper_hole.mbt` | Create | HoleInfo, HoleRegistry |
| `lang/lambda/zipper/zipper_action.mbt` | Create | EditAction, Direction, ActionRecord, to_tree_edit_op |
| `lang/lambda/zipper/zipper_bridge.mbt` | Create | zipper_from_node_id, find_proj_node_for_focus, navigate |
| `lang/lambda/zipper/zipper_wbtest.mbt` | Create | All whitebox tests |
| `lang/lambda/zipper/zipper_bridge_wbtest.mbt` | Create | Bridge integration tests |

---

### Task 1: Add `Hole(Int)` to Term and TermSym (loom submodule)

**Files:**
- Modify: `loom/examples/lambda/src/ast/ast.mbt`
- Modify: `loom/examples/lambda/src/ast/sym.mbt`

All work in this task is in the `loom/` submodule. Run commands from `loom/examples/lambda/`.

- [ ] **Step 1: Add Hole(Int) variant to Term**

In `loom/examples/lambda/src/ast/ast.mbt`, add `Hole(Int)` after `Error(String)`:

```moonbit
  // Error term for malformed/missing nodes
  Error(String)
  // Hole — placeholder for deleted or incomplete nodes
  Hole(Int)
} derive(Show, Eq, ToJson, Debug)
```

- [ ] **Step 2: Add hole method to TermSym trait**

In `loom/examples/lambda/src/ast/sym.mbt`, add to the trait:

```moonbit
  /// Typed hole placeholder. Implement as abort() if you only process
  /// complete programs.
  hole(Int) -> Self
```

- [ ] **Step 3: Add Term::hole impl**

In `loom/examples/lambda/src/ast/sym.mbt`, add:

```moonbit
///|
pub impl TermSym for Term with hole(n) {
  Hole(n)
}
```

- [ ] **Step 4: Add Pretty::hole impl**

In `loom/examples/lambda/src/ast/sym.mbt`, add:

```moonbit
///|
pub impl TermSym for Pretty with hole(_n) {
  { repr: "_" }
}
```

- [ ] **Step 5: Add hole arm to replay**

In `loom/examples/lambda/src/ast/sym.mbt`, in the `replay` function, add before the closing brace:

```moonbit
    Hole(n) => T::hole(n)
```

- [ ] **Step 6: Run moon check**

Run: `cd loom/examples/lambda && moon check`
Expected: Errors in `proj_traits.mbt` (non-exhaustive matches). This is correct — we fix them in Task 2.

- [ ] **Step 7: Commit**

```bash
cd loom/examples/lambda && git add -A && git commit -m "feat: add Hole(Int) to Term and TermSym"
```

---

### Task 2: Add Hole to TreeNode, Renderable, and other exhaustive matches (loom submodule)

**Files:**
- Modify: `loom/examples/lambda/src/ast/proj_traits.mbt`
- Modify: `loom/examples/lambda/src/dot_node.mbt`
- Modify: `loom/examples/lambda/src/parser_properties_test.mbt`

- [ ] **Step 1: Add Hole to TreeNode::children**

In `proj_traits.mbt`, the `children` match has `_ => []` which already covers Hole. No change needed — verify this.

- [ ] **Step 2: Add Hole to TreeNode::same_kind**

In `proj_traits.mbt`, add before the wildcard `_ => false`:

```moonbit
    (Hole(_), Hole(_)) => true
```

- [ ] **Step 3: Add Hole to Renderable::kind_tag**

```moonbit
    Hole(_) => "Hole"
```

- [ ] **Step 4: Add Hole to Renderable::label**

```moonbit
    Hole(_) => "_"
```

- [ ] **Step 5: Add Hole to Renderable::placeholder**

```moonbit
    Hole(_) => "_"
```

- [ ] **Step 6: Add Hole to Renderable::unparse**

The `unparse` method calls `print_term(self)` which uses `replay` → `Pretty::hole` → `"_"`. No change needed — verify this.

- [ ] **Step 7: Add Hole to dot_node.mbt label match**

In `loom/examples/lambda/src/dot_node.mbt`, in the `label` method match (line ~18), add:

```moonbit
    @ast.Term::Hole(n) => "Hole(" + n.to_string() + ")"
```

- [ ] **Step 8: Add Hole to parser_properties_test.mbt check_well_formed**

In `loom/examples/lambda/src/parser_properties_test.mbt`, in `check_well_formed` (line ~192), add:

```moonbit
    @ast.Term::Hole(_) => ()
```

- [ ] **Step 9: Run moon check to find any remaining non-exhaustive matches**

Run: `cd loom/examples/lambda && moon check`
Expected: PASS. If any other files have non-exhaustive Term matches, add `Hole` arms.

- [ ] **Step 10: Run moon test**

Run: `cd loom/examples/lambda && moon test`
Expected: PASS

- [ ] **Step 11: Run moon info && moon fmt**

Run: `cd loom/examples/lambda && moon info && moon fmt`

- [ ] **Step 12: Commit**

```bash
cd loom/examples/lambda && git add -A && git commit -m "feat: add Hole to TreeNode, Renderable, and exhaustive matches"
```

---

### Task 3: Add Hole to lexer, parser, and CST→AST (loom submodule)

**Files:**
- Modify: `loom/examples/lambda/src/token/token.mbt`
- Modify: `loom/examples/lambda/src/syntax/syntax_kind.mbt`
- Modify: `loom/examples/lambda/src/lexer/lexer.mbt`
- Modify: `loom/examples/lambda/src/cst_parser.mbt`
- Modify: `loom/examples/lambda/src/term_convert.mbt`

- [ ] **Step 1: Write failing test for Hole parsing**

Add tests in an appropriate test file (e.g., `loom/examples/lambda/src/cst_parser_wbtest.mbt` or a new file):

```moonbit
test "parse underscore as Hole" {
  // parse() raises on diagnostics, returns Term directly
  let result = try { @parser.parse("_") } catch { _ => @ast.Error("parse failed") }
  inspect!(result, content="Hole(0)")
}

test "parse hole in expression" {
  let result = try { @parser.parse("(λx. _)") } catch { _ => @ast.Error("parse failed") }
  inspect!(result, content="Lam(\"x\", Hole(0))")
}

test "print_term Hole outputs underscore" {
  inspect!(@ast.print_term(@ast.Hole(42)), content="_")
}
```

Note: `parse()` returns `@ast.Term` directly (raises on errors). `parse_term()` returns `(@ast.Term, Array[Diagnostic])`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd loom/examples/lambda && moon test`
Expected: FAIL — `_` is not a recognized token.

- [ ] **Step 3: Add Hole token variant**

In `loom/examples/lambda/src/token/token.mbt`, add after `Semicolon`:

```moonbit
  Hole // _ (typed hole placeholder)
```

- [ ] **Step 4: Add HoleToken and HoleLiteral syntax kinds**

In `loom/examples/lambda/src/syntax/syntax_kind.mbt`:

Add to the enum:
```moonbit
  HoleToken // _
  HoleLiteral // Hole expression node
```

Add to `is_token`:
```moonbit
    | HoleToken => true
```

Add to `to_raw` (use next available numbers, 35 and 36):
```moonbit
    HoleToken => 35
    HoleLiteral => 36
```

Add to `from_raw`:
```moonbit
    35 => HoleToken
    36 => HoleLiteral
```

- [ ] **Step 5: Add `_` token recognition to lexer**

In `loom/examples/lambda/src/lexer/lexer.mbt`, add a case in the main match before the identifier pattern:

```moonbit
    Some('_') =>
      @core.LexStep::Produced(
        @core.TokenInfo::new(@token.Hole, 1),
        next_offset=pos + 1,
      )
```

- [ ] **Step 6: Add Hole to token_starts_expression**

In `loom/examples/lambda/src/cst_parser.mbt`, in `token_starts_expression`, add `@token.Hole` to the match:

```moonbit
    | @token.Hole
```

- [ ] **Step 7: Add Hole parsing to parse_atom**

In `loom/examples/lambda/src/cst_parser.mbt`, in `parse_atom`, add a case before the catch-all:

```moonbit
    @token.Hole =>
      ctx.node(@syntax.HoleLiteral, fn() { ctx.emit_token(@syntax.HoleToken) })
```

- [ ] **Step 8: Add HoleLiteral to term_convert**

In `loom/examples/lambda/src/term_convert.mbt`, in the CST→AST conversion match, add:

```moonbit
    @syntax.HoleLiteral => @ast.Term::Hole(0)
```

- [ ] **Step 9: Run tests**

Run: `cd loom/examples/lambda && moon check && moon test`
Expected: All tests pass, including the new Hole parsing tests.

- [ ] **Step 10: Run moon info && moon fmt**

Run: `cd loom/examples/lambda && moon info && moon fmt`

- [ ] **Step 11: Commit**

```bash
cd loom/examples/lambda && git add -A && git commit -m "feat: parse _ as Hole(0) in lambda calculus"
```

---

### Task 4: Bump loom submodule in canopy

**Files:**
- Modify: `loom` (submodule pointer)

- [ ] **Step 1: Bump submodule**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt
git add loom
git commit -m "chore: bump loom submodule (Hole variant in Term)"
```

- [ ] **Step 2: Verify canopy builds**

Run: `moon check`
Expected: May show errors if any existing code has non-exhaustive matches on Term. Fix them by adding `Hole(_) =>` arms.

- [ ] **Step 3: Fix any non-exhaustive matches in canopy**

Check `lang/lambda/edits/` and `lang/lambda/proj/` for matches on Term that need a Hole arm.

- [ ] **Step 4: Run moon test**

Run: `moon test`
Expected: PASS

- [ ] **Step 5: Commit fixes**

```bash
git add -A && git commit -m "fix: handle Hole variant in canopy Term matches"
```

---

### Task 5: Create zipper package with core types and navigation

**Files:**
- Create: `lang/lambda/zipper/moon.pkg`
- Create: `lang/lambda/zipper/zipper.mbt`

- [ ] **Step 1: Create moon.pkg**

```
import {
  "dowdiness/lambda/ast" @ast,
  "dowdiness/canopy/framework/core" @core,
  "moonbitlang/core/immut/list" @immut/list,
}
```

- [ ] **Step 2: Write failing navigation tests**

Create `lang/lambda/zipper/zipper_wbtest.mbt`:

```moonbit
test "go_down then go_up is identity" {
  let z = from_root(@ast.App(@ast.Var("f"), @ast.Int(1)))
  let down = go_down(z).unwrap()
  let up = go_up(down).unwrap()
  inspect!(to_root(up), content="App(Var(\"f\"), Int(1))")
}

test "go_right then go_left is identity" {
  let z = from_root(@ast.App(@ast.Var("f"), @ast.Int(1)))
  let down = go_down(z).unwrap()
  let right = go_right(down).unwrap()
  let left = go_left(right).unwrap()
  inspect!(to_root(left), content="App(Var(\"f\"), Int(1))")
}

test "go_down on leaf returns None" {
  let z = from_root(@ast.Int(42))
  inspect!(go_down(z), content="None")
}

test "go_down on Hole returns None" {
  let z = from_root(@ast.Hole(0))
  inspect!(go_down(z), content="None")
}

test "traverse all children of If" {
  let z = from_root(@ast.If(@ast.Int(1), @ast.Int(2), @ast.Int(3)))
  let c = go_down(z).unwrap()
  inspect!(c.focus, content="Int(1)")
  let t = go_right(c).unwrap()
  inspect!(t.focus, content="Int(2)")
  let e = go_right(t).unwrap()
  inspect!(e.focus, content="Int(3)")
  inspect!(go_right(e), content="None")
}

test "Module navigation: defs then body" {
  let z = from_root(@ast.Module([("x", @ast.Int(1)), ("y", @ast.Int(2))], @ast.Var("x")))
  let d0 = go_down(z).unwrap()
  inspect!(d0.focus, content="Int(1)")
  let d1 = go_right(d0).unwrap()
  inspect!(d1.focus, content="Int(2)")
  let body = go_right(d1).unwrap()
  inspect!(body.focus, content="Var(\"x\")")
  inspect!(go_right(body), content="None")
}

test "focus_at ancestor walk" {
  let term = @ast.App(@ast.Var("f"), @ast.Int(1))
  let z = focus_at(term, [0, 0, 0]) // too deep
  inspect!(depth(z), content="1") // stops at Var("f"), depth 1
}

test "focus_at exact path" {
  let term = @ast.If(@ast.Int(1), @ast.Int(2), @ast.Int(3))
  let z = focus_at(term, [2]) // third child = else branch
  inspect!(z.focus, content="Int(3)")
}

test "navigate_to_child child 0" {
  let z = from_root(@ast.App(@ast.Var("f"), @ast.Int(1)))
  let c = navigate_to_child(z, 0).unwrap()
  inspect!(c.focus, content="Var(\"f\")")
}

test "navigate_to_child child 1" {
  let z = from_root(@ast.App(@ast.Var("f"), @ast.Int(1)))
  let c = navigate_to_child(z, 1).unwrap()
  inspect!(c.focus, content="Int(1)")
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `moon test -p dowdiness/canopy/lang/lambda/zipper`
Expected: FAIL — types not defined yet.

- [ ] **Step 4: Implement zipper.mbt**

Create `lang/lambda/zipper/zipper.mbt` with:
- `TermCtx` enum (11 variants)
- `Zipper` struct (`focus: Term`, `path: @immut/list.T[TermCtx]`)
- `plug` function
- `go_down`, `go_up`, `go_left`, `go_right`
- `to_root`, `from_root`, `depth`
- `children_of`
- `ctx_to_child_index`
- `navigate_to_child`
- `to_path_indices`
- `focus_at` (with ancestor-walk — always returns Zipper, never None)

See design plan for all code.

- [ ] **Step 5: Run tests**

Run: `moon test -p dowdiness/canopy/lang/lambda/zipper`
Expected: PASS

- [ ] **Step 6: Run moon check**

Run: `moon check`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add lang/lambda/zipper/ && git commit -m "feat: add Zipper core types and navigation"
```

---

### Task 6: Add PositionRole

**Files:**
- Create: `lang/lambda/zipper/zipper_role.mbt`
- Modify: `lang/lambda/zipper/zipper_wbtest.mbt`

- [ ] **Step 1: Write failing tests**

Add to `zipper_wbtest.mbt`:

```moonbit
test "root position" {
  let z = from_root(@ast.Int(42))
  inspect!(position_role(z), content="Root")
}

test "function position in App" {
  let z = from_root(@ast.App(@ast.Var("f"), @ast.Int(1)))
    |> go_down()
    |> Option::unwrap()
  inspect!(position_role(z), content="FunctionPosition")
}

test "argument position in App" {
  let z = from_root(@ast.App(@ast.Var("f"), @ast.Int(1)))
    |> go_down()
    |> Option::unwrap()
    |> go_right()
    |> Option::unwrap()
  inspect!(position_role(z), content="ArgumentPosition")
}

test "else branch in If" {
  let z = from_root(@ast.If(@ast.Int(1), @ast.Int(2), @ast.Int(3)))
    |> go_down()
    |> Option::unwrap()
    |> go_right()
    |> Option::unwrap()
    |> go_right()
    |> Option::unwrap()
  inspect!(position_role(z), content="ElseBranch")
}

test "let definition role carries name" {
  let z = from_root(@ast.Module([("x", @ast.Int(1))], @ast.Var("x")))
    |> go_down()
    |> Option::unwrap()
  inspect!(position_role(z), content="LetDefinition(\"x\")")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `moon test -p dowdiness/canopy/lang/lambda/zipper`
Expected: FAIL — `position_role` not defined.

- [ ] **Step 3: Implement zipper_role.mbt**

Create `lang/lambda/zipper/zipper_role.mbt` with `PositionRole` enum and `position_role` function. See design plan for code.

- [ ] **Step 4: Run tests**

Run: `moon test -p dowdiness/canopy/lang/lambda/zipper`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lang/lambda/zipper/zipper_role.mbt lang/lambda/zipper/zipper_wbtest.mbt
git commit -m "feat: add PositionRole and position_role"
```

---

### Task 7: Add EditAction and TreeEditOp dispatch

**Files:**
- Create: `lang/lambda/zipper/zipper_action.mbt`
- Modify: `lang/lambda/zipper/moon.pkg`
- Modify: `lang/lambda/zipper/zipper_wbtest.mbt`

Note: EditAction must be defined before HoleRegistry (Task 8), because `HoleInfo` has `created_by: EditAction`.

- [ ] **Step 1: Add edits import to moon.pkg**

Update `lang/lambda/zipper/moon.pkg` to add the edits dependency:

```
import {
  "dowdiness/lambda/ast" @ast,
  "dowdiness/canopy/framework/core" @core,
  "dowdiness/canopy/lang/lambda/edits" @edits,
  "moonbitlang/core/immut/list" @immut/list,
}
```

- [ ] **Step 2: Write failing tests**

Add to `zipper_wbtest.mbt`:

```moonbit
test "to_tree_edit_op maps Delete" {
  let id = @core.NodeId::from_int(5)
  let op = to_tree_edit_op(id, Delete)
  inspect!(op, content="Delete(node_id=NodeId(5))")
}

test "to_tree_edit_op maps WrapLam" {
  let id = @core.NodeId::from_int(5)
  let op = to_tree_edit_op(id, WrapLam("x"))
  inspect!(op, content="WrapInLambda(node_id=NodeId(5), var_name=\"x\")")
}

test "to_tree_edit_op maps Unwrap" {
  let id = @core.NodeId::from_int(5)
  let op = to_tree_edit_op(id, Unwrap(1))
  inspect!(op, content="Unwrap(node_id=NodeId(5), keep_child_index=1)")
}
```

- [ ] **Step 3: Implement zipper_action.mbt**

Create `lang/lambda/zipper/zipper_action.mbt` with:
- `EditAction` enum (9 variants: Delete, WrapLam, WrapApp, WrapIf, WrapBop, Unwrap, SwapChildren, ChangeOperator, CommitEdit)
- `Direction` enum (Up, Down, Left, Right)
- `ActionRecord` struct
- `to_tree_edit_op` function

```moonbit
///|
pub(all) enum EditAction {
  Delete
  WrapLam(String)
  WrapApp
  WrapIf
  WrapBop(@ast.Bop)
  Unwrap(Int)
  SwapChildren
  ChangeOperator(@ast.Bop)
  CommitEdit(String)
} derive(Show)

///|
pub(all) enum Direction {
  Up
  Down
  Left
  Right
} derive(Show)

///|
pub(all) struct ActionRecord {
  action : EditAction
  cursor_before : @core.NodeId
  cursor_after : @core.NodeId
  role : PositionRole
} derive(Show)

///|
pub fn to_tree_edit_op(cursor : @core.NodeId, action : EditAction) -> @edits.TreeEditOp {
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

- [ ] **Step 4: Run tests**

Run: `moon test -p dowdiness/canopy/lang/lambda/zipper`
Expected: PASS

- [ ] **Step 5: Run moon check**

Run: `moon check`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add lang/lambda/zipper/ && git commit -m "feat: add EditAction enum and TreeEditOp dispatch"
```

---

### Task 8: Add HoleRegistry

**Files:**
- Create: `lang/lambda/zipper/zipper_hole.mbt`
- Modify: `lang/lambda/zipper/moon.pkg`
- Modify: `lang/lambda/zipper/zipper_wbtest.mbt`

Note: `HoleInfo` depends on `EditAction` (from Task 7) and `PositionRole` (from Task 6).
`HoleRegistry::prune` needs `@immut/hashset`, so add the import.

- [ ] **Step 1: Add hashset import to moon.pkg**

Update `lang/lambda/zipper/moon.pkg`:

```
import {
  "dowdiness/lambda/ast" @ast,
  "dowdiness/canopy/framework/core" @core,
  "dowdiness/canopy/lang/lambda/edits" @edits,
  "moonbitlang/core/immut/list" @immut/list,
  "moonbitlang/core/immut/hashset" @immut/hashset,
}
```

- [ ] **Step 2: Write failing tests**

Add to `zipper_wbtest.mbt`:

```moonbit
test "HoleRegistry fresh_hole_id increments" {
  let reg = HoleRegistry::new()
  inspect!(reg.fresh_hole_id(), content="0")
  inspect!(reg.fresh_hole_id(), content="1")
  inspect!(reg.fresh_hole_id(), content="2")
}

test "HoleRegistry register and get" {
  let reg = HoleRegistry::new()
  let id = @core.NodeId::from_int(5)
  let info : HoleInfo = { created_by: Delete, role: Root }
  reg.register(id, info)
  inspect!(reg.get(id).is_empty(), content="false")
  inspect!(reg.get(@core.NodeId::from_int(99)).is_empty(), content="true")
}
```

- [ ] **Step 3: Implement zipper_hole.mbt**

Create `lang/lambda/zipper/zipper_hole.mbt` with `HoleInfo`, `HoleRegistry` (new, fresh_hole_id, register, get, prune). See design plan for code.

- [ ] **Step 4: Run tests**

Run: `moon test -p dowdiness/canopy/lang/lambda/zipper`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lang/lambda/zipper/ && git commit -m "feat: add HoleInfo and HoleRegistry"
```

---

### Task 9: Add Zipper ↔ NodeId bridge

**Files:**
- Create: `lang/lambda/zipper/zipper_bridge.mbt`
- Create: `lang/lambda/zipper/zipper_bridge_wbtest.mbt`

- [ ] **Step 1: Write failing tests**

Create `lang/lambda/zipper/zipper_bridge_wbtest.mbt`:

```moonbit
test "find_proj_node_for_focus at root" {
  let term = @ast.Int(42)
  let z = from_root(term)
  // Build a minimal ProjNode manually
  let proj = @core.ProjNode::new(term, 0, 2, @core.next_proj_node_id({ val: 0 }), [])
  let found = find_proj_node_for_focus(z, proj)
  inspect!(found.is_empty(), content="false")
}

test "path_indices_to_node finds target" {
  let id0 = @core.NodeId::from_int(0)
  let id1 = @core.NodeId::from_int(1)
  let id2 = @core.NodeId::from_int(2)
  let child0 : @core.ProjNode[@ast.Term] = { node_id: 0, kind: @ast.Var("f"), children: [], start: 0, end: 1 }
  let child1 : @core.ProjNode[@ast.Term] = { node_id: 1, kind: @ast.Int(1), children: [], start: 2, end: 3 }
  let root : @core.ProjNode[@ast.Term] = { node_id: 2, kind: @ast.App(@ast.Var("f"), @ast.Int(1)), children: [child0, child1], start: 0, end: 3 }
  let indices = path_indices_to_node(root, id1)
  inspect!(indices, content="Some([1])")
}
```

- [ ] **Step 2: Implement zipper_bridge.mbt**

Create `lang/lambda/zipper/zipper_bridge.mbt` with:
- `path_indices_to_node`
- `find_proj_node_for_focus`
- `zipper_from_node_id`
- `navigate` (the NodeId-level navigation function)
- `node_id_at_offset` (thin wrapper around `source_map.innermost_node_at`)
- `text_range_from_node_id` (thin wrapper around `source_map.get_range`)

See design plan for code.

- [ ] **Step 3: Run tests**

Run: `moon test -p dowdiness/canopy/lang/lambda/zipper`
Expected: PASS

- [ ] **Step 4: Run moon check**

Run: `moon check`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lang/lambda/zipper/ && git commit -m "feat: add Zipper-NodeId bridge functions"
```

---

### Task 10: Add available_actions

**Files:**
- Modify: `lang/lambda/zipper/zipper_role.mbt`
- Modify: `lang/lambda/zipper/zipper_wbtest.mbt`

- [ ] **Step 1: Write failing test**

Add to `zipper_wbtest.mbt`:

```moonbit
test "available_actions includes SwapChildren for Bop" {
  let z = from_root(@ast.Bop(@ast.Plus, @ast.Int(1), @ast.Int(2)))
  let actions = available_actions_for_zipper(z)
  let has_swap = actions.iter().any(fn(a) { match a { SwapChildren => true; _ => false } })
  inspect!(has_swap, content="true")
}

test "available_actions excludes SwapChildren for App" {
  let z = from_root(@ast.App(@ast.Var("f"), @ast.Int(1)))
  let actions = available_actions_for_zipper(z)
  let has_swap = actions.iter().any(fn(a) { match a { SwapChildren => true; _ => false } })
  inspect!(has_swap, content="false")
}
```

- [ ] **Step 2: Implement available_actions_for_zipper**

Add to `zipper_role.mbt`:

```moonbit
///|
pub fn available_actions_for_zipper(z : Zipper) -> Array[EditAction] {
  let focus = z.focus
  let actions : Array[EditAction] = []
  actions.push(Delete)
  actions.push(WrapLam("x"))
  actions.push(WrapApp)
  actions.push(WrapIf)
  actions.push(WrapBop(@ast.Plus))
  actions.push(WrapBop(@ast.Minus))
  let n = children_of(focus).length()
  for i in 0..<n {
    actions.push(Unwrap(i))
  }
  match focus {
    @ast.Bop(..) | @ast.If(..) => actions.push(SwapChildren)
    _ => ()
  }
  match focus {
    @ast.Bop(@ast.Plus, _, _) => actions.push(ChangeOperator(@ast.Minus))
    @ast.Bop(@ast.Minus, _, _) => actions.push(ChangeOperator(@ast.Plus))
    _ => ()
  }
  actions
}
```

- [ ] **Step 3: Run tests**

Run: `moon test -p dowdiness/canopy/lang/lambda/zipper`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add lang/lambda/zipper/ && git commit -m "feat: add available_actions_for_zipper"
```

---

### Task 11: Run full test suite and finalize

**Files:**
- Modify: various `.mbti` files (generated)

- [ ] **Step 1: Run moon info && moon fmt**

Run: `moon info && moon fmt`

- [ ] **Step 2: Run full test suite**

Run: `moon test`
Expected: PASS

- [ ] **Step 3: Run loom tests**

Run: `cd loom/examples/lambda && moon test`
Expected: PASS

- [ ] **Step 4: Check git diff on .mbti files**

Run: `git diff -- '**/*.mbti'`
Review: Verify only the expected new public APIs appear.

- [ ] **Step 5: Commit interface files**

```bash
git add -A && git commit -m "chore: update .mbti interfaces for zipper package"
```

---

## Notes for Implementer

1. **TreeEditOp uses labelled arguments.** Notice `Delete(node_id=cursor)` not `Delete(cursor)`. All TreeEditOp variants use labelled fields (e.g., `node_id~`, `var_name~`, `keep_child_index~`).

2. **Submodule workflow.** Tasks 1-3 modify the loom submodule. Commit inside `loom/`, then bump the submodule pointer in canopy (Task 4). Push the submodule changes to the loom remote before pushing canopy.

3. **`LambdaEditorState`, `relocate_cursor`, and integration are NOT in this plan.** They correspond to design plan steps 8-9 and depend on wiring keyboard events through the JS bridge, which requires a separate design for the web integration layer. The zipper package is independently useful and testable without the integration layer. A follow-up plan will cover `LambdaEditorState`, `on_tree_key`, `on_tree_navigate`, `relocate_cursor`, and `register_new_holes`.

4. **Test output format.** MoonBit's `inspect!` uses `derive(Show)` output. Run `moon test --update` if the exact string format doesn't match — then verify the updated snapshot is correct.

5. **ProjNode construction in tests.** The `ProjNode` struct may require `pub(all)` access or a constructor. Check if `ProjNode::new` exists or if struct literal construction works from the test package. If not, use whitebox tests (the `_wbtest.mbt` suffix).
