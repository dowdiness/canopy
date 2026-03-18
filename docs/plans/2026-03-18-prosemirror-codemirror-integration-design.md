# ProseMirror + CodeMirror 6 Integration Design

## Summary

Integrate ProseMirror as the structural editing shell and CodeMirror 6 as inline text editors for leaf AST nodes, replacing the current contenteditable div and Rabbita tree renderer. ProseMirror's schema-driven document model mirrors the AST (ProjNode), while CM6 NodeViews handle text editing for variable names, integer literals, and lambda parameters. The eg-walker CRDT (TextDoc) remains the single source of truth; PM state is a derived view, reconciled after CRDT state changes.

This architecture is designed to generalize into a projectional editing framework where new content types are supported by defining new PM schemas and AST↔schema mappings.

## Motivation

1. **Better text editing UX** (highest priority) — contenteditable provides no syntax highlighting, keybindings, or proper cursor handling. CM6 delivers all three.
2. **Better structural editing** — the current Rabbita tree renderer is custom-built. PM provides battle-tested block manipulation, drag-drop, inline editing, decorations, and node views out of the box.
3. **Extensibility** — PM's plugin system and CM6's extension system provide rich ecosystems for autocomplete, linting, formatting, and future features.
4. **Collaboration** — peer cursors/selections rendered as PM Decorations, wired to the existing ephemeral presence system.

## Architecture Overview

Three layers connected by a TypeScript bridge:

```
┌─────────────────────────────────────────────────────────────────┐
│                     PRESENTATION LAYER                           │
│                                                                  │
│  ProseMirror EditorView                                         │
│  ├─ Structural PM nodes (module, lambda, application, if_expr)  │
│  └─ CM6 NodeViews for leaves (var_ref, int_literal, param)      │
│                                                                  │
│  User actions → PM Transactions or CM6 Changes                  │
└──────────────────────────┬───────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                       BRIDGE LAYER (TypeScript)                  │
│                                                                  │
│  Outbound: PM Transaction → classify → CRDT ops                 │
│  Inbound:  CRDT change → ProjNode diff → PM Transaction         │
│  Loop prevention via transaction metadata tagging                │
└──────────────────────────┬───────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    CRDT LAYER (MoonBit → JS FFI)                 │
│                                                                  │
│  SyncEditor: TextDoc + ImperativeParser + ProjNode memo          │
│  + SourceMap memo + Registry memo + UndoManager + EphemeralStore │
└─────────────────────────────────────────────────────────────────┘
```

### Authority Model

The CRDT TextDoc is always the source of truth. PM EditorState is a derived view — analogous to a React component rendering from a store. PM can propose changes, but the CRDT decides the canonical state. Consequences:

- PM state may temporarily diverge during edit → reconcile cycles
- Undo/redo uses SyncEditor.UndoManager, not PM's history plugin
- Collaboration uses eg-walker sync, not prosemirror-collab
- PM schema validation is advisory: CRDT text may parse to Error nodes; PM renders them without rejecting them

## PM Schema Definition

Each `@ast.Term` variant maps to a ProseMirror node type. The `term` group enforces valid nesting.

| MoonBit Term | PM Node Type | Content Expression | PM Children | Editable Part |
|---|---|---|---|---|
| `Int(n)` | `int_literal` | (atom, leaf) | 0 | CM6 inline: number (attr-driven) |
| `Var(name)` | `var_ref` | (atom, leaf) | 0 | CM6 inline: identifier (attr-driven) |
| `Unbound(name)` | `unbound_ref` | (atom, leaf) | 0 | CM6 inline: identifier with error styling |
| `Lam(x, body)` | `lambda` | `"term"` | 1 (body) | Param name as attr, rendered via custom NodeView with inline CM6 |
| `App(f, x)` | `application` | `"term term"` | 2 | Both children are nested PM nodes |
| `Bop(op, l, r)` | `binary_op` | `"term term"` | 2 | Operator stored as attr; operands are nested PM nodes |
| `If(c, t, e)` | `if_expr` | `"term term term"` | 3 | Three children: nested PM nodes |
| `Module(defs, body)` | `module` | `"let_def* term"` | N+1 | Top-level container, **not in term group** — only valid at doc level |
| `Unit` | `unit` | (atom, leaf) | 0 | Not editable |
| `Error(msg)` | `error_node` | (atom, leaf) | 0 | Not editable; renders error message |

