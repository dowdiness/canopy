# EditorProtocol — Framework-Agnostic Integration Layer

**Status:** Completed and archived. The current protocol source of truth is
[`protocol/README.md`](../../protocol/README.md), the MoonBit implementation in
[`protocol/`](../../protocol/), and the TypeScript mirror in
[`adapters/editor-adapter/types.ts`](../../adapters/editor-adapter/types.ts).
This plan is historical and may describe implementation details as they existed
when the protocol layer was designed.

## Why

The examples/ apps duplicate heavy TypeScript logic that MoonBit already knows
how to compute. The three worst offenders:

1. **ProjNode → editor conversion** — `ideal/web/convert.ts` and
   `prosemirror/convert.ts` each walk ProjNode JSON and build PM nodes.
   Same logic, two copies, tightly coupled to the JSON shape MoonBit emits.

2. **Incremental reconciliation** — `ideal/web/reconciler.ts` and
   `prosemirror/reconciler.ts` each diff old PM doc vs new ProjNode.
   MoonBit already knows what changed (memo pipeline), but throws away
   that knowledge and exports a full snapshot.

3. **Global-state bridge** — `ideal/main/bridge_ffi.mbt` has 20+ inline
   JS externs communicating through `globalThis.__canopy_*` globals and
   hidden button clicks. The `<canopy-editor>` Web Component and Rabbita
   share a mutable SyncEditor singleton with no typed channel between them.

This causes: duplication across examples, JSON marshaling overhead,
fragile global-state coordination, and high cost for adding new editor
variants (each needs its own conversion + reconciliation TS code).

## Scope

In:
- `protocol/` — package for protocol types (`ViewPatch`, `ViewNode`,
  `UserIntent`). Separate from `core/` to keep rendering concerns
  (`css_class`, `editable`, `widget`) out of the structural primitive layer
  (`NodeId`, `ProjNode`, `SourceMap`).
- `editor/` — new `ViewUpdater` component on `SyncEditor`
- `examples/web/` — first migration target (simplest, validates types)
- `examples/ideal/` — migrate from global-state bridge to protocol
- `examples/prosemirror/` — migrate from TS reconciler to protocol

Out:
- `examples/rabbita/` — already pure MoonBit, no protocol needed for its
  own views (only for future CM6 embedding)
- `examples/relay-server/` — already 100% MoonBit relay logic
- `examples/canvas/` — viewport math stays in TS (DOM-native)
- Sync protocol unification (separate concern, not blocked by this)
- Binary serialization optimization (future, on top of generic JSON layer)

## Current State

### Data flow today

```
Edit → SyncEditor pipeline → full ProjNode/SourceMap snapshot (JSON)
  → TS walks snapshot, diffs against previous editor state
  → TS applies framework-specific operations (CM6/PM)
```

### Key APIs (from moon ide)

```
SyncEditor::get_proj_node()  → ProjNode[T]?     // memo-backed
SyncEditor::get_source_map() → SourceMap         // memo-backed
SyncEditor::get_errors()     → Array[String]
SyncEditor::get_text()       → String
SyncEditor::get_cursor()     → Int
```

```
ProjNode[T] { kind: T, start: Int, end: Int, node_id: Int, children: Array[ProjNode[T]] }
SourceMap   { node_to_range, ranges, token_spans }
NodeId(Int)
```

Traits on T:
```
trait TreeNode   { children(Self) -> Array[Self]; same_kind(Self, Self) -> Bool }
trait Renderable { kind_tag(Self) -> String; label(Self) -> String; placeholder(Self) -> String; unparse(Self) -> String }
```

### Integration patterns

| Example | Pattern | TS logic weight |
|---------|---------|----------------|
| `ideal` | Rabbita host + `<canopy-editor>` Web Component | Heavy — bridge_ffi.mbt (20+ externs), convert.ts, reconciler.ts, bridge.ts |
| `prosemirror` | Standalone PM editor | Heavy — convert.ts, reconciler.ts, bridge.ts, sync.ts |
| `web` | Vanilla DOM editor | Medium — tree rendering from JSON, error list, graphviz |
| `demo-react` | React + Valtio hook | Medium — custom hook, proxy state, op logging |
| `block-editor` | Block contentEditable | Light — autoformat detection, block rendering |
| `rabbita` | Pure MoonBit TEA | None — direct SyncEditor access |
| `relay-server` | Cloudflare Workers | None — 100% MoonBit relay |
| `canvas` | Pointer + viewport | Light — RAF render loop, hit detection |

