# Markdown Block Editor — Implementation Plan (Sub-projects 0–1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate the textarea overlay input technique and build the Markdown CST → ProjNode projection pipeline.

**Architecture:** Sub-project 0 is a standalone HTML/TS spike. Sub-project 1 follows the JSON editor projection pattern: `syntax_to_proj_node` + `populate_token_spans` + `build_markdown_projection_memos`.

**Tech Stack:** MoonBit (lang/markdown/proj/), TypeScript (spike), loom Markdown parser (`dowdiness/markdown`), canopy core (`dowdiness/canopy/core`), incr (`dowdiness/incr`), seam (`dowdiness/seam`)

**Design doc:** `docs/plans/2026-04-04-markdown-block-editor-design.md`

---

## File Structure

### Sub-project 0: Textarea overlay spike

| File | Action | Responsibility |
|------|--------|---------------|
| `examples/web/spike-block-input.html` | Create | Standalone HTML page for spike |

### Sub-project 1: Markdown projection

| File | Action | Responsibility |
|------|--------|---------------|
| `moon.mod.json` | Modify | Add `dowdiness/markdown` module dependency |
| `lang/markdown/proj/moon.pkg` | Create | Package definition with imports |
| `lang/markdown/proj/proj_node.mbt` | Create | `syntax_to_proj_node` — CST → ProjNode[@markdown.Block] |
| `lang/markdown/proj/populate_token_spans.mbt` | Create | Token span extraction for SourceMap |
| `lang/markdown/proj/markdown_memo.mbt` | Create | Reactive memo wrapper (3 memos) |
| `lang/markdown/proj/proj_node_wbtest.mbt` | Create | Whitebox projection tests |

**Type model:** Uses `@markdown.Block` directly as `T` in `ProjNode[T]` — same pattern as JSON using `@json.JsonValue`. No custom Block enum. `TreeNode` and `Renderable` impls already exist in `loom/examples/markdown/src/proj_traits.mbt`.

---

## Sub-project 0: Textarea Overlay Spike

### Task 1: Phase A — static textarea positioning

**Files:**
- Create: `examples/web/spike-block-input.html`

