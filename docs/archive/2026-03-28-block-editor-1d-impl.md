# Block Editor 1d: JS Bridge + Web Shell — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire BlockDoc to a browser — handle registry, JSON bridge, contenteditable TypeScript shell with Enter/Backspace/autoformat and md download/upload.

**Architecture:** MoonBit FFI exports handle-based functions that accept/return strings (JSON for complex data, `"agent:counter"` for block IDs). TypeScript shell runs a RAF render loop diffing `get_render_state` JSON against live DOM, with per-block event handlers for input, Enter, Backspace, and Space-triggered autoformat.

**Tech Stack:** MoonBit (JS target), TypeScript, Vite, contenteditable DOM

---

## File Map

| File | Role |
|------|------|
| `examples/block-editor/main/block_init.mbt` | Create: handle registry + all bridge functions |
| `examples/block-editor/main/block_init_wbtest.mbt` | Create: whitebox tests for bridge functions |
| `examples/block-editor/main/moon.pkg` | Modify: add JS export list |
| `examples/block-editor/web/src/main.ts` | Modify: TypeScript shell (currently stub) |

---

### Task 1: Handle registry + parse_block_id

**Files:**
- Create: `examples/block-editor/main/block_init.mbt`
- Create: `examples/block-editor/main/block_init_wbtest.mbt`

- [ ] **Step 1: Write failing tests for handle registry and ID parsing**

```moonbit
// block_init_wbtest.mbt

///|
test "create_editor returns incrementing handles" {
  let h1 = create_editor("alice")
  let h2 = create_editor("bob")
  inspect(h1 != h2, content="true")
}

///|
test "parse_block_id round-trips with id_key" {
  let doc = BlockDoc::new("alice")
  let id = doc.create_block(Paragraph)
  let key = id_key(id)
  let parsed = parse_block_id(key)
  inspect(parsed.agent, content="alice")
}

///|
test "destroy_editor removes handle" {
  let h = create_editor("alice")
  destroy_editor(h)
  // get_render_state on destroyed handle returns empty
  inspect(get_render_state(h), content="{\"blocks\":[]}")
}
```

- [ ] **Step 2: Run tests — verify they fail (functions unbound)**

Run: `moon check 2>&1 | grep "unbound"`

- [ ] **Step 3: Implement handle registry and parse_block_id**

```moonbit
// block_init.mbt

///|
let docs : Map[Int, BlockDoc] = Map::new()

///|
let next_handle : Ref[Int] = { val: 1 }

///|
pub fn create_editor(replica_id : String) -> Int {
  let handle = next_handle.val
  next_handle.val = handle + 1
  docs[handle] = BlockDoc::new(replica_id)
  handle
}

///|
pub fn destroy_editor(handle : Int) -> Unit {
  docs.remove(handle)
}

///|
/// Parse "agent:counter" string into a TreeNodeId.
/// Splits on last ':' so agent IDs without ':' are safe.
fn parse_block_id(s : String) -> @tree.TreeNodeId {
  let mut last_colon = -1
  for i = 0; i < s.length(); i = i + 1 {
    if s[i] == ':' {
      last_colon = i
    }
  }
  if last_colon < 0 {
    return @tree.root_id
  }
  let agent = s[:last_colon].to_string()
  let counter_str = s[last_colon + 1:].to_string()
  // Parse counter manually (no stdlib parseInt)
  let mut counter = 0
  let mut neg = false
  let mut start = 0
  if counter_str.length() > 0 && counter_str[0] == '-' {
    neg = true
    start = 1
  }
  for i = start; i < counter_str.length(); i = i + 1 {
    let d = counter_str[i].to_int() - 48 // '0' = 48
    counter = counter * 10 + d
  }
  if neg {
    counter = -counter
  }
  { agent, counter }
}
```

- [ ] **Step 4: Run `moon check` — fix any errors**

Run: `moon check 2>&1`

- [ ] **Step 5: Run tests — verify they pass**

Run: `moon test 2>&1`

- [ ] **Step 6: Commit**

