# Ideal Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a unified Canopy editor where Rabbita hosts PM+CM6 inside a Web Component, with configurable panels, dual editing modes, and real-time collaboration.

**Architecture:** Rabbita (MoonBit Elm architecture) is the host app. A `<canopy-editor>` Web Component wraps ProseMirror + CodeMirror 6 in Shadow DOM. SyncEditor (MoonBit CRDT) is the single source of truth. Communication uses DOM properties (in) and CustomEvents (out).

**Tech Stack:** MoonBit, Rabbita v0.11.5, ProseMirror, CodeMirror 6, TypeScript, Vite, WebSocket

**Spec:** `docs/superpowers/specs/2026-03-19-ideal-editor-design.md`

---

## File Structure

### New: `examples/ideal/` — The unified editor app

```
examples/ideal/
├── moon.mod.json                 # MoonBit module (depends on rabbita, editor, projection)
├── main/
│   ├── moon.pkg                  # Package config (is-main: true)
│   ├── main.mbt                  # Rabbita app entry point (Model/Msg/update/view)
│   ├── model.mbt                 # Model, EditorMode, WorkspaceLayout types
│   ├── msg.mbt                   # Msg enum, PanelId, BottomTab types
│   ├── view_toolbar.mbt          # Toolbar view (mode toggle, undo/redo, examples)
│   ├── view_outline.mbt          # Outline panel view (tree nav, peers)
│   ├── view_inspector.mbt        # Inspector panel view (node details, actions)
│   ├── view_bottom.mbt           # Bottom panel view (problems, op log, CRDT, graphviz)
│   ├── view_editor.mbt           # Renders <canopy-editor> Web Component
│   ├── bridge_ffi.mbt            # MoonBit FFI externs for Web Component communication
│   └── bridge_ffi_js.mbt         # JS target FFI implementations
├── web/
│   ├── package.json              # npm deps (prosemirror-*, codemirror, vite)
│   ├── vite.config.ts            # Vite config (MoonBit build + TS)
│   ├── index.html                # HTML shell with <div id="app">
│   ├── src/
│   │   ├── canopy-editor.ts      # Web Component definition (<canopy-editor>)
│   │   ├── schema.ts             # PM schema (adapted from examples/prosemirror)
│   │   ├── bridge.ts             # CRDT ↔ PM bridge (adapted from examples/prosemirror)
│   │   ├── reconciler.ts         # PM document reconciler (from examples/prosemirror)
│   │   ├── convert.ts            # ProjNode ↔ PM node conversion
│   │   ├── types.ts              # TypeScript types (ProjNodeJson, CrdtModule)
│   │   ├── text-nodeview.ts      # Text Mode NodeViews (code-style, CM6 leaves)
│   │   ├── structure-nodeview.ts # Structure Mode NodeViews (block-style, draggable)
│   │   ├── leaf-editor.ts        # CM6 leaf editor (per-leaf-node CM6 instance)
│   │   ├── decorations.ts        # PM decorations (peer cursors, errors, eval ghosts)
│   │   ├── slider-widget.ts      # CM6 widget: inline number slider
│   │   ├── sync.ts               # WebSocket sync client (from examples/prosemirror)
│   │   ├── theme.ts              # CSS custom property reader + CM6/PM theme
│   │   └── keymap.ts             # Keyboard shortcuts (PM keymap plugin)
│   ├── server/
│   │   └── ws-server.ts          # WebSocket relay (adapted from examples/demo-react)
│   └── styles/
│       └── editor.css            # Base styles + CSS custom properties for theming
```

### Reused from existing code

| Source | Reuse |
|---|---|
| `examples/prosemirror/src/schema.ts` | Adapt → `web/src/schema.ts` |
| `examples/prosemirror/src/bridge.ts` | Adapt → `web/src/bridge.ts` |
| `examples/prosemirror/src/reconciler.ts` | Adapt → `web/src/reconciler.ts` |
| `examples/prosemirror/src/convert.ts` | Adapt → `web/src/convert.ts` |
| `examples/prosemirror/src/types.ts` | Adapt → `web/src/types.ts` |
| `examples/prosemirror/src/sync.ts` | Adapt → `web/src/sync.ts` |
| `examples/prosemirror/src/leaf-view.ts` | Refactor → `web/src/leaf-editor.ts` |
| `examples/prosemirror/src/lambda-view.ts` | Merge → `web/src/text-nodeview.ts` |
| `examples/prosemirror/src/let-def-view.ts` | Merge → `web/src/text-nodeview.ts` |
| `examples/demo-react/server/ws-server.ts` | Adapt → `web/server/ws-server.ts` |
| `examples/rabbita/main/main.mbt` | Reference for Rabbita patterns → new `main/` files |
| `editor/` | Use as-is (SyncEditor, undo, ephemeral) |
| `projection/` | Use as-is (ProjNode, TreeEditorState, SourceMap) |

---

## Task 1: Scaffold the project

