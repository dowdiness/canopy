# Markdown Edit Ops + FFI — Implementation Plan (Sub-project 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement 7 Markdown edit ops, the SyncEditor constructor, the protocol bridge, and FFI exports so the Markdown editor is fully wired from MoonBit through to JS.

**Architecture:** Follows the JSON editor pattern exactly: `MarkdownEditOp` enum → `compute_markdown_edit` dispatcher → `apply_markdown_edit` bridge → `new_markdown_editor` SyncEditor constructor → FFI exports. Each edit op computes `SpanEdit`s against the Markdown source text; the parser re-parses incrementally after.

**Tech Stack:** MoonBit (`lang/markdown/edits/`, `ffi/`), loom Markdown parser (`dowdiness/markdown`), canopy core (`SpanEdit`, `FocusHint`, `SourceMap`, `ProjNode`), canopy editor (`SyncEditor::new_generic`)

**Design doc:** `docs/plans/2026-04-04-markdown-block-editor-design.md`

**Prerequisite:** Sub-project 1 (projection pipeline) must be merged. ✅ Done (PR #115).

---

## File Structure

| File | Action | Responsibility |
|------|--------|---------------|
| `lang/markdown/edits/moon.pkg` | Create | Package definition with imports |
| `lang/markdown/edits/markdown_edit_op.mbt` | Create | `MarkdownEditOp` enum (7 ops) |
| `lang/markdown/edits/compute_markdown_edit.mbt` | Create | Dispatch + edit handlers |
| `lang/markdown/edits/markdown_edit_bridge.mbt` | Create | `apply_markdown_edit` — bridge from op to SyncEditor |
| `lang/markdown/edits/sync_editor_markdown.mbt` | Create | `new_markdown_editor` constructor |
| `lang/markdown/edits/compute_markdown_edit_wbtest.mbt` | Create | Whitebox tests for edit handlers |
| `ffi/crdt_markdown.mbt` | Create | FFI exports for JS |

---

### Task 1: Create package and MarkdownEditOp enum

**Files:**
- Create: `lang/markdown/edits/moon.pkg`
- Create: `lang/markdown/edits/markdown_edit_op.mbt`

- [ ] **Step 1: Create moon.pkg**

```bash
mkdir -p lang/markdown/edits
```

Write `lang/markdown/edits/moon.pkg`:

```json
import {
  "dowdiness/canopy/editor" @editor,
  "dowdiness/canopy/core" @core,
  "dowdiness/canopy/lang/markdown/proj" @md_proj,
  "dowdiness/markdown" @markdown,
  "dowdiness/loom" @loom,
  "dowdiness/loom/core" @loomcore,
}
```

- [ ] **Step 2: Write MarkdownEditOp enum**

Write `lang/markdown/edits/markdown_edit_op.mbt`:

```moonbit
///| Edit operations for the Markdown block editor.

///|
using @core {type NodeId, type ProjNode, type SourceMap, type SpanEdit, type FocusHint}

///|
pub(all) enum MarkdownEditOp {
  CommitEdit(node_id~ : NodeId, new_text~ : String)
  ChangeHeadingLevel(node_id~ : NodeId, level~ : Int)
  ToggleListItem(node_id~ : NodeId)
  Delete(node_id~ : NodeId)
  InsertBlockAfter(node_id~ : NodeId)
  SplitBlock(node_id~ : NodeId, offset~ : Int)
  MergeWithPrevious(node_id~ : NodeId)
} derive(Show, Eq)
```

- [ ] **Step 3: Run moon check**

```bash
moon check
```

- [ ] **Step 4: Commit**

```bash
git add lang/markdown/edits/
git commit -m "feat(markdown/edits): add package with MarkdownEditOp enum (7 ops)"
```

---

### Task 2: Implement compute_markdown_edit dispatcher and CommitEdit

**Files:**
- Create: `lang/markdown/edits/compute_markdown_edit.mbt`

- [ ] **Step 1: Write dispatcher + CommitEdit handler**

Write `lang/markdown/edits/compute_markdown_edit.mbt`:

```moonbit
///| Compute SpanEdits for Markdown edit operations.

///|
using @core {type NodeId, type ProjNode, type SourceMap, type SpanEdit, type FocusHint}

///|
pub fn compute_markdown_edit(
  op : MarkdownEditOp,
  source : String,
  proj : ProjNode[@markdown.Block],
  source_map : SourceMap,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  match op {
    CommitEdit(node_id~, new_text~) =>
      compute_commit_edit(source_map, node_id, new_text)
    ChangeHeadingLevel(node_id~, level~) =>
      compute_change_heading_level(source, source_map, node_id, level)
    ToggleListItem(node_id~) =>
      compute_toggle_list_item(source, proj, source_map, node_id)
    Delete(node_id~) => compute_delete(source_map, node_id)
    InsertBlockAfter(node_id~) =>
      compute_insert_block_after(source_map, node_id)
    SplitBlock(node_id~, offset~) =>
      compute_split_block(source, proj, source_map, node_id, offset)
    MergeWithPrevious(node_id~) =>
      compute_merge_with_previous(source, proj, source_map, node_id)
  }
}

///|
/// Replace the editable "text" span of a block with new content.
fn compute_commit_edit(
  source_map : SourceMap,
  node_id : NodeId,
  new_text : String,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  match source_map.get_token_span(node_id, "text") {
    Some(range) =>
      Ok(
        Some(
          (
            [
              SpanEdit::{
                start: range.start,
                delete_len: range.end - range.start,
                inserted: new_text,
              },
            ],
            FocusHint::MoveCursor(position=range.start + new_text.length()),
          ),
        ),
      )
    None => Err("no text span for node " + node_id.to_string())
  }
}

///|
/// Change heading level (1-6) or convert paragraph↔heading.
fn compute_change_heading_level(
  source : String,
  source_map : SourceMap,
  node_id : NodeId,
  level : Int,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not found in source map")
  }
  let block_text = source.substring(start=range.start, end=range.end)
  // Find where content starts (after any existing prefix)
  let content_start = match source_map.get_token_span(node_id, "text") {
    Some(text_range) => text_range.start - range.start // relative to block start
    None => {
      // No text span — might be converting from a paragraph with no marker
      // Content is the whole block (skip trailing newline)
      let mut end = block_text.length()
      if end > 0 && block_text[end - 1] == '\n' {
        end = end - 1
      }
      0
    }
  }
  // Extract content text (without any existing prefix)
  let content = source.substring(
    start=range.start + content_start,
    end=range.end,
  )
  // Trim trailing newline from content
  let trimmed = if content.length() > 0 &&
    content[content.length() - 1] == '\n' {
    content.substring(end=content.length() - 1)
  } else {
    content
  }
  // Build new block text
  let new_prefix = if level > 0 {
    "#".repeat(level) + " "
  } else {
    "" // level 0 means convert to paragraph (no prefix)
  }
  let new_block = new_prefix + trimmed
  Ok(
    Some(
      (
        [
          SpanEdit::{
            start: range.start,
            delete_len: range.end - range.start,
            inserted: new_block + "\n",
          },
        ],
        FocusHint::MoveCursor(
          position=range.start + new_prefix.length() + trimmed.length(),
        ),
      ),
    ),
  )
}

///|
/// Toggle paragraph↔list item.
fn compute_toggle_list_item(
  source : String,
  proj : ProjNode[@markdown.Block],
  source_map : SourceMap,
  node_id : NodeId,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not found in source map")
  }
  // Get block content (text span)
  let content = match source_map.get_token_span(node_id, "text") {
    Some(text_range) =>
      source.substring(start=text_range.start, end=text_range.end)
    None => source.substring(start=range.start, end=range.end)
  }
  // Check if this node is already a list item
  let is_list_item = match find_node(proj, node_id) {
    Some(node) => node.kind is ListItem(_)
    None => false
  }
  let (new_text, prefix_len) = if is_list_item {
    // List item → paragraph: remove "- " prefix, just content
    (content, 0)
  } else {
    // Paragraph → list item: add "- " prefix
    ("- " + content, 2)
  }
  Ok(
    Some(
      (
        [
          SpanEdit::{
            start: range.start,
            delete_len: range.end - range.start,
            inserted: new_text + "\n",
          },
        ],
        FocusHint::MoveCursor(
          position=range.start + prefix_len + content.length(),
        ),
      ),
    ),
  )
}

///|
/// Delete a block (including trailing newline).
fn compute_delete(
  source_map : SourceMap,
  node_id : NodeId,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not found in source map")
  }
  Ok(
    Some(
      (
        [SpanEdit::{ start: range.start, delete_len: range.end - range.start, inserted: "" }],
        FocusHint::RestoreCursor,
      ),
    ),
  )
}

///|
/// Insert empty paragraph after a block.
fn compute_insert_block_after(
  source_map : SourceMap,
  node_id : NodeId,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not found in source map")
  }
  // Insert "\n\n" at the end of the block — creates a blank line + new paragraph
  let insert_pos = range.end
  Ok(
    Some(
      (
        [SpanEdit::{ start: insert_pos, delete_len: 0, inserted: "\n" }],
        FocusHint::MoveCursor(position=insert_pos + 1),
      ),
    ),
  )
}

///|
/// Split block at cursor offset.
fn compute_split_block(
  source : String,
  proj : ProjNode[@markdown.Block],
  source_map : SourceMap,
  node_id : NodeId,
  offset : Int,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  let text_range = match source_map.get_token_span(node_id, "text") {
    Some(r) => r
    None => return Err("no text span for split")
  }
  let range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("node not found")
  }
  // Split at offset 0 → insert empty paragraph before
  if offset <= 0 {
    return compute_insert_block_after(source_map, node_id)
  }
  // Split at end → insert empty paragraph after
  let text_len = text_range.end - text_range.start
  if offset >= text_len {
    return compute_insert_block_after(source_map, node_id)
  }
  // Split point in source coordinates
  let split_pos = text_range.start + offset
  // Check if this is a list item — second half gets "- " prefix
  let is_list_item = match find_node(proj, node_id) {
    Some(node) => node.kind is ListItem(_)
    None => false
  }
  let separator = if is_list_item { "\n- " } else { "\n\n" }
  // Delete from split point to end of block, then insert separator + rest
  let rest = source.substring(start=split_pos, end=range.end)
  // Trim trailing newline from rest if present
  let trimmed_rest = if rest.length() > 0 && rest[rest.length() - 1] == '\n' {
    rest.substring(end=rest.length() - 1)
  } else {
    rest
  }
  let inserted = separator + trimmed_rest + "\n"
  Ok(
    Some(
      (
        [
          SpanEdit::{
            start: split_pos,
            delete_len: range.end - split_pos,
            inserted,
          },
        ],
        FocusHint::MoveCursor(position=split_pos + separator.length()),
      ),
    ),
  )
}

///|
/// Merge block with previous block.
fn compute_merge_with_previous(
  source : String,
  proj : ProjNode[@markdown.Block],
  source_map : SourceMap,
  node_id : NodeId,
) -> Result[(Array[SpanEdit], FocusHint)?, String] {
  // Find this node's index among siblings
  let doc = proj
  let siblings = doc.children
  let mut idx = -1
  for i in 0..<siblings.length() {
    if siblings[i].id() == node_id {
      idx = i
      break
    }
  }
  // First block — no-op
  if idx <= 0 {
    return Ok(None)
  }
  let prev_node = siblings[idx - 1]
  let prev_range = match source_map.get_range(prev_node.id()) {
    Some(r) => r
    None => return Err("previous node not in source map")
  }
  let curr_range = match source_map.get_range(node_id) {
    Some(r) => r
    None => return Err("current node not in source map")
  }
  // Get current block's text content
  let curr_text = match source_map.get_token_span(node_id, "text") {
    Some(r) => source.substring(start=r.start, end=r.end)
    None => ""
  }
  // Merge: delete from end of previous block's text to end of current block,
  // then insert the current block's text
  let prev_text_end = match source_map.get_token_span(prev_node.id(), "text") {
    Some(r) => r.end
    None => prev_range.end
  }
  let cursor_pos = prev_text_end
  Ok(
    Some(
      (
        [
          SpanEdit::{
            start: prev_text_end,
            delete_len: curr_range.end - prev_text_end,
            inserted: curr_text,
          },
        ],
        FocusHint::MoveCursor(position=cursor_pos),
      ),
    ),
  )
}

///|
/// Find a ProjNode by NodeId in the tree.
fn find_node(
  root : ProjNode[@markdown.Block],
  target : NodeId,
) -> ProjNode[@markdown.Block]? {
  if root.id() == target {
    return Some(root)
  }
  for child in root.children {
    match find_node(child, target) {
      Some(found) => return Some(found)
      None => continue
    }
  }
  None
}
```

- [ ] **Step 2: Run moon check**

```bash
moon check
```

Fix any compilation errors. Likely issues:
- `String::repeat` may need verification
- `String` indexing returns `UInt16`, not `Char` — use `for c in s` for char access
- `Range.start` / `Range.end` field access — verify if these are `.start` or `.start()` methods

- [ ] **Step 3: Commit**

```bash
git add lang/markdown/edits/compute_markdown_edit.mbt
git commit -m "feat(markdown/edits): implement compute_markdown_edit with 7 edit handlers"
```

---

### Task 3: Write edit handler tests

**Files:**
- Create: `lang/markdown/edits/compute_markdown_edit_wbtest.mbt`

- [ ] **Step 1: Write whitebox tests**

Write `lang/markdown/edits/compute_markdown_edit_wbtest.mbt`:

```moonbit
///| Whitebox tests for Markdown edit ops.

///|
/// Helper: parse, project, compute edit, return new source text.
fn apply_edit(
  source : String,
  op : MarkdownEditOp,
) -> String raise @loomcore.LexError {
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let source_map = @core.SourceMap::from_ast(proj)
  @md_proj.populate_token_spans(
    source_map,
    {
      let (cst, _) = @markdown.parse_cst(source)
      @seam.SyntaxNode::from_cst(cst)
    },
    proj,
  )
  match compute_markdown_edit(op, source, proj, source_map) {
    Ok(Some((edits, _))) => {
      let sorted = edits.copy()
      sorted.sort_by(fn(a, b) { b.start.compare(a.start) })
      let mut result = source
      for edit in sorted {
        let before = result.substring(end=edit.start)
        let after = result.substring(start=edit.start + edit.delete_len)
        result = before + edit.inserted + after
      }
      result
    }
    Ok(None) => source // no-op
    Err(msg) => abort("edit failed: " + msg)
  }
}

///|
test "commit_edit: change paragraph text" {
  let source = "Hello world\n"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let para_id = proj.children[0].id()
  let result = apply_edit(source, CommitEdit(node_id=para_id, new_text="Goodbye"))
  inspect(result.contains("Goodbye"), content="true")
}

///|
test "change_heading_level: paragraph to h2" {
  let source = "Hello\n"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let para_id = proj.children[0].id()
  let result = apply_edit(
    source,
    ChangeHeadingLevel(node_id=para_id, level=2),
  )
  inspect(result.contains("## Hello"), content="true")
}

///|
test "change_heading_level: h1 to h3" {
  let source = "# Title\n"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let heading_id = proj.children[0].id()
  let result = apply_edit(
    source,
    ChangeHeadingLevel(node_id=heading_id, level=3),
  )
  inspect(result.contains("### Title"), content="true")
}

///|
test "toggle_list_item: paragraph to list item" {
  let source = "Hello\n"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let para_id = proj.children[0].id()
  let result = apply_edit(source, ToggleListItem(node_id=para_id))
  inspect(result.contains("- Hello"), content="true")
}

///|
test "delete: remove a block" {
  let source = "# Title\n\nParagraph\n"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let para_id = proj.children[1].id()
  let result = apply_edit(source, Delete(node_id=para_id))
  inspect(result.contains("Paragraph"), content="false")
}

///|
test "insert_block_after: adds newline" {
  let source = "Hello\n"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let para_id = proj.children[0].id()
  let result = apply_edit(source, InsertBlockAfter(node_id=para_id))
  // Should have two newlines (blank line separator)
  inspect(result.length() > source.length(), content="true")
}

///|
test "merge_with_previous: first block is no-op" {
  let source = "Hello\n"
  let (proj, _) = @md_proj.parse_to_proj_node(source)
  let para_id = proj.children[0].id()
  let result = apply_edit(source, MergeWithPrevious(node_id=para_id))
  inspect(result, content="Hello\n")
}
```

- [ ] **Step 2: Run tests**

```bash
moon test --update -p dowdiness/canopy/lang/markdown/edits
```

Review snapshots, then:

```bash
moon test -p dowdiness/canopy/lang/markdown/edits
```

Fix any failures — the edit handlers may need adjustments based on actual SourceMap ranges.

- [ ] **Step 3: Commit**

```bash
git add lang/markdown/edits/
git commit -m "test(markdown/edits): add edit handler tests for 7 ops"
```

---

### Task 4: Implement bridge and SyncEditor constructor

**Files:**
- Create: `lang/markdown/edits/markdown_edit_bridge.mbt`
- Create: `lang/markdown/edits/sync_editor_markdown.mbt`

- [ ] **Step 1: Write the bridge**

Write `lang/markdown/edits/markdown_edit_bridge.mbt`:

```moonbit
///| Bridge from MarkdownEditOp to SyncEditor text edits.

///|
pub fn apply_markdown_edit(
  editor : @editor.SyncEditor[@markdown.Block],
  op : MarkdownEditOp,
  timestamp_ms : Int,
) -> Result[Unit, String] {
  let source = editor.get_text()
  let proj = match editor.get_proj_node() {
    Some(p) => p
    None => return Err("no projection available")
  }
  let source_map = editor.get_source_map()
  match compute_markdown_edit(op, source, proj, source_map) {
    Ok(Some((edits, focus_hint))) => {
      if edits.is_empty() {
        return Ok(())
      }
      let sorted = edits.copy()
      sorted.sort_by(fn(a, b) { b.start.compare(a.start) })
      let old_cursor = editor.get_cursor()
      for edit in sorted {
        editor.apply_text_edit_internal(
          edit.start,
          edit.delete_len,
          edit.inserted,
          timestamp_ms,
          true,
          false,
        )
      }
      match focus_hint {
        @core.FocusHint::RestoreCursor => editor.move_cursor(old_cursor)
        @core.FocusHint::MoveCursor(position~) => editor.move_cursor(position)
      }
      Ok(())
    }
    Ok(None) => Ok(()) // no-op (e.g., merge on first block)
    Err(msg) => Err(msg)
  }
}
```

- [ ] **Step 2: Write the SyncEditor constructor**

Write `lang/markdown/edits/sync_editor_markdown.mbt`:

```moonbit
///| SyncEditor constructor for Markdown.

///|
pub fn new_markdown_editor(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
) -> @editor.SyncEditor[@markdown.Block] {
  @editor.SyncEditor::new_generic(
    agent_id,
    fn(s) { @loom.new_imperative_parser(s, @markdown.markdown_grammar) },
    @md_proj.build_markdown_projection_memos,
    capture_timeout_ms~,
  )
}
```

- [ ] **Step 3: Run moon check**

```bash
moon check
```

Fix any issues with `SyncEditor` method names — verify `get_text`, `get_proj_node`, `get_source_map`, `get_cursor`, `move_cursor`, `apply_text_edit_internal` exist with these exact names.

- [ ] **Step 4: Run tests**

```bash
moon test -p dowdiness/canopy/lang/markdown/edits
```

- [ ] **Step 5: moon info && moon fmt**

```bash
moon info && moon fmt
```

- [ ] **Step 6: Commit**

```bash
git add lang/markdown/edits/
git commit -m "feat(markdown/edits): add bridge and new_markdown_editor constructor"
```

---

### Task 5: Add FFI exports

**Files:**
- Create: `ffi/crdt_markdown.mbt`

- [ ] **Step 1: Write FFI exports**

Write `ffi/crdt_markdown.mbt`:

```moonbit
///| FFI exports for the Markdown editor.

///|
let markdown_editors : Map[Int, @editor.SyncEditor[@markdown.Block]] = Map::new()

///|
let markdown_view_states : Map[Int, @editor.ViewUpdateState] = Map::new()

///|
let markdown_next_handle : Ref[Int] = { val: 20000 }

///|
pub fn create_markdown_editor(agent_id : String) -> Int {
  let handle = markdown_next_handle.val
  markdown_next_handle.val = handle + 1
  markdown_editors[handle] = @md_edits.new_markdown_editor(agent_id)
  handle
}

///|
pub fn destroy_markdown_editor(handle : Int) -> Unit {
  markdown_editors.remove(handle)
  markdown_view_states.remove(handle)
}

///|
pub fn markdown_get_text(handle : Int) -> String {
  match markdown_editors.get(handle) {
    Some(ed) => ed.get_text()
    None => ""
  }
}

///|
pub fn markdown_set_text(handle : Int, text : String) -> Unit {
  match markdown_editors.get(handle) {
    Some(ed) => ed.set_text(text)
    None => ()
  }
}

///|
pub fn markdown_compute_view_patches_json(handle : Int) -> String {
  match markdown_editors.get(handle) {
    Some(ed) => {
      let state = match markdown_view_states.get(handle) {
        Some(s) => s
        None => {
          let s = @editor.ViewUpdateState::new()
          markdown_view_states[handle] = s
          s
        }
      }
      let patches = @editor.compute_view_patches(state, ed)
      @json.Json::array(patches.map(fn(p) { p.to_json() })).stringify()
    }
    None => "[]"
  }
}

///|
pub fn markdown_apply_edit(
  handle : Int,
  op_type : String,
  node_id : Int,
  param1 : String,
  param2 : Int,
  timestamp_ms : Int,
) -> String {
  match markdown_editors.get(handle) {
    Some(ed) => {
      let nid = @core.NodeId(node_id)
      let op : @md_edits.MarkdownEditOp = match op_type {
        "commit_edit" =>
          @md_edits.MarkdownEditOp::CommitEdit(node_id=nid, new_text=param1)
        "change_heading_level" =>
          @md_edits.MarkdownEditOp::ChangeHeadingLevel(
            node_id=nid,
            level=param2,
          )
        "toggle_list_item" =>
          @md_edits.MarkdownEditOp::ToggleListItem(node_id=nid)
        "delete" => @md_edits.MarkdownEditOp::Delete(node_id=nid)
        "insert_block_after" =>
          @md_edits.MarkdownEditOp::InsertBlockAfter(node_id=nid)
        "split_block" =>
          @md_edits.MarkdownEditOp::SplitBlock(node_id=nid, offset=param2)
        "merge_with_previous" =>
          @md_edits.MarkdownEditOp::MergeWithPrevious(node_id=nid)
        _ => return "{\"status\":\"error\",\"message\":\"unknown op: " + op_type + "\"}"
      }
      match @md_edits.apply_markdown_edit(ed, op, timestamp_ms) {
        Ok(()) => "{\"status\":\"ok\"}"
        Err(msg) =>
          "{\"status\":\"error\",\"message\":\"" + msg + "\"}"
      }
    }
    None => "{\"status\":\"error\",\"message\":\"invalid handle\"}"
  }
}
```

- [ ] **Step 2: Update ffi/moon.pkg**

Add the markdown edits import to `ffi/moon.pkg`:

```
"dowdiness/canopy/lang/markdown/edits" @md_edits,
```

Also add the FFI link exports for the new functions. Check the existing `link` section and add:

```
"create_markdown_editor",
"destroy_markdown_editor",
"markdown_get_text",
"markdown_set_text",
"markdown_compute_view_patches_json",
"markdown_apply_edit",
```

- [ ] **Step 3: Run moon check**

```bash
moon check
```

- [ ] **Step 4: Run full test suite**

```bash
moon test
```

Expected: all tests pass (no regression).

- [ ] **Step 5: moon info && moon fmt**

```bash
moon info && moon fmt
```

- [ ] **Step 6: Commit**

```bash
git add ffi/ lang/markdown/edits/
git commit -m "feat(ffi): add Markdown editor FFI exports (create, edit, patches)"
```

---

### Task 6: Verify full round-trip

- [ ] **Step 1: Add a round-trip integration test**

Add to `lang/markdown/edits/compute_markdown_edit_wbtest.mbt`:

```moonbit
///|
test "round-trip: new_markdown_editor + apply_markdown_edit" {
  let ed = new_markdown_editor("test")
  ed.set_text("# Hello\n\nWorld\n")
  // Force a reparse/projection cycle
  let state = @editor.ViewUpdateState::new()
  let _ = @editor.compute_view_patches(state, ed)
  // Apply heading level change
  let proj = ed.get_proj_node().unwrap()
  let heading_id = proj.children[0].id()
  let result = apply_markdown_edit(
    ed,
    ChangeHeadingLevel(node_id=heading_id, level=3),
    0,
  )
  inspect(result is Ok(_), content="true")
  inspect(ed.get_text().contains("### Hello"), content="true")
}
```

- [ ] **Step 2: Run tests**

```bash
moon test -p dowdiness/canopy/lang/markdown/edits
```

- [ ] **Step 3: Run full test suite**

```bash
moon test
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add lang/markdown/edits/
git commit -m "test(markdown/edits): add SyncEditor round-trip integration test"
```

---

## Acceptance Criteria

- [ ] `MarkdownEditOp` enum with 7 variants
- [ ] `compute_markdown_edit` dispatches all 7 ops to handlers
- [ ] Each handler returns `(Array[SpanEdit], FocusHint)`
- [ ] `apply_markdown_edit` bridge wires ops to SyncEditor
- [ ] `new_markdown_editor` constructor works with `SyncEditor::new_generic`
- [ ] FFI exports: `create_markdown_editor`, `markdown_apply_edit`, `markdown_compute_view_patches_json`
- [ ] Edit handler tests pass
- [ ] SyncEditor round-trip test passes
- [ ] All existing tests pass (no regression)
- [ ] `moon check` passes

## Validation

```bash
moon check && moon test                                      # canopy
moon test -p dowdiness/canopy/lang/markdown/edits            # edit tests
```

## What's Next

After Sub-project 2, write implementation plans for:
- **Sub-project 3:** BlockInput + MarkdownPreview (`lib/editor-adapter/`)
- **Sub-project 4:** Web editor (`examples/web/markdown.html`)