Additional:
- `let_def`: content `"term"`, attrs `{ name: string }`. Child of `module`. **Not a ProjNode kind** — synthesized during ProjNode→PM conversion (see mapping note).

### Structural Mapping Notes

**Lambda nodes — param as attribute, not child:**
`ProjNode` for `Lam(param, body)` stores the parameter name as a string inside `Term::Lam` and has only **one child** (the body): `children: [body]`. To keep the PM tree 1:1 with ProjNode children, `lambda` stores the param name as an attribute and has content `"term"` (one child: body). The lambda's custom NodeView renders `λ[CM6: param].` before the body content hole, allowing inline editing of the param name without a separate child node.

**Module/let_def — synthesized PM nodes:**
`ProjNode` for `Module(defs, body)` stores children as `[def0_init, def1_init, ..., body]` with def names embedded in `Term::Module([(name, term), ...], body)`. There is no `LetDef` variant in `@ast.Term`. The bridge **synthesizes** `let_def` PM nodes during ProjNode→PM conversion:
- Each `(name, init)` pair → `let_def` PM node with `name` attr and `init` as child
- The final child → direct `term` child of `module`

During PM→ProjNode conversion (outbound), `let_def` nodes are **collapsed** back:
- Collect `let_def` children's names and init terms → Module def pairs
- The final non-let_def child → Module body

**Let_def name editing:**
`let_def` has a `name` attribute that needs inline editing (same problem as lambda `param`). The `LetDefView` custom NodeView renders `let [CM6: name] =` before the init expression content hole, using token spans from the parser (see Prerequisites).

Key schema decisions:
- Leaf nodes are `atom: true` — PM delegates rendering to CM6 NodeViews
- Lambda `param` is an attribute with a custom NodeView (not a separate PM child node) — matches ProjNode's 1-child structure
- `module` is **not** in the `term` group — it is only valid as a direct child of `doc`. This prevents structurally invalid nesting (Module inside Lambda/App/If), which the MoonBit parser only constructs at the source-file boundary.
- `term` group enforces that only valid AST nodes appear as children of compound terms
- Every node carries a `nodeId` attribute (default `null`, validated during conversion)
- `let_def` nodes carry a synthetic `nodeId` derived from the corresponding ProjNode init child's ID — this enables stable reconciliation
- `let_def` has a custom NodeView (`LetDefView`) with inline CM6 for the binding name, symmetric with `LambdaView`'s param editing
- No marks — lambda calculus has no inline formatting; future content types can add marks
- `text` node is reserved by PM but unused in this schema

```typescript
const schema = new Schema({
  nodes: {
    doc:          { content: "module | term" },
    module:       { content: "let_def* term",  // NOT in term group — only valid at doc level
                    attrs: { nodeId: { default: null } } },
    let_def:      { content: "term",
                    attrs: { name: { default: "x" }, nodeId: { default: null } } },
    lambda:       { content: "term", group: "term",
                    attrs: { param: { default: "x" }, nodeId: { default: null } } },
    application:  { content: "term term", group: "term",
                    attrs: { nodeId: { default: null } } },
    binary_op:    { content: "term term", group: "term",
                    attrs: { op: { default: "Plus" }, nodeId: { default: null } } },
    if_expr:      { content: "term term term", group: "term",
                    attrs: { nodeId: { default: null } } },
    int_literal:  { group: "term", atom: true,
                    attrs: { value: { default: 0 }, nodeId: { default: null } } },
    var_ref:      { group: "term", atom: true,
                    attrs: { name: { default: "x" }, nodeId: { default: null } } },
    unbound_ref:  { group: "term", atom: true,
                    attrs: { name: { default: "x" }, nodeId: { default: null } } },
    error_node:   { group: "term", atom: true,
                    attrs: { message: { default: "" }, nodeId: { default: null } } },
    unit:         { group: "term", atom: true,
                    attrs: { nodeId: { default: null } } },
    text:         {},
  },
  marks: {}
});
```

## Selection Model: Dual Ownership

PM and CM6 own different selection scopes. This is a fundamental architectural constraint: PM atom nodes expose only boundary positions (before/after the atom), not per-character positions inside the atom. Therefore PM selections and decorations **cannot address offsets within CM6 leaves**.

### Structural Selection (PM-owned)

PM's selection system handles:
- Selecting entire nodes (click on a node → `NodeSelection`)
- Moving between nodes (arrow keys at CM6 boundaries escape to PM)
- Range selection across multiple nodes (shift-click, shift-arrow)
- Drag-and-drop source/target selection