**Files:**
- Create: `examples/ideal/moon.mod.json`
- Create: `examples/ideal/main/moon.pkg`
- Create: `examples/ideal/web/package.json`
- Create: `examples/ideal/web/vite.config.ts`
- Create: `examples/ideal/web/index.html`

- [ ] **Step 1: Create moon.mod.json**

```json
{
  "name": "dowdiness/ideal-editor",
  "version": "0.1.0",
  "deps": {
    "moonbit-community/rabbita": "0.11.5",
    "dowdiness/canopy": { "path": "../.." },
    "dowdiness/text_change": { "path": "../../lib/text-change" }
  },
  "source": "."
}
```

- [ ] **Step 2: Create main/moon.pkg**

```json
{
  "import": [
    "moonbit-community/rabbita",
    "moonbit-community/rabbita/html",
    "dowdiness/canopy/editor",
    "dowdiness/canopy/projection",
    "dowdiness/text_change"
  ],
  "targets": {
    "js": ["is-main", true]
  }
}
```

- [ ] **Step 3: Create web/package.json with PM+CM6 deps**

```json
{
  "name": "canopy-ideal-editor",
  "private": true,
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "prebuild:moonbit": "cd ../.. && moon build --target js"
  },
  "dependencies": {
    "prosemirror-model": "^1.22.0",
    "prosemirror-state": "^1.4.3",
    "prosemirror-view": "^1.34.0",
    "prosemirror-transform": "^1.9.0",
    "prosemirror-commands": "^1.6.0",
    "prosemirror-keymap": "^1.2.2",
    "prosemirror-history": "^1.4.1",
    "@codemirror/state": "^6.4.0",
    "@codemirror/view": "^6.26.0",
    "@codemirror/commands": "^6.5.0",
    "@codemirror/language": "^6.10.0",
    "ws": "^8.18.0"
  },
  "devDependencies": {
    "typescript": "^5.4.0",
    "vite": "^5.4.0",
    "@types/ws": "^8.5.0"
  }
}
```

- [ ] **Step 4: Create minimal vite.config.ts**

Reference `examples/prosemirror/vite.config.ts` for the MoonBit build output path pattern (`_build/js/release/build/...`). Adapt for the `ideal` example's module path.

- [ ] **Step 5: Create index.html with app mount point**

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Canopy Editor</title>
  <link rel="stylesheet" href="/src/styles/editor.css">
</head>
<body>
  <div id="app"></div>
  <script type="module" src="/src/canopy-editor.ts"></script>
</body>
</html>
```

- [ ] **Step 6: Install npm dependencies**

```bash
cd examples/ideal/web && npm install
```

- [ ] **Step 7: Run `moon update` and verify deps resolve**

```bash
cd examples/ideal && moon update
```

Expected: deps download successfully.

- [ ] **Step 8: Commit**

```bash
git add examples/ideal/
git commit -m "feat(ideal): scaffold project with moon.mod.json, vite, PM+CM6 deps"
```

---

## Task 2: Web Component shell (`<canopy-editor>`)

**Files:**
- Create: `examples/ideal/web/src/canopy-editor.ts`
- Create: `examples/ideal/web/src/types.ts`
- Create: `examples/ideal/web/styles/editor.css`

- [ ] **Step 1: Define CrdtModule interface in types.ts**

Copy from `examples/prosemirror/src/types.ts` and adapt. This defines the FFI surface the Web Component uses to talk to the MoonBit CRDT module.

```typescript
export interface CrdtModule {
  create_editor_with_undo(agentId: string, timeoutMs: number): number;
  get_text(handle: number): string;
  get_proj_node_json(handle: number): string;
  get_source_map_json(handle: number): string;
  get_errors_json(handle: number): string;
  insert_at(handle: number, pos: number, char: string, timestamp: number): void;
  delete_at(handle: number, pos: number, timestamp: number): boolean;
  undo_manager_undo(handle: number): string | undefined;
  undo_manager_redo(handle: number): string | undefined;
  apply_sync_json(handle: number, json: string): void;
  export_all_json(handle: number): string;
  get_version_json(handle: number): string;
}

export interface ProjNodeJson {
  id: string;
  kind: string;
  label: string;
  span: [number, number];
  children: ProjNodeJson[];
}
```

- [ ] **Step 2: Create the Web Component class**

```typescript
// canopy-editor.ts
export class CanopyEditor extends HTMLElement {
  private shadow: ShadowRoot;
  private editorContainer: HTMLDivElement;
  private _mode: 'text' | 'structure' = 'text';

  static get observedAttributes() {
    return ['mode', 'readonly'];
  }

  constructor() {
    super();
    this.shadow = this.attachShadow({ mode: 'open' });
    this.editorContainer = document.createElement('div');
    this.editorContainer.id = 'editor-root';
    this.shadow.appendChild(this.editorContainer);
  }

  connectedCallback() {
    // PM + CM6 mounted later via mount() call
  }

  attributeChangedCallback(name: string, _old: string, val: string) {
    if (name === 'mode') this._mode = val as 'text' | 'structure';
  }