## Desired State

### Architecture

```
┌──────────────────── MoonBit ────────────────────┐
│                                                  │
│  SyncEditor pipeline (CRDT → parse → project)   │
│       │                                          │
│       ▼                                          │
│  ViewUpdater                                     │
│    diffs previous ViewNode tree vs current        │
│    emits Array[ViewPatch]                        │
│                                                  │
│  For Rabbita host:                               │
│    native views → Rabbita VDOM (no protocol)     │
│    foreign widgets → ViewPatch (in-process call) │
│                                                  │
│  For TS host:                                    │
│    all views → ViewPatch (via FFI/JSON)          │
└──────────────────┬───────────────────────────────┘
                   │ EditorProtocol
          ┌────────┴────────┐
          │  TS Adapters    │
          │  CM6 / PM / HTML│
          └─────────────────┘
```

### Principles

1. **MoonBit computes, TS renders** — all pure computation (diffing,
   position mapping, AST walking) happens in MoonBit
2. **Diffs, not snapshots** — MoonBit sends what changed, not full state
3. **Language-agnostic** — protocol doesn't know Lambda/JSON/Markdown
4. **Framework-agnostic** — protocol doesn't know CM6/PM
5. **Single owner** — Rabbita (or the TS host) is the sole owner of
   SyncEditor; adapters never touch CRDT directly

## Protocol Types

All protocol types live in `protocol/`, separate from the structural
primitives in `core/`. This keeps rendering concerns (`css_class`,
`editable`, `widget`) out of the core layer.

### ViewNode — language-agnostic node representation

```moonbit
/// protocol/view_node.mbt
pub(all) struct ViewNode {
  id : NodeId
  kind_tag : String       // from Renderable::kind_tag — "lam", "app", "json_object"
  label : String          // from Renderable::label — human-readable
  text : String?          // leaf text content (for editable leaves)
  text_range : (Int, Int) // from SourceMap — absolute text positions
  token_spans : Array[TokenSpan]  // sub-editable spans (binding, operator, etc.)
  editable : Bool         // has inline-editable text (CM6 nodeview or contentEditable)
  css_class : String      // styling hook (kind_tag based)
  children : Array[ViewNode]

  fn new(
    id~ : NodeId,
    kind_tag~ : String,
    label~ : String,
    text? : String,
    text_range~ : (Int, Int),
    token_spans~ : Array[TokenSpan] = [],
    editable~ : Bool = false,
    css_class~ : String = "",
    children~ : Array[ViewNode] = [],
  ) -> ViewNode
}

pub(all) struct TokenSpan {
  role : String     // "binding", "operator", "keyword", etc.
  start : Int
  end : Int

  fn new(role~ : String, start~ : Int, end~ : Int) -> TokenSpan
}
```

Constructed from `ProjNode[T]` + `SourceMap` by the `ViewUpdater`.
The `T : Renderable` trait provides `kind_tag`, `label`, `placeholder`.
TS never needs to know the concrete `T` type.

**Relationship to InteractiveTreeNode:** Both representations survive.
`InteractiveTreeNode[T]` carries UI state (`selected`, `collapsed`,
`editing`, `drop_target`) and retains the type parameter `T` for
pattern matching in Rabbita VDOM. `ViewNode` is the serializable,
type-erased subset for cross-boundary communication. Rabbita native
views use `InteractiveTreeNode` directly; foreign widgets receive
`ViewNode` via the protocol. No duplication — different concerns.

### ViewPatch — what changed

