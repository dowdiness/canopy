# Block Editor Implementation Plan (Phase 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a working block editor at `examples/block-editor/` supporting paragraph, heading, and list blocks — single peer, in-browser Markdown download/upload, no collaboration yet.

**Architecture:** MoonBit owns a pure state machine (`BlockDoc`). TypeScript is a thin shell: forwards input events in, reads state via `get_render_state(handle)`, patches `contenteditable` divs on each RAF frame. Block structure is a `TreeDoc` (Kleppmann's CRDT). Block content is a `Map[BlockId, TextDoc]`.

**Prerequisites:** `@tree.TreeDoc` and `@text.TextDoc` are available from `dowdiness/event-graph-walker` (shipped in PR #12). No additional CRDT work needed before starting.

**V1 simplifications (known deviations from the design doc):**
- **No unified oplog.** Each `TextDoc` is an independent CRDT instance with no shared causal history. Unified version vector across tree + text ops is Phase 2 (design doc §"Joint CRDT invariants").
- **Explicit order array.** `TreeDoc` does not expose `create_node_after`. `BlockDoc` carries an `order: Array[BlockId]` for display ordering. The tree still records structural ops for future sync.
- **Line-by-line Markdown parser.** No Loom grammar. Multi-line paragraphs are accumulated across blank-line boundaries. Unknown syntax falls through to `Paragraph` (not `Raw`; raw-block preservation is Phase 2).
- **Numbered-list start number ignored.** Exporter always renumbers from `1`. `3. item` round-trips to `1. item`.
- **Save/load = browser download/upload.** No file-system API, no `.crdt` sidecar. A toolbar provides a "Download .md" button and a file-picker "Upload .md" button.

**Design reference:** [2026-03-28-block-editor-design.md](2026-03-28-block-editor-design.md)

---

## File Map

| File | Responsibility |
|------|----------------|
| `examples/block-editor/moon.mod.json` | Module declaration (deps: canopy, for event-graph-walker) |
| `examples/block-editor/main/moon.pkg` | Package config + JS export list |
| `examples/block-editor/main/block_types.mbt` | BlockId, BlockType, ListStyle |
| `examples/block-editor/main/block_doc.mbt` | BlockDoc struct + CRUD: create, delete, set_text, get_text, children, block_type, set_type |
| `examples/block-editor/main/block_export.mbt` | `block_doc_to_markdown(doc) -> String` |
| `examples/block-editor/main/block_import.mbt` | `block_doc_from_markdown(md, replica_id) -> BlockDoc` |
| `examples/block-editor/main/block_init.mbt` | Handle registry, exported bridge wrappers, `get_render_state` |
| `examples/block-editor/main/ffi.mbt` | Stub for future JS externs |
| `examples/block-editor/main/block_doc_wbtest.mbt` | Whitebox tests |
| `examples/block-editor/web/index.html` | HTML shell with `#editor-root` |
| `examples/block-editor/web/src/main.ts` | Bootstrap, keyboard wiring, RAF render loop, DOM patching |
| `examples/block-editor/web/package.json` | npm scripts |
| `examples/block-editor/web/tsconfig.json` | TypeScript config |
| `examples/block-editor/web/vite.config.ts` | Vite config (mirrors canvas) |

---

## Task 1: Scaffold the module

**Files to create:**
- `examples/block-editor/moon.mod.json`
- `examples/block-editor/main/moon.pkg`
- `examples/block-editor/main/ffi.mbt`
- `examples/block-editor/web/package.json`
- `examples/block-editor/web/tsconfig.json`
- `examples/block-editor/web/vite.config.ts`
- `examples/block-editor/web/index.html`

---

- [ ] **Step 1: Create moon.mod.json**

```json
{
  "name": "dowdiness/canopy-block-editor",
  "version": "0.1.0",
  "source": ".",
  "deps": {
    "dowdiness/canopy": {
      "path": "../.."
    }
  },
  "preferred-target": "js"
}
```

Save to: `examples/block-editor/moon.mod.json`

---

- [ ] **Step 2: Create main/moon.pkg (minimal — exports filled in Task 7)**

```moonpkg
options(
  "is-main": true,
  link: {
    "js": {
      "exports": [],
    },
  },
)
```

Save to: `examples/block-editor/main/moon.pkg`

---

- [ ] **Step 3: Create ffi.mbt stub**

```moonbit
// JS externs go here (future: clipboard, file I/O, etc.)
```

Save to: `examples/block-editor/main/ffi.mbt`

---

- [ ] **Step 4: Create web/package.json**

```json
{
  "name": "block-editor-web",
  "private": true,
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "prebuild:moonbit": "cd ../.. && moon build --target js --release --source-map",
    "build:full": "npm run prebuild:moonbit && npm run build"
  },
  "devDependencies": {
    "typescript": "^5.4.0",
    "vite": "^5.4.0"
  }
}
```

Save to: `examples/block-editor/web/package.json`

---

- [ ] **Step 5: Create web/tsconfig.json**

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "skipLibCheck": true
  },
  "include": ["src"]
}
```

Save to: `examples/block-editor/web/tsconfig.json`

---

- [ ] **Step 6: Create web/vite.config.ts**

Mirror the canvas vite config exactly (path to MoonBit output, no framework plugin needed).

```typescript
import { defineConfig } from 'vite';
import path from 'path';

export default defineConfig({
  build: {
    outDir: 'dist',
    rollupOptions: {
      input: path.resolve(__dirname, 'index.html'),
    },
  },
  resolve: {
    alias: {
      '@moonbit': path.resolve(
        __dirname,
        '../../_build/js/release/build/examples/block-editor/main',
      ),
    },
  },
});
```

Save to: `examples/block-editor/web/vite.config.ts`

---

- [ ] **Step 7: Create web/index.html**

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Block Editor</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: #1a1a2e;
      color: #e0e0e0;
      font-family: Inter, system-ui, sans-serif;
      display: flex;
      justify-content: center;
      padding: 48px 16px;
    }
    #editor-root {
      width: 100%;
      max-width: 720px;
    }
    .block {
      position: relative;
      outline: none;
      padding: 3px 0;
      line-height: 1.6;
      white-space: pre-wrap;
      word-break: break-word;
    }
    .block:focus { background: rgba(130, 80, 223, 0.04); border-radius: 4px; }
    .block[data-type="paragraph"]   { font-size: 1rem; }
    .block[data-type="heading"][data-level="1"] { font-size: 2rem; font-weight: 700; margin-top: 1.5em; }
    .block[data-type="heading"][data-level="2"] { font-size: 1.5rem; font-weight: 600; margin-top: 1.25em; }
    .block[data-type="heading"][data-level="3"] { font-size: 1.25rem; font-weight: 600; margin-top: 1em; }
    .block[data-type="list_item"] { padding-left: 1.5em; }
    .block[data-type="list_item"]::before { content: attr(data-bullet); position: absolute; left: 0; }
    .block[data-type="code"] {
      font-family: 'JetBrains Mono', monospace;
      background: rgba(255,255,255,0.05);
      border-radius: 4px;
      padding: 12px;
      font-size: 0.9rem;
    }
    .block[data-type="divider"] { border-top: 1px solid rgba(255,255,255,0.15); height: 0; padding: 12px 0; }
    .block[data-type="quote"] {
      border-left: 3px solid #8250df;
      padding-left: 1em;
      color: rgba(255,255,255,0.7);
    }
    #toolbar {
      display: flex;
      gap: 8px;
      margin-bottom: 24px;
    }
    #toolbar button, #toolbar label {
      background: rgba(130, 80, 223, 0.15);
      border: 1px solid rgba(130, 80, 223, 0.4);
      color: #c792ea;
      border-radius: 4px;
      padding: 4px 12px;
      font-size: 0.85rem;
      cursor: pointer;
    }
    #toolbar button:hover, #toolbar label:hover { background: rgba(130, 80, 223, 0.3); }
    #btn-upload-input { display: none; }
  </style>
</head>
<body>
  <div id="editor-root">
    <div id="toolbar">
      <button id="btn-download">Download .md</button>
      <label for="btn-upload-input">Upload .md
        <input id="btn-upload-input" type="file" accept=".md,text/markdown,text/plain" />
      </label>
    </div>
    <div id="editor-blocks"></div>
  </div>
  <script type="module" src="./src/main.ts"></script>
</body>
</html>
```