  // Called by Rabbita's raw_effect(AfterRender)
  mount(crdtHandle: number, crdt: CrdtModule) {
    // Will be filled in Task 4
  }

  // Properties (Rabbita → PM)
  set projNode(json: string) { /* Task 5 */ }
  set sourceMap(json: string) { /* Task 5 */ }
  set peers(json: string) { /* Task 12 */ }
  set errors(json: string) { /* Task 9 */ }
  set selectedNode(id: string | null) { /* Task 8 */ }
  get mode() { return this._mode; }
  set mode(m: 'text' | 'structure') { this._mode = m; /* Task 10 */ }
}

customElements.define('canopy-editor', CanopyEditor);
```

- [ ] **Step 3: Create base CSS with custom properties**

```css
/* styles/editor.css */
:root {
  --canopy-bg: #1a1a2e;
  --canopy-panel-bg: #1e1e36;
  --canopy-surface: #252540;
  --canopy-border: #2a2a48;
  --canopy-fg: #e8e8f0;
  --canopy-muted: #5a5a7a;
  --canopy-accent: #8250df;
  --canopy-keyword: #c792ea;
  --canopy-identifier: #82aaff;
  --canopy-number: #f78c6c;
  --canopy-string: #c3e88d;
  --canopy-operator: #ff5370;
  --canopy-error: #cf222e;
  --canopy-success: #28c840;
}
```

- [ ] **Step 4: Verify the custom element registers**

Open `index.html` in browser. Check devtools: `document.querySelector('canopy-editor')` should exist (once added to HTML). No errors in console.

- [ ] **Step 5: Commit**

```bash
git add examples/ideal/web/src/ examples/ideal/web/styles/
git commit -m "feat(ideal): add <canopy-editor> Web Component shell with types and theme CSS"
```

---

## Task 3: PM Schema

**Files:**
- Create: `examples/ideal/web/src/schema.ts`

- [ ] **Step 1: Copy and adapt schema from prosemirror example**

```bash
cp examples/prosemirror/src/schema.ts examples/ideal/web/src/schema.ts
```

Review the existing schema. It defines node types: `module`, `let_def`, `lambda`, `application`, `binary_op`, `if_expr`, `int_literal`, `var_ref`, `unbound_ref`, `error_node`, `unit`. Keep all of these — they map 1:1 to the ProjNode kinds from the projection module.

- [ ] **Step 2: Verify schema compiles**

```bash
cd examples/ideal/web && npx tsc --noEmit src/schema.ts
```

- [ ] **Step 3: Commit**

```bash
git add examples/ideal/web/src/schema.ts
git commit -m "feat(ideal): add PM schema for lambda calculus AST nodes"
```

---

## Task 4: PM EditorView inside Web Component

**Files:**
- Modify: `examples/ideal/web/src/canopy-editor.ts`
- Create: `examples/ideal/web/src/leaf-editor.ts`
- Create: `examples/ideal/web/src/text-nodeview.ts`
- Create: `examples/ideal/web/src/keymap.ts`

- [ ] **Step 1: Create leaf-editor.ts — CM6 instance factory**

Adapt from `examples/prosemirror/src/leaf-view.ts`. This creates a CM6 EditorView for a single leaf node (int literal, variable name, parameter). The CM6 instance dispatches `text-change` CustomEvents on the host `<canopy-editor>` element.

Key: each CM6 instance receives the `nodeId` so events include which leaf was edited.

- [ ] **Step 2: Create text-nodeview.ts — Text Mode NodeViews**

Merge logic from `examples/prosemirror/src/lambda-view.ts` and `let-def-view.ts`. Each NodeView renders its node as inline code, embedding a CM6 leaf editor for editable parts.

NodeView constructor signature: `(node, view, getPos, decorations, innerDecos, mode)` — the `mode` flag allows switching rendering style later (Task 10).

- [ ] **Step 3: Create keymap.ts**

Adapt from `examples/prosemirror/src/keymap.ts`. Map Cmd+Z → fire `request-undo` CustomEvent, Cmd+Shift+Z → fire `request-redo` CustomEvent. PM does NOT execute undo itself — the host (Rabbita) owns undo via SyncEditor.

- [ ] **Step 4: Wire PM EditorView into the Web Component's `mount()` method**

```typescript
mount(crdtHandle: number, crdt: CrdtModule) {
  const projJson = crdt.get_proj_node_json(crdtHandle);
  const projNode = JSON.parse(projJson);
  const doc = projNodeToPmNode(projNode, this.schema);

  this.pmView = new EditorView(this.editorContainer, {
    state: EditorState.create({ doc, schema: this.schema, plugins: [...] }),
    nodeViews: createTextNodeViews(this, crdtHandle, crdt),
    dispatchTransaction: (tr) => this.handleTransaction(tr),
  });
}
```

- [ ] **Step 5: Test manually — mount the editor, type in a CM6 leaf**

Open dev server. Call `mount()` with a test CRDT handle. Verify PM renders the document and CM6 leaf editors appear for editable nodes.

- [ ] **Step 6: Commit**

```bash
git add examples/ideal/web/src/
git commit -m "feat(ideal): PM EditorView with CM6 leaf editors inside Web Component"
```

---

## Task 5: CRDT Bridge (PM ↔ SyncEditor)

**Files:**
- Create: `examples/ideal/web/src/bridge.ts`
- Create: `examples/ideal/web/src/reconciler.ts`
- Create: `examples/ideal/web/src/convert.ts`

- [ ] **Step 1: Copy and adapt convert.ts**

```bash
cp examples/prosemirror/src/convert.ts examples/ideal/web/src/convert.ts
```

This converts `ProjNodeJson` → PM `Node` and back. Verify it works with the schema from Task 3.

- [ ] **Step 2: Copy and adapt reconciler.ts**

```bash
cp examples/prosemirror/src/reconciler.ts examples/ideal/web/src/reconciler.ts
```

The reconciler diffs a new ProjNode tree against the current PM doc and produces minimal transactions. This preserves CM6 NodeViews in unchanged leaves.

- [ ] **Step 3: Create bridge.ts — CRDT-first structural edit flow**

Adapt from `examples/prosemirror/src/bridge.ts`. Key change from the original: structural edits are **CRDT-first**. The bridge does NOT let PM execute transforms internally first.

```typescript
export class CrdtBridge {
  constructor(
    private host: CanopyEditor,
    private handle: number,
    private crdt: CrdtModule,
    private pmView: EditorView,
  ) {}

