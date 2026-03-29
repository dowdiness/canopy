# Edit Action Progression

## Two Layers of Structural Editing

Canopy has two representations for structural edits:

**EditAction** — cursor-relative, keyboard-driven, no NodeId. A small enum representing what the user intends to do at the current cursor position. Maps trivially to TreeEditOp by resolving the cursor NodeId.

**TreeEditOp** — node-specific, mouse-driven, carries NodeId. The full vocabulary of structural operations with tested text-computation handlers. The backend that EditAction delegates to.

EditAction starts small (core structural operations) and grows over time as keyboard workflows are designed for more complex operations. Each promotion from TreeEditOp-only to EditAction is a deliberate decision to add keyboard-driven access to an operation.

---

## Current EditAction (Phase 1)

The initial EditAction enum covers operations that are context-free — they need only the focused node and its immediate structure:

- **Delete** — replace with placeholder hole
- **WrapLam, WrapApp, WrapIf, WrapBop** — wrap focused node in a new constructor
- **Unwrap** — remove a level of nesting, keeping one child
- **SwapChildren** — swap operands in Bop, or swap branches in If (backend supports these two constructors only)
- **ChangeOperator** — toggle binary operator
- **CommitEdit** — commit inline-edited text

These operations share a property: they require only the cursor NodeId and (for wrap/unwrap) the immediate children structure. No scope analysis, no multi-node coordination, no FlatProj lookup.

**Suppressed for certain node types:** Delete, Wrap, and Unwrap are not offered for Hole nodes (already a placeholder — deleting would produce a meaningless substitution) or Module nodes (Module uses dedicated binding-level operations from Tier A). This matches the existing action filter policy.

---

## Deferred Operations

### Tier A: Module Binding Operations

**Operations:** AddBinding, DeleteBinding, DuplicateBinding, MoveBindingUp, MoveBindingDown

**Why deferred:** These operate at the module level, not the cursor level. They require FlatProj — the flattened representation of a Module's let-bindings — to determine indices, boundaries, and ordering. MoveBindingUp and MoveBindingDown additionally require free-variable analysis to prevent scope violations (moving a binding above the binding it depends on).

**What's needed to promote:**

1. **Module-aware cursor context.** The Zipper's PositionRole already distinguishes LetDefinition and LetBody. The cursor must be on a binding (PositionRole = LetDefinition) for these operations to be available.

2. **FlatProj access in dispatch.** The dispatch function needs access to FlatProj, currently available via `SyncEditor::get_flat_proj()`. This is a getter call, not a new dependency.

3. **Scope guard for reordering.** MoveBindingUp/Down must check whether the binding at the destination position depends on or is depended upon by the moving binding. This requires free-variable analysis, which exists in the compute handlers.

**Keyboard mapping:** natural candidates for `Alt+Up` / `Alt+Down` (reorder), `Ctrl+D` (duplicate), `Ctrl+Backspace` (delete binding), `Ctrl+Enter` (add binding).

**Promotion path:** Add `MoveBindingUp`, `MoveBindingDown`, `DeleteBinding`, `DuplicateBinding`, `AddBinding` as EditAction variants. Dispatch maps to the corresponding TreeEditOp. The compute handlers already handle all the complexity — promotion is just adding enum variants and keyboard bindings.

---

### Tier B: Drop / Relocate

**Operation:** Drop(source, target, position)

**Why deferred:** Drop requires TWO NodeIds (source and target) plus a DropPosition. EditAction is cursor-relative — it operates on one NodeId (the cursor). Drop is fundamentally a two-position operation.

**What's needed to promote:**

1. **Two-cursor interaction model.** One approach: the cursor marks the source, a separate "target" selection marks the destination. Another: a modal workflow — "cut" marks the source, then "paste at cursor" provides the target.

2. **The cut/paste model.** This fits EditAction naturally:
   - `Cut` — removes the focused node, stores it in a clipboard (as NodeId + source text)
   - `PasteAt(DropPosition)` — inserts the clipboard content at the cursor position (Before, After, or Inside)
   - These are two separate EditActions, each cursor-relative

3. **DropPosition in the Zipper.** PositionRole already tells you what position you're in. For pasting, the UI can offer Before/After/Inside based on the cursor's context.

**Promotion path:** Add `Cut` and `PasteAt(DropPosition)` as EditAction variants. `Cut` maps to removing the node's text and storing it. `PasteAt` maps to inserting stored text at the cursor position. The existing `compute_drop` handler's logic applies to both steps. This is more complex than a single TreeEditOp mapping — it requires clipboard state in LambdaEditorState.

---

### Tier C: Refactoring Operations