Save to: `examples/block-editor/web/index.html`

---

- [ ] **Step 8: Verify moon check passes**

```bash
cd examples/block-editor && moon check
```

If it fails with a dependency error, `moon update` first.

---

- [ ] **Step 9: Commit scaffold**

```
feat(block-editor): scaffold examples/block-editor module
```

---

## Task 2: Core block types

**File to create:** `examples/block-editor/main/block_types.mbt`

---

- [ ] **Step 1: Write block_types.mbt**

```moonbit
///| Block editor core types.
///
/// BlockId is a type alias for TreeNodeId from event-graph-walker/tree.
/// Blocks are tree nodes; their text content lives in per-block TextDocs.

///|
/// Visual style for list items.
pub enum ListStyle {
  Bullet   // rendered as "- "
  Numbered // rendered as "1. " (number computed from siblings)
  Todo     // rendered as "- [ ] " or "- [x] "
} derive(Show, Eq, ToJson)

///|
/// Block type. Stored as a string property on the TreeDoc node.
/// Use `block_type_to_string` / `block_type_from_string` for
/// property serialization.
pub enum BlockType {
  Paragraph
  Heading(Int)      // level 1–6
  ListItem(ListStyle)
  Quote
  Code(String)      // language (empty = plain)
  Divider           // horizontal rule, no text content
  Raw               // verbatim Markdown, no structured parsing
} derive(Show, Eq, ToJson)

///|
pub fn block_type_to_string(t : BlockType) -> (String, Map[String, String]) {
  let props : Map[String, String] = Map::new()
  match t {
    Paragraph => ("paragraph", props)
    Heading(n) => {
      props.set("level", n.to_string())
      ("heading", props)
    }
    ListItem(style) => {
      let s = match style {
        Bullet => "bullet"
        Numbered => "numbered"
        Todo => "todo"
      }
      props.set("list_style", s)
      ("list_item", props)
    }
    Quote => ("quote", props)
    Code(lang) => {
      props.set("language", lang)
      ("code", props)
    }
    Divider => ("divider", props)
    Raw => ("raw", props)
  }
}

///|
pub fn block_type_from_props(
  type_str : String,
  get : (String) -> String?,
) -> BlockType {
  match type_str {
    "paragraph" => Paragraph
    "heading" => {
      let level = match get("level") {
        Some(s) => match Int::parse(s) {
          Ok(n) => n
          Err(_) => 1
        }
        None => 1
      }
      Heading(level)
    }
    "list_item" => {
      let style = match get("list_style") {
        Some("numbered") => Numbered
        Some("todo") => Todo
        _ => Bullet
      }
      ListItem(style)
    }
    "quote" => Quote
    "code" => Code(get("language").or(""))
    "divider" => Divider
    "raw" => Raw
    _ => Paragraph
  }
}
```

Save to: `examples/block-editor/main/block_types.mbt`

---

- [ ] **Step 2: Verify types compile**

```bash
cd examples/block-editor && moon check
```

---

- [ ] **Step 3: Commit**

```
feat(block-editor): add core block types
```

---

## Task 3: BlockDoc struct and CRUD

**Files to create:**
- `examples/block-editor/main/block_doc.mbt`
- `examples/block-editor/main/block_doc_wbtest.mbt`

---

- [ ] **Step 1: Write the failing tests first**

```moonbit
///| Whitebox tests for BlockDoc CRUD operations.

///|
test "BlockDoc: create paragraph and read text" {
  let doc = @main.BlockDoc::new("alice")
  let id = doc.create_block(Paragraph, parent=@main.root_block_id)
  doc.set_text(id, "Hello, world")
  inspect(doc.get_text(id), content="Hello, world")
}

///|
test "BlockDoc: create heading with level" {
  let doc = @main.BlockDoc::new("alice")
  let id = doc.create_block(Heading(2), parent=@main.root_block_id)
  doc.set_text(id, "Introduction")
  inspect(doc.get_type(id), content="Heading(2)")
  inspect(doc.get_text(id), content="Introduction")
}

///|
test "BlockDoc: children order is insertion order" {
  let doc = @main.BlockDoc::new("alice")
  let a = doc.create_block(Paragraph, parent=@main.root_block_id)
  let b = doc.create_block(Paragraph, parent=@main.root_block_id)
  let c = doc.create_block(Paragraph, parent=@main.root_block_id)
  let children = doc.children(@main.root_block_id)
  inspect(children.length(), content="3")
  inspect(children[0] == a, content="true")
  inspect(children[1] == b, content="true")
  inspect(children[2] == c, content="true")
}

///|
test "BlockDoc: delete block removes from children" {
  let doc = @main.BlockDoc::new("alice")
  let a = doc.create_block(Paragraph, parent=@main.root_block_id)
  let _ = doc.create_block(Paragraph, parent=@main.root_block_id)
  doc.delete_block(a)
  let children = doc.children(@main.root_block_id)
  inspect(children.length(), content="1")
  inspect(doc.is_alive(a), content="false")
}

///|
test "BlockDoc: change block type" {
  let doc = @main.BlockDoc::new("alice")
  let id = doc.create_block(Paragraph, parent=@main.root_block_id)
  doc.set_text(id, "my text")
  doc.set_type(id, Heading(1))
  inspect(doc.get_type(id), content="Heading(1)")
  inspect(doc.get_text(id), content="my text")
}

///|
test "BlockDoc: list item style" {
  let doc = @main.BlockDoc::new("alice")
  let id = doc.create_block(ListItem(Todo), parent=@main.root_block_id)
  doc.set_text(id, "buy milk")
  inspect(doc.get_type(id), content="ListItem(Todo)")
  doc.set_checked(id, true)
  inspect(doc.get_checked(id), content="true")
}

///|
test "BlockDoc: create_block_after inserts at correct position" {
  let doc = @main.BlockDoc::new("alice")
  let a = doc.create_block(Paragraph, parent=@main.root_block_id)
  let b = doc.create_block(Paragraph, parent=@main.root_block_id)
  // Insert c after a — should land between a and b
  let c = doc.create_block_after(a, Paragraph)
  let children = doc.children(@main.root_block_id)
  inspect(children.length(), content="3")
  inspect(children[0] == a, content="true")
  inspect(children[1] == c, content="true")
  inspect(children[2] == b, content="true")
}

///|
test "BlockDoc: create_block_after appends when after_id is last" {
  let doc = @main.BlockDoc::new("alice")
  let a = doc.create_block(Paragraph, parent=@main.root_block_id)
  let b = doc.create_block_after(a, Paragraph)
  let children = doc.children(@main.root_block_id)
  inspect(children.length(), content="2")
  inspect(children[0] == a, content="true")
  inspect(children[1] == b, content="true")
}
```