  // CM6 leaf edit → CRDT
  handleLeafEdit(nodeId: string, start: number, deleteLen: number, inserted: string) {
    // Map node-relative position to CRDT position via source map
    const sourceMap = JSON.parse(this.crdt.get_source_map_json(this.handle));
    const nodeSpan = sourceMap[nodeId];
    const crdtPos = nodeSpan[0] + start;

    // Apply to CRDT (character by character for FugueMax)
    for (let i = 0; i < deleteLen; i++) {
      this.crdt.delete_at(this.handle, crdtPos, Date.now());
    }
    for (const ch of inserted) {
      this.crdt.insert_at(this.handle, crdtPos, ch, Date.now());
    }

    // Fire event for Rabbita
    this.host.dispatchEvent(new CustomEvent('text-change', {
      detail: { nodeId, start, deleteLen, inserted },
      bubbles: true, composed: true,
    }));
  }

  // Reconcile PM from new CRDT state (after external changes)
  reconcile() {
    const projJson = this.crdt.get_proj_node_json(this.handle);
    const projNode = JSON.parse(projJson);
    reconcilePmDoc(this.pmView, projNode, this.schema);
  }
}
```

- [ ] **Step 4: Wire bridge into Web Component's `mount()`**

After creating the PM EditorView, create the CrdtBridge. Pass it to NodeViews so leaf edits route through the bridge.

- [ ] **Step 5: Wire `.projNode` and `.sourceMap` property setters with loop prevention**

```typescript
set projNode(json: string) {
  if (this.bridge) {
    // CRITICAL: Mark as external to prevent echo loop.
    // reconcile() creates PM transactions with { fromExternal: true }.
    // dispatchTransaction checks this flag and suppresses text-change events.
    this.bridge.reconcile();
  }
}
```

In `canopy-editor.ts`'s `handleTransaction`:
```typescript
private handleTransaction(tr: Transaction) {
  this.pmView!.updateState(this.pmView!.state.apply(tr));
  // Suppress text-change for external reconciliation
  if (tr.getMeta('fromExternal')) return;
  if (!tr.docChanged) return;
  // ... fire text-change CustomEvent
}
```

- [ ] **Step 6: Test manually — type in CM6 leaf, verify CRDT text updates**

Type a character in a CM6 leaf editor. Check that `crdt.get_text(handle)` reflects the change. Check that the `text-change` CustomEvent fires.

- [ ] **Step 7: Commit**

```bash
git add examples/ideal/web/src/bridge.ts examples/ideal/web/src/reconciler.ts examples/ideal/web/src/convert.ts
git commit -m "feat(ideal): CRDT bridge with reconciler and CRDT-first edit flow"
```

---

## Task 6: Minimal Rabbita host (Model + view + Web Component mount)

**Files:**
- Create: `examples/ideal/main/model.mbt`
- Create: `examples/ideal/main/msg.mbt`
- Create: `examples/ideal/main/view_editor.mbt`
- Create: `examples/ideal/main/bridge_ffi.mbt`
- Create: `examples/ideal/main/bridge_ffi_js.mbt`
- Create: `examples/ideal/main/main.mbt`

- [ ] **Step 1: Define Model types in model.mbt**

```moonbit
pub enum EditorMode {
  Text
  Structure
}

pub enum BottomTab {
  Problems
  OpLog
  CrdtState
  Graphviz
}

pub enum PanelId {
  Outline
  Inspector
  Bottom
}

