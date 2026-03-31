# JSON Web Editor Implementation Plan

**Status:** Complete (PR #104)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a web-based JSON editor at `examples/web/json.html` backed by the existing JSON CRDT pipeline (`lang/json/proj/` + `lang/json/edits/`).

**Architecture:** Add JSON-specific FFI exports (`crdt_json.mbt`) with a separate handle registry (the type parameter `@json.JsonValue` differs from lambda's `@ast.Term`). Add a new HTML page + TypeScript module to `examples/web/` following the existing lambda editor pattern. The JSON editor shows a contenteditable text input, a formatted ProjNode tree view, structural edit buttons, and parse errors.

**Tech Stack:** MoonBit (FFI), TypeScript, Vite, HTML/CSS (dark theme matching existing lambda editor)

**Depends on:** `lang/json/proj/` and `lang/json/edits/` — already complete with 79 tests + 8 benchmarks.

---

## File Structure

| Action | Path | Responsibility |
|--------|------|---------------|
| Create | `crdt_json.mbt` | JSON editor FFI: handle registry, create/destroy, text ops, projection, structural edits |
| Create | `examples/web/json.html` | JSON editor page: text input, tree view, edit buttons, errors |
| Create | `examples/web/src/json-editor.ts` | TypeScript bridge: DOM ↔ MoonBit FFI for JSON editor |
| Modify | `examples/web/src/main.ts` | Add JSON page entry (if multi-page) or leave separate |
| Modify | `moon.pkg.json` (root) | Ensure `lang/json/edits` is a dependency of the root package |

---

### Task 1: Add JSON FFI Exports

The root canopy module (`crdt.mbt`) has a lambda-typed registry `Map[Int, SyncEditor[@ast.Term]]`. We need a parallel registry for JSON editors since the type parameter differs.

**Files:**
- Create: `crdt_json.mbt`
- Modify: `moon.pkg.json` (root) — add `dowdiness/canopy/lang/json/edits` to imports if not present

- [ ] **Step 1: Check root package imports**

Run: `moon check 2>&1`

Look at `moon.pkg.json` in the repo root. Verify `lang/json/edits` is importable. If not, add the import.

- [ ] **Step 2: Create `crdt_json.mbt` with handle registry and editor creation**

```moonbit
// crdt_json.mbt — JavaScript bindings for JSON CRDT Editor

///|
let json_editors : Map[Int, @editor.SyncEditor[@json.JsonValue]] = Map::new()

///|
let json_next_handle : Ref[Int] = { val: 10000 }

///|
pub fn create_json_editor(agent_id : String) -> Int {
  let handle = json_next_handle.val
  json_next_handle.val = handle + 1
  json_editors[handle] = @json_edits.new_json_editor(agent_id)
  handle
}

///|
pub fn destroy_json_editor(handle : Int) -> Unit {
  json_editors.remove(handle)
}

///|
pub fn json_get_text(handle : Int) -> String {
  match json_editors.get(handle) {
    Some(ed) => ed.get_text()
    None => ""
  }
}

///|
pub fn json_set_text(handle : Int, new_text : String) -> Unit {
  match json_editors.get(handle) {
    Some(ed) => ed.set_text(new_text)
    None => ()
  }
}

///|
pub fn json_get_errors(handle : Int) -> String {
  match json_editors.get(handle) {
    Some(ed) => ed.get_errors().to_json().stringify()
    None => "[]"
  }
}

///|
pub fn json_get_proj_node_json(handle : Int) -> String {
  match json_editors.get(handle) {
    Some(ed) =>
      match ed.get_proj_node() {
        Some(proj) => proj.to_json().stringify()
        None => "null"
      }
    None => "null"
  }
}

///|
pub fn json_get_source_map_json(handle : Int) -> String {
  match json_editors.get(handle) {
    Some(ed) => ed.get_source_map().to_json().stringify()
    None => "[]"
  }
}

///|
pub fn json_apply_edit(
  handle : Int,
  op_json : String,
  timestamp_ms : Int,
) -> String {
  match json_editors.get(handle) {
    Some(ed) => {
      let json = @json.parse(op_json) catch {
        _ => return "error: invalid JSON"
      }
      match parse_json_edit_op(json) {
        Ok(op) =>
          match @json_edits.apply_json_edit(ed, op, timestamp_ms) {
            Ok(_) => "ok"
            Err(err) => "error: " + err.message()
          }
        Err(msg) => "error: " + msg
      }
    }
    None => "error: invalid handle"
  }
}

///|
fn parse_json_edit_op(json : @json.JsonValue) -> Result[@json_edits.JsonEditOp, String] {
  // Parse {"op": "Delete", "node_id": 3} etc.
  guard let Object(obj) = json else { Err("expected object") }
  guard let Some(String(op)) = obj.get("op") else { Err("missing op field") }
  match op {
    "Delete" => {
      guard let Some(Number(id)) = obj.get("node_id") else {
        Err("missing node_id")
      }
      Ok(@json_edits.JsonEditOp::Delete(node_id=@core.NodeId(id.to_int())))
    }
    "AddMember" => {
      guard let Some(Number(id)) = obj.get("object_id") else {
        Err("missing object_id")
      }
      guard let Some(String(key)) = obj.get("key") else {
        Err("missing key")
      }
      Ok(
        @json_edits.JsonEditOp::AddMember(
          object_id=@core.NodeId(id.to_int()),
          key~,
        ),
      )
    }
    "AddElement" => {
      guard let Some(Number(id)) = obj.get("array_id") else {
        Err("missing array_id")
      }
      Ok(
        @json_edits.JsonEditOp::AddElement(
          array_id=@core.NodeId(id.to_int()),
        ),
      )
    }
    "ChangeType" => {
      guard let Some(Number(id)) = obj.get("node_id") else {
        Err("missing node_id")
      }
      guard let Some(String(type_str)) = obj.get("new_type") else {
        Err("missing new_type")
      }
      let new_type = match type_str {
        "null" => @json_edits.JsonType::JNull
        "bool" => @json_edits.JBool
        "number" => @json_edits.JNumber
        "string" => @json_edits.JString
        "array" => @json_edits.JArray
        "object" => @json_edits.JObject
        _ => return Err("unknown type: " + type_str)
      }
      Ok(
        @json_edits.JsonEditOp::ChangeType(
          node_id=@core.NodeId(id.to_int()),
          new_type~,
        ),
      )
    }
    "CommitEdit" => {
      guard let Some(Number(id)) = obj.get("node_id") else {
        Err("missing node_id")
      }
      guard let Some(String(new_value)) = obj.get("new_value") else {
        Err("missing new_value")
      }
      Ok(
        @json_edits.JsonEditOp::CommitEdit(
          node_id=@core.NodeId(id.to_int()),
          new_value~,
        ),
      )
    }
    "RenameKey" => {
      guard let Some(Number(id)) = obj.get("object_id") else {
        Err("missing object_id")
      }
      guard let Some(Number(idx)) = obj.get("key_index") else {
        Err("missing key_index")
      }
      guard let Some(String(new_key)) = obj.get("new_key") else {
        Err("missing new_key")
      }
      Ok(
        @json_edits.JsonEditOp::RenameKey(
          object_id=@core.NodeId(id.to_int()),
          key_index=idx.to_int(),
          new_key~,
        ),
      )
    }
    "WrapInArray" => {
      guard let Some(Number(id)) = obj.get("node_id") else {
        Err("missing node_id")
      }
      Ok(
        @json_edits.JsonEditOp::WrapInArray(
          node_id=@core.NodeId(id.to_int()),
        ),
      )
    }
    "WrapInObject" => {
      guard let Some(Number(id)) = obj.get("node_id") else {
        Err("missing node_id")
      }
      guard let Some(String(key)) = obj.get("key") else {
        Err("missing key")
      }
      Ok(
        @json_edits.JsonEditOp::WrapInObject(
          node_id=@core.NodeId(id.to_int()),
          key~,
        ),
      )
    }
    "Unwrap" => {
      guard let Some(Number(id)) = obj.get("node_id") else {
        Err("missing node_id")
      }
      Ok(
        @json_edits.JsonEditOp::Unwrap(node_id=@core.NodeId(id.to_int())),
      )
    }
    _ => Err("unknown op: " + op)
  }
}
```

- [ ] **Step 3: Verify it compiles**

Run: `moon check 2>&1`

Fix any import issues (ensure `@json_edits` alias exists in `moon.pkg.json` for `lang/json/edits`).

- [ ] **Step 4: Run `moon info && moon fmt`**

Run: `moon info && moon fmt`

Verify the new FFI functions appear in `pkg.generated.mbti`.

- [ ] **Step 5: Build JS target**

Run: `moon build --target js 2>&1`

Expected: success. The new functions are now available in `canopy.js`.

- [ ] **Step 6: Commit**

```bash
git add crdt_json.mbt moon.pkg.json *.mbti
git commit -m "feat: add JSON editor FFI exports (crdt_json.mbt)"
```

---

### Task 2: Create JSON Editor HTML Page

Follow the existing lambda editor pattern (`examples/web/index.html`) with a JSON-specific layout: text editor, ProjNode tree panel, structural edit toolbar, and error panel.

**Files:**
- Create: `examples/web/json.html`

- [ ] **Step 1: Create `examples/web/json.html`**

The page has:
1. A `contenteditable` text input area (like the lambda editor)
2. A "Tree View" panel showing the ProjNode structure as a collapsible tree
3. A structural edit toolbar (buttons for Add Member, Add Element, Delete, Change Type, etc.)
4. A parse errors panel
5. Example buttons with common JSON snippets

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>JSON CRDT Editor</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      font-family: 'Consolas', 'Monaco', 'Courier New', monospace;
      background: #1e1e1e;
      color: #d4d4d4;
      padding: 20px;
    }

    .container { max-width: 1400px; margin: 0 auto; }
    h1 { color: #4ec9b0; margin-bottom: 10px; }
    .subtitle { color: #858585; margin-bottom: 20px; }

    .main-layout {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 20px;
    }

    .editor-container {
      background: #252526;
      border: 1px solid #3c3c3c;
      border-radius: 4px;
      padding: 15px;
    }

    .examples-bar {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-bottom: 12px;
      padding-bottom: 12px;
      border-bottom: 1px solid #3c3c3c;
      align-items: center;
    }
    .examples-label { color: #858585; font-size: 13px; margin-right: 5px; }

    .example-btn, .edit-btn {
      padding: 6px 12px;
      background: #3c3c3c;
      color: #d4d4d4;
      border: 1px solid #555;
      border-radius: 3px;
      cursor: pointer;
      font-size: 12px;
      font-family: inherit;
      transition: background 0.2s;
    }
    .example-btn:hover, .edit-btn:hover { background: #4c4c4c; border-color: #666; }
    .edit-btn:disabled { opacity: 0.4; cursor: not-allowed; }
    .edit-btn.destructive { border-color: #f4877188; }
    .edit-btn.destructive:hover:not(:disabled) { background: #f4877133; }

    #editor {
      min-height: 300px;
      outline: none;
      font-size: 14px;
      line-height: 1.5;
      white-space: pre-wrap;
      word-wrap: break-word;
    }
    #editor:empty:before {
      content: 'Type JSON here... e.g. {"name": "world", "count": 42}';
      color: #6a6a6a;
    }

    .panel {
      background: #252526;
      border: 1px solid #3c3c3c;
      border-radius: 4px;
      padding: 15px;
      margin-bottom: 15px;
    }
    .panel h2 {
      color: #4ec9b0;
      font-size: 14px;
      margin-bottom: 10px;
      text-transform: uppercase;
    }

    .edit-toolbar {
      display: flex;
      flex-wrap: wrap;
      gap: 6px;
      margin-bottom: 12px;
      padding-bottom: 12px;
      border-bottom: 1px solid #3c3c3c;
    }

    #tree-view {
      font-size: 13px;
      line-height: 1.6;
      overflow: auto;
      max-height: 400px;
    }
    .tree-node { padding-left: 16px; }
    .tree-node-label {
      cursor: pointer;
      padding: 2px 6px;
      border-radius: 3px;
    }
    .tree-node-label:hover { background: #3c3c3c; }
    .tree-node-label.selected { background: #264f78; }
    .tree-key { color: #9cdcfe; }
    .tree-string { color: #ce9178; }
    .tree-number { color: #b5cea8; }
    .tree-bool { color: #569cd6; }
    .tree-null { color: #569cd6; font-style: italic; }
    .tree-type { color: #858585; font-size: 11px; }

    .error-list { list-style: none; }
    .error-item {
      color: #f48771;
      padding: 5px 0;
      border-left: 3px solid #ff0000;
      padding-left: 10px;
      margin-bottom: 5px;
    }

    .selected-info {
      font-size: 12px;
      color: #858585;
      margin-bottom: 8px;
    }

    @media (max-width: 1024px) {
      .main-layout { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>{} JSON CRDT Editor</h1>
    <p class="subtitle">Structural JSON editing with CRDT collaboration</p>

    <div class="main-layout">
      <div>
        <div class="editor-container">
          <div class="examples-bar">
            <span class="examples-label">Examples:</span>
            <button class="example-btn" data-example='{"hello": "world"}'>Simple</button>
            <button class="example-btn" data-example='{"name": "Alice", "age": 30, "active": true}'>Object</button>
            <button class="example-btn" data-example='[1, 2, 3, "four", null]'>Array</button>
            <button class="example-btn" data-example='{"users": [{"name": "Alice", "roles": ["admin"]}, {"name": "Bob", "roles": ["user"]}]}'>Nested</button>
          </div>
          <div id="editor" contenteditable="plaintext-only" spellcheck="false"></div>
        </div>

        <div class="panel" style="margin-top: 15px;">
          <h2>Parse Errors</h2>
          <ul id="error-output" class="error-list">
            <li>No errors</li>
          </ul>
        </div>
      </div>

      <div>
        <div class="panel">
          <h2>Structure</h2>
          <div class="edit-toolbar">
            <button class="edit-btn" id="btn-add-member" disabled>+ Member</button>
            <button class="edit-btn" id="btn-add-element" disabled>+ Element</button>
            <button class="edit-btn" id="btn-wrap-array" disabled>[ Wrap ]</button>
            <button class="edit-btn" id="btn-wrap-object" disabled>{ Wrap }</button>
            <button class="edit-btn" id="btn-change-type" disabled>Type...</button>
            <button class="edit-btn destructive" id="btn-delete" disabled>Delete</button>
            <button class="edit-btn destructive" id="btn-unwrap" disabled>Unwrap</button>
          </div>
          <div id="selected-info" class="selected-info">Click a node in the tree to select it</div>
          <div id="tree-view">
            <p style="color: #858585;">Type JSON to see the structure...</p>
          </div>
        </div>
      </div>
    </div>
  </div>

  <script type="module" src="/src/json-editor.ts"></script>
</body>
</html>
```

- [ ] **Step 2: Commit**

```bash
git add examples/web/json.html
git commit -m "feat: add JSON editor HTML page"
```

---

### Task 3: Create JSON Editor TypeScript Bridge

The TypeScript module connects the HTML page to the MoonBit FFI. It manages: editor handle, text sync, ProjNode tree rendering, node selection, and structural edit dispatch.

**Files:**
- Create: `examples/web/src/json-editor.ts`

- [ ] **Step 1: Create `examples/web/src/json-editor.ts`**

```typescript
import * as crdt from '@moonbit/crdt';

// --- State ---
const agentId = 'json-' + Math.random().toString(36).slice(2, 8);
const handle = crdt.create_json_editor(agentId);
let selectedNodeId: number | null = null;
let lastText = '';
let scheduled = false;

// --- DOM refs ---
const editorEl = document.getElementById('editor') as HTMLDivElement;
const treeViewEl = document.getElementById('tree-view') as HTMLDivElement;
const errorEl = document.getElementById('error-output') as HTMLUListElement;
const selectedInfoEl = document.getElementById('selected-info') as HTMLDivElement;

// --- Example buttons ---
document.querySelectorAll('.example-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    const example = (btn as HTMLElement).dataset.example || '';
    editorEl.textContent = example;
    crdt.json_set_text(handle, example);
    lastText = example;
    updateUI();
  });
});

// --- Text sync ---
editorEl.addEventListener('input', () => {
  if (scheduled) return;
  scheduled = true;
  requestAnimationFrame(() => {
    scheduled = false;
    const text = editorEl.textContent || '';
    if (text !== lastText) {
      crdt.json_set_text(handle, text);
      lastText = text;
    }
    updateUI();
  });
});

// --- Tree rendering ---
interface ProjNode {
  id: number;
  tag: string;
  children: [string, ProjNode][];
}

function renderTree(node: ProjNode, parentKey?: string): string {
  const isSelected = node.id === selectedNodeId;
  const cls = isSelected ? 'tree-node-label selected' : 'tree-node-label';
  const label = buildLabel(node, parentKey);

  let html = `<div class="tree-node">`;
  html += `<div class="${cls}" data-node-id="${node.id}">${label}</div>`;
  for (const [key, child] of node.children) {
    html += renderTree(child, key);
  }
  html += `</div>`;
  return html;
}

function buildLabel(node: ProjNode, parentKey?: string): string {
  const keyPrefix = parentKey ? `<span class="tree-key">${escapeHTML(parentKey)}</span>: ` : '';
  const tag = node.tag;

  // Leaf values
  if (tag.startsWith('"')) return keyPrefix + `<span class="tree-string">${escapeHTML(tag)}</span>`;
  if (tag === 'true' || tag === 'false') return keyPrefix + `<span class="tree-bool">${tag}</span>`;
  if (tag === 'null') return keyPrefix + `<span class="tree-null">null</span>`;
  if (/^-?\d/.test(tag)) return keyPrefix + `<span class="tree-number">${tag}</span>`;

  // Containers
  if (tag === 'Object') return keyPrefix + `<span class="tree-type">{} Object (${node.children.length})</span>`;
  if (tag === 'Array') return keyPrefix + `<span class="tree-type">[] Array (${node.children.length})</span>`;

  return keyPrefix + `<span class="tree-type">${escapeHTML(tag)}</span>`;
}

// --- Node selection ---
treeViewEl.addEventListener('click', (e) => {
  const target = (e.target as HTMLElement).closest('[data-node-id]') as HTMLElement | null;
  if (!target) return;
  selectedNodeId = parseInt(target.dataset.nodeId!, 10);
  updateUI();
  updateToolbar();
});

// --- Toolbar ---
function updateToolbar() {
  const proj = getProjNode();
  const node = proj && selectedNodeId !== null ? findNode(proj, selectedNodeId) : null;

  const btnAddMember = document.getElementById('btn-add-member') as HTMLButtonElement;
  const btnAddElement = document.getElementById('btn-add-element') as HTMLButtonElement;
  const btnWrapArray = document.getElementById('btn-wrap-array') as HTMLButtonElement;
  const btnWrapObject = document.getElementById('btn-wrap-object') as HTMLButtonElement;
  const btnChangeType = document.getElementById('btn-change-type') as HTMLButtonElement;
  const btnDelete = document.getElementById('btn-delete') as HTMLButtonElement;
  const btnUnwrap = document.getElementById('btn-unwrap') as HTMLButtonElement;

  const isObject = node?.tag === 'Object';
  const isArray = node?.tag === 'Array';
  const hasNode = node !== null;

  btnAddMember.disabled = !isObject;
  btnAddElement.disabled = !isArray;
  btnWrapArray.disabled = !hasNode;
  btnWrapObject.disabled = !hasNode;
  btnChangeType.disabled = !hasNode;
  btnDelete.disabled = !hasNode;
  btnUnwrap.disabled = !(isObject && node.children.length === 1) && !(isArray && node.children.length === 1);

  if (node) {
    selectedInfoEl.textContent = `Selected: node #${selectedNodeId} (${node.tag})`;
  } else {
    selectedInfoEl.textContent = 'Click a node in the tree to select it';
  }
}

function findNode(node: ProjNode, id: number): ProjNode | null {
  if (node.id === id) return node;
  for (const [, child] of node.children) {
    const found = findNode(child, id);
    if (found) return found;
  }
  return null;
}

function getProjNode(): ProjNode | null {
  const json = crdt.json_get_proj_node_json(handle);
  if (json === 'null') return null;
  return JSON.parse(json);
}

// --- Edit dispatch ---
function applyEdit(op: Record<string, unknown>) {
  const result = crdt.json_apply_edit(handle, JSON.stringify(op), Date.now());
  if (result !== 'ok') {
    console.error('Edit failed:', result);
  }
  // Sync text back to contenteditable
  const newText = crdt.json_get_text(handle);
  if (editorEl.textContent !== newText) {
    editorEl.textContent = newText;
    lastText = newText;
  }
  updateUI();
  updateToolbar();
}

document.getElementById('btn-add-member')!.addEventListener('click', () => {
  if (selectedNodeId === null) return;
  const key = prompt('Member key:');
  if (key === null) return;
  applyEdit({ op: 'AddMember', object_id: selectedNodeId, key });
});

document.getElementById('btn-add-element')!.addEventListener('click', () => {
  if (selectedNodeId === null) return;
  applyEdit({ op: 'AddElement', array_id: selectedNodeId });
});

document.getElementById('btn-wrap-array')!.addEventListener('click', () => {
  if (selectedNodeId === null) return;
  applyEdit({ op: 'WrapInArray', node_id: selectedNodeId });
});

document.getElementById('btn-wrap-object')!.addEventListener('click', () => {
  if (selectedNodeId === null) return;
  const key = prompt('Wrapper key:');
  if (key === null) return;
  applyEdit({ op: 'WrapInObject', node_id: selectedNodeId, key });
});

document.getElementById('btn-change-type')!.addEventListener('click', () => {
  if (selectedNodeId === null) return;
  const type = prompt('New type (null, bool, number, string, array, object):');
  if (type === null) return;
  applyEdit({ op: 'ChangeType', node_id: selectedNodeId, new_type: type });
});

document.getElementById('btn-delete')!.addEventListener('click', () => {
  if (selectedNodeId === null) return;
  applyEdit({ op: 'Delete', node_id: selectedNodeId });
  selectedNodeId = null;
});

document.getElementById('btn-unwrap')!.addEventListener('click', () => {
  if (selectedNodeId === null) return;
  applyEdit({ op: 'Unwrap', node_id: selectedNodeId });
});

// --- UI update ---
function updateUI() {
  // Tree view
  const proj = getProjNode();
  if (proj) {
    treeViewEl.innerHTML = renderTree(proj);
  } else {
    treeViewEl.innerHTML = '<p style="color: #858585;">Type JSON to see the structure...</p>';
  }

  // Errors
  const errors: string[] = JSON.parse(crdt.json_get_errors(handle));
  if (errors.length === 0) {
    errorEl.innerHTML = '<li>No errors</li>';
  } else {
    errorEl.innerHTML = errors
      .map(e => `<li class="error-item">${escapeHTML(e)}</li>`)
      .join('');
  }
}

function escapeHTML(text: string): string {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// --- Init ---
updateUI();
updateToolbar();
```

- [ ] **Step 2: Verify dev server loads the page**

Run: `cd examples/web && npm run dev`

Open `http://localhost:5173/json.html` in browser. Verify:
- Page loads without JS errors
- Typing `{"a": 1}` shows a tree with Object > "a": 1
- Example buttons populate the editor
- Clicking a tree node highlights it and enables toolbar buttons

- [ ] **Step 3: Commit**

```bash
git add examples/web/src/json-editor.ts
git commit -m "feat: add JSON editor TypeScript bridge"
```

---

### Task 4: Verify Build and Vite Multi-Page

Ensure the JSON page works in production build (Vite multi-page mode).

**Files:**
- Modify: `examples/web/vite.config.ts` (add `json.html` to `build.rollupOptions.input` if needed)

- [ ] **Step 1: Check if Vite auto-discovers `json.html`**

Run: `cd examples/web && npx vite build 2>&1`

If it only builds `index.html`, add multi-page input:

```typescript
// In vite.config.ts, add to defineConfig:
build: {
  target: 'esnext',
  rollupOptions: {
    input: {
      main: 'index.html',
      json: 'json.html',
    },
  },
},
```

- [ ] **Step 2: Verify production build**

Run: `cd examples/web && npx vite build 2>&1`

Expected: Both `index.html` and `json.html` appear in `dist/`.

- [ ] **Step 3: Preview production build**

Run: `cd examples/web && npx vite preview`

Open `http://localhost:4173/json.html`. Verify it works identically to dev mode.

- [ ] **Step 4: Commit**

```bash
git add examples/web/vite.config.ts
git commit -m "feat: configure Vite multi-page build for JSON editor"
```

---

### Task 5: Run Full Test Suite and Final Verification

- [ ] **Step 1: Run all MoonBit tests**

Run: `moon test 2>&1`

Expected: All 616+ tests pass (including existing JSON tests in `lang/json/`).

- [ ] **Step 2: Run JS build**

Run: `moon build --target js 2>&1`

Expected: Success.

- [ ] **Step 3: Run web build**

Run: `cd examples/web && npm run build 2>&1`

Expected: Both pages built successfully.

- [ ] **Step 4: Run `moon info && moon fmt`**

Run: `moon info && moon fmt`

- [ ] **Step 5: Verify no unintended API changes**

Run: `git diff -- '*.mbti'`

Expected: Only new `create_json_editor`, `json_*` functions added.

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "chore: fmt and interface update for JSON editor"
```

---

## Acceptance Criteria

1. `http://localhost:5173/json.html` loads a working JSON editor
2. Typing valid JSON shows the ProjNode tree in the Structure panel
3. Parse errors appear in the errors panel for malformed JSON
4. Clicking a tree node enables relevant structural edit buttons
5. Structural edits (Add Member, Add Element, Delete, Change Type, Wrap, Unwrap) modify the text and update the tree
6. Example buttons load pre-built JSON documents
7. `moon test` passes (all existing + new tests)
8. `moon build --target js` succeeds
9. `examples/web/` production build includes both `index.html` and `json.html`

## Out of Scope (follow-ups)

- Collaborative sync (WebSocket) for JSON editor — reuse existing relay infrastructure later
- Undo/redo UI — backend supports it via `SyncEditor`, add buttons later
- RenameKey / CommitEdit UI — needs inline text input, not just buttons
- CodeMirror 6 integration — the contenteditable approach is sufficient for MVP
- JSON FlatProj optimization (28ms → 16ms) — tracked in TODO.md §12
- Navigation between lambda and JSON editors (router/tabs)