**Operations:** ExtractToLet, InlineDefinition, InlineAllUsages, Rename

**Why deferred:** These require deep scope analysis — free-variable computation, binder resolution, usage discovery, lambda-capture checking. They also produce multiple coordinated text edits across different parts of the document. Each operation has multiple code paths depending on context (lambda-bound vs. module-bound, sole usage vs. multiple usages, node-in-def vs. node-in-body).

**What's needed to promote each:**

#### ExtractToLet(VarName)
- **Scope guard:** must check that the extracted expression has no free variables that are lambda-captured (would change semantics when moved to module level)
- **Context-dependent editing:** three different edit strategies depending on whether there's a module, whether the node is in a definition or the body
- **User input:** requires a variable name from the user (dialog or inline prompt)
- **Promotion path:** Add `ExtractToLet(VarName)` to EditAction. Dispatch maps to `TreeEditOp::ExtractToLet(cursor, name)`. The compute handler does the scope checking. The variable name comes from a prompt triggered by the keyboard shortcut.

#### InlineDefinition
- **Binder resolution:** must determine whether the focused Var refers to a lambda parameter or a module binding. Lambda-bound variables cannot be inlined.
- **Capture-safety:** must verify that inlining won't introduce variable capture (a free variable in the initializer shadowed by a lambda at the usage site)
- **Usage-count branching:** sole usage → inline + delete binding. Multiple usages → inline only this occurrence.
- **Promotion path:** Add `Inline` to EditAction. Dispatch maps to `TreeEditOp::InlineDefinition(cursor)`. Cursor must be on a Var node (PositionRole-filtered). The compute handler handles all the complexity.

#### InlineAllUsages
- **Blanket scope check:** must verify capture-safety at every usage site, not just one
- **Multi-point editing:** replaces every usage in the document, then deletes the binding. Edits must be applied in reverse document order to preserve offsets.
- **Promotion path:** Add `InlineAll` to EditAction. Cursor must be on a binding node. Maps to `TreeEditOp::InlineAllUsages(cursor)`.

#### Rename(NewName)
- **Multi-path dispatch:** different logic for renaming a Var (resolve its binder first), a lambda parameter (rename param + all bound occurrences), or a module binding (rename binding + all usages)
- **Shadowing guards:** must check that the new name doesn't collide with existing bindings or introduce captures
- **Token-span editing:** uses fine-grained token spans (parameter name, binding name) rather than whole-node spans, requiring SourceMap token-level lookup
- **User input:** requires the new name from the user
- **Promotion path:** Add `Rename(VarName)` to EditAction. Dispatch maps to `TreeEditOp::Rename(cursor, new_name)`. Works when cursor is on a Var, Lam, or binding.

---

### Tier D: InsertChild

**Operation:** InsertChild(parent, index, kind)

**Why deferred:** For non-Module nodes, InsertChild requires reconstructing the entire parent expression — it splices a new child into the parent's children array and re-renders the whole subtree via the pretty printer. This is expensive and the semantics are unclear (what does "insert a child at index 2 of an App" mean?).

For Module nodes, InsertChild is equivalent to AddBinding (already in Tier A).

**What's needed to promote:**
- Clear semantics for what "insert child" means for each constructor. For App, Bop, If, Lam — these have fixed arity, so insertion doesn't make structural sense. For Module — it's AddBinding.
- Unless the language is extended with variadic constructors, InsertChild on non-Module nodes is not a meaningful operation.

**Promotion path:** Not applicable for the lambda calculus. AddBinding (Tier A) covers the Module case. If the language grows variadic constructs, revisit.

---

## Progression Summary

| Tier | Operations | Barrier | When to Promote |
|------|-----------|---------|-----------------|
| **Phase 1** (now) | Delete, Wrap*, Unwrap, Swap, ChangeOp, CommitEdit | None | Initial implementation |
| **A** | Binding ops (Add, Delete, Dup, Move) | FlatProj access, scope guards for Move | When tree-pane keyboard shortcuts are designed |
| **B** | Cut / PasteAt | Two-cursor model, clipboard state | When keyboard-driven relocation is needed |
| **C** | ExtractToLet, Inline, InlineAll, Rename | Scope analysis, user input (name prompts) | When refactoring keyboard shortcuts are designed |
| **D** | InsertChild (non-Module) | Fixed-arity constructors, unclear semantics | Not applicable for lambda calculus |

Each tier's promotion is independent — Tier B doesn't block Tier C. The compute handlers already exist for all operations. Promotion means adding an EditAction variant, a dispatch mapping, a keyboard binding, and an `available_actions` filter.
