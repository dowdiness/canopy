# Scope-Colored Compact Tree View — Phase 1

## Why

The current tree view renders a plain indented tree with kind-based coloring.
Identifiers are visually undifferentiated — you can't tell at a glance which
variable refers to which binder, where definitions are introduced, or how
scopes relate to each other.

A scope-colored compact view communicates structural information through color
and font weight without adding visual overlay noise, and reveals deeper
structure incrementally through selection-driven highlighting.

## Design Principles

These principles were established during brainstorming and guide all decisions:

1. **Lenses over information dump** — don't show all structural info at once.
   Provide focused views that unfold on demand.
2. **Incremental unfolding responding to demand** — the tree is calm by
   default; structure emerges around the cursor as the user explores.
3. **No layout disturbance** — never shift existing content when revealing
   detail. Popups (future) must not occlude relevant text.
4. **Color is not noise when it replaces, not overlays** — full binder
   coloring remaps existing monochrome text to meaningful color. It doesn't
   add visual weight.
5. **Start minimal, prove it works, then layer on** — Phase 1 is the
   foundation. Tooltips, data flow lens, font size variation are future layers.

## Scope

In:
- `examples/ideal/main/` — `ScopeAnnotation` struct, new Rabbita view function,
  model extensions (scope_map, outline_mode, highlight_set), outline mode toggle
- `lang/lambda/edits/scope.mbt` — existing `resolve_binder` / `find_usages`
  (consumed, not modified)
- `core/proj_node.mbt` — ProjNode[T] used as rose tree for generic zipper navigation
- `examples/ideal/` CSS — binder palette, selection states, def-site weight

Out:
- Tooltips / popups (future task, see TODO.md)
- Data flow lens
- Font size variation by structural role
- Expand/collapse of complex expressions
- Scope rails, nested frames, or other layout decorations
- `examples/web/` HTMLAdapter (Phase 1 targets the ideal editor only)
- Changes to `protocol/view_node.mbt` (framework genericity contract)

## Current State

- **Tree rendering**: `examples/ideal/main/view_outline.mbt` renders an
  indented tree using Rabbita from `InteractiveTreeNode[Term]` (not ViewNode).
  Each node is a `div.tree-row` with kind-based CSS class, click handler, and
  collapse toggle. The tree data is refreshed via `refresh()` in `main.mbt`
  which calls `outline_state.refresh(editor.get_proj_node(), editor.get_source_map())`.