```moonbit
/// protocol/view_patch.mbt
pub enum ViewPatch {
  // Text view (CM6)
  TextChange(from~ : Int, to~ : Int, insert~ : String)

  // Tree view (PM, custom HTML, outline)
  ReplaceNode(node_id~ : NodeId, node~ : ViewNode)
  InsertChild(parent_id~ : NodeId, index~ : Int, child~ : ViewNode)
  RemoveChild(parent_id~ : NodeId, index~ : Int, child_id~ : NodeId)
  UpdateNode(node_id~ : NodeId, label~ : String, css_class~ : String, text? : String)

  // Decorations (syntax highlighting, errors, peer cursors)
  SetDecorations(decorations~ : Array[Decoration])
  SetDiagnostics(diagnostics~ : Array[Diagnostic])

  // Selection
  SetSelection(anchor~ : Int, head~ : Int)
  SelectNode(node_id~ : NodeId)

  // Full rebuild (initial load or major structural change)
  FullTree(root~ : ViewNode?)
}

pub(all) struct Decoration {
  from : Int
  to : Int
  css_class : String
  data : String?    // e.g. peer name for cursor labels
  widget : Bool     // true = CM6 widget decoration (cursor caret), false = inline mark

  fn new(
    from~ : Int,
    to~ : Int,
    css_class~ : String,
    data? : String,
    widget~ : Bool = false,
  ) -> Decoration
}

pub(all) struct Diagnostic {
  from : Int
  to : Int
  severity : String  // "error", "warning", "info"
  message : String

  fn new(
    from~ : Int,
    to~ : Int,
    severity~ : String,
    message~ : String,
  ) -> Diagnostic
}
```

`UpdateNode` includes an optional `text?` field so leaf content changes
(e.g. `Int(4)` → `Int(5)`) can be applied without replacing the node,
preserving CM6 inline editor focus.

### UserIntent — what the user wants

```moonbit
/// protocol/user_intent.mbt
pub enum UserIntent {
  // Text editing (from CM6 or contentEditable)
  TextEdit(from~ : Int, to~ : Int, insert~ : String)

  // Structural editing (from PM or outline)
  StructuralEdit(node_id~ : NodeId, op~ : String, params~ : Map[String, String])

  // Selection / cursor
  SelectNode(node_id~ : NodeId)
  SetPmCursor(pm_tree_position~ : Int)
  SetDocCursor(doc_code_unit_offset~ : Int)

  // Undo/redo
  Undo
  Redo

  // Commit inline edit (e.g. rename binding)
  CommitEdit(node_id~ : NodeId, value~ : String)
}
```

**Why StructuralEdit uses stringly-typed params:** The protocol boundary
is language-agnostic — it must work for Lambda, JSON, Markdown, and future
languages without changing the protocol types. The typed `TreeEditOp` enum
is language-specific (Lambda has `WrapInLambda`, JSON has `WrapInObject`).
The mapping from `(op, params)` → `TreeEditOp` happens inside MoonBit
immediately after deserialization, where type safety is restored:

```moonbit
fn parse_structural_intent(
  op : String, node_id : NodeId, params : Map[String, String]
) -> TreeEditOp? {
  match op {
    "WrapInLambda" => Some(@lambda_edits.WrapInLambda(
      node_id~, var_name=params.get("var_name").or("x")))
    "Delete" => Some(@lambda_edits.Delete(node_id~))
    // ... other ops
    _ => None
  }
}
```

The stringly-typed layer is thin (one match expression per language) and
contained. Adapters send intent; MoonBit validates and dispatches.

## ViewUpdater

Lives on `SyncEditor`. Computes patches by diffing previous vs current
ViewNode trees.

**Diffing strategy:** The ViewUpdater maintains its own previous
`ViewNode?` tree. On each `compute_view_patches` call, it:

1. Builds the current `ViewNode` tree from `get_proj_node()` + `get_source_map()`
2. Diffs the previous tree against the current tree
3. Emits minimal `ViewPatch` operations
4. Stores the current tree as the new previous

This is a full tree diff — O(n) in the number of nodes. It does NOT
leverage the memo pipeline's internal change tracking (which is
lambda-specific via `changed_def_indices_ref` in `projection_memo.mbt`).
The tree diff is the same algorithm as `TreeEditorState::refresh`'s
stamp comparison, but reimplemented to emit `ViewPatch` instead of
building `InteractiveTreeNode`. The stamp comparison logic (compare
`kind_tag`, `label`, child count, `text_range`) cannot be shared as a
function because the input types differ, but the algorithm is identical.

Leveraging the memo pipeline's change knowledge for O(changed) diffing
is a deferred optimization — it would require a generic change-notification
mechanism on the memo system, which is out of scope for Phase 1.