Save to: `examples/block-editor/main/block_doc_wbtest.mbt`

---

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd examples/block-editor && moon test
```

Expected: compile errors (BlockDoc not defined yet).

---

- [ ] **Step 3: Implement block_doc.mbt**

```moonbit
///| BlockDoc — collaborative block document.
///
/// Structure is a TreeDoc (Kleppmann's movable-tree CRDT).
/// Each block's text content is an independent TextDoc (FugueMax).
/// Block type, level, style, and other metadata are stored as TreeDoc
/// string properties and decoded on read via `block_type_from_props`.

///|
/// Public re-export of TreeNodeId for callers who need it.
pub typealias BlockId = @tree.TreeNodeId

///|
/// The root sentinel. All top-level blocks are children of root_block_id.
pub let root_block_id : BlockId = @tree.root_id

///|
pub struct BlockDoc {
  priv tree : @tree.TreeDoc
  priv texts : Map[BlockId, @text.TextDoc]
  /// Display order for root-level blocks. V1 simplification: TreeDoc does not
  /// expose `create_node_after`, so we track order explicitly. Phase 2 replaces
  /// this with fractional-index–based TreeDoc ordering.
  priv mut order : Array[BlockId]
  priv replica_id : String
}

///|
pub fn BlockDoc::new(replica_id : String) -> BlockDoc {
  {
    tree: @tree.TreeDoc::new(replica_id),
    texts: Map::new(),
    order: [],
    replica_id,
  }
}

///|
/// Internal helper: attach type properties and a TextDoc to a newly created node id.
fn BlockDoc::init_block(
  self : BlockDoc,
  id : BlockId,
  block_type : BlockType,
) -> Unit {
  let (type_str, extra) = block_type_to_string(block_type)
  self.tree.set_property(id, "type", type_str)
  for key, value in extra {
    self.tree.set_property(id, key, value)
  }
  match block_type {
    Divider => ()
    _ => self.texts.set(id, @text.TextDoc::new(self.replica_id))
  }
}

///|
/// Create a new block of the given type as the last child of `parent`.
/// Returns the new block's id.
pub fn BlockDoc::create_block(
  self : BlockDoc,
  block_type : BlockType,
  parent~ : BlockId,
) -> BlockId {
  let id = self.tree.create_node(parent~)
  self.init_block(id, block_type)
  if parent == root_block_id {
    self.order.push(id)
  }
  id
}

///|
/// Create a new block immediately after `after_id` in display order.
/// If `after_id` is not in the order (e.g., not a root block), appends.
pub fn BlockDoc::create_block_after(
  self : BlockDoc,
  after_id : BlockId,
  block_type : BlockType,
) -> BlockId {
  let id = self.tree.create_node(parent=root_block_id)
  self.init_block(id, block_type)
  // Find insertion index
  let mut insert_at = self.order.length()
  for i = 0; i < self.order.length(); i = i + 1 {
    if self.order[i] == after_id {
      insert_at = i + 1
      break
    }
  }
  // Rebuild order with id at insert_at
  let new_order : Array[BlockId] = []
  for i = 0; i < self.order.length(); i = i + 1 {
    if i == insert_at { new_order.push(id) }
    new_order.push(self.order[i])
  }
  if insert_at == self.order.length() { new_order.push(id) }
  self.order = new_order
  id
}

///|
/// Delete a block (moves to trash in TreeDoc; removes from display order).
pub fn BlockDoc::delete_block(self : BlockDoc, id : BlockId) -> Unit {
  self.tree.delete_node(id)
  let filtered : Array[BlockId] = []
  for bid in self.order {
    if bid != id { filtered.push(bid) }
  }
  self.order = filtered
}

///|
/// Move a block to a new parent (e.g., rearrange blocks).
pub fn BlockDoc::move_block(
  self : BlockDoc,
  id : BlockId,
  new_parent~ : BlockId,
) -> Unit {
  self.tree.move_node(target=id, new_parent~)
}

///|
/// Get visible children of a block (excludes deleted blocks).
/// For root_block_id, returns the explicit display order.
/// For non-root blocks, delegates to TreeDoc (Phase 2 nested blocks).
pub fn BlockDoc::children(self : BlockDoc, parent : BlockId) -> Array[BlockId] {
  if parent == root_block_id {
    // Filter out any blocks deleted externally (e.g., via apply_remote_op)
    let result : Array[BlockId] = []
    for id in self.order {
      if self.tree.is_alive(id) { result.push(id) }
    }
    result
  } else {
    self.tree.children(parent)
  }
}

///|
/// Check if a block is alive (not deleted).
pub fn BlockDoc::is_alive(self : BlockDoc, id : BlockId) -> Bool {
  self.tree.is_alive(id)
}

///|
/// Get the block type by reading its TreeDoc properties.
pub fn BlockDoc::get_type(self : BlockDoc, id : BlockId) -> BlockType {
  let type_str = self.tree.get_property(id, "type").or("paragraph")
  block_type_from_props(type_str, fn(key) { self.tree.get_property(id, key) })
}

///|
/// Change the block type (updates TreeDoc properties in-place).
/// Text content is preserved.
pub fn BlockDoc::set_type(self : BlockDoc, id : BlockId, t : BlockType) -> Unit {
  let (type_str, extra) = block_type_to_string(t)
  self.tree.set_property(id, "type", type_str)
  for key, value in extra {
    self.tree.set_property(id, key, value)
  }
}

///|
/// Get the text content of a block.
/// Returns empty string if the block has no TextDoc (e.g., Divider).
pub fn BlockDoc::get_text(self : BlockDoc, id : BlockId) -> String {
  match self.texts.get(id) {
    Some(text_doc) => text_doc.text()
    None => ""
  }
}

///|
/// Replace the full text content of a block.
/// Uses delete-all + insert to set arbitrary text.
pub fn BlockDoc::set_text(self : BlockDoc, id : BlockId, text : String) -> Unit {
  match self.texts.get(id) {
    None => ()
    Some(text_doc) => {
      let current = text_doc.text()
      // Delete all existing characters (delete-first to satisfy FugueMax ordering)
      for i = current.length() - 1; i >= 0; i = i - 1 {
        text_doc.delete(@text.Pos::at(i))
      }
      // Insert new text
      if text.length() > 0 {
        text_doc.insert(@text.Pos::at(0), text)
      }
    }
  }
}

///|
/// Apply a single-character insert at position `pos`.
/// Called by the TypeScript shell on each keypress.
pub fn BlockDoc::insert_char(
  self : BlockDoc,
  id : BlockId,
  pos : Int,
  ch : String,
) -> Unit {
  match self.texts.get(id) {
    None => ()
    Some(text_doc) => text_doc.insert(@text.Pos::at(pos), ch)
  }
}