pub struct CursorInfo {
  line : Int
  col : Int
  offset : Int
}

pub struct WorkspaceLayout {
  outline_visible : Bool
  inspector_visible : Bool
  bottom_visible : Bool
}

pub struct OpLogEntry {
  timestamp : Int
  agent : String
  op_type : String
  detail : String
}

pub struct PeerInfo {
  name : String
  color : String
  cursor_pos : Int
}

pub struct Model {
  editor : @editor.SyncEditor
  outline_state : @proj.TreeEditorState
  mode : EditorMode
  workspace : WorkspaceLayout
  cursor : CursorInfo?
  selected_node : String?
  diagnostics_open : Bool
  peers : Array[PeerInfo]
  next_timestamp : Int
  projection_dirty : Bool
  refresh_scheduled : Bool
  bottom_tab : BottomTab
  op_log : Array[OpLogEntry]         // circular buffer, max 100 entries
}
```

- [ ] **Step 2: Define Msg enum in msg.mbt**

```moonbit
pub enum Msg {
  // Mode & layout
  SetMode(EditorMode)
  TogglePanel(PanelId)
  SelectBottomTab(BottomTab)
  // From Web Component (PM+CM6 events)
  TextChange(node_id~ : String, start~ : Int, delete_len~ : Int, inserted~ : String)
  CursorMove(line~ : Int, col~ : Int, offset~ : Int)
  NodeSelected(node_id~ : String)
  StructuralEditRequested(op~ : String, node_id~ : String)
  // Projection
  RefreshProjection
  // Collaboration
  SyncReceived(String)
  SyncBroadcast
  PeerPresenceUpdate(name~ : String, data~ : String)
  // Undo/redo (from toolbar buttons or Web Component request-undo/request-redo events)
  Undo
  Redo
  // UI
  LoadExample(String)
  OutlineNodeClicked(String)
}
```

- [ ] **Step 3: Define FFI externs in bridge_ffi.mbt**

```moonbit
// JS FFI for Web Component communication
extern "js" fn mount_editor(handle : Int) -> Unit
extern "js" fn set_editor_proj_node(json : String) -> Unit
extern "js" fn set_editor_source_map(json : String) -> Unit
extern "js" fn set_editor_mode(mode : String) -> Unit
extern "js" fn set_editor_errors(json : String) -> Unit
```

- [ ] **Step 4: Implement FFI in bridge_ffi_js.mbt**

JS-target implementations that call the `<canopy-editor>` element's methods/properties.

- [ ] **Step 5: Create view_editor.mbt — renders the Web Component**

```moonbit
fn view_editor(dispatch : Dispatch[Msg], model : Model) -> Html {
  @html.node("canopy-editor",
    @html.Attrs::new()
      .attr("mode", match model.mode { Text => "text"; Structure => "structure" })
      .handler("text-change", fn(event, _scheduler) {
        // Extract detail from CustomEvent, dispatch TextChange
      })
      .handler("node-selected", fn(event, _scheduler) {
        // Extract detail, dispatch NodeSelected
      })
      .handler("structural-edit-request", fn(event, _scheduler) {
        // Extract detail, dispatch StructuralEditRequested
      })
      .handler("cursor-move", fn(event, _scheduler) {
        // Extract detail, dispatch CursorMove
      })
      .handler("request-undo", fn(_event, _scheduler) {
        dispatch(Undo)
      })
      .handler("request-redo", fn(_event, _scheduler) {
        dispatch(Redo)
      }),
    [],
  )
}
```

- [ ] **Step 6: Create main.mbt — minimal app with init + update + view**

```moonbit
fn init_model() -> Model {
  let editor = @editor.SyncEditor::new("local")
  let init_text = "let id = \\x.x"
  editor.set_text(init_text)
  let tree_state = @proj.TreeEditorState::from_projection(
    editor.get_proj_node(), editor.get_source_map(),
  )
  {
    editor, outline_state: tree_state, mode: Text,
    workspace: { outline_visible: false, inspector_visible: false, bottom_visible: false },
    cursor: None, selected_node: None, diagnostics_open: false,
    peers: [], next_timestamp: 1,
    projection_dirty: false, refresh_scheduled: false,
    bottom_tab: Problems, op_log: [],
  }
}

fn update(dispatch : Dispatch[Msg], msg : Msg, model : Model) -> (Cmd, Model) {
  match msg {
    Undo => {
      model.editor.undo()
      // Use module-level FFI function (not SyncEditor method) for JSON serialization
      let cmd = @rabbita.effect(fn() { update_web_component_state(model) })
      (cmd, model)
    }
    Redo => {
      model.editor.redo()
      let cmd = @rabbita.effect(fn() { update_web_component_state(model) })
      (cmd, model)
    }
    _ => (@rabbita.none, model)
  }
}

