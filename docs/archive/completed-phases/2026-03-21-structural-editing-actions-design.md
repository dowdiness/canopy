# Structural Editing Actions — Design Spec

**Date:** 2026-03-21
**Status:** Complete
**Scope:** Add structural editing actions with context-sensitive UI for desktop (keyboard) and mobile (touch)

## Problem

The projectional editor currently has only two structural editing actions with UI bindings: Delete (Backspace) and Wrap in λ (Cmd+L). This is too limited for productive structural editing.

## Goals

- Provide a complete structural editing vocabulary for the lambda calculus AST
- Context-sensitive action filtering — only show valid actions per node type
- Keyboard-first desktop experience (which-key overlay, mnemonic keys)
- Touch-native mobile experience (floating action sheet, large touch targets)
- Shared action model across both presentation layers

## AST Node Types (Reference)

```
Int(Int) | Var(VarName) | Lam(VarName, Term) | App(Term, Term)
Bop(Bop, Term, Term) | If(Term, Term, Term) | Module(Array[(VarName, Term)], Term)
Unit | Unbound(VarName) | Error(String)
```

`Bop` enum: `Plus`, `Minus` (may grow — all menus/cycles must derive from the enum).

### Projection-time vs semantic AST

The projection pipeline builds `ProjNode` trees directly from CST via `syntax_to_proj_node`. Name resolution (`resolve()`) is a **separate pass not integrated into the projection pipeline** — it produces `Unbound` nodes in the semantic AST but these never appear as ProjNode kinds. At projection time, all variable references are `Var`, never `Unbound`. Actions targeting `Unbound` are deferred until name resolution is integrated.

### Module is root-only

The grammar creates `Module` nodes only from top-level `SourceFile` `LetDef*` children (`term_convert` and `to_proj_node`). Nested `Module` nodes do not occur in practice. This design is scoped to **root Module + def/body positions only**. "Nearest enclosing Module" always means the root.

## Addressing: NodeId vs Binding Identity

### Expression nodes: NodeId

`NodeId` identifies `ProjNode` entries (expression-level AST nodes). All expression-targeted actions use `NodeId`.

### Let-bindings: Binding NodeId from FlatProj

`FlatProj.defs` stores `Array[(String, ProjNode, Int, NodeId)]` where the 4th element is a **dedicated binding NodeId** allocated by `to_flat_proj` (line 26: `NodeId(next_proj_node_id(counter))`). This ID is distinct from the init expression's `ProjNode.node_id` and is preserved across reparses by `reconcile_flat_proj` (which matches by name).

Module-level actions (DeleteBinding, DuplicateBinding, MoveBinding, InlineAllUsages) target bindings via this **binding NodeId**.

**Known limitation:** `reconcile_flat_proj` matches defs by name, so renaming a binding produces a fresh binding NodeId. This means selection/UI state on a binding is lost after rename. Acceptable for initial implementation — can be improved by matching on position or content hash later.

**Known inconsistency:** `FlatProj::from_proj_node` (used for round-tripping) reuses `init_child.node_id` as the binding ID instead of the dedicated ID. This doesn't affect the primary `to_flat_proj`/`to_flat_proj_incremental` path used by the editor pipeline.

### Binding selection model

There is no `ProjNode` for a let-binding as a whole — only the init expression has a `ProjNode` (as a child of the root Module `ProjNode`). The binding's name token is stored on the Module's SourceMap token_spans as `"name:0"`, `"name:1"`, etc.

**How a user selects a binding:** The user selects the init expression's ProjNode (a child of the Module node). The system detects that this node is at a def position (not the body) by checking whether the selected NodeId matches any `flat_proj.defs[i].1.node_id`. When a match is found, `NodeContext` is populated:

```
NodeContext {
  is_let_binding: true,
  binding_node_id: Some(flat_proj.defs[i].3),  // the dedicated binding NodeId
  binding_def_index: Some(i),                   // position in defs array
  module_node_id: Some(root_module_id),
}
```

This context determines whether binding-level actions (Delete binding, Duplicate, Move, Inline all) appear in the action menu alongside the init expression's own actions. The init expression's actions (Extract, Wrap, etc.) still apply to the init expression itself; binding actions apply to the whole `let name = expr` entry.