- **Scope resolution**: `lang/lambda/edits/scope.mbt` provides `resolve_binder`
  (variable → binder lookup) and `find_usages` (binder → usage set). Both
  are tested and used by edit operations. `resolve_binder` returns
  `LamBinder(lam_id)` (the Lam node's NodeId) or
  `ModuleBinder(binding_node_id, def_index)` (the def's NodeId).
- **Tree navigation**: `core/proj_zipper.mbt` provides generic ProjNode
  navigation via `navigate_proj(cursor, direction, proj_root) -> NodeId?`.
  Uses path arithmetic — O(n) DFS to find path, O(depth) to compute neighbor.
  The old Term-level Huet zipper (`lang/lambda/zipper/`) was removed in PR #133.
- **Model state**: `examples/ideal/main/model.mbt` has `selected_node : String?`,
  `outline_state : TreeEditorState[Term]`, and the editor provides
  `get_proj_node()`, `get_source_map()`, and term access.
- **Free variables**: `lang/lambda/edits/free_vars.mbt` computes free variable
  sets respecting shadowing.

## Desired State

A compact inline tree view in the ideal editor where:

1. Each module definition renders as a single inline line (not indented tree).
2. Every identifier carries its binder's color at all times (8-hue palette,
   `hash(binder_name) mod 8`).
3. Definition sites render in bold (`font-weight: 700`), usages in regular
   (`font-weight: 400`).
4. Selecting a node (keyboard or pointer) highlights its binder and all
   sibling usages; unrelated nodes dim. Selecting a non-identifier (keyword,
   operator, literal) clears the highlight set.
5. All rendering and selection logic lives in MoonBit (Rabbita view functions).
   TypeScript is limited to CSS custom properties.

## Key Design Decisions

### D1: Where does the compact view live?

**Decision:** A toggle mode within the outline panel. The user switches between
"Tree" (existing indented tree) and "Compact" (new inline view) via a tab or
keybinding in the outline panel header. Both modes share the same underlying
data; only the `view` function differs.

Why: The outline panel already renders the tree. Adding a mode is less
disruptive than a new panel, and lets users compare the two views.

### D2: ViewNode stays generic — use a Rabbita-local struct

**Decision:** Do NOT add binder fields to `protocol/view_node.mbt`. ViewNode
is part of the framework-agnostic protocol layer (see ADR: Framework Genericity
Contract). Instead, create a Rabbita-local struct `ScopeAnnotation` in
`examples/ideal/main/` that maps `NodeId` to binder info:

```
struct ScopeAnnotation {
  binder_id : NodeId?
  is_definition : Bool
  color_index : Int
  usage_ids : Array[NodeId]
}
```

Stored in the Rabbita `Model` as `scope_map : Map[NodeId, ScopeAnnotation]`.
Rebuilt inside `refresh()` (the same function that rebuilds `outline_state`)
by walking the `ProjNode[Term]` tree from `editor.get_proj_node()` and calling
`resolve_binder` and `find_usages` from `lang/lambda/edits/scope.mbt`.

### D3: Line wrapping — Term::Module is the multi-line boundary

**Decision:** Simple expression bodies render on a single inline line. When a
definition body is a nested `Term::Module` (which is what `BlockExpr`
`{ LetDef* Expression? }` is lowered to during projection — see
`lang/lambda/proj/proj_node.mbt:156`), it renders as an indented sub-block
(one line per inner def), mirroring the top-level module layout recursively.

Detection rule: check if a `ProjNode`'s `kind` is `Term::Module` with
children. Single-expression blocks are unwrapped during projection and render
inline. No arbitrary line wrapping or truncation.

### D4: Color stability — hash by binder name, not NodeId

**Decision:** `color_index` is computed from the binder's name string (e.g.,
`"x"`, `"add"`), not from `NodeId`. Specifically:
`color_index = hash(binder_name) mod 8`.

NodeIds change across edits, which would cause colors to jump as the user
types. Hashing by name means the same variable name always gets the same color
across edits. Trade-off: shadowed names share a color — acceptable because
shadowing is explicit and visible from position.

### D5: Keyboard navigation via ProjNode path arithmetic

**Decision:** Use `core/navigate_proj` for generic ProjNode tree navigation.
ProjNode has uniform `children: Array[ProjNode[T]]`, so navigation is direct
path arithmetic (parent = drop last index, child = append 0, siblings = ±1).
No per-language `TermCtx` needed. The old Term-level Huet zipper was removed
in PR #133; edit actions use `lang/lambda/edits/` (get_actions_for_node).

- `Left` / `Right` → `go_left` / `go_right` (sibling ProjNodes = inline tokens)
- `Up` / `Down` → `go_up` / `go_down` (nesting levels = enter/exit blocks)
- `Escape` → clear selection (return to calm state)

The zipper should be **persistent** — stored in the Rabbita model, not
constructed and discarded per move. This gives O(1) navigation instead of
O(n) per step (the Term zipper rebuilds from scratch each time via DFS +
path replay). Rebuild the zipper O(depth) after text edits via saved path
indices.

Navigation stays **node-level** — the zipper moves between `ProjNode`s, which
in the compact view correspond to visible tokens. No separate token-level
selection model needed. The selected node is still `NodeId` (directly available
on `focus.id()` — no bridge translation needed).

Future: language-specific behavior (edit actions, position roles) can
pattern-match on `focus.kind : T` rather than requiring a Term-level zipper.
This migration is out of scope for Phase 1 — see TODO.md §11.

### D6: Binder identity — init expression NodeId for module defs, Lam NodeId for params

**Decision:** `resolve_binder` returns `LamBinder(lam_id)` or
`ModuleBinder(binding_node_id, def_index)`. These map to selectable nodes:

- `LamBinder(lam_id)`: the `Lam` node's NodeId. The `Lam` node is a real
  `ProjNode`. Clicking the `λx` region selects the Lam node.