// Helper: push current SyncEditor state to the Web Component
fn update_web_component_state(model : Model) -> Unit {
  // Calls module-level FFI functions that serialize to JSON
  // and set properties on <canopy-editor>
  set_editor_proj_node(get_proj_node_json_ffi(model.editor))
  set_editor_source_map(get_source_map_json_ffi(model.editor))
  set_editor_errors(get_errors_json_ffi(model.editor))
}

fn view(dispatch : Dispatch[Msg], model : Model) -> Html {
  @html.div(class="app-shell", [
    view_toolbar(dispatch, model),  // stub created in this task
    @html.div(class="workspace", [
      view_editor(dispatch, model),
    ]),
  ])
}

fn main {
  let app = @rabbita.cell(model=init_model(), update~, view~)
  @rabbita.new(app).mount("app")
  // Mount Web Component after DOM render
  // (actual mount call done via raw_effect in init or first render)
}
```

- [ ] **Step 7: Create stub view_toolbar.mbt**

Minimal toolbar so the view function compiles:
```moonbit
fn view_toolbar(_dispatch : Dispatch[Msg], _model : Model) -> Html {
  @html.div(class="toolbar", [@html.text("Canopy Editor")])
}
```

- [ ] **Step 8: Write unit tests in main/model_wbtest.mbt**

Test init_model creates valid state, and update handles Undo/Redo messages.

- [ ] **Step 9: Run quality checks**

```bash
cd examples/ideal && moon check && moon test && moon info && moon fmt
```

- [ ] **Step 10: Build MoonBit + run Vite dev server**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/crdt && moon build --target js
cd examples/ideal/web && npm run dev
```

Expected: Editor renders with PM + CM6. Typing works.

- [ ] **Step 11: Commit**

```bash
git add examples/ideal/main/
git commit -m "feat(ideal): minimal Rabbita host with Web Component mount and basic update loop"
```

---

## Task 7: Outline panel

**Files:**
- Create: `examples/ideal/main/view_outline.mbt`
- Modify: `examples/ideal/main/main.mbt` (add outline to view)
- Modify: `examples/ideal/main/msg.mbt` (add outline messages if needed)

- [ ] **Step 1: Implement view_outline.mbt**

Adapt `view_tree_node` from `examples/rabbita/main/main.mbt` (lines 260-329). Renders the `TreeEditorState` as a collapsible tree with node icons. Click dispatches `OutlineNodeClicked(id)`.

Add peers section at the bottom (reuse the peers display from rabbita example).

- [ ] **Step 2: Wire into main view**

```moonbit
fn view(dispatch, model) -> Html {
  @html.div(class="app-shell", [
    view_toolbar(dispatch, model),
    @html.div(class="workspace", [
      if model.workspace.outline_visible { view_outline(dispatch, model) } else { @html.text("") },
      view_editor(dispatch, model),
    ]),
  ])
}
```

- [ ] **Step 3: Handle OutlineNodeClicked in update**

Send `raw_effect` to set `.selectedNode` property on the Web Component, which causes PM to scroll to and highlight the node.

- [ ] **Step 4: Handle RefreshProjection**

Reuse the deferred refresh pattern from rabbita example (16ms debounce). On refresh, update `outline_state` from the new projection.

- [ ] **Step 5: Test — click outline node, verify PM scrolls to it**

- [ ] **Step 6: Quality checks + Commit**

```bash
cd examples/ideal && moon check && moon test && moon info && moon fmt
git add examples/ideal/main/view_outline.mbt
git commit -m "feat(ideal): outline panel with tree navigation and peer list"
```

---

## Task 8: Inspector panel

**Files:**
- Create: `examples/ideal/main/view_inspector.mbt`

- [ ] **Step 1: Implement view_inspector.mbt**

Shows selected node details (kind, label, type, span). Adapt from rabbita example's inspector section. Reads `model.selected_node` and looks up the node in the projection.

Actions section: buttons for "Wrap in lambda", "Extract to let", "Delete node". Each dispatches `StructuralEditRequested(op, node_id)`.

CRDT section: agent name, version vector, op count from `model.editor`.

- [ ] **Step 2: Handle StructuralEditRequested in update**

CRDT-first: call `editor.apply_tree_edit(op, timestamp)`. On success, send `raw_effect` to reconcile PM via `.projNode` property. On error, do nothing.

- [ ] **Step 3: Handle NodeSelected in update**

Update `model.selected_node`. The outline panel and inspector both react to this.

- [ ] **Step 4: Wire into main view**

Add inspector to the workspace layout, conditionally visible.

- [ ] **Step 5: Test — select node in PM, verify inspector shows details**

- [ ] **Step 6: Quality checks + Commit**

```bash
cd examples/ideal && moon check && moon test && moon info && moon fmt
git add examples/ideal/main/view_inspector.mbt
git commit -m "feat(ideal): inspector panel with node details, actions, and CRDT metadata"
```

---

## Task 9: Bottom panel (Problems tab)

**Files:**
- Create: `examples/ideal/main/view_bottom.mbt`

- [ ] **Step 1: Implement view_bottom.mbt with tab switching**