```moonbit
/// editor/view_updater.mbt

/// Compute patches after a state change.
/// Called by the host (Rabbita update or TS after FFI edit call).
pub fn[T : Renderable + TreeNode] SyncEditor::compute_view_patches(
  self : SyncEditor[T],
) -> Array[ViewPatch]

/// Compute patches for text changes specifically.
/// Produces TextChange patches from the last applied text edit.
pub fn[T] SyncEditor::compute_text_patches(
  self : SyncEditor[T],
) -> Array[ViewPatch]

/// Build a full ViewNode tree from current projection state.
/// Used for initial load and full rebuild.
pub fn[T : Renderable] SyncEditor::get_view_tree(
  self : SyncEditor[T],
) -> ViewNode?

/// Convert a ProjNode subtree to ViewNode.
/// Pure helper — used by compute_view_patches and get_view_tree.
pub fn[T : Renderable] proj_to_view_node(
  node : ProjNode[T],
  source_map : SourceMap,
) -> ViewNode
```

### Module/let_def wrapper synthesis

Both existing PM reconcilers synthesize `let_def` wrapper nodes that do
not exist in `ProjNode`. The Module ProjNode has
`children = [init0, init1, ..., body]` but PM needs
`children = [let_def(init0), let_def(init1), ..., body]`.

This synthesis is handled in `proj_to_view_node`, not in the adapters.
When converting a Module-kind ProjNode, `proj_to_view_node` emits
synthetic `ViewNode` wrappers with `kind_tag = "let_def"` around each
definition child. The PM adapter receives the wrapped structure and maps
it directly to PM schema nodes — no wrapper synthesis needed in TS.

This means `ViewNode` trees may differ structurally from `ProjNode` trees
where language-specific presentation requires it. The wrapper synthesis is
language-specific code in the `proj_to_view_node` impl for each language
(Lambda, JSON, etc.), not in the generic protocol layer.

### Patch computation strategy

1. **Text edits** — `SyncEditor` already tracks the last edit position
   via `apply_text_edit`. Emit `TextChange(from, to, insert)` directly
   from the edit parameters — no diffing needed.

2. **Tree patches** — Full diff of previous `ViewNode` tree vs current.
   Walk both trees in parallel; emit `UpdateNode` for label/text/class
   changes, `ReplaceNode` for kind changes, `InsertChild`/`RemoveChild`
   for structural changes. Skip unchanged subtrees by comparing
   `kind_tag`, `label`, `text`, `text_range`, and child count (stamp).

3. **Decorations** — Computed from `SourceMap` token spans + `get_errors()`.
   Emitted as `SetDecorations` with CSS classes matching design tokens
   (e.g. `"canopy-keyword"`, `"canopy-identifier"`). Peer cursor
   decorations use `widget = true` so the adapter creates CM6 widget
   decorations with cursor labels, not inline marks.

4. **Diagnostics** — From `get_errors()`, mapped to text ranges via
   SourceMap where possible.

### Mode switching (text vs structure)

The `ideal` example has text mode (CM6) and structure mode (PM). The host
controls which adapter is active and dispatches patches accordingly:

- **Text mode active:** emit `TextChange` + `SetDecorations` +
  `SetSelection`. Tree patches are suppressed (PM is not mounted).
- **Structure mode active:** emit tree patches + `SetDecorations` +
  `SelectNode`. `TextChange` is suppressed (CM6 is not mounted).
- **Mode switch:** emit `FullTree` to initialize the newly mounted
  adapter, then resume incremental patches.

The ViewUpdater always computes all patch types. The host filters by
active mode before forwarding to the adapter. This keeps the ViewUpdater
mode-agnostic.

## Adapter Interface (TypeScript)

```typescript
// lib/editor-adapter/adapter.ts

interface EditorAdapter {
  /** Apply patches from MoonBit ViewUpdater */
  applyPatches(patches: ViewPatch[]): void;

  /** Register callback for user intents */
  onIntent(callback: (intent: UserIntent) => void): void;

  /** Clean up resources */
  destroy(): void;
}
```

### JSON wire format

MoonBit's `derive(ToJson)` on enums produces array-based JSON
(`["TextChange", 1, 5, "hello"]`). This does not match the object-based
TS discriminated unions. Therefore, all protocol types use **custom
`to_json`/`from_json` implementations** that produce object-based JSON:

```json
{ "type": "TextChange", "from": 1, "to": 5, "insert": "hello" }
{ "type": "ReplaceNode", "node_id": 42, "node": { "id": 42, ... } }
```