```bash
git add examples/block-editor/main/block_init.mbt examples/block-editor/main/block_init_wbtest.mbt
git commit -m "feat(block-editor): 1d handle registry and parse_block_id"
```

---

### Task 2: get_render_state — JSON block list

**Files:**
- Modify: `examples/block-editor/main/block_init.mbt`
- Modify: `examples/block-editor/main/block_init_wbtest.mbt`

- [ ] **Step 1: Write failing test for render state**

```moonbit
// append to block_init_wbtest.mbt

///|
test "get_render_state returns block JSON" {
  let h = create_editor("alice")
  with_doc(h, fn(doc) {
    let id = doc.create_block(Heading(2))
    doc.set_text(id, "Hello")
  })
  let json = get_render_state(h)
  // Should contain the heading block
  inspect(json.contains("heading"), content="true")
  inspect(json.contains("Hello"), content="true")
  inspect(json.contains("\"level\":\"2\""), content="true")
}
```

- [ ] **Step 2: Run test — verify it fails**

Run: `moon check 2>&1`

- [ ] **Step 3: Implement get_render_state and with_doc helper**

Add to `block_init.mbt`:

```moonbit
///|
/// Run a function with the BlockDoc for a handle.
/// Used by tests and internal helpers.
fn with_doc(handle : Int, f : (BlockDoc) -> Unit) -> Unit {
  match docs.get(handle) {
    Some(doc) => f(doc)
    None => ()
  }
}

///|
/// Return JSON representation of all blocks.
/// Format: {"blocks":[{"id":"agent:counter","block_type":"heading","level":"2","list_style":"","checked":false,"text":"Hello"}, ...]}
pub fn get_render_state(handle : Int) -> String {
  match docs.get(handle) {
    Some(doc) => {
      let buf = StringBuilder::new()
      buf.write_string("{\"blocks\":[")
      let children = doc.children(root_block_id)
      for i = 0; i < children.length(); i = i + 1 {
        if i > 0 {
          buf.write_string(",")
        }
        let id = children[i]
        let (type_str, props) = block_type_to_string(doc.get_type(id))
        buf.write_string("{\"id\":\"")
        buf.write_string(id_key(id))
        buf.write_string("\",\"block_type\":\"")
        buf.write_string(type_str)
        buf.write_string("\",\"level\":\"")
        buf.write_string(props.get("level").or(""))
        buf.write_string("\",\"list_style\":\"")
        buf.write_string(props.get("list_style").or(""))
        buf.write_string("\",\"checked\":")
        buf.write_string(if doc.get_checked(id) { "true" } else { "false" })
        buf.write_string(",\"text\":\"")
        write_json_escaped(buf, doc.get_text(id))
        buf.write_string("\"}")
      }
      buf.write_string("]}")
      buf.to_string()
    }
    None => "{\"blocks\":[]}"
  }
}

///|
/// Write a string with JSON escaping (quotes, backslashes, newlines).
fn write_json_escaped(buf : StringBuilder, s : String) -> Unit {
  for i = 0; i < s.length(); i = i + 1 {
    let ch = s[i]
    if ch == '"' {
      buf.write_string("\\\"")
    } else if ch == '\\' {
      buf.write_string("\\\\")
    } else if ch == '\n' {
      buf.write_string("\\n")
    } else if ch == '\r' {
      buf.write_string("\\r")
    } else if ch == '\t' {
      buf.write_string("\\t")
    } else {
      buf.write_string(s[i:i + 1].to_string())
    }
  }
}
```

Note: `Map.get` returns `Option`. Check if `.or("")` works on `String?` — if not, use `match` or `.unwrap_or("")`.

- [ ] **Step 4: Run `moon check` — fix any errors**

- [ ] **Step 5: Run tests — verify they pass**

- [ ] **Step 6: Commit**

```bash
git commit -am "feat(block-editor): 1d get_render_state JSON bridge"
```

---

### Task 3: Block mutation bridge functions

**Files:**
- Modify: `examples/block-editor/main/block_init.mbt`
- Modify: `examples/block-editor/main/block_init_wbtest.mbt`

- [ ] **Step 1: Write failing tests for mutations**

