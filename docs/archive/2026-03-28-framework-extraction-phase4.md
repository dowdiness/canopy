# Framework Extraction Phase 4: Traits to Loom + Lambda-Specific Code to lang/lambda/

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move `TreeNode`/`Renderable` traits to `dowdiness/loom/core`, move their `@ast.Term` impls to `dowdiness/lambda/ast`, then extract all remaining lambda-specific code from `projection/` into `lang/lambda/` packages. End state: `projection/` contains only generic code re-exported from `framework/core/` or generic functions using loom-defined traits.

**Architecture:** Three sub-phases. Phase 4a adds trait definitions to the loom submodule. Phase 4b adds trait impls to the lambda submodule. Phase 4c moves lambda-specific code out of `projection/` in the canopy module. Each sub-phase is a separate PR to a different repo/module.

**Prereqs:** Phase 3 done (PR #66). `framework/core/` exists with `NodeId`, `ProjNode[T]`, helpers.

**Modules touched:**
- `dowdiness/loom` (submodule at `loom/loom/`) — Phases 4a
- `dowdiness/lambda` (submodule at `loom/examples/lambda/`) — Phase 4b
- `dowdiness/canopy` (root) — Phase 4c

---

## Phase overview

| Phase | What | Repo | Risk |
|-------|------|------|------|
| 4a — Traits to loom/core | Add TreeNode + Renderable to `dowdiness/loom/core` | loom | Low |
| 4b — Impls in lambda/ast | Add `impl TreeNode/Renderable for Term` in `dowdiness/lambda/ast` | loom (lambda) | Low |
| 4c — Extract lang/lambda/ | Move lambda code from projection/ to lang/lambda/ packages | canopy | High |

Each phase must pass all tests (`moon test` in the relevant module) before proceeding.

---

## Phase 4a — Add traits to loom/core

**Goal:** Define `TreeNode` and `Renderable` in `dowdiness/loom/core` so any language's AST can implement them.

### Task 1: Add trait definitions to loom/core

**Files:**
- Create: `loom/loom/src/core/proj_traits.mbt`
- Modify: `loom/loom/src/core/moon.pkg` (may need warning suppression)

- [ ] **Step 1: Create `loom/loom/src/core/proj_traits.mbt`**

```moonbit
// Capability traits for projectional editing over arbitrary AST types.
// Language AST packages implement these; the editor framework consumes them
// via trait bounds without depending on any specific AST type.

///|
/// Tree structure capability — structural access for reconciliation and traversal.
pub(open) trait TreeNode {
  children(Self) -> Array[Self]
  same_kind(Self, Self) -> Bool
}

///|
/// Rendering + text capability — display and serialization for projectional editors.
pub(open) trait Renderable {
  kind_tag(Self) -> String
  label(Self) -> String
  placeholder(Self) -> String
  unparse(Self) -> String
}
```

- [ ] **Step 2: Run checks in loom**

```bash
cd loom/loom && moon check && moon test
```

Expected: pass. The traits have no implementations yet in loom — they're `pub(open)` so no warning for unused traits.

If there IS a warning for unused traits, add to `loom/loom/src/core/moon.pkg`:
```
warnings = "-9"
```
(or whichever code suppresses unused trait warnings — check the actual warning number)

- [ ] **Step 3: Update interfaces**

```bash
cd loom/loom && moon info && moon fmt
```

- [ ] **Step 4: Commit in loom submodule**

```bash
cd loom/loom
git add src/core/proj_traits.mbt src/core/moon.pkg src/core/pkg.generated.mbti
git commit -m "feat(core): add TreeNode and Renderable traits for projectional editing"
```

---

## Phase 4b — Add trait impls in lambda/ast

**Goal:** Implement `TreeNode` and `Renderable` for `@ast.Term` in the lambda/ast package (which owns the type and depends on loom).

### Task 2: Add trait impls to lambda/ast

**Files:**
- Create: `loom/examples/lambda/src/ast/proj_traits.mbt`
- Modify: `loom/examples/lambda/src/ast/moon.pkg` (add `dowdiness/loom/core` import)

- [ ] **Step 1: Update `loom/examples/lambda/src/ast/moon.pkg`**

Add `dowdiness/loom/core` to imports:

```json
import {
  "dowdiness/loom/core" @loomcore,
  "moonbitlang/core/json",
}
```

- [ ] **Step 2: Create `loom/examples/lambda/src/ast/proj_traits.mbt`**

```moonbit
// TreeNode and Renderable implementations for Term.
// These traits are defined in dowdiness/loom/core and enable
// projectional editors to work with the lambda AST generically.

///|
pub impl @loomcore.TreeNode for Term with children(self) {
  match self {
    Lam(_, body) => [body]
    App(f, a) => [f, a]
    Bop(_, l, r) => [l, r]
    If(c, t, e) => [c, t, e]
    Module(defs, body) => {
      let result : Array[Term] = []
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
pub impl @loomcore.TreeNode for Term with same_kind(self, other) {
  match (self, other) {
    (Int(_), Int(_)) => true
    (Var(_), Var(_)) => true
    (Lam(_, _), Lam(_, _)) => true
    (App(_, _), App(_, _)) => true
    (Bop(_, _, _), Bop(_, _, _)) => true
    (If(_, _, _), If(_, _, _)) => true
    (Module(_, _), Module(_, _)) => true
    (Unit, Unit) => true
    (Error(_), Error(_)) => true
    (Unbound(_), Unbound(_)) => true
    _ => false
  }
}

///|
pub impl @loomcore.Renderable for Term with kind_tag(self) {
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
pub impl @loomcore.Renderable for Term with label(self) {
  match self {
    Int(n) => n.to_string()
    Var(name) => name
    Lam(param, _) => "\u{03BB}" + param
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
pub impl @loomcore.Renderable for Term with placeholder(self) {
  match self {
    Int(_) => "0"
    Var(_) => "x"
    Lam(_, _) => "\u{03BB}x. x"
    App(_, _) => "f x"
    Bop(Plus, _, _) => "0 + 0"
    Bop(Minus, _, _) => "0 - 0"
    If(_, _, _) => "if 0 then 0 else 0"
    Module(_, _) => "let x = 0"
    Unit => "()"
    Unbound(_) => "x"
    Error(_) => "?"
  }
}

///|
pub impl @loomcore.Renderable for Term with unparse(self) {
  print_term(self)
}
```

- [ ] **Step 3: Run checks in lambda**

```bash
cd loom/examples/lambda && moon check && moon test
```

Expected: all pass.

- [ ] **Step 4: Update interfaces**

```bash
cd loom/examples/lambda && moon info && moon fmt
```

- [ ] **Step 5: Commit in lambda submodule**

```bash
cd loom/examples/lambda
git add src/ast/proj_traits.mbt src/ast/moon.pkg src/ast/pkg.generated.mbti
git commit -m "feat(ast): implement TreeNode and Renderable for Term"
```

- [ ] **Step 6: Push both loom commits and bump submodule in canopy**

```bash
cd loom && git push
cd .. && git add loom && git commit -m "chore: bump loom (TreeNode/Renderable in loom/core, impls in lambda/ast)"
```

---

## Phase 4c — Update canopy to use loom-defined traits

**Goal:** Remove `TreeNode`/`Renderable` from `projection/traits.mbt`, import from `@loomcore` instead. Move `SourceMap` to `framework/core/`. Move lambda-specific code to `lang/lambda/` packages.

### Task 3: Switch projection/ to use loom-defined traits

**Files:**
- Modify: `projection/traits.mbt` — remove trait definitions, re-export from loom
- Delete: `projection/traits_term.mbt` — impls now in lambda/ast
- Modify: `projection/moon.pkg` — may need adjustments
- Modify: `editor/sync_editor_tree_edit.mbt` — `@proj.Renderable` → `@loomcore.Renderable`

- [ ] **Step 1: Replace `projection/traits.mbt`**

```moonbit
// Traits re-exported from loom/core for backward compatibility.
// Canonical definitions: dowdiness/loom/core/proj_traits.mbt
// Canonical impls: dowdiness/lambda/ast/proj_traits.mbt

pub using @loomcore {
  trait TreeNode,
  trait Renderable,
}
```

> **Note:** Verify `pub using` works for traits. If not, consumers must import
> `@loomcore` directly. In that case, this file becomes a comment-only placeholder
> and all `@proj.TreeNode` / `@proj.Renderable` references switch to `@loomcore.TreeNode` etc.

- [ ] **Step 2: Delete `projection/traits_term.mbt`**

```bash
git rm projection/traits_term.mbt
```

The impls now live in `loom/examples/lambda/src/ast/proj_traits.mbt`.

- [ ] **Step 3: Run `moon check`**

Expected: errors in files using bare `TreeNode` / `Renderable`. These were previously
defined in-package; now they come from loom via `pub using`. If `pub using` with traits
works, bare names resolve package-wide. If not, add `using @loomcore { trait TreeNode, trait Renderable }` to each file that needs them:

- `projection/reconcile_ast.mbt`
- `projection/tree_editor_model.mbt`
- `projection/tree_editor_refresh.mbt`

And update `editor/sync_editor_tree_edit.mbt`:
- `@proj.Renderable` → `@loomcore.Renderable` (5 occurrences)

- [ ] **Step 4: Run full test suite**

```bash
moon test
```

Expected: all 517+ tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: switch to loom-defined TreeNode/Renderable, remove projection/traits_term.mbt"
```

---

### Task 4: Move SourceMap to framework/core/

**Files:**
- Move: `projection/source_map.mbt` (generic parts) → `framework/core/source_map.mbt`
- Create: `projection/source_map_token_spans.mbt` — lambda-specific `populate_token_spans` as standalone fn
- Modify: `projection/source_map_json.mbt` → move to `framework/core/source_map_json.mbt`
- Modify: `framework/core/moon.pkg` — add `@loomcore` dep (for Range)

- [ ] **Step 1: Add loom/core dep to framework/core/moon.pkg**

```
import {
  "dowdiness/loom/core" @loomcore,
}
```

- [ ] **Step 2: Create `framework/core/source_map.mbt`**

Copy the full SourceMap struct + all generic methods from `projection/source_map.mbt`.
Add `using @loomcore { type Range }` at top.
Remove `populate_token_spans`, `collect_token_spans_source_file`, `collect_token_spans_expr`
(those are lambda-specific).

- [ ] **Step 3: Create `projection/source_map_token_spans.mbt`**

Convert the lambda-specific methods to standalone functions:

```moonbit
// Lambda-specific token span extraction.
// SourceMap is now in framework/core; these are standalone functions.

///|
pub fn populate_token_spans(
  source_map : SourceMap,
  syntax_root : @seam.SyntaxNode,
  proj_root : ProjNode[@ast.Term],
) -> Unit {
  collect_token_spans_source_file(source_map, syntax_root, proj_root)
}

///|
fn collect_token_spans_source_file(
  source_map : SourceMap,
  syntax_root : @seam.SyntaxNode,
  proj_root : ProjNode[@ast.Term],
) -> Unit {
  // ... (same body as current SourceMap::collect_token_spans_source_file,
  //      but with `source_map` as first param instead of `self`)
}

///|
fn collect_token_spans_expr(
  source_map : SourceMap,
  syntax_node : @seam.SyntaxNode,
  proj_node : ProjNode[@ast.Term],
) -> Unit {
  // ... (same body as current SourceMap::collect_token_spans_expr,
  //      but with `source_map` as first param instead of `self`)
}
```

- [ ] **Step 4: Update callers of `populate_token_spans`**

In `editor/projection_memo.mbt`, change:
```moonbit
// Before:
prev_sm.populate_token_spans(syntax_root, root)
// After:
@proj.populate_token_spans(prev_sm, syntax_root, root)
```

(2 call sites in projection_memo.mbt)

- [ ] **Step 5: Update `projection/source_map.mbt`**

Replace the full file with re-export + backward compat:

```moonbit
// SourceMap re-exported from framework/core.
pub using @core { type SourceMap }
```

- [ ] **Step 6: Move `projection/source_map_json.mbt` → `framework/core/source_map_json.mbt`**

```bash
git mv projection/source_map_json.mbt framework/core/source_map_json.mbt
```

- [ ] **Step 7: Run `moon check` and fix import issues**

SourceMap methods are now on `@core.SourceMap`. Since `pub using @core { type SourceMap }`
makes the type available, bare `SourceMap` should work. Method calls like
`source_map.get_range(...)` should resolve since MoonBit dispatches methods on the
canonical type regardless of how it was imported.

- [ ] **Step 8: Move reconcile to framework/core/**

Now that TreeNode is in loom/core (not projection/), `reconcile[T : TreeNode]` can move to
`framework/core/`. Create `framework/core/reconcile.mbt` with the generic reconcile +
reconcile_children functions. Update `projection/reconcile_ast.mbt` to delegate:

```moonbit
// Backward-compat alias.
pub fn reconcile_ast(
  old : ProjNode[@ast.Term],
  new : ProjNode[@ast.Term],
  counter : Ref[Int],
) -> ProjNode[@ast.Term] {
  @core.reconcile(old, new, counter)
}
```

- [ ] **Step 9: Run full test suite**

```bash
moon test && moon build --target js
```

Expected: all pass.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "refactor: move SourceMap and reconcile to framework/core/"
```

---

### Task 5: Move lambda-specific projection builders to lang/lambda/proj/

**Files:**
- Create: `lang/lambda/proj/moon.pkg`
- Move: `projection/proj_node.mbt` (lambda builders) → `lang/lambda/proj/proj_node.mbt`
- Move: `projection/flat_proj.mbt` → `lang/lambda/proj/flat_proj.mbt`

- [ ] **Step 1: Create `lang/lambda/proj/moon.pkg`**

```json
import {
  "dowdiness/canopy/framework/core" @core,
  "dowdiness/lambda" @parser,
  "dowdiness/lambda/ast" @ast,
  "dowdiness/loom/core" @loomcore,
  "dowdiness/seam" @seam,
}
```

- [ ] **Step 2: Move proj_node.mbt lambda builders**

Move `syntax_to_proj_node`, `to_proj_node`, `rebuild_kind`, `parse_to_proj_node`,
`error_node_with_span`, `error_node_for_syntax`, `app_node`, `bop_node` from
`projection/proj_node.mbt` to `lang/lambda/proj/proj_node.mbt`.

Remove the `pub using @core { type ProjNode }` from the moved file (it goes via direct import).
Keep a `pub using` re-export in `projection/proj_node.mbt` if needed for backward compat.

Update callers: `@proj.syntax_to_proj_node` → `@lambda_proj.syntax_to_proj_node` etc.

- [ ] **Step 3: Move flat_proj.mbt**

Move `projection/flat_proj.mbt` → `lang/lambda/proj/flat_proj.mbt`.
This file already uses `@core.next_proj_node_id`, `@core.assign_fresh_ids`, `NodeId::from_int`.
It needs to import from `projection/` for `reconcile_ast` (or from `@core` if reconcile moved).

- [ ] **Step 4: Update lang/lambda/flat/ to import from lang/lambda/proj/**

`lang/lambda/flat/versioned_flat_proj.mbt` references `@proj.FlatProj`. After the move,
it should reference `@lambda_proj.FlatProj`.

- [ ] **Step 5: Run `moon check` and fix import chains**

The key change: `editor/projection_memo.mbt` uses `@proj.to_flat_proj`, `@proj.to_flat_proj_incremental`,
`@proj.reconcile_flat_proj`. These now come from `@lambda_proj`.

- [ ] **Step 6: Run full test suite**

```bash
moon test && moon build --target js
```

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor: move lambda projection builders to lang/lambda/proj/"
```

---

### Task 6: Move lambda-specific edit handlers to lang/lambda/edits/

**Files:**
- Create: `lang/lambda/edits/moon.pkg`
- Move: `projection/text_edit.mbt` + all `projection/text_edit_*.mbt` → `lang/lambda/edits/`
- Move: `projection/tree_lens.mbt` → `lang/lambda/edits/tree_lens.mbt`
- Move: `projection/scope.mbt`, `projection/free_vars.mbt`, `projection/actions.mbt` → `lang/lambda/edits/`

- [ ] **Step 1: Create `lang/lambda/edits/moon.pkg`**

```json
import {
  "dowdiness/canopy/framework/core" @core,
  "dowdiness/canopy/lang/lambda/proj" @lambda_proj,
  "dowdiness/lambda/ast" @ast,
  "dowdiness/loom/core" @loomcore,
  "dowdiness/seam" @seam,
  "moonbitlang/core/immut/hashset" @immut/hashset,
}
```

- [ ] **Step 2: Move all text_edit files**

```bash
git mv projection/text_edit.mbt lang/lambda/edits/
git mv projection/text_edit_binding.mbt lang/lambda/edits/
git mv projection/text_edit_commit.mbt lang/lambda/edits/
git mv projection/text_edit_delete.mbt lang/lambda/edits/
git mv projection/text_edit_drop.mbt lang/lambda/edits/
git mv projection/text_edit_middleware.mbt lang/lambda/edits/
git mv projection/text_edit_refactor.mbt lang/lambda/edits/
git mv projection/text_edit_rename.mbt lang/lambda/edits/
git mv projection/text_edit_structural.mbt lang/lambda/edits/
git mv projection/text_edit_utils.mbt lang/lambda/edits/
git mv projection/text_edit_wrap.mbt lang/lambda/edits/
git mv projection/tree_lens.mbt lang/lambda/edits/
git mv projection/scope.mbt lang/lambda/edits/
git mv projection/free_vars.mbt lang/lambda/edits/
git mv projection/actions.mbt lang/lambda/edits/
```

- [ ] **Step 3: Fix imports in moved files**

All moved files used bare `NodeId`, `ProjNode`, `SourceMap`, `FocusHint`, `DropPosition`
from the same package. Now they need imports:

Add to each file (or use a shared pattern):
```moonbit
using @core { type NodeId, type ProjNode }
using @loomcore { type Range }
```

`FocusHint` and `DropPosition` need to come from wherever they're defined (currently
`projection/types.mbt` or `framework/core/types.mbt`).

- [ ] **Step 4: Update editor/tree_edit_bridge.mbt**

Change imports from `@proj.compute_text_edit`, `@proj.EditContext`, `@proj.TreeEditOp`,
`@proj.FocusHint` to `@lambda_edits.*`.

- [ ] **Step 5: Update editor/tree_edit_json.mbt**

Change `@proj.TreeEditOp` → `@lambda_edits.TreeEditOp`.

- [ ] **Step 6: Move test files**

```bash
git mv projection/text_edit_wbtest.mbt lang/lambda/edits/
git mv projection/tree_lens_wbtest.mbt lang/lambda/edits/
git mv projection/scope_wbtest.mbt lang/lambda/edits/
git mv projection/free_vars_wbtest.mbt lang/lambda/edits/
git mv projection/actions_wbtest.mbt lang/lambda/edits/
git mv projection/text_lens_regression_wbtest.mbt lang/lambda/edits/
```

- [ ] **Step 7: Run `moon check` iteratively and fix all import errors**

This is the most error-prone step. Run `moon check` after each batch of fixes.
Most errors will be "type X not found" → add the right import.

- [ ] **Step 8: Run full test suite**

```bash
moon test && moon build --target js
```

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "refactor: move lambda edit handlers, scope, actions to lang/lambda/edits/"
```

---

### Task 7: Clean up projection/ and update backward compat

**Goal:** `projection/` should now contain only re-exports and generic code. Verify and clean up.

- [ ] **Step 1: Audit remaining projection/ files**

```bash
ls projection/*.mbt | grep -v '_test\|_wbtest\|_benchmark'
```

Expected remaining files:
- `types.mbt` — re-exports NodeId, keeps DropPosition/FocusHint
- `traits.mbt` — re-exports TreeNode/Renderable from loom
- `proj_node.mbt` — re-exports ProjNode from @core
- `source_map.mbt` — re-exports SourceMap from @core
- `source_map_token_spans.mbt` — lambda-specific standalone fn (consider moving to lang/lambda/proj/)
- `reconcile_ast.mbt` — backward compat alias
- `tree_editor.mbt` — generic (no @ast refs)
- `tree_editor_model.mbt` — mostly generic (has `is_valid_drop` with @ast.Term)
- `tree_editor_refresh.mbt` — generic

- [ ] **Step 2: Verify no @ast refs in remaining generic files**

```bash
grep -l '@ast\|@parser\|@syntax' projection/*.mbt | grep -v '_test\|_wbtest\|_benchmark'
```

Move any remaining @ast-dependent files or functions.

- [ ] **Step 3: Remove unused imports from projection/moon.pkg**

After moving lambda-specific files, `projection/` may no longer need `@parser`, `@ast`,
`@syntax`, `@seam`. Remove them if unused.

- [ ] **Step 4: Run full test suite + JS build**

```bash
moon test && moon build --target js
```

- [ ] **Step 5: Update `moon info && moon fmt`**

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: clean up projection/ — remove unused lambda imports"
```

---

## Notes

### Submodule commit workflow

Phases 4a and 4b modify the loom submodule. The workflow is:
1. Make changes inside `loom/`
2. Commit inside the submodule
3. Push the submodule to its remote
4. In canopy root, `git add loom` to update the submodule pointer
5. Commit the pointer update in canopy

### Test counts

- loom/loom: ~126 tests
- loom/examples/lambda: ~405 tests
- canopy: ~517 tests
- All must pass after each task

### Backward compatibility

`projection/` retains `pub using` re-exports so that `@proj.NodeId`, `@proj.ProjNode`,
`@proj.SourceMap`, `@proj.TreeNode`, `@proj.Renderable` continue to work. Consumers
can migrate to `@core.*` or `@loomcore.*` at their own pace.

### `DropPosition` and `FocusHint`

These enums stay in `projection/types.mbt` (local definitions, not re-exports) because
`pub using` makes enums abstract. They may eventually move to `framework/core/` if
MoonBit fixes this limitation, or to `lang/lambda/edits/` since `TreeEditOp` uses them.

### `tree_editor.mbt` and `TreeEditOp`

`tree_editor.mbt` pattern-matches on `TreeEditOp` which has lambda-specific variants
(`WrapInLambda`, `WrapInApp`, etc.). After Task 6 moves `TreeEditOp` to `lang/lambda/edits/`,
`tree_editor.mbt` needs to import it — or be split into generic operations (expand/collapse/select)
and lambda-specific operations. This split is deferred to a follow-up.