The custom impls are straightforward — each variant maps to a JSON object
with a `"type"` discriminator. The TS side uses `switch (patch.type)` for
dispatch, which is the natural pattern for discriminated unions.

```typescript
// lib/editor-adapter/types.ts

type ViewPatch =
  | { type: "TextChange"; from: number; to: number; insert: string }
  | { type: "ReplaceNode"; node_id: number; node: ViewNode }
  | { type: "InsertChild"; parent_id: number; index: number; child: ViewNode }
  | { type: "RemoveChild"; parent_id: number; index: number; child_id: number }
  | { type: "UpdateNode"; node_id: number; label: string; css_class: string; text?: string }
  | { type: "SetDecorations"; decorations: Decoration[] }
  | { type: "SetDiagnostics"; diagnostics: Diagnostic[] }
  | { type: "SetSelection"; anchor: number; head: number }
  | { type: "SelectNode"; node_id: number }
  | { type: "FullTree"; root: ViewNode | null };

type Decoration = {
  from: number;
  to: number;
  css_class: string;
  data?: string;
  widget: boolean;  // true = CM6 widget (cursor caret), false = inline mark
};

type UserIntent =
  | { type: "TextEdit"; from: number; to: number; insert: string }
  | { type: "StructuralEdit"; node_id: number; op: string; params: Record<string, string> }
  | { type: "SelectNode"; node_id: number }
  | { type: "SetPmCursor"; pm_tree_position: number }
  | { type: "SetDocCursor"; doc_code_unit_offset: number }
  | { type: "Undo" }
  | { type: "Redo" }
  | { type: "CommitEdit"; node_id: number; value: string };

type ViewNode = {
  id: number;
  kind_tag: string;
  label: string;
  text?: string;
  text_range: [number, number];
  token_spans: { role: string; start: number; end: number }[];
  editable: boolean;
  css_class: string;
  children: ViewNode[];
};
```

### Planned adapters

| Adapter | Target | Estimated size | Key behavior |
|---------|--------|---------------|-------------|
| `CM6Adapter` | CodeMirror 6 | ~80 lines | `TextChange` → `view.dispatch({changes})`, `SetDecorations` → `Decoration.set` (mark) / `Decoration.widget` (cursor), `SetSelection` → `view.dispatch({selection})` |
| `PMAdapter` | ProseMirror | ~200-300 lines | `ReplaceNode` → find by `data-node-id` attr → `ReplaceStep`, `InsertChild`/`RemoveChild` → node-level steps, `SelectNode` → `NodeSelection`. Includes schema definition, NodeView factories for leaf editing, and node-id index maintenance. Larger than other adapters because PM's document model requires schema-aware step construction. |
| `HTMLAdapter` | Vanilla DOM | ~60 lines | `ReplaceNode` → replace element with `data-node-id`, `FullTree` → rebuild via template |

## Rabbita Integration

### Native views (no protocol)

Outline, inspector, toolbar, bottom panel, action overlay — rendered via
Rabbita VDOM from `Model` which holds `SyncEditor` and `TreeEditorState`
directly. No serialization. This is unchanged.

### Foreign widget (protocol replaces bridge_ffi.mbt)

The `<canopy-editor>` Web Component becomes a stateless renderer driven
by the protocol. Rabbita is the sole owner of `SyncEditor`.

#### Current flow (broken)

```
CM6 keystroke
  → TS sets globalThis.__canopy_pending_*
  → TS clicks hidden trigger button
  → Rabbita VDOM handler reads js_take_*() global
  → Rabbita dispatches Msg
  → update() calls editor method
  → MoonBit calls js_reconcile_editor_with_text()
  → TS updates CM6
```

#### New flow (protocol)

```
CM6 keystroke
  → CM6Adapter captures UserIntent(TextEdit(from, to, insert))
  → Adapter calls MoonBit intent callback
  → Rabbita dispatches Msg::EditorIntent(intent)
  → update() calls editor.apply_text_edit(...)
  → editor.compute_view_patches() → Array[ViewPatch]
  → Rabbita effect: adapter.applyPatches(patches)
  → CM6Adapter applies TextChange + SetDecorations
```

#### Rabbita Model changes