Tabbed panel: Problems | Op Log | CRDT State | Graphviz. Only implement Problems tab first — other tabs are stubs.

Problems tab: call `model.editor.get_errors()` and render as a list. Each error shows line number and message. Click dispatches `OutlineNodeClicked` to jump to the error location.

- [ ] **Step 2: Wire `.errors` property to Web Component**

After projection refresh, send errors JSON to the Web Component for squiggly underline decorations.

- [ ] **Step 3: Wire into main view**

Add bottom panel below the editor area, conditionally visible.

- [ ] **Step 4: Test — introduce a parse error, verify it appears in Problems tab and as squiggly in PM**

- [ ] **Step 5: Quality checks + Commit**

```bash
cd examples/ideal && moon check && moon test && moon info && moon fmt
git add examples/ideal/main/view_bottom.mbt
git commit -m "feat(ideal): bottom panel with Problems tab and error decorations"
```

---

## Task 10: Structure Mode NodeViews

**Files:**
- Create: `examples/ideal/web/src/structure-nodeview.ts`
- Modify: `examples/ideal/web/src/canopy-editor.ts` (mode switching)

- [ ] **Step 1: Implement structure-nodeview.ts**

Block-style rendering. Each NodeView renders as a bordered box with:
- Grip handle (drag source)
- Node type tag badge (LET, LAMBDA, BINOP)
- Expand/collapse toggle
- Nested children blocks

Use PM's `NodeView.dom` as the block container. Editable leaves get a CM6 instance on double-click.

- [ ] **Step 2: Implement mode switching in Web Component**

When `.mode` changes:
1. Store the new mode
2. Call `this.pmView.updateState(this.pmView.state)` to force all NodeViews to re-render
3. NodeView constructors check `this.host.mode` and render accordingly

- [ ] **Step 3: Handle drag-and-drop**

Use PM's built-in drag-and-drop. Structure Mode NodeViews set `draggable: true` on their DOM. PM schema validation ensures drops are only allowed at valid positions. On drop, fire `structural-edit-request` CustomEvent.

- [ ] **Step 4: Test — toggle mode, verify blocks appear. Drag a block, verify it moves.**

- [ ] **Step 5: Commit**

```bash
git add examples/ideal/web/src/structure-nodeview.ts
git commit -m "feat(ideal): structure mode NodeViews with draggable blocks"
```

---

## Task 11: Toolbar

**Files:**
- Create: `examples/ideal/main/view_toolbar.mbt`

- [ ] **Step 1: Implement view_toolbar.mbt**

- Mode toggle: Text / Structure buttons. Active mode highlighted with accent color.
- Undo / Redo buttons.
- Examples dropdown: buttons for Identity, Church 2, Add, Conditional, Apply.
- Connection status indicator.

- [ ] **Step 2: Handle SetMode in update**

Update `model.mode`. Send `raw_effect` to set `.mode` on the Web Component.

- [ ] **Step 3: Handle LoadExample in update**

Call `model.editor.set_text(example_text)`. Refresh projection. Send `raw_effect` to reconcile PM.

- [ ] **Step 4: Test — click mode toggle, verify switch. Load example, verify content changes.**

- [ ] **Step 5: Quality checks + Commit**

```bash
cd examples/ideal && moon check && moon test && moon info && moon fmt
git add examples/ideal/main/view_toolbar.mbt
git commit -m "feat(ideal): toolbar with mode toggle, undo/redo, and example loader"
```

---

## Task 12: Collaboration (WebSocket sync + peer cursors)

**Files:**
- Create: `examples/ideal/web/src/sync.ts`
- Create: `examples/ideal/web/src/decorations.ts`
- Create: `examples/ideal/web/server/ws-server.ts`
- Modify: `examples/ideal/main/msg.mbt` (add SyncReceived, PeerPresenceUpdate)

- [ ] **Step 1: Copy and adapt WebSocket server**

```bash
cp examples/demo-react/server/ws-server.ts examples/ideal/web/server/ws-server.ts
```

- [ ] **Step 2: Copy and adapt sync client**

```bash
cp examples/prosemirror/src/sync.ts examples/ideal/web/src/sync.ts
```

Wire into the Web Component. On remote sync received, fire a `sync-received` CustomEvent.

- [ ] **Step 3: Create decorations.ts — peer cursor PM decorations**

Render colored carets with name labels as PM widget decorations. Read from `.peers` property.

- [ ] **Step 4: Handle SyncReceived in Rabbita update**

Apply sync to SyncEditor. Send `raw_effect` to update `.projNode`, `.sourceMap`, `.peers` on the Web Component. Refresh outline.

- [ ] **Step 5: Test — open two browser tabs, type in one, verify the other updates**

- [ ] **Step 6: Commit**

```bash
git add examples/ideal/web/src/sync.ts examples/ideal/web/src/decorations.ts examples/ideal/web/server/
git commit -m "feat(ideal): WebSocket collaboration with peer cursors"
```

---

## Task 13: Inline widgets (sliders + eval ghosts)