- `ModuleBinder(binding_node_id, def_index)`: the init expression's NodeId
  (e.g., for `let add = λx. x + 1`, binding_node_id is the `λx. x + 1`
  ProjNode's id). See `flat_proj.mbt:279`.

**Important: there is no standalone LetDef ProjNode.** Module def names are
token spans on the Module node with `role="name:i"` (see
`populate_token_spans.mbt:44-50`). The def name `add` has no NodeId of its own.

**How the compact view handles this:** Each definition line is rendered as a
row. The row contains:
- The def name (rendered from Module's `name:i` token span, colored + bold)
- The `=` separator
- The init expression (rendered from the child ProjNode)

Clicking anywhere on the row selects the **init expression's NodeId** (which
is what `ModuleBinder` returns). The `scope_map` entry for the init
expression's NodeId has `is_definition = true`, `color_index` from the def
name, and `usage_ids` for all uses of the def name.

For lambda params: clicking the `λx` region selects the Lam node. The
`scope_map` entry for the Lam NodeId has `is_definition = true` for param `x`.

No synthetic binder IDs or new ProjNode types needed. The selectable unit
is the init expression (for module defs) or the Lam node (for params).

### D7: Non-identifier selection

**Decision:** When the user selects a node that has no entry in `scope_map`
(keywords, operators, literals, structural nodes), the highlight set is
**cleared** — all nodes return to full opacity. This returns the view to its
calm baseline state.

This is consistent with the "incremental unfolding" principle: structural info
only appears when you ask a meaningful question (select an identifier). Selecting
a `+` operator doesn't have a scope answer, so the view goes quiet.

## Architecture

### Functional Core (MoonBit) — all logic

**Layer 1: Scope annotation (Rabbita-local)**

`ScopeAnnotation` struct in `examples/ideal/main/`, populated inside the
existing `refresh()` function in `main.mbt`. `refresh()` already has access to
`editor.get_proj_node()` and `editor.get_source_map()`. The new code:

1. Walks the `ProjNode[Term]` tree
2. For each `Var` node: calls `resolve_binder` → `binder_id`, looks up binder
   name → `hash(name) mod 8` → `color_index`, sets `is_definition = false`
3. For each `Lam` node and module def node: sets `is_definition = true`,
   calls `find_usages` → `usage_ids`, computes `color_index` from param/def name
4. Stores all annotations in `scope_map : Map[NodeId, ScopeAnnotation]`

**Layer 2: Compact inline view**

New Rabbita view function `view_compact_tree(dispatch, model) -> Html`:
- Reads `InteractiveTreeNode[Term]` from `model.outline_state` (same data
  source as `view_outline_node`)
- Reads `model.scope_map` for binder coloring and definition status
- Renders each module definition as one inline `div` with `span` per child node
- Nested `Term::Module` children render as indented sub-blocks (recursive)
- Applies `class="binder-{color_index}"` for color (index from name hash)
- Applies `class="def-site"` for font weight at definition sites
- Reads `model.highlight_set` to apply `"highlighted"` / `"dimmed"` classes

Toggled via outline panel mode selector (Tree / Compact).

**Layer 3: Selection logic in `update`**

On `SelectNode(id)`:
1. Look up `scope_map[id]` → `ScopeAnnotation?`
2. If `Some(ann)`: highlight set = `{ann.binder_id} ∪ ann.usage_ids` (include
   the binder itself if `binder_id` is `Some`; for binders, include self + usages)
3. If `None` (non-identifier): clear highlight set → all nodes full opacity
4. Store `highlight_set : Set[NodeId]` in model
5. Rabbita re-renders — view reads highlight set, applies classes

**Layer 4: Keyboard navigation via ProjNode rose tree zipper**

Persistent zipper stored in `Model.zipper : ProjZipper[Term]?`.

**Initialization:**
- Click/pointer selection: `NodeId` → DFS `ProjNode` tree to find path
  indices → `focus_at(proj_root, indices)` → store zipper. O(n) once.
- Keyboard nav in compact view with no existing zipper: build from
  `model.selected_node` the same way.

**Lifecycle — rebuild/clear inside `refresh()`:**
All projection changes go through `refresh()` in `main.mbt` (text edits,
structural edits, undo, redo, example load — 8 call sites). Inside `refresh()`:
1. If `model.zipper` is `Some(z)`: save `z.path_indices()`
2. Rebuild outline_state + scope_map from new projection (existing)
3. Try `focus_at(new_proj_root, saved_indices)` → if the node at that
   path still exists and has the same kind, restore zipper
4. If path is invalid (node deleted/moved): clear `zipper = None`,
   clear `highlight_set`

**Navigation:**
`on_keydown` handler in the compact view:
- Reads `model.zipper`, calls `go_left`/`go_right`/`go_up`/`go_down`
- Returns `Some(new_zipper)` → update model + dispatch `SelectNode(new_zipper.focus.id())`
- Returns `None` (boundary) → no-op
- `Escape` → dispatch `ClearSelection`, set `zipper = None`

O(1) per move — no DFS, no bridge translation. NodeId directly from
`focus.id()`. No flat token list needed.

### Imperative Shell (TypeScript) — minimal glue

- CSS custom properties: `--binder-0` through `--binder-7`
- `<canopy-editor>` web component bridge (already exists)
- No rendering, selection, or keyboard logic

### CSS

```css
/* Binder palette — 8 hues */
:root {
  --binder-0: #e06c75;  /* rose */
  --binder-1: #61afef;  /* blue */
  --binder-2: #c3e88d;  /* green */
  --binder-3: #f78c6c;  /* orange */
  --binder-4: #dcdcaa;  /* gold */
  --binder-5: #c792ea;  /* purple */
  --binder-6: #89ddff;  /* cyan */
  --binder-7: #ff5370;  /* red */
}

/* Binder color classes */
.binder-0 { color: var(--binder-0); }
/* ... through .binder-7 */

/* Definition site weight */
.def-site { font-weight: 700; }

/* Selection states */
.highlighted { opacity: 1; }
.dimmed { opacity: 0.35; }
```

## Data Flow

### Initial render

```
Text → loom parse → SyntaxNode → syntax_to_proj_node → ProjNode[Term]
  → refresh():
      outline_state.refresh(proj_node, source_map)       [existing]
      walk ProjNode tree:
        Var nodes  → resolve_binder → binder_id, hash(name) mod 8
        Lam/Def nodes → find_usages → usage_ids, hash(name) mod 8
      → scope_map : Map[NodeId, ScopeAnnotation]          [new]
  → view_compact_tree reads InteractiveTreeNode + scope_map → Html
  → Rabbita diffs and patches DOM
```

### Selection

```
User presses → or clicks
  → on_keydown: model.zipper.go_right() → Some(new_zipper)
  → new_id = new_zipper.focus.id()          (O(1), no bridge)
  → update: model.zipper = new_zipper       (persistent, O(1))
  → update: scope_map[new_id] → Some(ann) or None
  → if Some: highlight_set = {ann.binder_id} ∪ ann.usage_ids
  → if None: highlight_set = {} (clear)
  → Rabbita re-renders view_compact_tree
  → highlighted nodes full opacity, dimmed nodes fade, or all normal if cleared
```

### Mode toggle

```
User clicks "Compact" tab in outline panel
  → dispatch SetOutlineMode(Compact)
  → update: model.outline_mode = Compact
  → Rabbita re-renders outline panel
  → view_compact_tree replaces view_outline_node
```

## Steps

1. Define `ScopeAnnotation` struct in `examples/ideal/main/` with `binder_id`,
   `is_definition`, `color_index`, `usage_ids`.
2. **Define let-definition render identity.** In `view_compact_tree`, each
   module def line maps to the init expression's NodeId (from
   `ModuleBinder(binding_node_id, def_index)`). The def name is rendered from
   the Module's `name:i` token span but clicking the row selects the init
   expression's NodeId. For lambda params, the Lam node's NodeId is selected.
   No new ProjNode types needed.