## Action Set

### Tier 1: Core Actions

| # | Action | Applies to | Behavior |
|---|--------|-----------|----------|
| 1 | **Extract to let** | Any expression node (not Unit/Error) | Prompt for name (validated: non-empty, valid identifier, no conflict with existing binding names in root Module). Insert `let name = expr` at the end of the root Module's defs. Replace selected expression with `Var(name)`. **Reject** if extracted expression contains free variables that are lambda-bound at the extraction site (see Free Variable Analysis). If no root Module exists (bare expression program), wrap the program in `Module([(name, expr)], original_body)`. After completion, cursor moves to the new `Var(name)` reference. |
| 2 | **Inline definition** | `Var` referencing a `let` binding in root Module | Resolve which binding the `Var` refers to: walk the root Module's defs array in sequential order — each def `i` is in scope for defs `i+1..n` and the body. Find the last def with matching name that is positioned before the `Var`'s containing def/body. Replace the `Var` occurrence with the binding's init expression text (via `@ast.print_term`). If this was the sole usage of that binding, remove the `let` binding. After completion, cursor moves to the start of the inlined expression. |
| 3 | **Rename** | `Lam` parameter or `let` binding name, or any `Var` | From binder (`Lam` param): rename the binder and all bound `Var` occurrences within the body, respecting shadowing (inner scopes that re-bind the same name are untouched). From `let` binding name: rename the binding and all `Var` references in subsequent defs and the Module body, respecting shadowing. From usage (`Var`): resolve to the binding site (Lam param or Module let-def) using the resolution rules above, then apply the same rename. Prompt for new name (validated: non-empty, valid identifier). Implementation: produces multiple `SpanEdit` entries — one for the binder token span, one for each bound `Var` node span. **Binder token spans:** For Lam params, use `source_map.get_token_span(lam_node_id, "param")`. For Module let-def names, use `source_map.get_token_span(module_node_id, "name:" + def_index.to_string())` — let-name tokens are stored on the root Module node with index-based roles (`"name:0"`, `"name:1"`, etc.), not on the binding NodeId. |
| 4 | **Unwrap** | `Lam`, `App`, `Bop`, `If` | Remove one structural layer, keeping a child. `Lam(x, body)` → `body`. `App(f, x)` → prompt: keep function or argument. `Bop(op, a, b)` → prompt: keep left or right. `If(c, t, e)` → prompt: keep condition, then-branch, or else-branch. Implementation: re-render the kept child via `@ast.print_term`, replace the parent's span. |
| 5 | **Swap children** | `Bop`, `If` | `Bop(op, a, b)` → `Bop(op, b, a)`. `If(c, t, e)` → `If(c, e, t)` (swap then/else, keep condition). Not offered for `App` — swapping function and argument is almost always semantically invalid. Implementation: rebuild the Term with swapped children, print, replace parent span. |
| 6 | **Delete** | Any expression node | (Exists) Replace with type-appropriate placeholder. |
| 7 | **Delete binding** | `let` binding in root Module (via binding NodeId) | Remove the entire `let name = expr\n` text span from the source. If other bindings or the body reference this name, they become unbound (user's responsibility). Implementation: compute the text range covering `let name = expr` plus trailing newline, emit a single `SpanEdit` with empty insertion. |
| 8 | **Inline all usages** | `let` binding in root Module (via binding NodeId) | Find all `Var` nodes that reference this binding's name (in subsequent defs and body, respecting shadowing). Replace each with the binding's init expression text. Then delete the binding. Composition of multiple `InlineDefinition` + `DeleteBinding`. Implementation: produces N+1 `SpanEdit` entries (N Var replacements + 1 binding deletion). |

### Tier 2: Composition Actions

| # | Action | Applies to | Behavior |
|---|--------|-----------|----------|
| 9 | **Wrap in λ** | Any node | (Exists) `λx. <selected>`. Prompt for parameter name. |
| 10 | **Wrap in if** | Any node | `if <cond_placeholder> then <selected> else <else_placeholder>`. Condition placeholder: `0`. Else placeholder: `0`. After completion, cursor moves to the condition placeholder position. |
| 11 | **Wrap in Bop** | Any node | Submenu derived from `Bop` enum variants. Result: `<selected> <op> <placeholder>`. Placeholder: `0`. After completion, cursor moves to the right-operand placeholder position. |
| 12 | **Wrap in App** | Any node | (Exists, needs key binding) `<selected> <placeholder>`. Placeholder: `a`. After completion, cursor moves to the argument placeholder position. |
| 13 | **Change operator** | `Bop` only | Submenu showing all `Bop` variants (derived from enum). Select target operator explicitly — no blind cycling. Implementation: rebuild Bop Term with new operator, print, replace span. |

### Tier 3: Module-level Actions

| # | Action | Applies to | Behavior |
|---|--------|-----------|----------|
| 14 | **Add binding** | Root Module node | Insert `let x = 0\n` at end of defs list (before body). Uses `InsertChild` internally. After completion, cursor moves to the init placeholder position. |
| 15 | **Duplicate binding** | `let` binding in Module (via binding NodeId) | Copy the binding text, insert below with `_copy` suffix on the name. |
| 16 | **Move binding up/down** | `let` binding in Module (via binding NodeId) | Swap position with adjacent binding. **Reject if the move would break sequential scoping.** Validation checks (let `A` = moving binding, `B` = adjacent binding): (1) Does `B.init` reference `A.name` as a free variable? If so, swapping changes whether `A` is in scope for `B`. (2) Does `A.init` reference `B.name` as a free variable? Same issue in reverse. (3) **Name capture check:** If `A.name == B.name` (duplicate top-level names — the grammar allows this), the swap silently retargets all references between the two defs from one shadow to the other. Reject in this case. (4) If any def between `A` and `B` references either `A.name` or `B.name`, the swap may change resolution for that intermediate def. For simplicity, initial implementation rejects any move where `A.name` or `B.name` appears free in either binding's init. |

## Context Menu Filtering

Only valid actions appear for each node type. Hidden keys are not shown in the which-key overlay / action sheet.

| Node type | Available actions |
|-----------|------------------|
| `Int` | Extract, Wrap(λ/if/Bop/App), Delete |
| `Var` | Extract, Inline, Rename, Wrap(λ/if/Bop/App), Delete |
| `Lam` | Extract, Rename, Unwrap, Wrap(λ/if/Bop/App), Delete |
| `App` | Extract, Unwrap, Wrap(λ/if/Bop/App), Delete |
| `Bop` | Extract, Unwrap, Swap, Change op, Wrap(λ/if/App), Delete |
| `If` | Extract, Unwrap, Swap, Wrap(λ/Bop/App), Delete |
| `Module` | Add binding |
| `Unit` | Wrap(λ/if/Bop/App), Delete |
| `Error` | Delete |

**Binding overlay:** When the selected node is a Module def's init expression (`NodeContext.is_let_binding == true`), the action menu shows **both** the init expression's actions (from the table above) **and** the binding-level actions: Rename (binding name), Duplicate, Move ↑/↓, Inline all usages, Delete binding. These are visually separated in the menu (e.g., a divider between "expression actions" and "binding actions").

**Notes:**
- `Unbound` is deferred — it does not appear in projection-time ProjNodes.
- Wrap(λ) and Wrap(App) are available on all expression nodes including self-wrapping.

## UI Design

### Shared Model

```
get_actions_for_node(node_kind: Term, context: NodeContext) -> Array[Action]

struct Action {
  id: String          // "extract_to_let", "rename", etc.
  label: String       // "Extract to let", "Rename"
  icon: String        // icon identifier
  mnemonic: Char      // keyboard shortcut key
  group: ActionGroup  // Core, Wrap, Module, Binding
  needs_input: Bool   // true for Extract, Rename (prompt for name)
}

struct NodeContext {
  is_let_binding: Bool       // true if selected node is a def's init expression
  binding_node_id: NodeId?   // FlatProj binding NodeId, if applicable
  binding_def_index: Int?    // position in FlatProj.defs array
  module_node_id: NodeId?    // root Module's NodeId, if one exists
}
```

### Desktop: Keyboard-First (Which-Key Overlay)

1. **Select node** via arrow keys or click
2. Press **Space** to open action overlay
3. Overlay appears **on the selected node**, showing only available actions with mnemonic keys:
   - `e` Extract to let
   - `i` Inline
   - `r` Rename
   - `u` Unwrap
   - `s` Swap children
   - `d` Delete / Delete binding
   - `c` Change operator
   - `w` Wrap → second level: `l` lambda, `i` if, `b` Bop, `a` App
   - `b` Binding → second level (only shown for def inits): `r` rename, `d` duplicate, `↑`/`↓` move, `i` inline all, `x` delete
   - `a` Add binding (only shown for Module node)
4. Press mnemonic key to execute (only enabled keys shown, based on context filtering)
5. **Esc** dismisses the overlay
6. If action needs input (Extract, Rename): inline text input appears at the node
7. If action needs choice (Unwrap on Bop/If, Change op, Wrap in Bop): second-level submenu appears

### Mobile: Touch-Native (Floating Action Sheet)

1. **Tap** to select a node
2. **Long press** or **double-tap** to open action sheet
3. Floating action sheet appears **near the selected node**:
   - Positioned to avoid off-screen clipping (shift if near edges)
   - Minimum **44px touch targets** (Apple HIG)
   - **Icons + labels** for each action
   - Wrap actions in a collapsible sub-row (tap "Wrap..." to expand)
   - Binding actions in a separate section (when applicable)
4. **Tap an action** to execute
5. **Tap outside** to dismiss
6. **Swipe on selected node** as shortcut for Delete (most common destructive action)
7. If action needs input: inline text input appears at the node

### Prompt Input Validation

When actions require a name (Extract to let, Rename):
- Non-empty string required
- Must be a valid identifier (matches lambda parser's identifier rules: `[a-zA-Z_][a-zA-Z0-9_]*`)
- Must not conflict with existing binding names in the target scope
- Validation errors shown inline below the input field

## Post-Edit Cursor Positioning

After structural edits, the editor needs to move the cursor to a meaningful position. This replaces the current behavior where `apply_tree_edit` always restores the old cursor position (line 43: `self.move_cursor(old_cursor)`).

### Approach: FocusHint returned alongside SpanEdits

Extend `compute_text_edit` return type to include a cursor hint:

```moonbit
pub(all) enum FocusHint {
  RestoreCursor                  // keep cursor where it was (current behavior)
  MoveCursor(position~ : Int)    // move cursor to this position (pre-edit coordinates)
}

// Updated return type:
pub fn compute_text_edit(...) -> Result[(Array[SpanEdit], FocusHint)?, String]
```

**Integration with `apply_tree_edit`:** After applying all `SpanEdit` entries in reverse document order, `apply_tree_edit` handles the `FocusHint`:

```moonbit
match focus_hint {
  RestoreCursor => self.move_cursor(old_cursor)
  MoveCursor(position~) => {
    // Remap position through applied edits to get post-edit coordinates.
    // Since edits are sorted reverse by start position:
    let mut adjusted = position
    for edit in edits {  // already sorted reverse
      if edit.start <= position {
        if position < edit.start + edit.delete_len {
          // Position is inside a deleted region — move to edit start
          adjusted = edit.start
        } else {
          // Position is after the edit — shift by length delta
          adjusted = adjusted + edit.inserted.length().to_int() - edit.delete_len
        }
      }
    }
    self.move_cursor(adjusted)
  }
}
```

This uses only the existing `SyncEditor::move_cursor(position: Int)` API — no new editor primitives needed.

**Why `MoveCursor` instead of `FocusSpan`:** `SyncEditor` currently only exposes `move_cursor(position: Int)`, not a range-selection API. Moving the cursor to the start of a placeholder is sufficient — the user can then enter inline-edit mode by typing. Range selection can be added later if needed.

**Per-action cursor behavior:**

| Action | FocusHint |
|--------|-----------|
| Extract to let | `MoveCursor` to the start of inserted `Var(name)` |
| Inline | `MoveCursor` to the start of inlined expression |
| Rename | `RestoreCursor` |
| Unwrap | `MoveCursor` to the start of kept child |
| Swap | `RestoreCursor` |
| Delete | `RestoreCursor` |
| Delete binding | `RestoreCursor` |
| Inline all usages | `RestoreCursor` |
| Wrap in λ/if/Bop/App | `MoveCursor` to the start of first placeholder |
| Change operator | `RestoreCursor` |
| Add binding | `MoveCursor` to the start of init placeholder |
| Duplicate binding | `MoveCursor` to the start of duplicated init |
| Move binding | `RestoreCursor` |

### Placeholder convention

All wrap and insert operations use **parseable placeholders** from the existing `placeholder_text_for_kind` function: `0` for Int positions, `a` for Var positions, etc. No `_` hole syntax — the source must always be parseable. The cursor hint positions the cursor on the placeholder so the user can immediately type over it via inline-edit. Tab-to-next-placeholder is deferred.

## Free Variable Analysis

Required for Extract to let validation.

```moonbit
fn free_vars(term: @ast.Term, env: @immut/hashset.HashSet[String]) -> @immut/hashset.HashSet[String]
```

**Scoping rules (matching `resolve.mbt`):**
- `Var(x)`: if `x ∈ env` → bound (not free). If `x ∉ env` → free.
- `Lam(x, body)`: recurse into body with `env ∪ {x}`.
- `Module(defs, body)`: sequential scoping. For each def `(name_i, init_i)`:
  - Compute `free_vars(init_i, env_so_far)` — `name_i` is NOT in scope for its own init.
  - Add `name_i` to `env_so_far` for subsequent defs.
  - Compute `free_vars(body, env_with_all_defs)`.
- `App(f, a)`, `Bop(_, l, r)`: union of children's free vars.
- `If(c, t, e)`: union of all three children's free vars.
- `Int`, `Unit`, `Error`, `Unbound`: empty set.

### Extract validation

Given expression `e` selected at def index `k` (or in the Module body) within root Module with defs `d_0..d_n`:

1. Build two environments:
   - `module_env`: Module def names in scope at the extraction site.
     - If `e` is in `d_k.init`: `module_env = { d_0.name, ..., d_{k-1}.name }`.
     - If `e` is in the Module body: `module_env = { d_0.name, ..., d_n.name }`.
   - `lam_env`: Lam parameter names in scope at the extraction site (collected by walking up the AST from `e` through enclosing Lam nodes).
2. Compute `fv = free_vars(e, module_env ∪ lam_env)`.
   - This gives truly unresolved names — variables not bound by any Module def or enclosing Lam.
3. Compute `lam_captured = free_vars(e, module_env) \ fv`.
   - These are names that are lambda-bound at the extraction site but would become unbound if hoisted to Module level.
   - Equivalently: `lam_captured = free_vars(e, module_env) - free_vars(e, module_env ∪ lam_env)`. In practice, just compute `free_vars(e, module_env)` and check which of the results are in `lam_env`.
4. If `lam_captured` is non-empty, **reject** — the expression captures lambda-bound variables that would become unbound at Module level.
5. If `lam_captured` is empty, **allow** — names in `fv` (already-unresolved names) stay unresolved regardless of position, so hoisting doesn't change their status.

## Implementation Scope

### MoonBit (projection/ and editor/)

1. Extend `TreeEditOp` enum with new variants
2. Update `compute_text_edit` return type to `Result[(Array[SpanEdit], FocusHint)?, String]`; implement cases for each new operation
3. Add `get_actions_for_node` filtering function (new file: `projection/actions.mbt`)
4. Extend `parse_tree_edit_op` JSON parsing for all new variants
5. Add `free_vars` utility (new file: `projection/free_vars.mbt`)
6. Add scope resolution utilities: `resolve_binder`, `find_usages` (new file: `projection/scope.mbt`)
7. Update `TreeEditorState::apply_edit` for UI state handling of each new variant
8. Update `SyncEditor::apply_tree_edit` to use `FocusHint` for post-edit cursor positioning (replace `self.move_cursor(old_cursor)` with FocusHint-based remapping)
9. Update existing `compute_text_edit` cases (Delete, WrapInLambda, WrapInApp, etc.) to return `(edits, RestoreCursor)` for backward compatibility

### TypeScript (examples/ideal/web/)

1. Action overlay component (which-key style, desktop)
2. Action sheet component (floating, mobile)
3. Shared action filtering logic (calls `get_actions_for_node` via FFI)
4. Keybinding: Space to open overlay on selected node
5. Touch handlers: long press / double-tap
6. Inline text input for Extract/Rename prompts
7. NodeContext population: detect when selected node is a Module def init

### New TreeEditOp Variants

```moonbit
// Core
ExtractToLet(node_id~ : NodeId, var_name~ : String)
InlineDefinition(node_id~ : NodeId)
Rename(node_id~ : NodeId, new_name~ : String)
Unwrap(node_id~ : NodeId, keep_child_index~ : Int)
SwapChildren(node_id~ : NodeId)
DeleteBinding(binding_node_id~ : NodeId)
InlineAllUsages(binding_node_id~ : NodeId)

// Composition
WrapInIf(node_id~ : NodeId)
WrapInBop(node_id~ : NodeId, op~ : @ast.Bop)
ChangeOperator(node_id~ : NodeId, new_op~ : @ast.Bop)

// Module-level
AddBinding(module_node_id~ : NodeId)
DuplicateBinding(binding_node_id~ : NodeId)
MoveBindingUp(binding_node_id~ : NodeId)
MoveBindingDown(binding_node_id~ : NodeId)
```

(Delete, WrapInLambda, WrapInApp already exist.)

### JSON Wire Formats

```json
{ "type": "ExtractToLet", "node_id": 5, "var_name": "x" }
{ "type": "InlineDefinition", "node_id": 5 }
{ "type": "Rename", "node_id": 5, "new_name": "y" }
{ "type": "Unwrap", "node_id": 5, "keep_child_index": 0 }
{ "type": "SwapChildren", "node_id": 5 }
{ "type": "DeleteBinding", "binding_node_id": 5 }
{ "type": "InlineAllUsages", "binding_node_id": 5 }
{ "type": "WrapInIf", "node_id": 5 }
{ "type": "WrapInBop", "node_id": 5, "op": "Plus" }
{ "type": "ChangeOperator", "node_id": 5, "new_op": "Minus" }
{ "type": "AddBinding", "module_node_id": 5 }
{ "type": "DuplicateBinding", "binding_node_id": 5 }
{ "type": "MoveBindingUp", "binding_node_id": 5 }
{ "type": "MoveBindingDown", "binding_node_id": 5 }
```

## Dependencies

- **Free-variable analysis:** `free_vars(term, env) -> Set[VarName]` — sequential Module scoping as described above.
- **Scope resolution:** `resolve_binder(var_name, var_position, flat_proj) -> BindingSite?` — walks root Module defs in sequential order to find the binding that is in scope at the given position. Returns `LamBinder(NodeId)` or `ModuleBinder(binding_node_id, def_index)`.
- **Usage finding:** `find_usages(var_name, scope_start_index, flat_proj, registry) -> Array[NodeId]` — finds all `Var` nodes referencing the given name from `scope_start_index` onward in the Module defs + body, respecting shadowing by later defs or inner Lam params.

## Concurrent Editing (CRDT)

All structural edits route through the text CRDT as `SpanEdit[]`. Concurrent structural edits from different peers merge at the text level via FugueMax. This guarantees convergence of the text, but the merged text may not parse into a semantically valid AST (e.g., Peer A extracts a node while Peer B deletes it). This is acceptable — the parser produces `Error` nodes for malformed regions, and users can resolve conflicts structurally.

## Out of Scope

- `Unbound` node actions (requires name resolution integration into projection pipeline)
- Nested Module handling (grammar is root-only)
- Tab-to-next-placeholder navigation (initial implementation focuses one placeholder)
- Range selection via FocusHint (SyncEditor only has `move_cursor(Int)`, not selection API)
- Multi-node selection actions
- Custom user-defined actions
- Beta-reduction / eta-expansion
- Undo/redo (already exists via text CRDT)
