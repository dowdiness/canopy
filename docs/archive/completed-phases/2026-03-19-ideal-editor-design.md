# Canopy Ideal Editor — Design Spec

## Overview

A unified editor combining the best features from all four example apps (web, demo-react, prosemirror, rabbita) into a single, configurable workbench.

**Core decisions:**
- **Rabbita** (MoonBit Elm architecture) hosts the entire application
- **ProseMirror + CodeMirror 6** handle the editor surface inside a Web Component
- **SyncEditor** (MoonBit) is the single source of truth
- Two rendering modes: **Text Mode** (code-first) and **Structure Mode** (block-first)
- All panels are configurable and toggleable

## System Architecture

Three layers, one source of truth:

| Layer | Language | Responsibility |
|---|---|---|
| **Rabbita Host** | MoonBit | Model/Msg/update/view. Toolbar, outline, inspector, bottom panels, peers. Renders `<canopy-editor>` as opaque custom element |
| **`<canopy-editor>`** | JS/TS | Web Component wrapping PM+CM6. Shadow DOM isolates from Rabbita VDOM. Handles drag-drop, decorations, clipboard, inline widgets |
| **MoonBit Backend** | MoonBit | SyncEditor (CRDT + parser + projection + undo + ephemeral). Single source of truth |

### Why Web Component

Rabbita's virtual DOM diffs and patches the real DOM every render cycle. If PM/CM6 lived in Rabbita-managed DOM, the next diff would destroy their state. A Web Component with Shadow DOM creates a hard isolation boundary — Rabbita can never see or touch the DOM inside it. This is the Elm community consensus for code editor integration.

### Shared Module Instance

Both Rabbita and the Web Component call SyncEditor methods on the **same MoonBit JS module instance**. The Web Component is not fully encapsulated — it receives a reference to the SyncEditor handle at initialization and calls FFI functions directly (e.g., `crdt.get_proj_node_json(handle)`, `crdt.get_source_map_json(handle)`). The Shadow DOM isolates the **DOM**, not the **data**. This mirrors how the existing prosemirror bridge works.

### Communication Pattern

- **Rabbita → Web Component**: `raw_effect` sets properties (`.projNode`, `.mode`, `.peers`, `.errors`)
- **Web Component → Rabbita**: `CustomEvent` dispatches Msgs (`text-change`, `node-selected`, `structural-edit`)
- **Loop prevention**: External `.projNode` sets trigger PM reconciliation with a `fromExternal` transaction annotation. PM's `dispatchTransaction` checks this and suppresses the `text-change` event.

### Initialization Sequence

```
1. Rabbita mounts, renders <canopy-editor> via @html.node("canopy-editor", attrs, [])
   Rabbita attaches event listeners via Attrs::handler for text-change, node-selected, etc.
2. raw_effect(AfterRender): calls mount_editor(crdt_handle)
   Passes the SyncEditor handle so the Web Component can call FFI directly.
3. Web Component creates PM EditorView + CM6 instances in Shadow DOM
4. Web Component calls crdt.get_proj_node_json(handle) for initial ProjNode
5. PM reconciler builds initial document from ProjNode
6. Editor is ready — user can type
   All communication uses DOM CustomEvents (fired on the <canopy-editor> element).
   Rabbita's Attrs::handler listeners receive them.
```

## Model

```
struct Model {
  editor : SyncEditor
  outline_state : TreeEditorState   // for outline panel only
  mode : EditorMode                 // Text | Structure
  workspace : WorkspaceLayout       // which panels are visible
  cursor : CursorInfo?              // from CM6 events
  selected_node : NodeId?           // from PM selection events
  diagnostics_open : Bool
  peers : Array[PeerInfo]
  next_timestamp : Int
  projection_dirty : Bool
  refresh_scheduled : Bool
  bottom_tab : BottomTab
  op_log : Array[OpLogEntry]        // circular buffer, max 100 entries
}

enum EditorMode { Text; Structure }
enum BottomTab { Problems; OpLog; CrdtState; Graphviz }
enum PanelId { Outline; Inspector; Bottom }

struct CursorInfo {
  line : Int
  col : Int
  offset : Int
}

struct WorkspaceLayout {
  outline_visible : Bool
  inspector_visible : Bool
  bottom_visible : Bool
}
```