3. Add `scope_map : Map[NodeId, ScopeAnnotation]`, `outline_mode` (Tree |
   Compact), `highlight_set : Set[NodeId]`, and `zipper : ProjZipper[Term]?`
   to the Rabbita Model.
4. Extend `refresh()` in `main.mbt` to build `scope_map` by walking the
   `ProjNode[Term]` tree from `editor.get_proj_node()`, calling
   `resolve_binder` and `find_usages`. `color_index = hash(binder_name) mod 8`.
5. Add binder palette CSS and selection state CSS to the ideal editor.
6. Implement `view_compact_tree` Rabbita view function — reads
   `InteractiveTreeNode[Term]` + `scope_map`. Inline layout per def (def name
   from token span + init expression from child ProjNode), nested
   `Term::Module` as indented sub-blocks, binder color classes, def-site
   weight class.
7. Add outline panel mode toggle (Tree / Compact) to switch between
   `view_outline_node` and `view_compact_tree`.
8. Implement selection logic in `update` — look up `scope_map`, compute
   highlight set or clear if non-identifier.
9. Apply `"highlighted"` / `"dimmed"` classes in `view_compact_tree` based on
   `highlight_set`.
10. Implement ProjNode rose tree zipper (`ProjZipper[T]`) in
    `examples/ideal/main/` (or extract to a shared module). Types:
    `RoseCtx[T]` (parent data + left/right siblings), `RoseZipper[T]`
    (focus + path). Navigation: `go_up`, `go_down(i)`, `go_left`, `go_right`.