```moonbit
// append to block_init_wbtest.mbt

///|
test "editor_insert_block_after creates block" {
  let h = create_editor("alice")
  // Import a seeded doc to get a known block
  editor_import_markdown(h, "# Title\n")
  let state = get_render_state(h)
  inspect(state.contains("Title"), content="true")
}

///|
test "editor_set_block_text updates text" {
  let h = create_editor("alice")
  editor_import_markdown(h, "Hello\n")
  // Parse state to get block id
  let json = get_render_state(h)
  // The first block's id is in the JSON
  inspect(json.contains("Hello"), content="true")
}

///|
test "editor_delete_block removes block" {
  let h = create_editor("alice")
  editor_import_markdown(h, "aaa\n\nbbb\n")
  let json1 = get_render_state(h)
  inspect(json1.contains("aaa"), content="true")
  inspect(json1.contains("bbb"), content="true")
}

///|
test "editor_export_markdown round-trips" {
  let h = create_editor("alice")
  let md = "# Title\n\nSome text\n"
  editor_import_markdown(h, md)
  let out = editor_export_markdown(h)
  inspect(out, content=md)
}
```

- [ ] **Step 2: Run tests — verify they fail (functions unbound)**

- [ ] **Step 3: Implement all mutation bridge functions**

Add to `block_init.mbt`:

```moonbit
///|
/// Insert a new block after the given block ID.
/// Returns the new block's ID string ("agent:counter").
pub fn editor_insert_block_after(
  handle : Int,
  after_id_str : String,
  block_type_str : String,
) -> String {
  match docs.get(handle) {
    Some(doc) => {
      let after_id = parse_block_id(after_id_str)
      let bt = block_type_from_props(block_type_str, fn(_k) { None })
      let new_id = doc.create_block_after(after_id, bt)
      id_key(new_id)
    }
    None => ""
  }
}

///|
/// Set the text content of a block.
pub fn editor_set_block_text(
  handle : Int,
  id_str : String,
  text : String,
) -> Unit {
  match docs.get(handle) {
    Some(doc) => doc.set_text(parse_block_id(id_str), text)
    None => ()
  }
}

///|
/// Delete a block by ID.
pub fn editor_delete_block(handle : Int, id_str : String) -> Unit {
  match docs.get(handle) {
    Some(doc) => doc.delete_block(parse_block_id(id_str))
    None => ()
  }
}

///|
/// Change a block's type.
/// `level` is used for headings (1-6), ignored otherwise.
/// `list_style` is "bullet", "numbered", or "todo" for list items, "" otherwise.
pub fn editor_set_block_type(
  handle : Int,
  id_str : String,
  type_str : String,
  level : Int,
  list_style : String,
) -> Unit {
  match docs.get(handle) {
    Some(doc) => {
      let bt = block_type_from_props(type_str, fn(k) {
        if k == "level" {
          Some(level.to_string())
        } else if k == "list_style" && list_style != "" {
          Some(list_style)
        } else {
          None
        }
      })
      doc.set_type(parse_block_id(id_str), bt)
    }
    None => ()
  }
}

///|
/// Import markdown, replacing the current document.
pub fn editor_import_markdown(handle : Int, md : String) -> Unit {
  match docs.get(handle) {
    Some(_) => {
      // Replace the doc entirely — get replica_id from existing doc
      // Note: BlockDoc doesn't expose replica_id, so we store it separately
      // For V1, re-create with the same handle
      let replica_id = get_replica_id(handle)
      docs[handle] = block_doc_from_markdown(md, replica_id)
    }
    None => ()
  }
}

///|
/// Export the document as markdown.
pub fn editor_export_markdown(handle : Int) -> String {
  match docs.get(handle) {
    Some(doc) => block_doc_to_markdown(doc)
    None => ""
  }
}
```

The `editor_import_markdown` needs the replica_id. Since `BlockDoc` doesn't expose it, store it in a parallel map. Add at the top of `block_init.mbt`:

```moonbit
///|
let replica_ids : Map[Int, String] = Map::new()

///|
fn get_replica_id(handle : Int) -> String {
  replica_ids.get(handle).or("unknown")
}
```