```moonbit
// examples/ideal/main/model.mbt

pub struct Model {
  editor : @editor.SyncEditor[@ast.Term]
  outline_state : @proj.TreeEditorState[@ast.Term]
  // ... existing UI fields ...
  // REMOVED: no more bridge_ffi.mbt globals
}

pub enum Msg {
  // ... existing variants ...
  // NEW: typed intent from foreign widget
  EditorIntent(@protocol.UserIntent)
  // REMOVED: TextChangedFromEditor, NodeSelected(String),
  //          StructuralEditRequested, SyncStatusChanged(String)
}
```

#### What bridge_ffi.mbt becomes

The 20+ inline JS externs reduce to ~3:

```moonbit
/// Register a callback that receives UserIntent JSON from the adapter.
extern "js" fn register_intent_callback(cb : (String) -> Unit) -> Unit

/// Send patches to the adapter.
extern "js" fn adapter_apply_patches(patches_json : String) -> Unit

/// Query adapter for geometry (overlay positioning).
extern "js" fn adapter_get_node_rect(node_id : Int) -> String
```

## FFI Serialization

### Generic layer (JSON)

All ViewPatch/UserIntent types use custom `to_json`/`from_json`
implementations that produce object-based JSON with `"type"` discriminators
(not `derive(ToJson)` which produces array-based JSON).

```moonbit
// MoonBit → TS
let patches = editor.compute_view_patches()
adapter_apply_patches(patches.to_json().stringify())

// TS → MoonBit
register_intent_callback(fn(json_str) {
  let intent = @protocol.UserIntent::from_json(@json.parse(json_str))
  dispatch(EditorIntent(intent))
})
```

### Optimized layer (future)

For hot paths (text editing, decoration updates), bypass JSON:

```moonbit
// Direct FFI for text changes — no JSON overhead
extern "js" fn adapter_text_change(from : Int, to : Int, insert : String) -> Unit
```

This optimization is deferred — JSON is adequate for the initial
implementation and profiling will identify actual bottlenecks.

## Root FFI Deprecation Strategy

The root-level `crdt*.mbt` FFI files (`crdt.mbt`, `crdt_json.mbt`,
`crdt_undo.mbt`, `crdt_projection.mbt`, `crdt_ephemeral.mbt`,
`crdt_websocket.mbt`, `crdt_relay.mbt`) export ~57 functions to JS.
These remain unchanged during migration for backwards compatibility.

Deprecation timeline:
- **Phase 2-3:** `examples/web` and `examples/ideal` migrate to protocol.
  Root FFI still used by `examples/demo-react`.
- **Phase 5 (optional):** `examples/demo-react` migrates. At this point
  all consumers use the protocol.
- **After Phase 5:** Root FFI files can be removed or reduced to thin
  wrappers around protocol calls. This is a separate cleanup task.

## Steps

### Phase 0: Benchmark spike (validate JSON transport)

1. Write a microbenchmark: build a realistic ViewNode tree (100 defs,
   ~1000 nodes) via `proj_to_view_node`, serialize to JSON, parse in
   a JS test harness. Validate that round-trip is < 1ms.
2. If > 1ms: design the optimized FFI layer before Phase 1 instead of
   deferring it. If < 1ms: proceed with JSON as initial transport.

### Phase 1: Protocol types + ViewUpdater (`protocol/` + `editor/`)

3. Create `protocol/` package with `moon.pkg.json`
4. Add `ViewNode`, `TokenSpan`, `ViewPatch`, `Decoration`, `Diagnostic`,
   `UserIntent` types with `fn new(...)` constructors
5. Add custom `to_json`/`from_json` impls producing object-based JSON
   with `"type"` discriminators
6. Add `proj_to_view_node` helper (ProjNode[T] + SourceMap → ViewNode),
   including Module/let_def wrapper synthesis for Lambda
7. Add `SyncEditor::compute_view_patches` and `get_view_tree`
8. Unit tests in `protocol/` (round-trip serialization) and `editor/`
   (patch computation for insert, delete, wrap, undo edits)

### Phase 2: TS adapter library + examples/web migration

9. Create `lib/editor-adapter/` TS package with `EditorAdapter` interface,
    `ViewPatch`/`UserIntent`/`ViewNode` TS type definitions, JSON parsing