## Messages

```
enum Msg {
  // Mode & layout
  SetMode(EditorMode)
  TogglePanel(PanelId)
  SelectBottomTab(BottomTab)

  // From Web Component (PM+CM6 events)
  TextChange(node_id: String, start: Int, delete_len: Int, inserted: String)
  CursorMove(line: Int, col: Int, offset: Int)
  NodeSelected(node_id: String)
  StructuralEditRequested(op: String, node_id: String)  // request, not done yet

  // Projection
  RefreshProjection

  // Collaboration
  SyncReceived(String)
  SyncBroadcast
  PeerPresenceUpdate(name: String, data: String)

  // Undo/redo (from toolbar buttons or Web Component request-undo/request-redo events)
  Undo
  Redo

  // UI
  LoadExample(String)
  OutlineNodeClicked(NodeId)
}
```

## Web Component Interface

### Properties (Rabbita → PM)

| Property | Type | Purpose |
|---|---|---|
| `.projNode` | `JSON` | Projected AST (ProjNode tree). PM reconciler diffs against current PM doc and patches incrementally. This is the primary state channel — NOT raw text. |
| `.sourceMap` | `JSON` | Source position mapping. Needed by NodeViews to map node-relative edits to CRDT positions. |
| `.mode` | `"text" \| "structure"` | Switches NodeView rendering style |
| `.peers` | `JSON` | Peer cursor positions for decorations |
| `.errors` | `JSON` | Diagnostics for squiggly underlines |
| `.selectedNode` | `String?` | Highlight node from outline click |
| `.readonly` | `Bool` | Disable editing |

Note: The Web Component also has direct access to the SyncEditor handle (passed at initialization). It calls `crdt.get_proj_node_json()` and `crdt.get_source_map_json()` itself for the initial state. After initialization, Rabbita pushes updates via properties when external changes occur (structural edits, remote sync).

### Events (PM → Rabbita)

| Event | Detail | Purpose |
|---|---|---|
| `text-change` | `{nodeId, start, deleteLen, inserted}` | Per-leaf-node edit from CM6. `start` is relative to the node's span, mapped to CRDT position via SourceMap. Multiple CM6 instances (one per leaf) fire independently. |
| `cursor-move` | `{line, col, offset}` | Cursor position |
| `node-selected` | `{nodeId, kind, label}` | PM NodeSelection changed |
| `structural-edit-request` | `{op, nodeId}` | User initiated a drag-drop or action. This is a **request**, not a completed operation — Rabbita applies it to the CRDT first, then reconciles PM. |
| `request-undo` / `request-redo` | `{}` | User pressed Cmd+Z inside PM. Maps to `Undo`/`Redo` Msg. |

## PM NodeView Modes

### Text Mode NodeViews

Code-style rendering. Each AST node renders as syntax-colored inline text. CM6 instances handle editable leaves (parameters, literals, variable names).

Inline widgets:
- **Number sliders**: CM6 widget decorations on integer literals. Drag to change value.
- **Eval ghost text**: PM line decorations showing reduction results at end of lines.
- **Type annotations**: PM decorations showing inferred types, muted color.
- **Peer cursors**: PM widget decorations with colored carets and name labels.
- **Error squigglies**: PM mark decorations for parse errors.

### Structure Mode NodeViews

Block-style rendering. Each AST node renders as a bordered, draggable box with nesting.

Interactions:
- **Drag-and-drop**: PM handles drag ghosts, snap targets, valid drop positions via schema validation.
- **Collapse/expand**: Per-node visibility toggle.
- **Inline edit**: Double-click opens CM6 for that node's text.
- **Node type tags**: LET, LAMBDA, BINOP as styled badges.
- **Slider widgets**: On integer literal nodes.
- **Node palette**: Sidebar with draggable templates (lambda, let, if, integer, variable).

### Mode Transition

Setting `.mode` on the Web Component triggers PM NodeViews to re-render in the new style. No CRDT change — same text, different rendering.