///|
/// Delete the character at position `pos`.
/// Called by the TypeScript shell on Backspace/Delete.
pub fn BlockDoc::delete_char(self : BlockDoc, id : BlockId, pos : Int) -> Unit {
  match self.texts.get(id) {
    None => ()
    Some(text_doc) => text_doc.delete(@text.Pos::at(pos))
  }
}

///|
/// Get `checked` property (for todo list items).
pub fn BlockDoc::get_checked(self : BlockDoc, id : BlockId) -> Bool {
  match self.tree.get_property(id, "checked") {
    Some("true") => true
    _ => false
  }
}

///|
/// Set `checked` property (for todo list items).
pub fn BlockDoc::set_checked(self : BlockDoc, id : BlockId, checked : Bool) -> Unit {
  self.tree.set_property(id, "checked", if checked { "true" } else { "false" })
}
```

Save to: `examples/block-editor/main/block_doc.mbt`

---

- [ ] **Step 4: Run tests to confirm they pass**

```bash
cd examples/block-editor && moon test
```

Fix any compilation or assertion errors before continuing.

---

- [ ] **Step 5: Commit**

```
feat(block-editor): BlockDoc struct and CRUD with whitebox tests
```

---

## Task 4: Markdown export

Add `block_doc_to_markdown` to a new file.

---

- [ ] **Step 1: Add failing export tests**

Append to `block_doc_wbtest.mbt`:

```moonbit
///|
test "export: paragraph" {
  let doc = @main.BlockDoc::new("alice")
  let p = doc.create_block(Paragraph, parent=@main.root_block_id)
  doc.set_text(p, "Hello world")
  inspect(
    @main.block_doc_to_markdown(doc),
    content="Hello world",
  )
}

///|
test "export: heading" {
  let doc = @main.BlockDoc::new("alice")
  let h = doc.create_block(Heading(2), parent=@main.root_block_id)
  doc.set_text(h, "Section")
  inspect(
    @main.block_doc_to_markdown(doc),
    content="## Section",
  )
}

///|
test "export: mixed blocks" {
  let doc = @main.BlockDoc::new("alice")
  let h = doc.create_block(Heading(1), parent=@main.root_block_id)
  doc.set_text(h, "Title")
  let p = doc.create_block(Paragraph, parent=@main.root_block_id)
  doc.set_text(p, "Intro text.")
  let li = doc.create_block(ListItem(Bullet), parent=@main.root_block_id)
  doc.set_text(li, "First item")
  inspect(
    @main.block_doc_to_markdown(doc),
    content=
      #|# Title
      #|
      #|Intro text.
      #|
      #|- First item
    ,
  )
}

///|
test "export: numbered list" {
  let doc = @main.BlockDoc::new("alice")
  let a = doc.create_block(ListItem(Numbered), parent=@main.root_block_id)
  doc.set_text(a, "Step one")
  let b = doc.create_block(ListItem(Numbered), parent=@main.root_block_id)
  doc.set_text(b, "Step two")
  inspect(
    @main.block_doc_to_markdown(doc),
    content=
      #|1. Step one
      #|2. Step two
    ,
  )
}

///|
test "export: todo list" {
  let doc = @main.BlockDoc::new("alice")
  let a = doc.create_block(ListItem(Todo), parent=@main.root_block_id)
  doc.set_text(a, "buy milk")
  doc.set_checked(a, false)
  let b = doc.create_block(ListItem(Todo), parent=@main.root_block_id)
  doc.set_text(b, "send email")
  doc.set_checked(b, true)
  inspect(
    @main.block_doc_to_markdown(doc),
    content=
      #|- [ ] buy milk
      #|- [x] send email
    ,
  )
}

///|
test "export: code block" {
  let doc = @main.BlockDoc::new("alice")
  let cb = doc.create_block(Code("moonbit"), parent=@main.root_block_id)
  doc.set_text(cb, "let x = 42")
  inspect(
    @main.block_doc_to_markdown(doc),
    content=
      #|```moonbit
      #|let x = 42
      #|```
    ,
  )
}

///|
test "export: divider" {
  let doc = @main.BlockDoc::new("alice")
  let p = doc.create_block(Paragraph, parent=@main.root_block_id)
  doc.set_text(p, "Before")
  let _ = doc.create_block(Divider, parent=@main.root_block_id)
  let p2 = doc.create_block(Paragraph, parent=@main.root_block_id)
  doc.set_text(p2, "After")
  inspect(
    @main.block_doc_to_markdown(doc),
    content=
      #|Before
      #|
      #|---
      #|
      #|After
    ,
  )
}
```

---

- [ ] **Step 2: Run tests to confirm new ones fail**

```bash
cd examples/block-editor && moon test
```

Expected: fail because `block_doc_to_markdown` is not defined.

---

- [ ] **Step 3: Implement block_export.mbt**

```moonbit
///| Markdown export for BlockDoc.
///
/// Renders the document tree (children of root_block_id in order) as
/// a CommonMark-compatible Markdown string.
///
/// Rules:
/// - Blank lines separate visually distinct block groups (heading/paragraph/divider
///   get blank line before and after; consecutive list items of the same style
///   do NOT get blank lines between them).
/// - Nested blocks (list children) are indented 2 spaces per level.
/// - Numbered list items are numbered sequentially within their run of siblings.
///
/// V1 limitation: only renders the top level (children of root).
/// Nested block children are deferred to Phase 2.

///|
fn render_block_md(
  doc : BlockDoc,
  id : BlockId,
  numbered_idx : Int,
) -> String {
  let text = doc.get_text(id)
  match doc.get_type(id) {
    Paragraph => text
    Heading(n) => {
      let prefix = String::make(n, '#') + " "
      prefix + text
    }
    ListItem(Bullet) => "- " + text
    ListItem(Numbered) => numbered_idx.to_string() + ". " + text
    ListItem(Todo) =>
      if doc.get_checked(id) {
        "- [x] " + text
      } else {
        "- [ ] " + text
      }
    Quote => "> " + text
    Code(lang) =>
      if lang.length() > 0 {
        "```" + lang + "\n" + text + "\n```"
      } else {
        "```\n" + text + "\n```"
      }
    Divider => "---"
    Raw => text
  }
}

///|
fn needs_blank_line_before(t : BlockType) -> Bool {
  match t {
    Heading(_) | Divider | Quote | Code(_) | Raw => true
    Paragraph | ListItem(_) => false
  }
}

///|
fn needs_blank_line_after(t : BlockType) -> Bool {
  match t {
    Heading(_) | Divider | Quote | Code(_) | Raw => true
    Paragraph | ListItem(_) => false
  }
}