10. Implement `HTMLAdapter` — vanilla DOM patching (~60 lines)
11. Migrate `examples/web` tree rendering from `getKindTag`/`getKindDisplayValue`
    to `HTMLAdapter` consuming `ViewNode`. Simplify JSON editor inline form
    to use `UserIntent`.
12. Validate: `examples/web` works end-to-end with protocol

### Phase 3: CM6 + PM adapters

13. Implement `CM6Adapter` — text changes, decorations (mark + widget),
    selection (~80 lines)
14. Implement `PMAdapter` — schema definition, NodeView factories,
    node-level operations via `data-node-id`, node-id index (~200-300 lines)

### Phase 4: Migrate examples/ideal (highest impact, highest risk)

Break into independently testable sub-steps:

15. **(4a) Text editing via protocol** — CM6 keystroke → UserIntent →
    SyncEditor → TextChange patch → CM6Adapter. Remove `set_text_and_record`
    FFI call from canopy-editor.ts. Verify typing works.
16. **(4b) Structural editing via protocol** — PM structural edit →
    UserIntent(StructuralEdit) → SyncEditor → tree patches → PMAdapter.
    Remove `apply_tree_edit_json` FFI call. Verify wrap/delete works.
17. **(4c) Undo/redo via protocol** — UserIntent(Undo/Redo) → SyncEditor
    → patches. Remove `js_undo_and_sync`/`js_redo_and_sync`. Verify
    undo/redo works in both modes.
18. **(4d) Selection sync via protocol** — Outline click → SelectNode
    intent → CM6/PM selection. Remove `js_set_editor_selected_node` and
    `__canopy_pending_node_selection`. Verify outline ↔ editor selection.
19. **(4e) Action overlay via protocol** — Replace
    `js_get_selected_node_rect`, `js_take_action_overlay_node` with
    `adapter_get_node_rect`. Verify action overlay positioning.
20. **(4f) Remove globals** — Delete all `globalThis.__canopy_*` state,
    hidden trigger buttons, remaining `bridge_ffi.mbt` externs beyond
    the ~3 protocol externs. Full integration test.

### Phase 5: Migrate examples/prosemirror

21. Replace `convert.ts` + `reconciler.ts` + `bridge.ts` with PMAdapter
22. Simplify `main.ts` to: create editor → get_view_tree → apply patches
23. Remove duplicated TS reconciliation logic

### Phase 6: Migrate examples/demo-react

24. Replace Valtio proxy pattern with protocol-based React hook
25. Hook calls `compute_view_patches()` on each change

### Phase 7: Migrate examples/block-editor + BlockAdapter

26. Implement `BlockAdapter` (~100 lines) — renders ViewNode trees as
    contentEditable block elements. Each `ViewNode` with `editable=true`
    becomes a contentEditable div. Block type from `kind_tag`, ARIA roles
    derived automatically.
27. Map block model to ViewNode: document root with block children, each
    block has `kind_tag` (heading/paragraph/list_item/checkbox),
    `text` for content, `css_class` for level/checked state.
28. Move autoformat detection (` # ` → heading, `- ` → list, `- [ ]` →
    checkbox) from TS to MoonBit. TS sends `UserIntent::TextEdit`,
    MoonBit detects patterns and emits `ReplaceNode` with new `kind_tag`.
29. Replace block-editor FFI (`get_render_state`, `editor_set_block_text`,
    `editor_insert_block_after`, `editor_delete_block`,
    `editor_set_block_type`) with protocol intents.
30. Keep in TS: focus management between blocks, drag-and-drop gestures,
    file download/upload.
31. Enables Markdown editor (TODO §12) as: MoonBit Markdown parser →
    `proj_to_view_node` → BlockAdapter. No new TS code needed.

## Acceptance Criteria

- [ ] `protocol/` has ViewNode, ViewPatch, UserIntent types with custom
      object-based `to_json`/`from_json`
- [ ] Phase 0 benchmark confirms JSON round-trip < 1ms at 100-def scale
- [ ] `SyncEditor::compute_view_patches` returns correct patches for:
  - [ ] Single character insert/delete
  - [ ] Structural edit (wrap, delete)
  - [ ] Remote sync application
  - [ ] Undo/redo
- [ ] `proj_to_view_node` produces correct ViewNode from ProjNode[Term]
      and ProjNode[JsonValue], including let_def wrapper synthesis