**Implementation:** Each NodeView constructor checks the current mode and renders accordingly. When mode changes, the Web Component calls `view.updateState(view.state)` which forces all NodeViews to re-render via their `update()` method. This is approach (2) from PM's options: NodeViews that internally switch rendering based on a mode flag.

### Theming

Shadow DOM isolates styles — PM/CM6 CSS cannot inherit from Rabbita's theme. CSS custom properties (variables) penetrate Shadow DOM, so the Web Component reads theme values from the host:

```css
/* Rabbita host sets these on :root or <canopy-editor> */
--canopy-bg: #1a1a2e;
--canopy-fg: #e8e8f0;
--canopy-accent: #8250df;
--canopy-keyword: #c792ea;
--canopy-identifier: #82aaff;
--canopy-number: #f78c6c;
--canopy-string: #c3e88d;
--canopy-operator: #ff5370;
--canopy-error: #cf222e;
--canopy-muted: #5a5a7a;

/* Shadow DOM CSS reads them */
.cm-keyword { color: var(--canopy-keyword); }
```

### Keyboard Routing

Keyboard events cross the Shadow DOM boundary. The Web Component handles editing keybindings (typing, Cmd+Z → fires `request-undo` event). Rabbita handles global shortcuts (Cmd+Shift+S for mode toggle, Cmd+1/2/3 for panel toggles) via a top-level key handler. PM's `keymap` plugin has lower priority — unhandled keys bubble up to Rabbita.

## Panel Features

### Outline Panel (left sidebar, Rabbita)