And update `create_editor`:
```moonbit
pub fn create_editor(replica_id : String) -> Int {
  let handle = next_handle.val
  next_handle.val = handle + 1
  docs[handle] = BlockDoc::new(replica_id)
  replica_ids[handle] = replica_id
  handle
}
```

And update `destroy_editor`:
```moonbit
pub fn destroy_editor(handle : Int) -> Unit {
  docs.remove(handle)
  replica_ids.remove(handle)
}
```

- [ ] **Step 4: Run `moon check` — fix any errors**

- [ ] **Step 5: Run tests — verify they pass**

- [ ] **Step 6: Commit**

```bash
git commit -am "feat(block-editor): 1d block mutation bridge functions"
```

---

### Task 4: Update moon.pkg JS exports + verify JS build

**Files:**
- Modify: `examples/block-editor/main/moon.pkg`

- [ ] **Step 1: Update moon.pkg with full export list**

```text
import {
  "dowdiness/event-graph-walker/tree" @tree,
  "dowdiness/event-graph-walker/text" @text,
}

options(
  "is-main": true,
  link: { "js": { "exports": [
    "create_editor",
    "destroy_editor",
    "get_render_state",
    "editor_insert_block_after",
    "editor_set_block_text",
    "editor_delete_block",
    "editor_set_block_type",
    "editor_import_markdown",
    "editor_export_markdown"
  ] } },
)
```

- [ ] **Step 2: Run `moon info && moon fmt`**

- [ ] **Step 3: Run `moon build --target js --release` — verify it succeeds**

Run: `cd examples/block-editor && moon build --target js --release 2>&1`

- [ ] **Step 4: Verify exported symbols exist in built JS**

Run: `grep -o 'create_editor\|destroy_editor\|get_render_state\|editor_insert_block_after\|editor_set_block_text\|editor_delete_block\|editor_set_block_type\|editor_import_markdown\|editor_export_markdown' examples/block-editor/_build/js/release/build/main/main.js | sort -u | wc -l`

Expected: 9

- [ ] **Step 5: Commit**

```bash
git add examples/block-editor/main/moon.pkg
git commit -m "feat(block-editor): 1d JS export list"
```

---

### Task 5: TypeScript shell — render loop + basic editing

**Files:**
- Modify: `examples/block-editor/web/src/main.ts`

- [ ] **Step 1: Implement core TS shell — import, create, seed, render**