- [ ] `examples/web` works with HTMLAdapter for tree rendering
- [ ] `examples/ideal` works with protocol (no globalThis.__canopy_*,
      no hidden buttons), tested incrementally via sub-steps 4a-4f
- [ ] `examples/prosemirror` works with PMAdapter (no local
      convert.ts/reconciler.ts)
- [ ] CM6Adapter correctly handles TextChange, SetDecorations (mark +
      widget), SetSelection
- [ ] PMAdapter correctly handles ReplaceNode, InsertChild, RemoveChild,
      UpdateNode (including leaf text updates)
- [ ] Rabbita outline, inspector, action overlay unaffected (still use
      direct InteractiveTreeNode model access)
- [ ] All existing tests pass: `moon test`, submodule tests, Playwright E2E
- [ ] No performance regression: protocol patch overhead < 1ms for typical
      edits at 100-def scale (benchmark with realistic content per project
      conventions)

## Validation

```bash
moon check
moon test
cd examples/web && npm run build
cd examples/ideal && npm run build
cd examples/prosemirror && npm run build
# Playwright E2E (demo-react has existing coverage)
cd examples/demo-react && npx playwright test
```

## Risks

- **PM position mapping** — PMAdapter needs to find PM document positions
  from NodeId. Strategy: maintain `data-node-id` attributes on PM nodes,
  walk PM doc to find target. May need an index for large documents.

- **Patch granularity** — `ReplaceNode` for any subtree change may be too
  coarse (replacing large subtrees when only one leaf changed). Mitigation:
  recursive diff in `compute_view_patches` emits minimal patches; leaf
  content changes use `UpdateNode(text~)` to avoid node replacement.

- **Rabbita VDOM integration** — Rabbita's `Html` type doesn't natively
  support "foreign widget slots." May need a `@rabbita.raw_element(dom_id)`
  or similar escape hatch. Current `ideal` uses a `<canopy-editor>` custom
  element which Rabbita renders as an opaque HTML tag — this likely works
  as-is.

- **Incremental decoration computation** — Recomputing all decorations on
  every edit may be expensive for large documents. Mitigation: only recompute
  decorations for changed SourceMap ranges. Defer optimization until
  profiling shows need.

- **Previous state storage** — ViewUpdater stores the previous ViewNode tree
  for diffing. At 1000 nodes this is ~100KB. Acceptable for the initial
  implementation; if memory is a concern, could diff ProjNode directly
  (reusing TreeEditorState's stamp comparison) instead of materializing
  ViewNode twice.

- **JSON serialization overhead** — The ViewNode tree for a 100-def module
  (~1000 nodes) must serialize, cross the FFI boundary, and parse in < 1ms.
  Phase 0 benchmark spike validates this assumption before committing to
  JSON transport. If validation fails, the optimized typed-FFI layer moves
  from "deferred" to "Phase 1 prerequisite."

- **SyncEditor type parameter** — `SyncEditor[T]` has a lambda-specific
  `proj_memo` field. `compute_view_patches` must use only the generic
  `cached_proj_node` path, not `proj_memo`. The `T : Renderable + TreeNode`
  bound is sufficient.

## Notes

- `InteractiveTreeNode[T]` (Rabbita native) and `ViewNode` (protocol)
  serve different purposes: `InteractiveTreeNode` carries UI state
  (`selected`, `collapsed`, `editing`, `drop_target`) and retains `T` for
  type-safe pattern matching in MoonBit. `ViewNode` is serializable,
  type-erased, and carries rendering hints (`css_class`, `editable`).
  Both are derived from `ProjNode[T]` + `SourceMap` but are not
  interchangeable.

- `TreeEditorState::refresh` implements the same "compare old vs new,
  skip unchanged subtrees" algorithm as `compute_view_patches`. The
  logic cannot be shared as a single function because the input and
  output types differ (`InteractiveTreeNode` vs `ViewNode`, UI state
  update vs patch emission), but the algorithm is identical.

- The existing `crdt*.mbt` FFI files remain during migration and are
  deprecated after all examples migrate (see "Root FFI Deprecation
  Strategy" section).

- Related TODO items: §10 Inspector panel, §11 Drag-and-drop foundation,
  §12 Multi-language support — all benefit from the protocol since new
  views/languages only need `proj_to_view_node` mapping, not new TS
  conversion code.