///|
pub fn block_doc_to_markdown(doc : BlockDoc) -> String {
  let blocks = doc.children(root_block_id)
  if blocks.length() == 0 {
    return ""
  }
  let lines : Array[String] = []
  let mut numbered_counter = 0
  let mut prev_type : BlockType? = None
  for i = 0; i < blocks.length(); i = i + 1 {
    let id = blocks[i]
    let t = doc.get_type(id)
    // Track numbering within consecutive Numbered runs
    match t {
      ListItem(Numbered) => numbered_counter = numbered_counter + 1
      _ => numbered_counter = 1
    }
    // Insert blank line before if needed
    let need_before = needs_blank_line_before(t) || match prev_type {
      Some(p) => needs_blank_line_after(p) || is_different_block_group(p, t)
      None => false
    }
    if need_before && lines.length() > 0 {
      lines.push("")
    }
    lines.push(render_block_md(doc, id, numbered_counter))
    prev_type = Some(t)
  }
  // Join and trim trailing blank lines
  let joined = lines.join("\n")
  joined.trim_end()
}

///|
/// Two blocks are in different visual groups if one is a list item and
/// the other is not, or if both are list items with different styles.
fn is_different_block_group(a : BlockType, b : BlockType) -> Bool {
  match (a, b) {
    (ListItem(sa), ListItem(sb)) => sa != sb
    (ListItem(_), _) | (_, ListItem(_)) => true
    _ => false
  }
}
```

Save to: `examples/block-editor/main/block_export.mbt`

---

- [ ] **Step 4: Run tests to confirm they pass**

```bash
cd examples/block-editor && moon test
```

Fix any assertion mismatches before continuing.

---

- [ ] **Step 5: Commit**

```
feat(block-editor): Markdown export with blank-line and numbering rules
```

---

## Task 5: Markdown import

---

- [ ] **Step 1: Add failing import tests**

Append to `block_doc_wbtest.mbt`:

```moonbit
///|
test "import: paragraph" {
  let doc = @main.block_doc_from_markdown("Hello world", "alice")
  let children = doc.children(@main.root_block_id)
  inspect(children.length(), content="1")
  inspect(doc.get_type(children[0]), content="Paragraph")
  inspect(doc.get_text(children[0]), content="Hello world")
}

///|
test "import: heading levels" {
  let md =
    #|# H1
    #|## H2
    #|### H3
  let doc = @main.block_doc_from_markdown(md, "alice")
  let children = doc.children(@main.root_block_id)
  inspect(children.length(), content="3")
  inspect(doc.get_type(children[0]), content="Heading(1)")
  inspect(doc.get_type(children[1]), content="Heading(2)")
  inspect(doc.get_type(children[2]), content="Heading(3)")
  inspect(doc.get_text(children[0]), content="H1")
}

///|
test "import: bullet list" {
  let md =
    #|- apples
    #|- oranges
    #|- bananas
  let doc = @main.block_doc_from_markdown(md, "alice")
  let children = doc.children(@main.root_block_id)
  inspect(children.length(), content="3")
  inspect(doc.get_type(children[0]), content="ListItem(Bullet)")
  inspect(doc.get_text(children[2]), content="bananas")
}

///|
test "import: numbered list" {
  let md =
    #|1. first
    #|2. second
  let doc = @main.block_doc_from_markdown(md, "alice")
  let children = doc.children(@main.root_block_id)
  inspect(children.length(), content="2")
  inspect(doc.get_type(children[0]), content="ListItem(Numbered)")
  inspect(doc.get_type(children[1]), content="ListItem(Numbered)")
  inspect(doc.get_text(children[0]), content="first")
}

///|
test "import: todo list" {
  let md =
    #|- [ ] not done
    #|- [x] done
  let doc = @main.block_doc_from_markdown(md, "alice")
  let children = doc.children(@main.root_block_id)
  inspect(children.length(), content="2")
  inspect(doc.get_type(children[0]), content="ListItem(Todo)")
  inspect(doc.get_checked(children[0]), content="false")
  inspect(doc.get_checked(children[1]), content="true")
}

///|
test "import: code block" {
  let md =
    #|```moonbit
    #|let x = 42
    #|```
  let doc = @main.block_doc_from_markdown(md, "alice")
  let children = doc.children(@main.root_block_id)
  inspect(children.length(), content="1")
  inspect(doc.get_type(children[0]), content="Code(\"moonbit\")")
  inspect(doc.get_text(children[0]), content="let x = 42")
}

///|
test "import: multi-line paragraph accumulated into one block" {
  let md =
    #|First line of paragraph
    #|second line of same paragraph
    #|
    #|New paragraph here
  let doc = @main.block_doc_from_markdown(md, "alice")
  let children = doc.children(@main.root_block_id)
  inspect(children.length(), content="2")
  inspect(doc.get_text(children[0]), content="First line of paragraph second line of same paragraph")
  inspect(doc.get_text(children[1]), content="New paragraph here")
}

///|
test "import: round-trip paragraph and heading" {
  let original =
    #|# My Document
    #|
    #|A paragraph of text.
    #|
    #|- item one
    #|- item two
  let doc = @main.block_doc_from_markdown(original, "alice")
  let exported = @main.block_doc_to_markdown(doc)
  inspect(
    exported,
    content=
      #|# My Document
      #|
      #|A paragraph of text.
      #|
      #|- item one
      #|- item two
    ,
  )
}
```

---

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd examples/block-editor && moon test
```

Expected: `block_doc_from_markdown` not defined.

---

- [ ] **Step 3: Implement block_import.mbt**

```moonbit
///| Markdown import for BlockDoc.
///
/// Line-by-line parser. Handles:
///   - Headings: "# " through "###### " (1–6 hashes)
///   - Bullet lists: "- " or "* "
///   - Numbered lists: "N. " (any digit(s) followed by ". ")
///   - Todo lists: "- [ ] " (unchecked) / "- [x] " (checked)
///   - Code fences: "```lang" ... "```"
///   - Block quotes: "> "
///   - Dividers: "---" or "***" or "___" (standalone)
///   - Paragraph: consecutive non-blank, non-special lines accumulated into one block.
///
/// V1 deviations: no nested block parsing; unknown syntax becomes Paragraph (not Raw).

///|
fn is_divider_line(line : String) -> Bool {
  let t = line.trim()
  t == "---" || t == "***" || t == "___"
}

///|
/// Returns true if `line` opens a new structured block (not a paragraph continuation).
fn is_special_line(line : String) -> Bool {
  if line.trim() == "" { return true }
  if is_divider_line(line) { return true }
  if starts_with(line, "```") { return true }
  if starts_with(line, "> ") { return true }
  match heading_level(line) {
    Some(_) => return true
    None => ()
  }
  match list_marker(line) {
    Some(_) => return true
    None => ()
  }
  false
}

///|
fn heading_level(line : String) -> (Int, String)? {
  let mut level = 0
  let mut i = 0
  while i < line.length() && line[i] == '#' {
    level = level + 1
    i = i + 1
  }
  if level == 0 || level > 6 {
    return None
  }
  if i < line.length() && line[i] == ' ' {
    Some((level, line.substring(start=i + 1)))
  } else {
    None
  }
}

///|
fn starts_with(s : String, prefix : String) -> Bool {
  s.length() >= prefix.length() &&
  s.substring(start=0, end=prefix.length()) == prefix
}