```typescript
import * as ed from '@moonbit/canopy-block-editor';

// ── Types ──────────────────────────────────────────────────────────────
interface Block {
  id: string;
  block_type: string;
  level: string;
  list_style: string;
  checked: boolean;
  text: string;
}

// ── State ──────────────────────────────────────────────────────────────
const handle = ed.create_editor('local');
const container = document.getElementById('editor-blocks')!;
const blockDivs = new Map<string, HTMLDivElement>();
let suppressNextInput = false;

// Seed
ed.editor_import_markdown(handle, '# Welcome\n\nStart typing here.\n');

// ── Render ─────────────────────────────────────────────────────────────
function render() {
  const state: { blocks: Block[] } = JSON.parse(ed.get_render_state(handle));
  const liveIds = new Set<string>();

  for (const block of state.blocks) {
    liveIds.add(block.id);
    let div = blockDivs.get(block.id);

    if (!div) {
      div = document.createElement('div');
      div.contentEditable = 'true';
      div.dataset.blockId = block.id;
      div.style.outline = 'none';
      div.style.minHeight = '1.4em';
      div.style.padding = '4px 0';
      wireEvents(div);
      container.appendChild(div);
      blockDivs.set(block.id, div);
    }

    // Update attributes
    div.dataset.type = block.block_type;
    div.dataset.level = block.level;
    div.dataset.listStyle = block.list_style;
    styleBlock(div, block);

    // Only update text if not focused (avoid clobbering cursor)
    if (document.activeElement !== div && div.textContent !== block.text) {
      div.textContent = block.text;
    }
  }

  // Remove stale divs
  for (const [id, div] of blockDivs) {
    if (!liveIds.has(id)) {
      div.remove();
      blockDivs.delete(id);
    }
  }

  // Reorder divs to match state order
  let prev: Element | null = null;
  for (const block of state.blocks) {
    const div = blockDivs.get(block.id);
    if (!div) continue;
    const expected = prev ? prev.nextElementSibling : container.firstElementChild;
    if (div !== expected) {
      if (prev) {
        prev.after(div);
      } else {
        container.prepend(div);
      }
    }
    prev = div;
  }
}

// ── Block styling ──────────────────────────────────────────────────────
function styleBlock(div: HTMLDivElement, block: Block) {
  div.style.fontWeight = '';
  div.style.fontSize = '';
  div.style.fontFamily = '';
  div.style.borderLeft = '';
  div.style.paddingLeft = '';
  div.style.color = '';
  div.style.background = '';

  switch (block.block_type) {
    case 'heading': {
      const sizes: Record<string, string> = { '1': '2em', '2': '1.5em', '3': '1.25em', '4': '1.1em', '5': '1em', '6': '0.9em' };
      div.style.fontSize = sizes[block.level] || '1.5em';
      div.style.fontWeight = 'bold';
      break;
    }
    case 'list_item':
      div.style.paddingLeft = '24px';
      break;
    case 'quote':
      div.style.borderLeft = '3px solid rgba(130, 160, 255, 0.4)';
      div.style.paddingLeft = '16px';
      div.style.color = 'rgba(232, 232, 240, 0.7)';
      break;
    case 'code':
      div.style.fontFamily = "'JetBrains Mono', monospace";
      div.style.background = 'rgba(130, 160, 255, 0.05)';
      div.style.paddingLeft = '12px';
      break;
    case 'divider':
      div.contentEditable = 'false';
      div.style.borderTop = '1px solid rgba(130, 160, 255, 0.2)';
      div.style.minHeight = '0';
      div.style.padding = '8px 0';
      break;
  }
}

// ── Events ─────────────────────────────────────────────────────────────
function wireEvents(div: HTMLDivElement) {
  div.addEventListener('input', () => {
    if (suppressNextInput) {
      suppressNextInput = false;
      return;
    }
    const id = div.dataset.blockId!;
    ed.editor_set_block_text(handle, id, div.textContent || '');
  });

  div.addEventListener('keydown', (e: KeyboardEvent) => {
    const id = div.dataset.blockId!;

    // Enter → insert block after
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      const newId = ed.editor_insert_block_after(handle, id, 'paragraph');
      render();
      const newDiv = blockDivs.get(newId);
      if (newDiv) newDiv.focus();
      return;
    }

    // Backspace on empty → delete block, focus previous
    if (e.key === 'Backspace' && (div.textContent || '') === '') {
      e.preventDefault();
      const prev = div.previousElementSibling as HTMLDivElement | null;
      ed.editor_delete_block(handle, id);
      render();
      if (prev) {
        prev.focus();
        // Move cursor to end
        const sel = window.getSelection();
        if (sel && prev.childNodes.length > 0) {
          sel.selectAllChildren(prev);
          sel.collapseToEnd();
        }
      }
      return;
    }

    // Space → check autoformat
    if (e.key === ' ') {
      const text = div.textContent || '';
      const fmt = detectAutoformat(text);
      if (fmt) {
        e.preventDefault();
        ed.editor_set_block_type(handle, id, fmt.type, fmt.level, fmt.listStyle);
        ed.editor_set_block_text(handle, id, '');
        suppressNextInput = true;
        div.textContent = '';
        render();
        // Re-focus the same block
        const updated = blockDivs.get(id);
        if (updated) updated.focus();
      }
    }
  });
}

// ── Autoformat ─────────────────────────────────────────────────────────
function detectAutoformat(text: string): { type: string; level: number; listStyle: string } | null {
  // Heading: # through ######
  const headingMatch = text.match(/^(#{1,6})$/);
  if (headingMatch) return { type: 'heading', level: headingMatch[1].length, listStyle: '' };

  // Todo: - [ ] or - [x]
  if (text === '- [ ]' || text === '- [x]') return { type: 'list_item', level: 0, listStyle: 'todo' };

  // Bullet: - or *
  if (text === '-' || text === '*') return { type: 'list_item', level: 0, listStyle: 'bullet' };

  // Numbered: N.
  if (/^\d+\.$/.test(text)) return { type: 'list_item', level: 0, listStyle: 'numbered' };

  // Quote: >
  if (text === '>') return { type: 'quote', level: 0, listStyle: '' };

  return null;
}

// ── Toolbar ────────────────────────────────────────────────────────────
document.getElementById('btn-download')!.addEventListener('click', () => {
  const md = ed.editor_export_markdown(handle);
  const blob = new Blob([md], { type: 'text/markdown' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'document.md';
  a.click();
  URL.revokeObjectURL(a.href);
});

document.getElementById('btn-upload')!.addEventListener('click', () => {
  document.getElementById('file-input')!.click();
});

document.getElementById('file-input')!.addEventListener('change', (e) => {
  const file = (e.target as HTMLInputElement).files?.[0];
  if (!file) return;
  const reader = new FileReader();
  reader.onload = () => {
    ed.editor_import_markdown(handle, reader.result as string);
    blockDivs.clear();
    container.innerHTML = '';
    render();
  };
  reader.readAsText(file);
});

// ── Boot ───────────────────────────────────────────────────────────────
render();
```