11. **Zipper initialization from selection.** On click or pointer selection:
    `NodeId` → DFS ProjNode tree to find path indices → `focus_at(proj_root,
    indices)` → store in `model.zipper`. On keyboard nav with no existing
    zipper: build from `model.selected_node` the same way.
12. **Zipper lifecycle in `refresh()`.** All 8 projection-changing paths go
    through `refresh()`. Inside refresh: save `zipper.path_indices()`, rebuild
    scope_map + outline_state, try `focus_at(new_proj_root, saved_indices)`.
    If path invalid (node deleted/moved): clear `zipper = None`, clear
    `highlight_set`. Paths that call refresh: text edits (EditorTextChanged),
    structural edits (TreeEdited, OverlayAction), undo, redo, LoadExample,
    EditorStructuralEdited.
13. Add keyboard navigation via persistent zipper in `on_keydown` handler.
    `go_left`/`go_right`/`go_up`/`go_down` on `model.zipper`. `Escape` clears.
14. Write unit tests for ProjNode zipper: `go_down`/`go_up` round-trip,
    `go_left`/`go_right` sibling traversal, `focus.id()` returns correct
    NodeId without bridge translation.
15. Write unit tests for `scope_map` building: verify `color_index` stability
    (same name → same index across rebuilds), correct `binder_id` for variables
    at different scope depths, correct `is_definition` flags, correct
    `usage_ids` sets. Test as pure functions over `ProjNode` trees.
16. Write unit tests for highlight set computation: variable selection →
    binder + usages, binder selection → self + usages, non-identifier →
    empty set.
17. Write snapshot tests for `view_compact_tree` Html output: verify class
    strings contain correct `binder-N` and `def-site` classes. Test the
    class-assignment helper functions, not serialized DOM.

## Acceptance Criteria

- [ ] Outline panel has Tree / Compact mode toggle.
- [ ] Compact mode renders one line per module definition; nested
      `Term::Module` bodies render as indented sub-blocks.
- [ ] All identifiers carry their binder's color (8-hue palette,
      `hash(binder_name) mod 8`).
- [ ] Color is stable across edits (same name → same color).
- [ ] Definition sites render bold (700), usages regular (400).
- [ ] Selecting a variable highlights its binder + all usages, dims the rest.
- [ ] Selecting a binder highlights all its usages + self, dims the rest.
- [ ] Selecting a non-identifier (keyword, operator, literal) clears highlights.
- [ ] `←`/`→` navigate between sibling ProjNodes via persistent rose tree
      zipper, `↑`/`↓` navigate nesting levels, `Escape` clears selection.
- [ ] Navigation is O(1) per move (persistent zipper, no DFS/bridge per step).
- [ ] `ScopeAnnotation` is Rabbita-local. `protocol/view_node.mbt` unchanged.
- [ ] `scope_map` is rebuilt inside `refresh()`, not via new incr wiring.
- [ ] All rendering and selection logic is in MoonBit (Rabbita). No TS logic
      beyond CSS variables.
- [ ] `moon check` and `moon test` pass.
- [ ] Unit tests for scope_map building (color stability, binder resolution,
      is_definition, usage_ids).