///|
/// Parse a line as a list marker. Returns (ListStyle, Bool /* checked */, rest_of_line)?
fn list_marker(line : String) -> (ListStyle, Bool, String)? {
  // Todo: "- [ ] " or "- [x] "
  if starts_with(line, "- [ ] ") {
    return Some((Todo, false, line.substring(start=6)))
  }
  if starts_with(line, "- [x] ") {
    return Some((Todo, true, line.substring(start=6)))
  }
  if starts_with(line, "* [ ] ") {
    return Some((Todo, false, line.substring(start=6)))
  }
  if starts_with(line, "* [x] ") {
    return Some((Todo, true, line.substring(start=6)))
  }
  // Bullet: "- " or "* "
  if starts_with(line, "- ") {
    return Some((Bullet, false, line.substring(start=2)))
  }
  if starts_with(line, "* ") {
    return Some((Bullet, false, line.substring(start=2)))
  }
  // Numbered: "N. " where N is one or more digits
  let mut i = 0
  while i < line.length() && line[i] >= '0' && line[i] <= '9' {
    i = i + 1
  }
  if i > 0 && i + 1 < line.length() && line[i] == '.' && line[i + 1] == ' ' {
    return Some((Numbered, false, line.substring(start=i + 2)))
  }
  None
}

///|
pub fn block_doc_from_markdown(md : String, replica_id : String) -> BlockDoc {
  let doc = BlockDoc::new(replica_id)
  let lines = md.split("\n")
  let mut i = 0
  while i < lines.length() {
    let line = lines[i]
    // Skip blank lines between blocks
    if line.trim() == "" {
      i = i + 1
      continue
    }
    // Code fence: "```lang"
    if starts_with(line, "```") {
      let lang = line.substring(start=3).trim()
      // Collect lines until closing "```"
      let code_lines : Array[String] = []
      i = i + 1
      while i < lines.length() && lines[i].trim() != "```" {
        code_lines.push(lines[i])
        i = i + 1
      }
      let id = doc.create_block(Code(lang), parent=root_block_id)
      doc.set_text(id, code_lines.join("\n"))
      i = i + 1 // skip closing "```"
      continue
    }
    // Divider
    if is_divider_line(line) {
      let _ = doc.create_block(Divider, parent=root_block_id)
      i = i + 1
      continue
    }
    // Heading
    match heading_level(line) {
      Some((level, text)) => {
        let id = doc.create_block(Heading(level), parent=root_block_id)
        doc.set_text(id, text)
        i = i + 1
        continue
      }
      None => ()
    }
    // Block quote: "> "
    if starts_with(line, "> ") {
      let id = doc.create_block(Quote, parent=root_block_id)
      doc.set_text(id, line.substring(start=2))
      i = i + 1
      continue
    }
    // List item
    match list_marker(line) {
      Some((style, checked, text)) => {
        let id = doc.create_block(ListItem(style), parent=root_block_id)
        doc.set_text(id, text)
        if checked {
          doc.set_checked(id, true)
        }
        i = i + 1
        continue
      }
      None => ()
    }
    // Paragraph (default) — accumulate continuation lines until blank or special
    let para_lines : Array[String] = [line]
    i = i + 1
    while i < lines.length() && not(is_special_line(lines[i])) {
      para_lines.push(lines[i])
      i = i + 1
    }
    let id = doc.create_block(Paragraph, parent=root_block_id)
    doc.set_text(id, para_lines.join(" "))
  }
  doc
}
```

Save to: `examples/block-editor/main/block_import.mbt`

---

- [ ] **Step 4: Run tests to confirm they pass**

```bash
cd examples/block-editor && moon test
```

Fix assertion mismatches. Run `moon test --update` if snapshot content is correct but format differs.

---

- [ ] **Step 5: Commit**

```
feat(block-editor): Markdown import — line-by-line parser for core block types
```

---

## Task 6: Render state JSON serialization

The TypeScript shell needs a JSON snapshot each RAF frame to patch the DOM.

---

- [ ] **Step 1: Add serialization test**

Append to `block_doc_wbtest.mbt`:

```moonbit
///|
test "get_render_state: JSON snapshot" {
  let doc = @main.BlockDoc::new("alice")
  let h = doc.create_block(Heading(1), parent=@main.root_block_id)
  doc.set_text(h, "Hello")
  let p = doc.create_block(Paragraph, parent=@main.root_block_id)
  doc.set_text(p, "World")
  // Parse JSON and spot-check fields (avoid brittle id-format assertions)
  let json_str = @main.render_state_to_json(doc)
  let parsed = @json.parse!(json_str)
  match parsed {
    Object(obj) => {
      match obj.get("blocks") {
        Some(Array(blocks)) => inspect(blocks.length(), content="2")
        _ => fail("expected blocks array")
      }
    }
    _ => fail("expected object")
  }
}
```

---

- [ ] **Step 2: Run test to confirm it fails**

---

- [ ] **Step 3: Add render_state_to_json to block_init.mbt**

Create `examples/block-editor/main/block_init.mbt`:

```moonbit
///| Handle registry and exported bridge wrappers.
///
/// Mirrors the canvas pattern: each `create_editor()` call returns an
/// integer handle. Bridge functions take the handle as first argument.

///|
let _registry : Array[BlockDoc] = []

///|
pub fn create_editor() -> Int {
  _registry.push(BlockDoc::new("local"))
  _registry.length() - 1
}

///|
/// Serializable block snapshot for TypeScript.
struct BlockJson {
  id : String    // "agent:counter"
  block_type : String
  level : Int    // 0 for non-headings
  list_style : String  // "bullet" | "numbered" | "todo" | ""
  checked : Bool
  text : String
} derive(ToJson)

///|
fn block_to_json(doc : BlockDoc, id : BlockId) -> BlockJson {
  let t = doc.get_type(id)
  let (type_str, _) = block_type_to_string(t)
  let level = match t {
    Heading(n) => n
    _ => 0
  }
  let list_style = match t {
    ListItem(Bullet) => "bullet"
    ListItem(Numbered) => "numbered"
    ListItem(Todo) => "todo"
    _ => ""
  }
  {
    id: id.agent + ":" + id.counter.to_string(),
    block_type: type_str,
    level,
    list_style,
    checked: doc.get_checked(id),
    text: doc.get_text(id),
  }
}

///|
struct RenderStateJson {
  blocks : Array[BlockJson]
} derive(ToJson)

///|
pub fn render_state_to_json(doc : BlockDoc) -> String {
  let block_ids = doc.children(root_block_id)
  let blocks : Array[BlockJson] = []
  for id in block_ids {
    blocks.push(block_to_json(doc, id))
  }
  let state : RenderStateJson = { blocks }
  state.to_json().stringify()
}

///|
pub fn get_render_state(handle : Int) -> String {
  render_state_to_json(_registry[handle])
}

///|
pub fn editor_insert_block_after(
  handle : Int,
  after_id_str : String,
  block_type_str : String,
) -> String {
  ignore(block_type_str)  // V1: always inserts a Paragraph; caller uses editor_set_block_type to convert
  let doc = _registry[handle]
  let new_id = match parse_block_id(after_id_str, doc) {
    Some(after_id) => doc.create_block_after(after_id, Paragraph)
    None => doc.create_block(Paragraph, parent=root_block_id)
  }
  new_id.agent + ":" + new_id.counter.to_string()
}

///|
pub fn editor_set_block_text(
  handle : Int,
  block_id_str : String,
  text : String,
) -> Unit {
  let doc = _registry[handle]
  match parse_block_id(block_id_str, doc) {
    Some(id) => doc.set_text(id, text)
    None => ()
  }
}