- `TreeEditorState` drives the tree — reuses existing rabbita code
- Click node → `OutlineNodeClicked(id)` → PM scrolls to and highlights node
- Selection syncs bidirectionally with PM
- Collapse/expand is outline-local (doesn't affect PM)
- Peers section at bottom showing connected agents

### Inspector Panel (right sidebar, Rabbita)

- Selected node details: kind, label, type, span, children
- Actions section:
  - Wrap in lambda (sends command to PM via `raw_effect`)
  - Extract to let
  - Swap arguments
  - Delete node
- CRDT section: agent, version vector, op count

### Bottom Panel (tabbed, Rabbita)

| Tab | Source | Content |
|---|---|---|
| **Problems** | `editor.get_errors()` | Error list with click-to-jump |
| **Op Log** | from demo-react | Recent CRDT operations (insert/delete/undo/sync) |
| **CRDT State** | SyncEditor | Version vector, document size, sync status |
| **Graphviz** | from web example | SVG AST visualization via `editor.get_ast_dot_resolved()` → rendered to SVG using the graphviz submodule. Rendered as a Rabbita `@html.node("div", ...)` with the SVG set via `raw_effect` (avoids innerHTML XSS concerns). |

### Toolbar (Rabbita)

- Mode toggle: Text / Structure (highlight active)
- Undo / Redo buttons
- Examples dropdown (Identity, Church 2, Add, Conditional, Apply)
- Connection status indicator (green dot + "Connected")

## Message Flows

### User types in Text Mode

```
CM6 instance (for leaf node X) onChange
  → CustomEvent("text-change", {nodeId: X, start, deleteLen, inserted})
    → dispatch(TextChange(X, s, d, i))
      → SourceMap maps (nodeId, start) → CRDT position
      → editor.apply_text_edit(crdt_pos, d, i, timestamp)
        → delay(RefreshProjection, 16ms)
          → outline_state.refresh()
No echo back to CM6 — it already has the text.
```

Note: Each PM leaf NodeView has its own CM6 instance. The `nodeId` in the event identifies which leaf was edited. The SourceMap converts node-relative positions to absolute CRDT positions.

### Structural edit (drag/action)

**CRDT-first, then reconcile PM.** PM does NOT execute the transform internally first — that would risk state divergence if the CRDT rejects the edit.

```
User drags block or clicks inspector action
  → CustomEvent("structural-edit-request", {op, nodeId})
    → dispatch(StructuralEditRequested(op, nodeId))
      → editor.apply_tree_edit(op, timestamp)
        → if Ok:
            batch([
              raw_effect: set .projNode, .sourceMap on Web Component,
              refresh outline_state
            ])
            PM reconciler diffs new ProjNode against current PM doc
            PM patches only changed nodes (preserves CM6 state in unchanged leaves)
        → if Err:
            (none, model)  // no change, PM stays as-is
```

### Remote peer sync

```
WebSocket message arrives
  → dispatch(SyncReceived(data))
    → editor.apply_sync(data)
      → batch([
           raw_effect: set .projNode, .sourceMap, .peers on Web Component,
           refresh outline_state
         ])
      → PM reconciler incrementally patches doc from new ProjNode
      → Unchanged NodeViews (and their CM6 instances) are preserved
```

## Feature Provenance

| Feature | Source | Integration |
|---|---|---|
| CM6 text editing | prosemirror example | Inside PM NodeViews |
| PM structural editing | prosemirror example | Drag-drop, transforms, schema |
| PM ↔ CRDT bridge | prosemirror example | bridge.ts, reconciler |
| Per-agent undo | demo-react + editor/ | UndoManager in SyncEditor |
| Outline tree | rabbita example | Left panel (Rabbita view) |
| Inspector | rabbita example | Right panel, syncs with PM |
| View modes | rabbita example | Mode toggle → Web Component |
| Graphviz | web example | Bottom panel tab |
| Op log | demo-react | Bottom panel tab |
| Example loader | web + demo-react | Toolbar dropdown |
| WebSocket sync | all examples | Unified in SyncEditor |
| Peer cursors | editor/ EphemeralStore | PM decorations |
| Inline sliders | **new** | PM/CM6 widget decorations |
| Eval ghost text | **new** | PM line decorations |
| Node palette | **new** | Structure mode sidebar |

## Dropped Features

| Feature | Why |
|---|---|
| `contenteditable` (web) | Replaced by CM6 inside PM NodeViews |
| Plain textarea (rabbita, react) | Replaced by CM6 |
| Rabbita block editor | Replaced by PM Structure Mode NodeViews |
| Dual-editor demo UI (react) | Real collab uses one editor + peer cursors |
| React framework (react) | Rabbita is the host |
| Standalone Graphviz page (web) | Becomes a bottom panel tab |
| AST debug text dump (web) | Replaced by inspector panel |

## Rabbita Status & Contributions

### Already Available (v0.11.5)

| Feature | API | Status |
|---|---|---|
| Custom element rendering | `@html.node(tag, attrs, children)` | Exists in `html/html.mbt` |
| Custom event listeners | `Attrs::handler(event_name, callback)` | Exists in `html/attrs.mbt`. Callback receives `@dom.Event`. Cast to `@dom.CustomEvent` to access `.detail`. |
| Side effects | `raw_effect(callback, kind)` with `AfterRender` | Exists. Used for mounting Web Component after DOM render. |
| Delayed commands | `delay(cmd, ms)` | Exists. Used for deferred projection refresh. |

**No P0 blockers.** Rabbita's current API supports the Web Component integration pattern.

### Contributions Needed (performance & DX)

| Contribution | Priority | Notes |
|---|---|---|
| `Html.lazy` | P1 | Skip re-rendering unchanged panels (outline, inspector) when only editor state changes |
| `Html.keyed` | P1 | Stable node identity for outline tree list rendering |
| `CustomEvent.detail` typed access | P2 | Convenience API to avoid manual cast from `Event` to `CustomEvent` |

Drag-and-drop is handled by PM inside the Web Component — no Rabbita contribution needed.

## Audience & Progressive Disclosure

The editor serves all audiences through panel configuration:

- **Newcomer**: Just the editor (all panels hidden). Clean, focused.
- **Developer**: Editor + outline + inspector. Productive editing.
- **Researcher**: All panels visible. Outline, inspector, problems, op log, CRDT state, Graphviz.
- **Showcase**: Structure mode with all panels. Shows what Canopy can do.

Panel visibility persists in `WorkspaceLayout` and is toggleable via toolbar or keyboard shortcuts.