- [ ] Unit tests for highlight set computation (variable, binder,
      non-identifier cases).
- [ ] Snapshot tests for compact view class assignment.

## Validation

```bash
moon check
moon test
cd examples/ideal && npm run dev  # Visual verification
```

## Risks

- **Binder palette collision**: With only 8 hues, programs with many binders
  will have color collisions. Acceptable for Phase 1 — the combination of
  color + position + font weight still disambiguates. Future: dynamic palette
  sizing or scope-local allocation.
- **Performance**: `resolve_binder` and `find_usages` are called per node
  during `refresh()`. Currently these walk the tree. For large programs, may
  need caching. Measure before optimizing.
- **Rabbita re-render cost**: Selection changes re-render the entire compact
  view. Rabbita's virtual DOM diff should handle this efficiently, but measure
  with programs of 50+ definitions.
- **Zipper granularity vs compact tokens**: The ProjNode zipper navigates
  the projection tree. Some ProjNodes may not have visible representations
  in the compact view (e.g., intermediate App nodes). If the zipper lands on
  an invisible node, compose a "skip to next visible" helper that calls
  `go_right`/`go_left` repeatedly until hitting a visible node. Resolve
  during implementation by testing with real expressions.
- **ProjNode zipper is new code**: The generic rose tree zipper doesn't exist
  yet as a standalone module. Phase 1 can implement it locally in
  `examples/ideal/main/` and extract to a library later (TODO.md §11).

## Future Layers (not in scope)

These build on Phase 1's foundation:

- **Smart tooltip**: popup on selection showing scope info (binding site, usage
  count). Smart positioning to avoid occluding relevant text. Tracked in
  TODO.md.
- **Data flow lens**: select an application to see argument → parameter binding.
- **Font size by structural role**: module defs largest, params medium, usages
  regular, syntax smallest.
- **Free variable highlighting**: unbound variables flagged with warning style.
- **Expand/collapse**: complex inline expressions expand into nested tree on
  demand (popup, not layout shift).

## Notes

- Design explored in brainstorming session 2026-04-04. Visual mockups in
  `.superpowers/brainstorm/` (if preserved).
- The existing `view_outline_node` in `examples/ideal/main/view_outline.mbt`
  is the code template — same patterns (recursive Html, class interpolation,
  dispatch) apply to the compact view.
- Binder resolution and usage tracking are already implemented and tested in
  `lang/lambda/edits/scope.mbt`. This plan wires them into rendering, not
  reimplements them.
- Navigation uses `core/navigate_proj` (path arithmetic on ProjNode[T]).
  The old Term-level zipper (`lang/lambda/zipper/`) was removed in PR #133.
  Edit actions use `lang/lambda/edits/get_actions_for_node`.
  work. The existing action system (`NodeActionContext`, `get_actions_for_node`
  in `action_model.mbt`) and Term-level zipper remain untouched in Phase 1.
  Migration of edit actions / position roles to ProjNode zipper is a separate
  follow-up tracked in TODO.md §11 (generic zipper libraries).
  See TODO.md §11 for the full extraction plan.
- The generic zipper library design has three layers: tree shapes (rose,
  binary, btree — each with fixed derivative), navigation algebra (shared
  interface for all shapes), and annotation traits (domain-specific behavior
  maintained incrementally as the zipper moves — push on go_down, pop on
  go_up). ScopeProvider is one such annotator. In Phase 1, scope_map is
  precomputed separately (needed for baseline binder coloring of all nodes).
  Future: the zipper's scope annotation could replace the separate
  `resolve_binder` call for highlight set computation on selection.
- Theory: the derivative of a type IS its zipper context type (McBride 2001).
  ProjNode[T] = T * List(X), derivative = T * List(X) * List(X) (parent
  data, left siblings, right siblings). T is in constant position, so the
  derivative is generic in T — one zipper for all languages, no codegen.
- Codex review (2026-04-04) identified 7 issues; all addressed in this revision.
  Key fixes: Rabbita-local ScopeAnnotation (not ViewNode), ProjNode zipper for
  navigation (not flat token lists), InteractiveTreeNode data source (not
  ViewNode), Term::Module detection (not BlockExpr), hash-by-name consistently,
  clear highlights on non-identifier selection, pure function test seams.