///|
pub fn editor_delete_block(handle : Int, block_id_str : String) -> Unit {
  let doc = _registry[handle]
  match parse_block_id(block_id_str, doc) {
    Some(id) => doc.delete_block(id)
    None => ()
  }
}

///|
pub fn editor_set_block_type(
  handle : Int,
  block_id_str : String,
  type_str : String,
  level : Int,
) -> Unit {
  let doc = _registry[handle]
  match parse_block_id(block_id_str, doc) {
    Some(id) => {
      let t = match type_str {
        "heading" => Heading(level)
        "paragraph" => Paragraph
        "list_item_bullet" => ListItem(Bullet)
        "list_item_numbered" => ListItem(Numbered)
        "list_item_todo" => ListItem(Todo)
        "quote" => Quote
        "code" => Code("")
        "divider" => Divider
        _ => Paragraph
      }
      doc.set_type(id, t)
    }
    None => ()
  }
}

///|
/// Parse "agent:counter" → BlockId by looking up in tree children.
fn parse_block_id(id_str : String, doc : BlockDoc) -> BlockId? {
  // Split on last ':' to handle agent names that might contain ':'
  let colon = id_str.last_index_of(":")
  if colon < 0 {
    return None
  }
  let agent = id_str.substring(start=0, end=colon)
  let counter_str = id_str.substring(start=colon + 1)
  match Int::parse(counter_str) {
    Ok(counter) => {
      let candidate : BlockId = { agent, counter }
      if doc.is_alive(candidate) { Some(candidate) } else { None }
    }
    Err(_) => None
  }
}

///|
pub fn editor_import_markdown(handle : Int, md : String) -> Unit {
  // Replace registry entry with freshly imported document
  let replica_id = _registry[handle].replica_id
  _registry[handle] = block_doc_from_markdown(md, replica_id)
}

///|
pub fn editor_export_markdown(handle : Int) -> String {
  block_doc_to_markdown(_registry[handle])
}
```

Save to: `examples/block-editor/main/block_init.mbt`

---

- [ ] **Step 4: Run tests to confirm they pass**

```bash
cd examples/block-editor && moon test
```

---

- [ ] **Step 5: Commit**

```
feat(block-editor): render state JSON serialization and bridge wrappers
```

---

## Task 7: Update moon.pkg with full export list

---

- [ ] **Step 1: Update moon.pkg**

```moonpkg
import {
  "moonbitlang/core/json",
}

options(
  "is-main": true,
  link: {
    "js": {
      "exports": [
        "create_editor",
        "get_render_state",
        "editor_insert_block_after",
        "editor_set_block_text",
        "editor_delete_block",
        "editor_set_block_type",
        "editor_import_markdown",
        "editor_export_markdown",
      ],
    },
  },
)
```

Save to: `examples/block-editor/main/moon.pkg`

---

- [ ] **Step 2: Build for JS target**

```bash
cd examples/block-editor && moon build --target js --release
```

---

- [ ] **Step 3: Verify exported symbols exist in the built JS**

```bash
grep -o 'create_editor\|get_render_state\|editor_insert_block_after' \
  _build/js/release/build/examples/block-editor/main/main.js | sort -u
```

Expected: all three names found.

---

- [ ] **Step 4: Run moon test one more time to confirm nothing broke**

```bash
cd examples/block-editor && moon test
```

---

- [ ] **Step 5: Commit**

```
feat(block-editor): wire JS export list in moon.pkg
```

---

## Task 8: TypeScript shell

---

- [ ] **Step 1: Create web/src/main.ts**

```typescript
type EditorModule = {
  create_editor:           () => number;
  get_render_state:        (h: number) => string;
  editor_insert_block_after:(h: number, after_id: string, block_type: string) => string;
  editor_set_block_text:   (h: number, id: string, text: string) => void;
  editor_delete_block:     (h: number, id: string) => void;
  editor_set_block_type:   (h: number, id: string, type: string, level: number) => void;
  editor_import_markdown:  (h: number, md: string) => void;
  editor_export_markdown:  (h: number) => string;
};

type BlockJson = {
  id:         string;
  block_type: string;
  level:      number;
  list_style: string;
  checked:    boolean;
  text:       string;
};

type RenderState = { blocks: BlockJson[] };

let mb: EditorModule;
let handle = -1;
let rafPending = false;
const root = document.getElementById('editor-blocks') as HTMLDivElement;
const blockDivs = new Map<string, HTMLDivElement>();

// ── RAF render loop ────────────────────────────────────────────────────────

function scheduleRender(): void {
  if (rafPending) return;
  rafPending = true;
  requestAnimationFrame(render);
}

function bulletFor(b: BlockJson): string {
  if (b.block_type !== 'list_item') return '';
  if (b.list_style === 'bullet') return '•';
  if (b.list_style === 'todo') return b.checked ? '☑' : '☐';
  return ''; // numbered — number rendered by CSS counter or inline
}

function render(): void {
  rafPending = false;
  const state: RenderState = JSON.parse(mb.get_render_state(handle));
  const seen = new Set<string>();

  state.blocks.forEach((block, idx) => {
    seen.add(block.id);
    let div = blockDivs.get(block.id);
    if (!div) {
      div = document.createElement('div');
      div.className   = 'block';
      div.contentEditable = 'true';
      div.dataset.blockId = block.id;
      attachBlockListeners(div);
      root.appendChild(div);
      blockDivs.set(block.id, div);
    }

    // Re-order if needed
    const currentIdx = Array.from(root.children).indexOf(div);
    if (currentIdx !== idx) root.insertBefore(div, root.children[idx] ?? null);

    div.dataset.type  = block.block_type;
    div.dataset.level = String(block.level);
    div.dataset.bullet = bulletFor(block);

    // Only patch textContent when focus is elsewhere (avoid caret jump)
    if (document.activeElement !== div && div.textContent !== block.text) {
      div.textContent = block.text;
    }
  });

  // Remove deleted blocks
  for (const [id, div] of blockDivs) {
    if (!seen.has(id)) { div.remove(); blockDivs.delete(id); }
  }
}

// ── Event wiring ───────────────────────────────────────────────────────────

function attachBlockListeners(div: HTMLDivElement): void {
  div.addEventListener('input', () => {
    const id = div.dataset.blockId!;
    mb.editor_set_block_text(handle, id, div.textContent ?? '');
    scheduleRender();
  });

  div.addEventListener('keydown', (e: KeyboardEvent) => {
    const id = div.dataset.blockId!;

    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      const newId = mb.editor_insert_block_after(handle, id, 'paragraph');
      scheduleRender();
      // Focus the new block after the DOM is patched
      requestAnimationFrame(() => {
        const newDiv = blockDivs.get(newId);
        if (newDiv) { newDiv.focus(); placeCursorAtStart(newDiv); }
      });
    }

    if (e.key === 'Backspace' && div.textContent === '') {
      e.preventDefault();
      const prevDiv = div.previousElementSibling as HTMLDivElement | null;
      mb.editor_delete_block(handle, id);
      scheduleRender();
      if (prevDiv) { prevDiv.focus(); placeCursorAtEnd(prevDiv); }
    }

    // Autoformat: Space after a Markdown prefix converts the block type.
    // e.g. "##" + Space → Heading(2), "-" + Space → BulletList
    if (e.key === ' ') {
      const text = (div.textContent ?? '').trimEnd();
      const fmt = detectAutoformat(text);
      if (fmt) {
        e.preventDefault();
        mb.editor_set_block_type(handle, id, fmt.type, fmt.level);
        mb.editor_set_block_text(handle, id, '');
        scheduleRender();
      }
    }
  });
}