### Intra-leaf Selection (CM6-owned)

Each CM6 instance manages its own:
- Cursor position within the leaf text
- Text selection ranges within the leaf
- IME/composition state

When a CM6 instance is focused, PM has a `NodeSelection` on the containing atom. The character-level cursor/selection is entirely within CM6.

### Peer Cursor Rendering (Split by Scope)

Remote peer cursors fall into two cases:

**Structural cursors** (peer has a node selected, or cursor is between nodes):
- Rendered as PM Widget/Inline Decorations
- PM positions are sufficient — just mark the node boundary

**Intra-leaf cursors** (peer's cursor is inside a leaf text):
- PM decorations **cannot** render inside atom nodes
- Instead: the bridge resolves the CRDT cursor position to a `(nodeId, localOffset)` pair
- Each CM6 NodeView receives its relevant peer cursors via a CM6 `StateField`
- CM6 renders peer cursors as CM6 Decorations (colored line + name label) within its own instance
- The bridge distributes cursor updates to the correct CM6 instance by nodeId

```typescript
// Bridge distributes peer cursors to CM6 instances
interface PeerCursorDistributor {
  // Called when remote presence updates arrive
  updatePeerCursors(cursors: PeerCursor[]): void;

  // Each CM6 NodeView registers itself
  registerLeafView(nodeId: number, cmView: EditorView): void;
  unregisterLeafView(nodeId: number): void;
}

interface PeerCursor {
  peerId: string;
  peerName: string;
  color: string;
  // Resolved to node-local coordinates:
  nodeId: number;        // which leaf the cursor is in
  localOffset: number;   // offset within that leaf
}
```

## Position Coordinate Systems

Three distinct position spaces exist in this architecture:

| Space | What it counts | Example |
|---|---|---|
| **CRDT text position** | Character offset in source text (`0..text.length`) | `let x = 1\nx` → `x` at the end is position 11 |
| **PM document position** | Structural position counting node open/close tokens | Each node boundary adds 1; **atoms count as 1 opaque unit** (no internal positions) |
| **CM6 local offset** | Character offset within a single CM6 instance | Always `0..leaf_text.length` |

**Critical constraint:** PM positions cannot address offsets inside atom nodes. An `int_literal` with value `42` occupies exactly 1 PM position. The bridge must convert between CRDT text positions and `(nodeId, localOffset)` pairs for any intra-leaf operation.

### Conversion: CRDT text pos → (nodeId, localOffset)

1. Find which ProjNode contains the text position via SourceMap (`innermost_node_at(pos)`)
2. `localOffset = pos - sourceMap.get_range(nodeId).start`
3. This pair can then be used to:
   - Target a specific CM6 instance (for peer cursor rendering)
   - Compute a PM boundary position (for structural operations): walk PM doc to find node with matching `nodeId`

### Conversion: CM6 local offset → CRDT text pos

1. The CM6 NodeView knows its `nodeId` (captured at construction)
2. Look up `SourceMap.get_range(nodeId).start`
3. CRDT position = `sourceMap.get_range(nodeId).start + cm6_offset`

### Conversion: PM doc pos → CRDT text pos

1. Resolve PM position to the nearest PM node (atoms resolve to the whole node)
2. Read `nodeId` from the PM node's attributes
3. Look up `SourceMap.get_range(nodeId)` → `(start, end)` in CRDT text space
4. For atom nodes: returns the node's start position (no finer granularity in PM)
5. For compound nodes with `contentDOM`: `start + local_offset` where offset is computed from child boundaries

## Bridge Layer

### Outbound: Editor → CRDT

PM transactions are intercepted via `dispatchTransaction` override. The bridge classifies each transaction to decide whether it modifies the document (authoritative — must route through CRDT) or is view-only (ephemeral — apply directly to PM):

```
PM Transaction (intercepted by dispatchTransaction)
  │
  ├─ has metadata { fromCrdt: true }?
  │    → apply directly to PM state (came from reconciler, skip CRDT)
  │
  ├─ is view-only? (no doc changes — selection, scroll, plugin state)
  │    → apply directly to PM state
  │    → this includes: selection updates, IME composition state,
  │      plugin state transitions, scroll position changes
  │    → detection: tr.docChanged === false
  │
  ├─ originated from CM6 NodeView? (leaf text edit)
  │    → for each character change in CM6 ChangeSet:
  │        1. look up nodeId from the PM node's attrs
  │        2. compute CRDT text position:
  │           SourceMap.get_range(nodeId).start + cm6_offset
  │        3. set SyncEditor cursor to computed CRDT position,
  │           then call insert_and_record(char, timestamp)
  │           or delete_and_record(timestamp)
  │        (character-at-a-time — required for proper CRDT interleaving)
  │    → after all CRDT ops: reconcile() to update PM state from CRDT
  │
  │    NOTE: insert_and_record / delete_and_record are cursor-based APIs
  │    (they operate at the current cursor position). The bridge must
  │    move_cursor() before each op. A new position-based API
  │    (insert_at / delete_at) would be cleaner and avoid mutating
  │    shared cursor state — this is a recommended prerequisite.
  │
  └─ structural PM step? (drag, delete node, wrap, insert child)
       → map PM node attrs → NodeIds
       → construct TreeEditOp (Delete, WrapInLambda, Drop, etc.)
       → call SyncEditor.apply_tree_edit()
       → round-trips: apply_edit_to_proj → unparse → set_text_and_record
       → reconcile() to update PM state from CRDT
```

**Transaction classification rule:**
- `tr.docChanged === false` → **apply directly** (ephemeral view state: selection, scroll, IME, plugin state). PM needs these to function correctly — selection updates, composition state, and drag-hover feedback must apply synchronously.
- `tr.docChanged === true` and no `fromCrdt` metadata → **route through CRDT** (authoritative edit). The original PM transaction is dropped; PM state is updated via reconcile after the CRDT processes the edit.
- `tr.getMeta("fromCrdt") === true` → **apply directly** (inbound from reconciler).

**Why doc-changing transactions are dropped:** The CRDT is the source of truth. The bridge routes edits through the CRDT, then reconciles PM state from the CRDT's derived ProjNode. This ensures PM always reflects the CRDT's canonical state and avoids divergence.

**Character-at-a-time for leaf edits:** Multi-character changes from CM6 are split into individual insert/delete ops. This matches the CRDT design philosophy (CLAUDE.md: "Character-level ops: Split multi-char inserts into individual chars") and ensures proper interleaving of concurrent edits from multiple peers.

### Inbound: CRDT → Editor

When CRDT state changes (from tree edit round-trip or remote sync):

1. `get_proj_node()` → new ProjNode tree with stable node IDs
2. Tree-diff current PM doc against new ProjNode (see Reconciler section):
   - Match nodes by `nodeId` attribute
   - Same type + same attrs → recurse into children
   - Attr mismatch → AttrStep
   - Type mismatch or missing/extra nodes → ReplaceStep
   - The reconciler walks both trees in parallel, tracking PM positions during traversal (not from SourceMap — PM positions must be computed structurally)
3. Dispatch PM transaction with `{ fromCrdt: true }` metadata
4. PM applies → NodeViews update → CM6 instances receive new content via `update()` method

### Loop Prevention

Every transaction is tagged with its origin via PM metadata:

- `dispatchTransaction` override intercepts all transactions before they reach PM state
- Transactions with `fromCrdt: true` are applied directly to PM (skip outbound handler)
- All other transactions are routed through the CRDT, then PM is updated via reconcile
- CM6 NodeViews use an `updating` boolean flag to prevent `forwardUpdate()` from firing during inbound reconcile updates

### TypeScript Interface

```typescript
interface CrdtBridge {
  // Outbound: called by PM dispatchTransaction override
  handleTransaction(tr: Transaction): void;

  // Inbound: called after CRDT state changes
  reconcile(): void;

  // Sync: called by WebSocket handler
  applyRemote(syncJson: string): void;
  exportSince(versionJson: string): string;

  // Leaf edits from CM6 NodeViews: SourceMap lookup + char-at-a-time CRDT ops
  handleLeafEdit(nodeId: number, cmUpdate: ViewUpdate): void;

  // Position conversion (used by cursor broadcast + peer rendering)
  crdtPosToPmPos(crdtPos: number): number;
  pmPosToCrdtPos(pmPos: number): number;
}
```

## CM6 NodeView Integration

### Which Nodes Use CM6

Two categories of CM6 usage:

**Leaf NodeViews** (atom nodes — CM6 is the entire rendering):
- `int_literal` — edit the number value
- `var_ref` — edit the variable name
- `unbound_ref` — edit the variable name (with error styling)

**Inline CM6 within compound NodeViews** (CM6 for an attribute, PM renders children):
- `lambda` — the `param` attribute is rendered as an inline CM6 editor before the body content hole

All other nodes use PM's default rendering for structural layout.

### NodeView Design

```typescript
class TermLeafView implements NodeView {
  dom: HTMLElement;
  cm: EditorView;           // CM6 instance
  node: ProsemirrorNode;
  view: EditorView;         // PM view
  getPos: () => number;
  nodeId: number;            // captured from node.attrs.nodeId
  bridge: CrdtBridge;        // reference to bridge for SourceMap access
  updating: boolean;         // loop prevention flag

  constructor(node, view, getPos, bridge) {
    this.nodeId = node.attrs.nodeId;
    this.bridge = bridge;
    // Create CM6 with node's attr-derived text value
    // e.g., for var_ref: node.attrs.name
    //        for int_literal: String(node.attrs.value)
    // Single-line, no gutters, no line numbers — inline editor
    // Wire CM6 onChange → forwardUpdate()
  }

  // PM → CM6: called when PM doc changes (inbound reconcile)
  update(node) {
    if (node.type !== this.node.type) return false;
    this.updating = true;
    this.nodeId = node.attrs.nodeId;  // may change after reconcile
    // diff old vs new attr text, apply CM6 ChangeSet
    this.node = node;
    this.updating = false;
    return true;
  }

  // CM6 → PM: called when user types in CM6
  forwardUpdate(cmUpdate) {
    if (this.updating) return;
    // Route through bridge — bridge handles:
    //   1. SourceMap.get_range(this.nodeId).start + cm6_offset → CRDT pos
    //   2. Character-at-a-time insert/delete on CRDT
    //   3. Reconcile PM state from CRDT
    this.bridge.handleLeafEdit(this.nodeId, cmUpdate);
  }

  // Focus coordination
  selectNode() { this.cm.focus(); }

  // Arrow key escape: when cursor hits edge of CM6,
  // move PM selection to next/prev node
  arrowHandler(dir) { /* ... */ }

  destroy() { this.cm.destroy(); }
}

// Lambda NodeView: structural node with inline CM6 for param name
class LambdaView implements NodeView {
  dom: HTMLElement;
  contentDOM: HTMLElement;    // PM manages children here (the body)
  paramCm: EditorView;       // CM6 for param name editing
  node: ProsemirrorNode;
  // ... similar lifecycle to TermLeafView.
  //
  // PARAM EDITING STRATEGY:
  // SourceMap stores whole-node spans only — it does NOT expose token-level
  // subranges (e.g., where the param name starts/ends within a lambda).
  // Raw offset arithmetic ("start + 1 for λ") is fragile: it assumes a
  // fixed surface form, breaks with whitespace/comments, and confuses
  // character offsets with byte offsets (λ is 2 UTF-8 bytes but 1 char).
  //
  // SOLUTION: Extend the projection layer to expose token spans.
  // The parser (LambdaExprView) already knows the param token's exact
  // character range. Add a `param_range: (Int, Int)?` field to ProjNode
  // for Lam nodes (or to a new TokenSpanMap alongside SourceMap).
  // The bridge reads param_range to compute the CRDT text position for
  // param edits, same as leaf edits: param_range.start + cm6_offset.
  //
  // This approach also applies to let_def names, which have the same
  // problem (see "let_def name editing" section below).
  //
  // PREREQUISITE: Expose token-level spans from the parser/projection
  // layer. See Prerequisites section.
}

// Let_def NodeView: structural node with inline CM6 for binding name
class LetDefView implements NodeView {
  dom: HTMLElement;
  contentDOM: HTMLElement;    // PM manages the init expression child
  nameCm: EditorView;        // CM6 for let binding name editing
  node: ProsemirrorNode;
  // Same token-span strategy as LambdaView.paramCm.
  // The parser (LetDefView) knows the name token's character range.
  // Bridge reads name_range from TokenSpanMap to compute CRDT positions.
}
```

### CM6 Configuration

- **Minimal chrome**: no gutters, no line numbers, no scrollbar — these are inline editors
- **Single-line mode**: leaf values are always single tokens
- **Shared extensions**: syntax highlighting theme and keybindings defined once, reused via CM6 `Compartment`
- **Lazy instantiation** (optional optimization): CM6 instances could be created on first focus and destroyed when the node is removed, with collapsed subtrees skipping creation. However, `NodeView.update()` must handle the case where CM6 is not yet instantiated — store pending attr values and apply them when CM6 is created. For the initial implementation, eager CM6 creation is simpler and sufficient.

### Performance

Many CM6 instances for large ASTs is a potential concern. Mitigations:
1. Only leaf nodes have CM6 — compound nodes (App, If, Lam) use PM rendering
2. Collapsed subtrees skip CM6 creation entirely
3. CM6 is lightweight when minimal (no workers, no complex state)
4. Lazy instantiation means off-screen leaves don't allocate CM6

## Reconciler: ProjNode → PM Doc Diffing

### Strategy

Tree-diff, not text-diff. Walk the ProjNode tree and PM document tree in parallel, emitting PM steps only where they diverge.

### Algorithm

The reconciler walks both trees in parallel, tracking PM document positions during traversal. PM positions are computed by structural traversal (counting node boundaries), **not** from SourceMap (which stores CRDT text positions, a different coordinate space).

```
reconcile(pmNode, projNode, pmPos, tr):
  // pmPos tracks the current PM document position during traversal

  1. Compare node types (pmNode.type.name vs projNode.kind tag)
     - mismatch → ReplaceStep: swap entire subtree at pmPos

  2. Compare attrs (var name, int value, op type)
     - mismatch → AttrStep: update in place
     - always update nodeId attr to match projNode.node_id

  3. Handle structural mapping asymmetries:
     - For `module`: synthesize/collapse let_def wrappers
       (ProjNode children [init0, init1, ..., body] ↔ PM children [let_def0, let_def1, ..., term])
     - For `lambda`: compare param attr (not a child)
     - All others: direct 1:1 child mapping

  4. Compare children count + order
     - same count → recurse into each child pair, advancing pmPos
     - different → use ProjNode's stable node_id for matching:
         * matched pairs → recurse
         * new nodes → insert step
         * removed nodes → delete step
         * reordered → delete + insert

  5. For CM6 NodeViews (atom leaves):
     - attr change triggers NodeView.update()
     - CM6 receives new text, applies internal diff
```

**Note:** The MoonBit codebase already has `reconcile_ast` and `reconcile_children` (using LCS) in `projection/reconcile_ast.mbt`. The TypeScript reconciler performs a similar operation in PM's coordinate space. Consider running the MoonBit reconciler first and only converting the resulting diff to PM steps, to maintain behavioral parity and avoid reimplementing the matching logic.

### Node Identity: Guarantees and Limitations

The reconciler uses `nodeId` attrs on PM nodes to match old PM nodes to new ProjNodes, preserving focus, selection, and scroll position where possible.

**Current identity guarantees (best-effort, not absolute):**
- FlatProj reconciliation preserves IDs for let-def initializers matched by name
- Children reconciliation uses LCS on kind tags — same-shaped siblings at stable positions keep their IDs
- The parser's incremental reuse (ReuseCursor) preserves subtree identity for unchanged regions

**Known limitations:**
- `FlatProj::to_proj_node` allocates a **fresh Module node ID** on every rebuild — the root container's ID is not stable
- LCS matching on same-shaped siblings (e.g., multiple `Var` children) can **swap IDs** after edits or reorders — the match is by shape, not by content
- Newly parsed nodes always get fresh IDs

**Consequences for the PM integration:**
- The reconciler must handle `nodeId` mismatches gracefully: when IDs don't match, fall back to type+content comparison instead of tearing down the subtree
- The root `module` PM node should not rely on `nodeId` for NodeView reuse — use a sentinel or always-update strategy
- Focus preservation is best-effort: rapid structural edits (especially reordering same-shaped siblings) may cause focus loss. This is acceptable for the initial implementation.

**Prerequisite improvement (recommended):** Strengthen `FlatProj::to_proj_node` to preserve the Module node's ID across rebuilds (e.g., carry the previous Module ID as a seed). This is a small change in `projection/flat_proj.mbt` that would significantly improve reconciler stability.

### When to Reconcile

- After `apply_tree_edit()` — structural edit round-tripped through text
- After `apply_sync_json()` — remote changes merged
- After CM6 leaf edits — character-at-a-time CRDT ops update the text, reconcile syncs PM state
- **Performance note**: `reconcile()` is called on every keystroke in CM6 NodeViews. **The memo is invalidated on every text change**, so each reconcile triggers: full ProjNode rebuild from CST, fresh Registry and SourceMap construction from the root, then a tree-diff against the PM doc. For small-to-medium ASTs this is acceptable, but it is **not** a cheap memo hit — it is proportional to the tree size.

  **Mitigation strategy (required for large documents):** Batch inbound PM refreshes to `requestAnimationFrame`. During rapid typing, accumulate CRDT ops synchronously (they are cheap — character-level inserts), but defer the reconcile to the next animation frame. This means PM state lags by at most one frame (~16ms) during typing, which is imperceptible. The architecture supports this: CM6 displays the user's edits immediately (it owns intra-leaf state), and the PM structural view updates on the next frame.

## Collaboration & Presence

### Sync Flow

No changes to the existing sync protocol:

```
Local edit → CRDT ops → export_since_json() → WebSocket → peers
Peers → WebSocket → apply_sync_json() → reconcile() → PM updates
```

### Peer Cursors

Dual rendering strategy matching the dual-selection model (see "Selection Model: Dual Ownership" section):

**Structural cursors** (peer has a node selected, or cursor is between nodes):
- Rendered as PM Widget/Inline Decorations
- PM positions are sufficient — mark the node boundary

**Intra-leaf cursors** (peer is typing inside a leaf):
- Rendered as CM6 Decorations within the relevant CM6 instance
- The `PeerCursorDistributor` routes cursor updates to the correct CM6 NodeView by `nodeId`
- Each CM6 instance renders its peer cursors as colored lines + name labels via a CM6 `StateField`

### Local Cursor Broadcast

Two sources of cursor updates:

**PM selection changes** (structural navigation):
- Extract `{ from, to }` from PM selection
- Resolve to containing node's `nodeId` → `SourceMap.get_range(nodeId).start`
- Call `SyncEditor.ephemeral_set_presence_with_selection()`

**CM6 cursor changes** (intra-leaf typing):
- Extract cursor position from the focused CM6 instance
- Compute CRDT text position: `SourceMap.get_range(nodeId).start + cm6_offset`
- Call `SyncEditor.ephemeral_set_presence_with_selection()`

### Remote Cursor Rendering

On remote presence update:
- `ephemeral_get_peer_cursors_json()` returns CRDT text positions
- Resolve each cursor to `(nodeId, localOffset)` via SourceMap
- Classify: is the target node an atom (leaf)?
  - **Yes** → route to the CM6 instance via `PeerCursorDistributor`
  - **No** → compute PM boundary position, render as PM Decoration

## Framework Generalization

The architecture is designed to extend beyond lambda calculus. The bridge layer works with generic PM Transactions, TreeEditOps, and SyncEditor. Only the schema mapping is language-specific.

### Pluggable Schema Layer

```
Schema Registry:
  register("lambda-calculus", {
    astToSchema:   Term → PM NodeSpec mapping
    schemaToAst:   PM Node → Term mapping
    parser:        text → CST → AST
    printer:       AST → text
    lezerGrammar:  (optional) CM6 syntax highlighting grammar
  })

  register("markdown", { ... })      // future
  register("json-schema", { ... })   // future
  register("custom-dsl", { ... })    // user-defined
```

Each registration provides:
- **Schema mapping**: bidirectional conversion between AST nodes and PM node types
- **Parser/printer**: text ↔ AST conversion (already exists as MoonBit loom infrastructure)
- **Optional Lezer grammar**: for CM6 syntax highlighting in inline editors

The Bridge Layer, Reconciler, CM6 NodeView infrastructure, and collaboration system remain unchanged across content types.

## Relationship to Existing Architecture

### What Changes

| Component | Current | After Integration |
|---|---|---|
| Text input | contenteditable div | CM6 NodeViews inside PM |
| Tree rendering | Rabbita TreeEditorState | ProseMirror NodeViews + schema |
| Selection/focus | Custom DOM management | PM selection system |
| Drag-drop | Custom TreeEditOp handlers | PM drag plugin → TreeEditOp bridge |
| Cursor rendering | Custom DOM elements | PM Decorations |

### Candidates for Deprecation

The following MoonBit infrastructure becomes largely redundant with PM's state management:
- `TreeEditorState` (`projection/tree_editor.mbt`) — PM handles selection, collapse, editing state
- `InteractiveTreeNode` / `InteractiveChildren` — PM NodeViews replace this rendering layer
- Rabbita frontend (`examples/rabbita/`) — replaced by the new PM+CM6 frontend

### What Stays the Same

| Component | Reason |
|---|---|
| SyncEditor | Remains the CRDT authority — no changes needed |
| TextDoc / FugueMax | Character-level CRDT unchanged |
| ProjNode / SourceMap / Registry | Derived views still computed by memo chain |
| TreeEditOp | Structural edit vocabulary unchanged — PM bridge translates to these |
| tree_edit_bridge.mbt | Round-trip logic unchanged |
| UndoManager | Still authoritative for undo/redo |
| EphemeralStore | Still handles presence; PM decorations are a new rendering layer |
| Sync protocol | export_since / apply_sync unchanged |
| ImperativeParser | Incremental parsing unchanged |

### Hylomorphism Pipeline Integration

This design fits into the pipeline from `Incremental-Hylomorphism.md` at stage ④:

```
① CRDT Ops → Text (fold over operation history)
② Text → CST (anamorphism: parsing via loom)
③ CST → Typed AST (catamorphism: incremental type check)
④ AST → Screen Display (catamorphism: rendering)
    ↑
    PM + CM6 replace the current rendering catamorphism
    PM schema is the "algebra" that maps AST → display
    CM6 NodeViews are the leaf rendering strategy
```

## Dependencies

- `prosemirror-model` — schema, document model
- `prosemirror-state` — editor state, transactions, plugins
- `prosemirror-view` — DOM rendering, NodeViews, decorations
- `prosemirror-transform` — steps, mapping
- `@codemirror/state` — CM6 editor state
- `@codemirror/view` — CM6 editor view, decorations
- `@codemirror/language` — syntax highlighting infrastructure

Not used:
- `prosemirror-collab` — replaced by eg-walker sync
- `prosemirror-history` — replaced by SyncEditor.UndoManager
- `@codemirror/collab` — replaced by eg-walker sync

## Open Questions

1. **CM6 lazy instantiation threshold** — at what AST size should we start lazy-creating CM6 instances? Start with eager creation; optimize if profiling shows it matters.
2. **PM schema strictness** — should the schema reject invalid AST structures, or should it be permissive and let error_nodes represent anything? Leaning permissive to match the parser's error recovery philosophy.
3. **Lezer grammar for lambda calculus** — should we write a Lezer grammar for CM6 syntax highlighting, or use a simpler token-based highlighter? Lezer is more correct but adds maintenance. For the initial implementation, a simple token colorizer is sufficient since CM6 leaf editors show only single tokens.
4. **Virtualization** — for very large documents, should PM render only visible nodes? PM doesn't have built-in virtualization. May not matter for AST-level documents (far fewer nodes than text lines).
5. **Transition plan** — recommend clean replacement (new `examples/prosemirror/` directory) rather than coexistence. The current web frontend (`examples/web/src/editor.ts`) is only ~77 lines. The Rabbita frontend can remain as-is for comparison during development and deprecated once the PM frontend is stable.

## Prerequisites

Before or alongside the PM integration, these codebase changes are needed:

1. **Add `Unbound` to `same_kind_tag`** — `projection/proj_node.mbt` line 304 is missing `(Unbound(_), Unbound(_)) => true`. Without this, the MoonBit reconciler will never match old `Unbound` nodes to new ones, causing unnecessary node replacement and ID churn.

2. **Expose token-level spans from the parser/projection layer** — SourceMap currently stores only whole-node `(start, end)` spans. Lambda param names and let_def binding names need their own character ranges for inline CM6 editing. Options:
   - Add `param_range: (Int, Int)?` field to ProjNode for `Lam` nodes
   - Add `name_range: (Int, Int)?` to the let_def representation
   - Or create a `TokenSpanMap` alongside SourceMap that maps `(nodeId, token_role)` → `(start, end)`
   - The parser views (`LambdaExprView`, `LetDefView`) already know these ranges — the plumbing just needs to surface them.

3. **Stabilize Module node_id across rebuilds** — `FlatProj::to_proj_node` allocates a fresh Module ID every time. The PM reconciler needs a stable root ID to avoid tearing down the entire PM document on every edit. Fix: carry the previous Module node_id as a seed in the memo chain.

4. **Add position-based edit API to SyncEditor** (recommended) — Current `insert_and_record` / `delete_and_record` are cursor-based (they operate at the current cursor position and mutate shared cursor state). The bridge needs a position-based API (`insert_at(pos, char, timestamp)` / `delete_at(pos, timestamp)`) that does not require moving the cursor. This avoids cursor-state coupling between PM and the CRDT.

5. **Verify duplicate let-names** — If the language allows duplicate `let` names (e.g., `let x = 1\nlet x = 2\nx`), the current `FlatProj` reconciliation-by-name may swap IDs between same-named definitions. This would cause the PM reconciler to match the wrong let_def nodes. Verify whether this is a real scenario and, if so, strengthen the reconciliation to use position or sequence number as a tiebreaker.