**Files:**
- Create: `examples/ideal/web/src/slider-widget.ts`
- Modify: `examples/ideal/web/src/text-nodeview.ts` (add eval ghost decorations)

- [ ] **Step 1: Create slider-widget.ts**

CM6 widget decoration that renders an `<input type="range">` next to integer literals. On change, fires a `text-change` event replacing the number text.

```typescript
class SliderWidget extends WidgetType {
  constructor(private value: number, private nodeId: string, private bridge: CrdtBridge) {}

  toDOM() {
    const wrapper = document.createElement('span');
    wrapper.className = 'canopy-slider';
    const input = document.createElement('input');
    input.type = 'range';
    input.min = '0'; input.max = '100';
    input.value = String(this.value);
    input.addEventListener('input', (e) => {
      const newVal = (e.target as HTMLInputElement).value;
      this.bridge.handleLeafEdit(this.nodeId, 0, String(this.value).length, newVal);
    });
    wrapper.appendChild(input);
    return wrapper;
  }
}
```

- [ ] **Step 2: Add eval ghost decorations**

PM line decorations that show `→ result` at the end of expression lines. Initially show the text representation of the AST node's evaluated form (if it's a simple reduction). Start with integer arithmetic only.

- [ ] **Step 3: Test — drag a slider, verify the number changes in CRDT and PM**

- [ ] **Step 4: Commit**

```bash
git add examples/ideal/web/src/slider-widget.ts
git commit -m "feat(ideal): inline number sliders and eval ghost decorations"
```

---

## Task 14: Bottom panel remaining tabs (Op Log, CRDT State, Graphviz)

**Files:**
- Modify: `examples/ideal/main/view_bottom.mbt`

- [ ] **Step 1: Op Log tab**

Display `model.op_log` — a circular buffer of recent operations. Each entry shows timestamp, agent, operation type (insert/delete/undo/sync), and affected text.

Populate op_log in the update function when TextChange, Undo, Redo, or SyncReceived messages are processed.

- [ ] **Step 2: CRDT State tab**

Display: agent name, version vector (`editor.get_version_json()`), document length, total ops count, sync status.

- [ ] **Step 3: Graphviz tab**

Call `editor.get_ast_dot_resolved()` to get DOT source. Use the graphviz submodule to render SVG. Display via `raw_effect` setting innerHTML on a container div (the DOT is from trusted internal data, not user input).

- [ ] **Step 4: Test — switch between tabs, verify content renders**

- [ ] **Step 5: Quality checks + Commit**

```bash
cd examples/ideal && moon check && moon test && moon info && moon fmt
git add examples/ideal/main/view_bottom.mbt
git commit -m "feat(ideal): bottom panel Op Log, CRDT State, and Graphviz tabs"
```

---

## Task 15: Panel configuration and progressive disclosure

**Files:**
- Modify: `examples/ideal/main/main.mbt` (panel toggle logic)
- Modify: `examples/ideal/main/view_toolbar.mbt` (panel toggle buttons)

- [ ] **Step 1: Add panel toggle buttons to toolbar**

Small icon buttons for Outline, Inspector, Bottom panel visibility. Each dispatches `TogglePanel(PanelId)`.

- [ ] **Step 2: Handle TogglePanel in update**

Toggle the corresponding field in `model.workspace`.

- [ ] **Step 3: Add keyboard shortcuts**

Rabbita top-level key handler:
- `Cmd+Shift+S` → toggle mode
- `Cmd+1` → toggle outline
- `Cmd+2` → toggle inspector
- `Cmd+3` → toggle bottom panel

- [ ] **Step 4: Test — toggle each panel, verify it shows/hides. Test keyboard shortcuts.**

- [ ] **Step 5: Quality checks + Commit**

```bash
cd examples/ideal && moon check && moon test && moon info && moon fmt
git add examples/ideal/main/
git commit -m "feat(ideal): configurable panel layout with keyboard shortcuts"
```

---

## Task 16: CSS polish and responsive layout

**Files:**
- Modify: `examples/ideal/web/styles/editor.css`

- [ ] **Step 1: Style the full workbench layout**

Flexbox layout matching the Paper artboard mockups:
- Title bar (40px)
- Toolbar (36px)
- Main body (flex row): outline sidebar (200px) | editor (flex:1) | inspector (220px)
- Bottom panel (140px, collapsible)

Dark theme using CSS custom properties.

- [ ] **Step 2: Style PM NodeViews for both modes**

Text mode: monospace font, syntax colors, line numbers.
Structure mode: bordered blocks, grip handles, node badges, drop targets.

- [ ] **Step 3: Style panels, tabs, tree, and inspector**

Match the visual design from the Paper artboards (Canopy — Text Mode, Canopy — Structure Mode).

- [ ] **Step 4: Visual review — compare with Paper artboard mockups**

- [ ] **Step 5: Commit**

```bash
git add examples/ideal/web/styles/
git commit -m "style(ideal): workbench layout and dark theme matching Paper mockups"
```