- [ ] **Step 1: Create the spike HTML file**

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>BlockInput Spike</title>
<style>
  body { font-family: 'Inter', system-ui, sans-serif; max-width: 600px; margin: 40px auto; }
  .block { position: relative; padding: 4px 8px; border-radius: 4px; cursor: text; min-height: 1.5em; }
  .block:hover { background: #f5f5f5; }
  .block.active { outline: 2px solid #8250df; }
  .block[data-kind="heading"] { font-size: 1.5em; font-weight: 700; }
  .block[data-kind="list_item"]::before { content: "• "; color: #666; }
  .block-text { white-space: pre-wrap; }
  .block-textarea {
    position: absolute; top: 0; left: 0; width: 100%; height: 100%;
    padding: inherit; margin: 0; border: none; outline: none; resize: none;
    font: inherit; color: inherit; background: transparent;
    overflow: hidden; box-sizing: border-box; z-index: 1;
  }
  .toolbar { margin-bottom: 16px; display: flex; gap: 8px; }
  .toolbar button { padding: 4px 12px; cursor: pointer; }
</style>
</head>
<body>

<div class="toolbar">
  <button id="btn-heading">Heading</button>
  <button id="btn-paragraph">Paragraph</button>
  <button id="btn-list">List Item</button>
</div>

<div id="editor"></div>

<script>
const blocks = [
  { id: "1", kind: "heading", text: "Hello World" },
  { id: "2", kind: "paragraph", text: "This is a paragraph with some text." },
  { id: "3", kind: "list_item", text: "First item" },
  { id: "4", kind: "list_item", text: "Second item" },
  { id: "5", kind: "paragraph", text: "Another paragraph." },
];

const editor = document.getElementById("editor");
let activeBlockId = null;
let textarea = null;
let blurBound = false;

function render() {
  editor.innerHTML = "";
  for (const block of blocks) {
    const div = document.createElement("div");
    div.className = "block" + (block.id === activeBlockId ? " active" : "");
    div.dataset.kind = block.kind;
    div.dataset.id = block.id;

    const textSpan = document.createElement("span");
    textSpan.className = "block-text";
    textSpan.textContent = block.text;
    div.appendChild(textSpan);

    div.addEventListener("click", (e) => {
      e.stopPropagation();
      activateBlock(block.id);
    });
    editor.appendChild(div);
  }
  if (activeBlockId) positionTextarea();
}

function activateBlock(blockId) {
  activeBlockId = blockId;
  blurBound = false;
  render();

  if (!textarea) {
    textarea = document.createElement("textarea");
    textarea.className = "block-textarea";
    textarea.addEventListener("pointerdown", (e) => e.stopPropagation());
    textarea.addEventListener("input", onInput);
    textarea.addEventListener("keydown", onKeydown);
  }
  positionTextarea();
}

function positionTextarea() {
  const block = blocks.find(b => b.id === activeBlockId);
  const div = editor.querySelector(`[data-id="${activeBlockId}"]`);
  if (!block || !div) return;

  div.appendChild(textarea);
  textarea.value = block.text;

  // Match font from the block div
  const style = getComputedStyle(div);
  textarea.style.font = style.font;
  textarea.style.padding = style.padding;
  textarea.style.lineHeight = style.lineHeight;
  // 1.05x height buffer (Excalidraw technique)
  textarea.style.height = (div.offsetHeight * 1.05) + "px";

  textarea.focus();

  // Deferred blur (Excalidraw pattern)
  if (!blurBound) {
    document.addEventListener("pointerup", (e) => {
      // Don't bind blur if click was on toolbar
      if (e.target.closest(".toolbar")) return;
      textarea.onblur = deactivate;
      blurBound = true;
    }, { once: true });
  }
}

function onInput() {
  const block = blocks.find(b => b.id === activeBlockId);
  if (!block) return;
  block.text = textarea.value;
  // Re-render the text behind the textarea
  const div = editor.querySelector(`[data-id="${activeBlockId}"]`);
  if (div) {
    const textSpan = div.querySelector(".block-text");
    if (textSpan) textSpan.textContent = block.text;
  }
}

function onKeydown(e) {
  if (e.isComposing || e.keyCode === 229) return;
  // Block navigation stubs
  if (e.key === "Enter" && !e.shiftKey) {
    e.preventDefault();
    console.log("Enter → InsertBlockAfter / SplitBlock");
  }
}

function deactivate() {
  activeBlockId = null;
  if (textarea && textarea.parentNode) textarea.parentNode.removeChild(textarea);
  render();
}

// Toolbar: test deferred blur
document.getElementById("btn-heading").addEventListener("click", () => {
  const block = blocks.find(b => b.id === activeBlockId);
  if (block) { block.kind = "heading"; render(); textarea?.focus(); }
});
document.getElementById("btn-paragraph").addEventListener("click", () => {
  const block = blocks.find(b => b.id === activeBlockId);
  if (block) { block.kind = "paragraph"; render(); textarea?.focus(); }
});
document.getElementById("btn-list").addEventListener("click", () => {
  const block = blocks.find(b => b.id === activeBlockId);
  if (block) { block.kind = "list_item"; render(); textarea?.focus(); }
});

document.addEventListener("click", (e) => {
  if (!e.target.closest("#editor") && !e.target.closest(".toolbar")) deactivate();
});

render();
</script>
</body>
</html>
```

- [ ] **Step 2: Test Phase A**

```bash
cd examples/web && npx vite --open spike-block-input.html
```

Test manually:
1. Click a block → textarea overlay appears, text editable
2. Type text → block text updates behind textarea
3. Click toolbar button → block type changes, textarea stays focused (deferred blur works)
4. Click outside → textarea removed
5. Test with Japanese IME (if available): composition underline visible, candidate window at correct position

- [ ] **Step 3: Phase B — add re-render loop**

Add the following to the `<script>` section of `spike-block-input.html`, replacing the `onInput` function:

```javascript
function onInput() {
  if (textarea.composing) return; // Skip during IME composition

  const block = blocks.find(b => b.id === activeBlockId);
  if (!block) return;

  // Save caret
  const selStart = textarea.selectionStart;
  const selEnd = textarea.selectionEnd;

  // Update backing data
  block.text = textarea.value;

  // Simulate re-render: replace the text span (DOM mutation under textarea)
  const div = editor.querySelector(`[data-id="${activeBlockId}"]`);
  if (div) {
    const textSpan = div.querySelector(".block-text");
    if (textSpan) textSpan.textContent = block.text;
    // Re-match textarea height
    textarea.style.height = (div.offsetHeight * 1.05) + "px";
  }

  // Restore caret
  textarea.selectionStart = selStart;
  textarea.selectionEnd = selEnd;
}

// IME composition guard
textarea.addEventListener("compositionstart", () => { textarea.composing = true; });
textarea.addEventListener("compositionend", () => {
  textarea.composing = false;
  onInput(); // Process the composed text
});
```

Wait — the `textarea` variable may not exist yet when adding listeners. Move the composition listeners into `activateBlock`:

Replace the full `activateBlock` function:

```javascript
function activateBlock(blockId) {
  activeBlockId = blockId;
  blurBound = false;
  render();

  if (!textarea) {
    textarea = document.createElement("textarea");
    textarea.className = "block-textarea";
    textarea.composing = false;
    textarea.addEventListener("pointerdown", (e) => e.stopPropagation());
    textarea.addEventListener("input", onInput);
    textarea.addEventListener("keydown", onKeydown);
    textarea.addEventListener("compositionstart", () => { textarea.composing = true; });
    textarea.addEventListener("compositionend", () => {
      textarea.composing = false;
      onInput();
    });
  }
  positionTextarea();
}
```

- [ ] **Step 4: Test Phase B**

Test manually:
1. Type rapidly → text updates smoothly, no caret jumping
2. Type with Japanese IME → composition underline persists during input, candidate window stays positioned, final text committed correctly on compositionend
3. Measure latency: open DevTools Performance tab, type 10 characters, verify each input cycle < 5ms (no parser in the loop yet — just DOM mutation + caret restore)

- [ ] **Step 5: Record result**

If both phases pass: proceed to Sub-project 1. The textarea overlay technique is validated.

If Phase B fails (IME breaks on re-render, caret lost): document what failed and consider alternatives (contenteditable per-block, debounced re-render).

---

## Sub-project 1: Markdown Projection

### Task 2: Add markdown dependency and create package

**Files:**
- Modify: `moon.mod.json`
- Create: `lang/markdown/proj/moon.pkg`

- [ ] **Step 1: Add `dowdiness/markdown` to moon.mod.json**

Add to the `deps` object in `moon.mod.json`:

```json
    "dowdiness/markdown": {
      "path": "./loom/examples/markdown"
    }
```

- [ ] **Step 2: Create package directory and moon.pkg**

```bash
mkdir -p lang/markdown/proj
```

Write `lang/markdown/proj/moon.pkg`:

```json
import {
  "dowdiness/canopy/core" @core,
  "dowdiness/incr" @incr,
  "dowdiness/markdown" @markdown,
  "dowdiness/loom" @loom,
  "dowdiness/loom/core" @loomcore,
  "dowdiness/seam" @seam,
}
```

- [ ] **Step 3: Run moon check**

```bash
moon update && moon check
```

Expected: passes (new package with imports resolved).

- [ ] **Step 4: Commit**

```bash
git add moon.mod.json lang/markdown/
git commit -m "feat(markdown): add lang/markdown/proj package, add dowdiness/markdown dep"
```

---

### Task 3: Implement `syntax_to_proj_node`

**Files:**
- Create: `lang/markdown/proj/proj_node.mbt`

- [ ] **Step 1: Write syntax_to_proj_node and parse_to_proj_node**

Write `lang/markdown/proj/proj_node.mbt`:

```moonbit
///| CST → ProjNode[@markdown.Block] projection for Markdown.

///|
/// Convenience: parse source and project in one call (for tests and REPL).
pub fn parse_to_proj_node(
  text : String,
) -> (@core.ProjNode[@markdown.Block], Array[String]) {
  let (cst, diagnostics) = @markdown.parse_cst(text) catch {
    _ => abort("parse failed")
  }
  let syntax_node = @seam.SyntaxNode::from_cst(cst)
  let errors = diagnostics.map(fn(d) { d.message })
  let root = syntax_to_proj_node(syntax_node, Ref::new(0))
  (root, errors)
}

///|
pub fn syntax_to_proj_node(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> @core.ProjNode[@markdown.Block] {
  match @markdown.SyntaxKind::from_raw(node.kind()) {
    DocumentNode => build_document(node, counter)
    HeadingNode => build_heading(node, counter)
    ParagraphNode => build_leaf(node, counter, @markdown.Block::Paragraph([]))
    UnorderedListNode => build_list(node, counter)
    ListItemNode => build_leaf(node, counter, @markdown.Block::ListItem([]))
    CodeBlockNode => build_code_block(node, counter)
    ErrorNode => {
      let err_text = match node.first_token() {
        Some(tok) => tok.text()
        None => ""
      }
      @core.ProjNode::new(
        @markdown.Block::Error(err_text),
        node.start(),
        node.end(),
        @core.next_proj_node_id(counter),
        [],
      )
    }
    _ =>
      @core.ProjNode::new(
        @markdown.Block::Paragraph([]),
        node.start(),
        node.end(),
        @core.next_proj_node_id(counter),
        [],
      )
  }
}

///|
fn build_document(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> @core.ProjNode[@markdown.Block] {
  let children : Array[@core.ProjNode[@markdown.Block]] = []
  for child in node.children() {
    if child.kind() |> @markdown.SyntaxKind::from_raw |> is_block_node {
      children.push(syntax_to_proj_node(child, counter))
    }
  }
  @core.ProjNode::new(
    @markdown.Block::Document([]),
    node.start(),
    node.end(),
    @core.next_proj_node_id(counter),
    children,
  )
}

///|
fn build_heading(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> @core.ProjNode[@markdown.Block] {
  let level = match node.find_token(@markdown.SyntaxKind::HeadingMarkerToken.to_raw()) {
    Some(tok) => {
      let mut n = 0
      for c in tok.text() {
        if c == '#' { n = n + 1 }
      }
      if n > 0 { n } else { 1 }
    }
    None => 1
  }
  @core.ProjNode::new(
    @markdown.Block::Heading(level, []),
    node.start(),
    node.end(),
    @core.next_proj_node_id(counter),
    [],
  )
}

///|
fn build_leaf(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
  kind : @markdown.Block,
) -> @core.ProjNode[@markdown.Block] {
  @core.ProjNode::new(
    kind,
    node.start(),
    node.end(),
    @core.next_proj_node_id(counter),
    [],
  )
}

///|
fn build_list(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> @core.ProjNode[@markdown.Block] {
  let children : Array[@core.ProjNode[@markdown.Block]] = []
  for child in node.children() {
    if @markdown.SyntaxKind::from_raw(child.kind()) == ListItemNode {
      children.push(syntax_to_proj_node(child, counter))
    }
  }
  @core.ProjNode::new(
    @markdown.Block::UnorderedList([]),
    node.start(),
    node.end(),
    @core.next_proj_node_id(counter),
    children,
  )
}

///|
fn build_code_block(
  node : @seam.SyntaxNode,
  counter : Ref[Int],
) -> @core.ProjNode[@markdown.Block] {
  let info = match node.find_token(@markdown.SyntaxKind::CodeFenceOpenToken.to_raw()) {
    Some(tok) =>
      match tok.text().view() {
        [.."```", ..rest] => rest.to_string().trim_end("\n").trim_end(" ")
        _ => ""
      }
    None => ""
  }
  @core.ProjNode::new(
    @markdown.Block::CodeBlock(info, ""),
    node.start(),
    node.end(),
    @core.next_proj_node_id(counter),
    [],
  )
}

///|
fn is_block_node(kind : @markdown.SyntaxKind) -> Bool {
  match kind {
    HeadingNode | ParagraphNode | UnorderedListNode | ListItemNode | CodeBlockNode |
    ErrorNode => true
    _ => false
  }
}
```

**Note:** `@markdown.Block` constructors require all fields: `Document(Array[Block])`, `Heading(Int, Array[Inline])`, `Paragraph(Array[Inline])`, etc. The projection passes empty arrays `[]` for the inline/block children since the ProjNode's own `children` field tracks the tree structure. The `@markdown.Block` value is just a tag carrying the semantic type — the actual children are in `ProjNode.children`.

- [ ] **Step 2: Run moon check**

```bash
moon check
```

Expected: passes. Fix any compilation errors.

- [ ] **Step 3: Commit**

```bash
git add lang/markdown/proj/proj_node.mbt
git commit -m "feat(markdown/proj): implement syntax_to_proj_node for Markdown CST"
```

---

### Task 4: Write projection tests

**Files:**
- Create: `lang/markdown/proj/proj_node_wbtest.mbt`

Whitebox tests (same pattern as `lang/json/proj/proj_node_wbtest.mbt`) — can access `parse_to_proj_node` directly.

- [ ] **Step 1: Write projection tests**

Write `lang/markdown/proj/proj_node_wbtest.mbt`:

```moonbit
///| Whitebox tests for Markdown projection.

///|
test "projection: empty document" {
  let (proj, errors) = parse_to_proj_node("")
  inspect(errors.length(), content="0")
  inspect(proj.children.length(), content="0")
}

///|
test "projection: single paragraph" {
  let (proj, _) = parse_to_proj_node("Hello world")
  inspect(proj.children.length(), content="1")
}

///|
test "projection: heading levels" {
  let (proj, _) = parse_to_proj_node("# H1\n\n## H2\n\n### H3")
  inspect(proj.children.length(), content="3")
}

///|
test "projection: unordered list" {
  let (proj, _) = parse_to_proj_node("- first\n- second\n- third")
  inspect(proj.children.length(), content="1")
  let list = proj.children[0]
  inspect(list.children.length(), content="3")
}

///|
test "projection: code block" {
  let (proj, _) = parse_to_proj_node("```js\nconsole.log(42)\n```")
  inspect(proj.children.length(), content="1")
}

///|
test "projection: mixed blocks" {
  let source = "# Title\n\nSome text.\n\n- item one\n- item two\n\nMore text."
  let (proj, _) = parse_to_proj_node(source)
  inspect(proj.children.length(), content="4")
}

///|
test "projection: node positions span source text" {
  let source = "# Hello\n\nWorld"
  let (proj, _) = parse_to_proj_node(source)
  inspect(proj.start, content="0")
  inspect(proj.children[0].start, content="0")
}

///|
test "projection: IDs are unique" {
  let (proj, _) = parse_to_proj_node("# H1\n\n- a\n- b")
  let ids : Array[Int] = []
  fn collect(node : @core.ProjNode[@markdown.Block]) {
    ids.push(node.node_id)
    for child in node.children {
      collect(child)
    }
  }
  collect(proj)
  let unique : Map[Int, Bool] = {}
  let mut all_unique = true
  for id in ids {
    if unique.get(id) == Some(true) {
      all_unique = false
    }
    unique[id] = true
  }
  inspect(all_unique, content="true")
}
```

**Note:** Tests use `inspect` without hardcoded `content=` for Show-derived `@markdown.Block` values. Run with `moon test --update` first to capture actual snapshot values, then verify they're correct.

- [ ] **Step 2: Run tests**

```bash
moon test --update -p dowdiness/canopy/lang/markdown/proj
```

Review the snapshot values, then:

```bash
moon test -p dowdiness/canopy/lang/markdown/proj
```

Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add lang/markdown/proj/
git commit -m "test(markdown/proj): add projection tests for Markdown CST → ProjNode"
```

---

### Task 5: Implement `populate_token_spans`

**Files:**
- Create: `lang/markdown/proj/populate_token_spans.mbt`

- [ ] **Step 1: Write populate_token_spans**

Write `lang/markdown/proj/populate_token_spans.mbt`:

```moonbit
///| Extract token spans from the Markdown CST into the SourceMap.
///
/// Uses `all_children()` (returns SyntaxElement = nodes + tokens)
/// because `children()` returns only child nodes, not tokens.

///|
pub fn populate_token_spans(
  source_map : @core.SourceMap,
  syntax_root : @seam.SyntaxNode,
  proj_root : @core.ProjNode[@markdown.Block],
) -> Unit {
  populate_block(source_map, syntax_root, proj_root)
}

///|
fn populate_block(
  source_map : @core.SourceMap,
  syntax_node : @seam.SyntaxNode,
  proj_node : @core.ProjNode[@markdown.Block],
) -> Unit {
  match proj_node.kind {
    Document(_) => {
      let syntax_children = collect_block_children(syntax_node)
      let len = proj_node.children.length().minimum(syntax_children.length())
      for i in 0..<len {
        populate_block(source_map, syntax_children[i], proj_node.children[i])
      }
    }
    Heading(_, _) => {
      // marker span (e.g., "## ") and text span
      match syntax_node.find_token(@markdown.SyntaxKind::HeadingMarkerToken.to_raw()) {
        Some(tok) =>
          source_map.set_token_span(
            proj_node.id(),
            "marker",
            @loomcore.Range::new(tok.start(), tok.end()),
          )
        None => ()
      }
      match syntax_node.find_token(@markdown.SyntaxKind::TextToken.to_raw()) {
        Some(tok) =>
          source_map.set_token_span(
            proj_node.id(),
            "text",
            @loomcore.Range::new(tok.start(), tok.end()),
          )
        None => ()
      }
    }
    Paragraph(_) | ListItem(_) => {
      // Single "text" span covering all inline content
      // Use find_token for the first TextToken
      match syntax_node.find_token(@markdown.SyntaxKind::TextToken.to_raw()) {
        Some(tok) =>
          source_map.set_token_span(
            proj_node.id(),
            "text",
            @loomcore.Range::new(tok.start(), tok.end()),
          )
        None => ()
      }
    }
    UnorderedList(_) => {
      let syntax_children = collect_syntax_children(syntax_node, @markdown.SyntaxKind::ListItemNode)
      let len = proj_node.children.length().minimum(syntax_children.length())
      for i in 0..<len {
        populate_block(source_map, syntax_children[i], proj_node.children[i])
      }
    }
    CodeBlock(_, _) => {
      match syntax_node.find_token(@markdown.SyntaxKind::CodeFenceOpenToken.to_raw()) {
        Some(tok) =>
          source_map.set_token_span(
            proj_node.id(),
            "fence_open",
            @loomcore.Range::new(tok.start(), tok.end()),
          )
        None => ()
      }
      match syntax_node.find_token(@markdown.SyntaxKind::CodeTextToken.to_raw()) {
        Some(tok) =>
          source_map.set_token_span(
            proj_node.id(),
            "code",
            @loomcore.Range::new(tok.start(), tok.end()),
          )
        None => ()
      }
      match syntax_node.find_token(@markdown.SyntaxKind::CodeFenceCloseToken.to_raw()) {
        Some(tok) =>
          source_map.set_token_span(
            proj_node.id(),
            "fence_close",
            @loomcore.Range::new(tok.start(), tok.end()),
          )
        None => ()
      }
    }
    Error(_) => ()
  }
}

///|
fn collect_block_children(node : @seam.SyntaxNode) -> Array[@seam.SyntaxNode] {
  let result : Array[@seam.SyntaxNode] = []
  for child in node.children() {
    if child.kind() |> @markdown.SyntaxKind::from_raw |> is_block_node {
      result.push(child)
    }
  }
  result
}

///|
fn collect_syntax_children(
  node : @seam.SyntaxNode,
  kind : @markdown.SyntaxKind,
) -> Array[@seam.SyntaxNode] {
  let result : Array[@seam.SyntaxNode] = []
  for child in node.children() {
    if @markdown.SyntaxKind::from_raw(child.kind()) == kind {
      result.push(child)
    }
  }
  result
}
```

**Note:** Uses `find_token(raw_kind)` instead of iterating `children()` (which only returns nodes). `find_token` searches for the first token of the given kind within the node's subtree. For heading marker, text, code fence tokens, this is sufficient since each block has at most one of each.

- [ ] **Step 2: Run moon check**

```bash
moon check
```

Expected: passes. Fix any compilation errors (verify `@loomcore.Range::new`, `@core.SourceMap::set_token_span`, `SyntaxNode::children` iterator signatures).

- [ ] **Step 3: Commit**

```bash
git add lang/markdown/proj/populate_token_spans.mbt
git commit -m "feat(markdown/proj): implement populate_token_spans for SourceMap"
```

---

### Task 6: Implement `build_markdown_projection_memos`

**Files:**
- Create: `lang/markdown/proj/markdown_memo.mbt`

- [ ] **Step 1: Write the memo builder**

Write `lang/markdown/proj/markdown_memo.mbt`:

```moonbit
///| Reactive memo wrapper for Markdown projection.

///|
pub fn build_markdown_projection_memos(
  rt : @incr.Runtime,
  _source_text : @incr.Signal[String],
  syntax_tree : @incr.Signal[@seam.SyntaxNode?],
  _parser : @loom.ImperativeParser[@markdown.Block],
) -> (
  @incr.Memo[@core.ProjNode[@markdown.Block]?],
  @incr.Memo[Map[@core.NodeId, @core.ProjNode[@markdown.Block]]],
  @incr.Memo[@core.SourceMap],
) {
  let counter : Ref[Int] = Ref::new(0)
  let prev_proj_ref : Ref[@core.ProjNode[@markdown.Block]?] = Ref::new(None)
  let proj_memo = @incr.Memo::new_no_backdate(
    rt,
    fn() {
      match syntax_tree.get() {
        None => None
        Some(syntax_root) => {
          let new_proj = syntax_to_proj_node(syntax_root, counter)
          let result = match prev_proj_ref.val {
            Some(old) => @core.reconcile(old, new_proj, counter)
            None => new_proj
          }
          prev_proj_ref.val = Some(result)
          Some(result)
        }
      }
    },
    label="markdown_proj",
  )
  let registry_memo = @incr.Memo::new_no_backdate(
    rt,
    fn() {
      let reg : Map[@core.NodeId, @core.ProjNode[@markdown.Block]] = {}
      match proj_memo.get() {
        Some(root) => @core.collect_registry(root, reg)
        None => ()
      }
      reg
    },
    label="markdown_registry",
  )
  let source_map_memo = @incr.Memo::new_no_backdate(
    rt,
    fn() {
      match (proj_memo.get(), syntax_tree.get()) {
        (Some(proj_root), Some(syntax_root)) => {
          let sm = @core.SourceMap::from_ast(proj_root)
          populate_token_spans(sm, syntax_root, proj_root)
          sm
        }
        _ => @core.SourceMap::new()
      }
    },
    label="markdown_source_map",
  )
  (proj_memo, registry_memo, source_map_memo)
}
```

- [ ] **Step 2: Run moon check**

```bash
moon check
```

Expected: passes. If `@core.reconcile`, `@core.collect_registry`, or `@core.SourceMap::from_ast`/`::new` signatures differ, fix to match actual API.

- [ ] **Step 3: Run all tests**

```bash
moon test -p dowdiness/canopy/lang/markdown/proj
```

Expected: all projection tests still pass.

- [ ] **Step 4: moon info && moon fmt**

```bash
moon info && moon fmt
```

- [ ] **Step 5: Commit**

```bash
git add lang/markdown/proj/
git commit -m "feat(markdown/proj): implement build_markdown_projection_memos (3 reactive memos)"
```

---

### Task 7: Verify full pipeline round-trip

- [ ] **Step 1: Add a round-trip test**

Add to `lang/markdown/proj/proj_node_test.mbt`:

```moonbit
///|
test "projection: incremental reparse preserves IDs" {
  let source = "# Hello\n\nWorld"
  let parser = @loom.new_imperative_parser(source, @markdown.markdown_grammar)
  let counter : Ref[Int] = Ref::new(0)

  // First projection
  let syntax1 = parser.get_syntax_tree().unwrap()
  let proj1 = syntax_to_proj_node(syntax1, counter)
  let heading_id = proj1.children[0].node_id
  let para_id = proj1.children[1].node_id

  // Incremental edit: change "World" to "World!"
  // Edit::new(start, old_len, new_len) — "World" (5 chars) → "World!" (6 chars)
  let edit = @loomcore.Edit::new(9, 5, 6)
  let _ = parser.edit(edit, "# Hello\n\nWorld!")

  // Second projection with reconciliation
  let syntax2 = parser.get_syntax_tree().unwrap()
  let proj2_raw = syntax_to_proj_node(syntax2, counter)
  let proj2 = @core.reconcile(proj1, proj2_raw, counter)

  // IDs should be preserved for unchanged structure
  inspect(proj2.children[0].node_id == heading_id, content="true")
  // Paragraph content changed, but structure is same — ID preserved
  inspect(proj2.children[1].node_id == para_id, content="true")
}
```

- [ ] **Step 2: Run tests**

```bash
moon test -p dowdiness/canopy/lang/markdown/proj
```

Expected: all pass, including the round-trip test.

- [ ] **Step 3: Run full canopy test suite**

```bash
moon test
```

Expected: all 721+ tests pass (no regression).

- [ ] **Step 4: Commit**

```bash
git add lang/markdown/proj/
git commit -m "test(markdown/proj): add incremental reparse round-trip test"
```

---

## Acceptance Criteria

- [ ] Textarea overlay spike (Phase A + B) validates the input technique
- [ ] `dowdiness/markdown` added to `moon.mod.json` deps
- [ ] `lang/markdown/proj/proj_node.mbt` — CST → ProjNode[@markdown.Block] for all block types
- [ ] `lang/markdown/proj/proj_node.mbt` — `parse_to_proj_node` convenience function
- [ ] `lang/markdown/proj/populate_token_spans.mbt` — token spans via `find_token()` for heading, paragraph, list, code
- [ ] `lang/markdown/proj/markdown_memo.mbt` — 3 reactive memos (proj, registry, source_map)
- [ ] Incremental reparse preserves node IDs via reconciliation
- [ ] All existing tests pass (no regression)
- [ ] `moon check` passes

## Validation

```bash
moon check && moon test                                    # canopy
moon test -p dowdiness/canopy/lang/markdown/proj          # projection tests
cd examples/web && npx vite spike-block-input.html        # spike
```

## What's Next

After Sub-projects 0–1, write implementation plans for:
- **Sub-project 2:** Edit ops + FFI (`lang/markdown/edits/`, `ffi/crdt_markdown.mbt`)
- **Sub-project 3:** BlockInput + MarkdownPreview (`lib/editor-adapter/`)
- **Sub-project 4:** Web editor (`examples/web/markdown.html`)