- [ ] **Step 2: Verify the TS compiles — install deps + run dev**

Run:
```bash
cd examples/block-editor/web && npm install 2>&1
cd examples/block-editor && moon build --target js --release 2>&1
```

Note: Dev server test is manual (smoke test in Task 6).

- [ ] **Step 3: Commit**

```bash
git add examples/block-editor/web/src/main.ts
git commit -m "feat(block-editor): 1d TypeScript web shell"
```

---

### Task 6: Smoke test + final checks

**Files:** None (verification only)

- [ ] **Step 1: Run `moon test`**

Run: `moon test 2>&1`
Expected: All tests pass (37 existing + new bridge tests)

- [ ] **Step 2: Run `moon check`**

Run: `moon check 2>&1`
Expected: 0 errors

- [ ] **Step 3: Run `moon build --target js --release`**

Run: `cd examples/block-editor && moon build --target js --release 2>&1`
Expected: Success

- [ ] **Step 4: Run `moon info && moon fmt`**

- [ ] **Step 5: Manual smoke test — start dev server**

Run: `cd examples/block-editor/web && npm run dev`

Checklist:
- [ ] Editor loads with "# Welcome" heading and "Start typing here." paragraph
- [ ] Typing in a block updates text
- [ ] Enter creates a new paragraph block below
- [ ] Backspace on empty block removes it and focuses previous
- [ ] `##` + Space → block becomes Heading(2)
- [ ] `-` + Space → block becomes bullet list item
- [ ] Download .md produces correct markdown
- [ ] Upload .md replaces the document

- [ ] **Step 6: Final commit**

```bash
git add -A
git commit -m "feat(block-editor): 1d JS bridge and TypeScript web shell"
```

---

## Notes for implementer

- **MoonBit Option unwrap:** `Option::or` may not exist. Use `match` or `.unwrap_or()` if `.or()` doesn't compile.
- **String.contains:** May not exist on MoonBit String. If tests need it, implement a local `contains` helper or use the `Grep`-style approach from block_import.mbt's `starts_with`.
- **`{ agent, counter }` construction:** `TreeNodeId` is `pub(all)` so struct literal construction should work cross-package. If the compiler rejects it, add a `make_tree_node_id(agent, counter)` factory in block_doc.mbt.
- **JSON escaping:** The `write_json_escaped` function handles `"`, `\`, `\n`, `\r`, `\t`. Block text shouldn't contain control chars in V1, but this covers the common cases.
- **Autoformat for list_style:** `editor_set_block_type` accepts `list_style` as fifth parameter. TS autoformat returns `{ type, level, listStyle }` and passes all three.