// ── Autoformat detection ───────────────────────────────────────────────────

function detectAutoformat(text: string): { type: string; level: number } | null {
  // "# " through "###### " → heading
  const headingMatch = text.match(/^(#{1,6})$/);
  if (headingMatch) return { type: 'heading', level: headingMatch[1].length };
  if (text === '-' || text === '*') return { type: 'list_item_bullet', level: 0 };
  if (/^\d+\.$/.test(text))         return { type: 'list_item_numbered', level: 0 };
  if (text === '- [ ]')             return { type: 'list_item_todo', level: 0 };
  if (text === '>')                 return { type: 'quote', level: 0 };
  return null;
}

function placeCursorAtStart(div: HTMLDivElement): void {
  const range = document.createRange();
  range.setStart(div, 0);
  range.collapse(true);
  const sel = window.getSelection();
  sel?.removeAllRanges();
  sel?.addRange(range);
}

function placeCursorAtEnd(div: HTMLDivElement): void {
  const range = document.createRange();
  range.selectNodeContents(div);
  range.collapse(false);
  const sel = window.getSelection();
  sel?.removeAllRanges();
  sel?.addRange(range);
}

// ── Bootstrap ─────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  const mod = await import('@moonbit/main.js');
  mb = mod as EditorModule;
  handle = mb.create_editor();

  // Seed with a starter document
  mb.editor_import_markdown(handle, [
    '# Welcome to Block Editor',
    '',
    'Start typing below. Press Enter to create a new block.',
    'Type "# " to convert a paragraph to a heading.',
    '',
    '- First bullet item',
    '- Second bullet item',
    '',
    '1. Step one',
    '2. Step two',
  ].join('\n'));

  scheduleRender();

  // ── Download Markdown ─────────────────────────────────────────────────────
  document.getElementById('btn-download')?.addEventListener('click', () => {
    const md = mb.editor_export_markdown(handle);
    const blob = new Blob([md], { type: 'text/markdown' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = 'document.md'; a.click();
    URL.revokeObjectURL(url);
  });

  // ── Upload Markdown ───────────────────────────────────────────────────────
  document.getElementById('btn-upload-input')?.addEventListener('change', (e: Event) => {
    const file = (e.target as HTMLInputElement).files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = () => {
      mb.editor_import_markdown(handle, reader.result as string);
      // Clear old divs so render loop recreates them in new order
      blockDivs.forEach(div => div.remove());
      blockDivs.clear();
      scheduleRender();
    };
    reader.readAsText(file);
  });
}

main();
```

Save to: `examples/block-editor/web/src/main.ts`

---

- [ ] **Step 2: Commit TypeScript shell**

```
feat(block-editor): TypeScript shell — contenteditable blocks, RAF render loop
```

---

## Task 9: Dev server smoke test

---

- [ ] **Step 1: Install npm dependencies**

```bash
cd examples/block-editor/web && npm install
```

---

- [ ] **Step 2: Build MoonBit output**

```bash
cd examples/block-editor && moon build --target js --release
```

---

- [ ] **Step 3: Start dev server**

```bash
cd examples/block-editor/web && npm run dev
```

---

- [ ] **Step 4: Verify the editor loads**

Open the URL shown by Vite. Confirm:
- Heading "Welcome to Block Editor" renders with large font
- Paragraphs and list items appear below
- No console errors

---

- [ ] **Step 5: Verify typing in a block**

Click on the paragraph and type text. Confirm:
- Characters appear as you type
- State is preserved on each keypress

---

- [ ] **Step 6: Verify Enter creates a new block**

Press Enter at the end of a block. Confirm:
- A new empty block appears below
- Cursor moves to the new block

---

- [ ] **Step 7: Verify Backspace deletes an empty block**

Press Backspace in an empty block. Confirm:
- The empty block is removed
- Cursor moves to the previous block

---

- [ ] **Step 8: Verify autoformat**

In a paragraph, type `##` then Space. Confirm:
- Block converts to a Heading(2)
- Text is cleared (prefix consumed)

Type `-` then Space. Confirm:
- Block converts to a bullet list item

---

- [ ] **Step 9: Verify Download .md**

Click the "Download .md" button. Confirm:
- A `document.md` file is downloaded
- Opening it shows the expected Markdown content

---

- [ ] **Step 10: Verify Upload .md**

Click "Upload .md" and choose a local Markdown file. Confirm:
- The editor reloads with blocks from the file
- Headings and lists render correctly

---

- [ ] **Step 11: Final commit**

```
feat(block-editor): working single-peer block editor demo
```

---

## Phase 2 (deferred)

After the first slice works:

1. **Nested blocks** — list items as parents of other blocks; indented rendering; replace `order` array with `TreeDoc::create_node_after`
2. **Unified oplog** — shared version vector + causal history across tree + text ops (design doc §"Joint CRDT invariants")
3. **Raw block preservation** — unknown Markdown syntax → `Raw` block, exported verbatim
4. **Loom Markdown grammar** — replace the hand-written line parser with a proper Loom grammar for CommonMark block structure
5. **Markdown source pane** — read-only or editable `export_markdown` view alongside the block view
6. **File persistence** — `.md` + `.crdt` sidecar, file watcher, reconciliation
7. **Collaboration** — two-peer sync via WebRTC using `TreeDoc::export_ops` / `apply_remote_op`
8. **Undo/redo** — document-level UndoManager spanning tree + text ops
9. **Slash commands** — `/heading`, `/bullet`, `/code` type conversions in addition to the Space-trigger autoformat already in Phase 1
10. **Rabbita rendering** — replace DOM patching with Rabbita Elm-architecture

---

## Notes for Implementation

- **`BlockDoc::set_text`** uses delete-then-insert for arbitrary assignment. The TypeScript shell should prefer `insert_char` / `delete_char` for incremental edits (preserves CRDT history granularity).
- **`render_state_to_json`** flattens the tree to a top-level array. Phase 2 will add a `depth` field and `parent_id` when nested blocks are needed.
- **`parse_block_id`** splits on the last `:`. Agent IDs must not contain `:` — enforce this in `BlockDoc::new` or document the constraint.
- **`editor_insert_block_after`** now uses `create_block_after` which maintains the explicit `order` array. When Phase 2 adds fractional-index–based TreeDoc ordering, replace `order` with `TreeDoc::create_node_after` and drop the array.
- **Autoformat** fires on Space (not Enter) so the user can undo the conversion by pressing Backspace before leaving the block. This matches Notion's behavior.
- **Upload replaces the document.** `editor_import_markdown` replaces the registry entry with a fresh `BlockDoc`. Old `BlockId`s are no longer valid; `blockDivs` must be cleared before the next render.
- **V1 known gaps (from Codex review):** unified oplog, Raw-block preservation, numbered-list start numbers, nested block creation. All documented in the V1 simplifications section at the top of this plan.
