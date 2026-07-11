# Container Phase 2: Per-Block Text (Path A) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-block text operations to the Container `Document`. Block editor drops its independent `TextState` map and uses `Document::insert_text` / `delete_text` directly.

**Architecture (Path A — shared global LVs):** Per-block FugueTree uses the same global LV space as the CausalGraph. No LvTable, no fugue rename, no internal pipeline changes. Each block's `FugueTree[String]` is indexed by global LVs directly, accepting O(max_global_lv) sparse overhead per block across both `items` and `children` arrays. Internal text pipeline refactoring (dense per-block ItemIds) is a separate future optimization — Phase 3 remote sync works without it.

**Tech Stack:** MoonBit, event-graph-walker submodule (container package, internal/fugue, internal/causal_graph), canopy block-editor

**Design reference:** `docs/plans/2026-03-29-container-design.md`

---

## File Map

### New files

| File | Responsibility |
|------|---------------|
| `container/text_block.mbt` | `TextBlock` — per-block text state: FugueTree[String] + text cache |
| `container/text_ops.mbt` | Document text methods: `insert_text`, `delete_text`, `replace_text`, `get_text`, `text_len` |
| `container/text_block_test.mbt` | TextBlock + Document text API tests |

### Modified files

| File | Change |
|------|--------|
| `container/document.mbt` | Add `blocks` field to Document struct |
| `container/errors.mbt` | Add `TextBlockNotFound` variant |
| `container/moon.pkg` | Add fugue import |
| `examples/block-editor/main/block_doc.mbt` | Replace `TextState` map with Document text ops |
| `examples/block-editor/main/moon.pkg` | Remove `@text` import |

---

## Task 1: Add TextBlock to container

TextBlock is a thin wrapper around `FugueTree[String]` with a text cache. Uses global LVs directly (Path A).

**Files:**
- Modify: `container/moon.pkg`
- Modify: `container/errors.mbt`
- Create: `container/text_block.mbt`

- [ ] **Step 1: Update moon.pkg — add fugue import**

```json
import {
  "dowdiness/event-graph-walker/internal/movable_tree" @mt,
  "dowdiness/event-graph-walker/internal/fractional_index" @fi,
  "dowdiness/event-graph-walker/internal/causal_graph" @cg,
  "dowdiness/event-graph-walker/internal/fugue" @fugue,
}
```

- [ ] **Step 2: Add TextBlockNotFound to errors.mbt**

Add one variant to the existing `DocumentError`:

```moonbit
TextBlockNotFound(id~ : @mt.TreeNodeId)
```

- [ ] **Step 3: Create text_block.mbt**

```moonbit
///| Per-block text state machine.
///
/// Each tree node that has text content gets a TextBlock. The FugueTree
/// uses global LVs from the shared CausalGraph (Path A). Per-block arrays
/// are sparse — a block with LVs [100, 105, 200] allocates a 201-slot
/// items array. This is the accepted tradeoff for Path A simplicity.
/// Internal dense-ItemId refactoring is a future optimization.
pub struct TextBlock {
  priv tree : @fugue.FugueTree[String]
  priv mut text_cache : String?
}

///|
pub fn TextBlock::new() -> TextBlock {
  { tree: @fugue.FugueTree::new(), text_cache: None }
}

///|
/// Insert a character at a visible position in this block's text.
///
/// Resolves Fugue origins (origin_left, origin_right) internally from
/// the visible items at `pos`. The caller provides only the position,
/// a global LV, and causal metadata.
///
/// Parameters:
/// - `pos`: 0-based visible character position (insert before this index)
/// - `lv`: global LV from the shared CausalGraph
/// - `content`: the character to insert
/// - `timestamp`: Lamport timestamp for ordering
/// - `agent`: replica ID for tiebreaking
pub fn TextBlock::insert_at(
  self : TextBlock,
  pos : Int,
  lv : Int,
  content : String,
  timestamp : Int,
  agent : String,
) -> Unit raise DocumentError {
  let len = self.tree.visible_count()
  if pos < 0 || pos > len {
    raise DocumentError::Internal(
      detail="TextBlock insert_at: position " +
        pos.to_string() +
        " out of bounds (len=" +
        len.to_string() +
        ")",
    )
  }
  let items = self.tree.get_visible_items()
  let origin_left : @fugue.Lv? = if pos == 0 {
    None
  } else {
    Some(items[pos - 1].0)
  }
  let origin_right : @fugue.Lv? = if pos >= items.length() {
    None
  } else {
    Some(items[pos].0)
  }
  self.tree.insert(
    {
      id: @fugue.Lv(lv),
      content,
      origin_left,
      origin_right,
      timestamp: @fugue.Timestamp(timestamp),
      agent: @fugue.ReplicaId(agent),
    },
  )
  self.text_cache = None
}

///|
/// Delete the character at a visible position in this block's text.
pub fn TextBlock::delete_at(
  self : TextBlock,
  pos : Int,
  del_timestamp : Int,
  del_agent : String,
) -> Unit raise DocumentError {
  let items = self.tree.get_visible_items()
  if pos < 0 || pos >= items.length() {
    raise DocumentError::Internal(
      detail="TextBlock delete_at: position " +
        pos.to_string() +
        " out of bounds (len=" +
        items.length().to_string() +
        ")",
    )
  }
  let (item_lv, _) = items[pos]
  try {
    self.tree.delete_with_ts(item_lv, del_timestamp, del_agent)
  } catch {
    @fugue.FugueError(err) =>
      raise DocumentError::Internal(
        detail="TextBlock delete: " + err.to_string(),
      )
  }
  self.text_cache = None
}

///|
/// Get the current visible text of this block.
pub fn TextBlock::text(self : TextBlock) -> String {
  match self.text_cache {
    Some(cached) => cached
    None => {
      let text = self.tree.to_text()
      self.text_cache = Some(text)
      text
    }
  }
}

///|
/// Get the visible character count.
pub fn TextBlock::len(self : TextBlock) -> Int {
  self.tree.visible_count()
}
```

- [ ] **Step 4: Run moon check**

```bash
cd event-graph-walker && moon check
```

Expected: 0 errors.

- [ ] **Step 5: moon info && moon fmt**

```bash
cd event-graph-walker && moon info && moon fmt
```

- [ ] **Step 6: Commit**

```bash
cd event-graph-walker
git add container/
git commit -m "feat(container): add TextBlock with per-block FugueTree (Path A global LVs)"
```

---

## Task 2: Add text ops to Document

Wire TextBlock into the container Document. Add text mutation methods that allocate global LVs from the shared CausalGraph and delegate to per-block FugueTree.

**Files:**
- Modify: `container/document.mbt`
- Create: `container/text_ops.mbt`

- [ ] **Step 1: Add blocks field to Document**

In `container/document.mbt`, add to the Document struct:

```moonbit
pub struct Document {
  // ... existing tree fields ...
  priv blocks : Map[@mt.TreeNodeId, TextBlock]
}
```

`TreeNodeId` derives `Eq` and `Hash` (`types.mbt:10`), so `Map[@mt.TreeNodeId, TextBlock]` works directly.

Update `Document::new` to initialize `blocks: {}`.

- [ ] **Step 2: Create text_ops.mbt**

```moonbit
///| Text operations on Document.

///|
/// Get or create the TextBlock for a tree node.
fn Document::get_or_create_text(
  self : Document,
  id : @mt.TreeNodeId,
) -> TextBlock {
  match self.blocks.get(id) {
    Some(block) => block
    None => {
      let block = TextBlock::new()
      self.blocks[id] = block
      block
    }
  }
}

///|
/// Delete a character at the given position in a block's text content.
pub fn Document::delete_text(
  self : Document,
  id : @mt.TreeNodeId,
  pos : Int,
) -> Unit raise DocumentError {
  if !self.is_alive(id) {
    raise DocumentError::TargetNotFound
  }
  let block = match self.blocks.get(id) {
    Some(b) => b
    None => raise DocumentError::TextBlockNotFound(id~)
  }
  let (_, timestamp) = self.next_version()!
  block.delete_at(pos, timestamp, self.agent_id)!
}

///|
/// Get the text content of a block.
pub fn Document::get_text(
  self : Document,
  id : @mt.TreeNodeId,
) -> String {
  match self.blocks.get(id) {
    Some(block) => block.text()
    None => ""
  }
}

///|
/// Get the text length of a block.
pub fn Document::text_len(
  self : Document,
  id : @mt.TreeNodeId,
) -> Int {
  match self.blocks.get(id) {
    Some(block) => block.len()
    None => 0
  }
}
```

**Implementation note — `next_version()` refactoring:**

The existing `next_timestamp()` calls `graph.add_version()` but discards the LV. Text ops need both LV (as FugueTree item ID) and timestamp (for conflict resolution). Add `next_version() -> (Int, Int)` and refactor `next_timestamp` to delegate to it.

Add to `container/document.mbt`:

```moonbit
///|
/// Allocate a new causal version. Returns (lv, timestamp).
fn Document::next_version(self : Document) -> (Int, Int) raise DocumentError {
  let frontier = self.graph.get_frontier()
  let parents = frontier.0
  let lv = try {
    self.graph.add_version(parents, self.agent_id)
  } catch {
    _ => raise DocumentError::Internal(detail="failed to allocate LV")
  }
  let graph_timestamp = match self.graph.get_entry(lv) {
    Some(entry) => entry.timestamp
    None => self.lamport_clock + 1
  }
  let timestamp = graph_timestamp.max(self.lamport_clock + 1)
  self.lamport_clock = timestamp
  (lv, timestamp)
}
```

Then simplify `next_timestamp`:

```moonbit
fn Document::next_timestamp(self : Document) -> Int {
  let (_, timestamp) = try { self.next_version() } catch { _ => (-1, self.lamport_clock + 1) }
  timestamp
}
```

And update `insert_text` to use `next_version()` (the canonical version — the only `insert_text` in the plan):

```moonbit
///|
/// Insert text at the given character position in a block's text content.
pub fn Document::insert_text(
  self : Document,
  id : @mt.TreeNodeId,
  pos : Int,
  text : String,
) -> Unit raise DocumentError {
  if !self.is_alive(id) {
    raise DocumentError::TargetNotFound
  }
  let block = self.get_or_create_text(id)
  loop text.view(), 0 {
    [], _ => ()
    [ch, ..rest], i => {
      let (lv, timestamp) = self.next_version()!
      block.insert_at(
        pos + i, lv, ch.to_string(), timestamp, self.agent_id,
      )!
      continue rest, i + 1
    }
  }
}
```

- [ ] **Step 3: Run moon check**

```bash
cd event-graph-walker && moon check
```

Fix any compilation errors.

- [ ] **Step 4: moon info && moon fmt**

```bash
cd event-graph-walker && moon info && moon fmt
```

- [ ] **Step 5: Commit**

```bash
cd event-graph-walker
git add container/
git commit -m "feat(container): add Document text ops (insert_text, delete_text, get_text)"
```

---

## Task 3: Write text integration tests

**Files:**
- Create: `container/text_block_test.mbt`

- [ ] **Step 1: Write TextBlock unit tests**

```moonbit
///|
test "text_block: insert and read" {
  let block = TextBlock::new()
  block.insert_at(0, 0, "H", 1, "alice")!
  block.insert_at(1, 1, "i", 2, "alice")!
  inspect(block.text(), content="Hi")
  inspect(block.len(), content="2")
}

///|
test "text_block: insert at middle" {
  let block = TextBlock::new()
  block.insert_at(0, 0, "A", 1, "alice")!
  block.insert_at(1, 1, "C", 2, "alice")!
  block.insert_at(1, 2, "B", 3, "alice")!
  inspect(block.text(), content="ABC")
}

///|
test "text_block: delete" {
  let block = TextBlock::new()
  block.insert_at(0, 0, "A", 1, "alice")!
  block.insert_at(1, 1, "B", 2, "alice")!
  block.insert_at(2, 2, "C", 3, "alice")!
  inspect(block.text(), content="ABC")
  block.delete_at(1, 4, "alice")!
  inspect(block.text(), content="AC")
  inspect(block.len(), content="2")
}

///|
test "text_block: insert out of bounds" {
  let block = TextBlock::new()
  block.insert_at(0, 0, "A", 1, "alice")!
  let result = try { block.insert_at(5, 1, "B", 2, "alice") } catch { _ => Err(()) }
  inspect(result is Err(_), content="true")
}

///|
test "text_block: delete out of bounds" {
  let block = TextBlock::new()
  block.insert_at(0, 0, "A", 1, "alice")!
  let result = try { block.delete_at(5, 2, "alice") } catch { _ => Err(()) }
  inspect(result is Err(_), content="true")
}

///|
test "text_block: delete after tombstone exists" {
  let block = TextBlock::new()
  block.insert_at(0, 0, "A", 1, "alice")!
  block.insert_at(1, 1, "B", 2, "alice")!
  block.insert_at(2, 2, "C", 3, "alice")!
  block.delete_at(1, 4, "alice")!  // B is now a tombstone
  inspect(block.text(), content="AC")
  block.delete_at(1, 5, "alice")!  // delete C (visible pos 1, after tombstone)
  inspect(block.text(), content="A")
}

///|
test "text_block: empty" {
  let block = TextBlock::new()
  inspect(block.text(), content="")
  inspect(block.len(), content="0")
}
```

- [ ] **Step 2: Write Document text integration tests**

```moonbit
///|
test "document: insert and read text" {
  let doc = Document::new("alice")!
  let node = doc.create_node(parent=@mt.root_id)!
  doc.insert_text(node, 0, "Hello")!
  inspect(doc.get_text(node), content="Hello")
  inspect(doc.text_len(node), content="5")
}

///|
test "document: delete text" {
  let doc = Document::new("alice")!
  let node = doc.create_node(parent=@mt.root_id)!
  doc.insert_text(node, 0, "Hello")!
  doc.delete_text(node, 1)!
  inspect(doc.get_text(node), content="Hllo")
}

///|
test "document: text on deleted node fails" {
  let doc = Document::new("alice")!
  let node = doc.create_node(parent=@mt.root_id)!
  doc.delete_node(node)!
  let result = try { doc.insert_text(node, 0, "x") } catch { _ => Err(()) }
  inspect(result is Err(_), content="true")
}

///|
test "document: multiple blocks independent" {
  let doc = Document::new("alice")!
  let n1 = doc.create_node(parent=@mt.root_id)!
  let n2 = doc.create_node(parent=@mt.root_id)!
  doc.insert_text(n1, 0, "AAA")!
  doc.insert_text(n2, 0, "BBB")!
  inspect(doc.get_text(n1), content="AAA")
  inspect(doc.get_text(n2), content="BBB")
}

///|
test "document: get_text on node without text returns empty" {
  let doc = Document::new("alice")!
  let node = doc.create_node(parent=@mt.root_id)!
  inspect(doc.get_text(node), content="")
  inspect(doc.text_len(node), content="0")
}

///|
test "document: tree and text ops share causal graph" {
  let doc = Document::new("alice")!
  let n1 = doc.create_node(parent=@mt.root_id)!
  // Tree op consumed some LVs; text ops should get later LVs
  doc.insert_text(n1, 0, "AB")!
  inspect(doc.get_text(n1), content="AB")
  // Create another node — causal ordering is preserved
  let n2 = doc.create_node(parent=@mt.root_id)!
  doc.insert_text(n2, 0, "X")!
  inspect(doc.get_text(n2), content="X")
}

///|
test "document: delete from nonexistent text block" {
  let doc = Document::new("alice")!
  let node = doc.create_node(parent=@mt.root_id)!
  // No text inserted yet → TextBlockNotFound
  let result = try { doc.delete_text(node, 0) } catch { _ => Err(()) }
  inspect(result is Err(_), content="true")
}

///|
test "document: insert at invalid position" {
  let doc = Document::new("alice")!
  let node = doc.create_node(parent=@mt.root_id)!
  doc.insert_text(node, 0, "AB")!
  // pos 5 is past end (len=2)
  let result = try { doc.insert_text(node, 5, "X") } catch { _ => Err(()) }
  inspect(result is Err(_), content="true")
}

///|
test "document: interleaved LV gaps across blocks" {
  let doc = Document::new("alice")!
  let n1 = doc.create_node(parent=@mt.root_id)!
  let n2 = doc.create_node(parent=@mt.root_id)!
  // Interleave: edit n1, then n2, then n1 again
  // Global LVs are non-contiguous within each block
  doc.insert_text(n1, 0, "A")!
  doc.insert_text(n2, 0, "X")!
  doc.insert_text(n1, 1, "B")!
  doc.insert_text(n2, 1, "Y")!
  doc.insert_text(n1, 2, "C")!
  inspect(doc.get_text(n1), content="ABC")
  inspect(doc.get_text(n2), content="XY")
}

///|
test "document: replace_text" {
  let doc = Document::new("alice")!
  let node = doc.create_node(parent=@mt.root_id)!
  doc.insert_text(node, 0, "Hello")!
  doc.replace_text(node, "World")!
  inspect(doc.get_text(node), content="World")
}

///|
test "document: replace_text on empty block" {
  let doc = Document::new("alice")!
  let node = doc.create_node(parent=@mt.root_id)!
  doc.replace_text(node, "New")!
  inspect(doc.get_text(node), content="New")
}

///|
test "document: replace_text with empty string" {
  let doc = Document::new("alice")!
  let node = doc.create_node(parent=@mt.root_id)!
  doc.insert_text(node, 0, "Hello")!
  doc.replace_text(node, "")!
  inspect(doc.get_text(node), content="")
  inspect(doc.text_len(node), content="0")
}
```

- [ ] **Step 3: Run tests**

```bash
cd event-graph-walker && moon check && moon test -p dowdiness/event-graph-walker/container
```

Expected: All container tests pass (25 existing tree + new text tests).

- [ ] **Step 4: Run full suite**

```bash
cd event-graph-walker && moon test
```

Expected: All pass.

- [ ] **Step 5: moon info && moon fmt**

```bash
cd event-graph-walker && moon info && moon fmt
```

- [ ] **Step 6: Commit**

```bash
cd event-graph-walker
git add container/
git commit -m "test(container): add TextBlock and Document text integration tests"
```

---

## Task 4: Wire block editor to Document text ops

Replace the block editor's independent `TextState` map with `Document::insert_text` / `delete_text`.

**Files:**
- Modify: `examples/block-editor/main/block_doc.mbt`
- Modify: `examples/block-editor/main/moon.pkg`

- [ ] **Step 1: Remove @text import from moon.pkg**

Remove the `@text` import. The `@container` import (already present) now provides text ops:

```json
import {
  "dowdiness/event-graph-walker/container" @container,
}
```

- [ ] **Step 2: Replace TextState usage in block_doc.mbt**

The block editor currently maintains `texts : Map[String, @text.TextState]`. Replace all `@text.TextState` operations with `@container.Document` text methods:

Remove from `BlockDoc` struct:
```moonbit
// DELETE: priv texts : Map[String, @text.TextState]
// DELETE: priv replica_id : String  (if only used for TextState::new)
```

Update `BlockDoc::new` to remove `texts` and `replica_id`.

Replace methods:

| Before | After |
|--------|-------|
| `self.texts[id_key(id)] = @text.TextState::new(self.replica_id)` in `create_block`/`create_block_after` | Remove — TextBlock is created lazily by `Document::get_or_create_text` |
| `self.texts.get(id_key(id))` → `tdoc.text()` in `get_text` | `self.tree.get_text(id)` |
| `tdoc.replace_range(...)` / `tdoc.insert(...)` in `set_text` | `self.tree.delete_text` + `self.tree.insert_text` or add `Document::set_text` helper |
| `tdoc.insert(@text.Pos::at(pos), ch)` in `insert_char` | `self.tree.insert_text(id, pos, ch)!` (swallow error with `catch { _ => () }`) |
| `tdoc.delete(@text.Pos::at(pos))` in `delete_char` | `self.tree.delete_text(id, pos)!` (swallow error with `catch { _ => () }`) |

For `set_text`, the current impl does `replace_range` (delete all + insert). With Document text ops, we need a `Document::replace_text` helper that snapshots the visible item LVs before mutating, then deletes those exact items. This avoids CRDT target drift — naively looping `delete_at(0)` n times deletes whatever is currently at the front, not the original characters, which breaks under concurrent edits.

Add to `container/text_ops.mbt`:

```moonbit
///|
/// Replace all text in a block atomically.
/// Snapshots visible LVs before deleting to avoid CRDT target drift.
pub fn Document::replace_text(
  self : Document,
  id : @mt.TreeNodeId,
  text : String,
) -> Unit raise DocumentError {
  if !self.is_alive(id) {
    raise DocumentError::TargetNotFound
  }
  // Snapshot current visible items before any mutation
  match self.blocks.get(id) {
    Some(block) => {
      let visible = block.tree.get_visible_items()
      // Delete each snapshotted item by its LV (not by position)
      for i = 0; i < visible.length(); i = i + 1 {
        let (item_lv, _) = visible[i]
        let (_, timestamp) = self.next_version()!
        try {
          block.tree.delete_with_ts(item_lv, timestamp, self.agent_id)
        } catch {
          @fugue.FugueError(_) => ()  // already deleted (concurrent)
        }
      }
      block.text_cache = None
    }
    None => ()
  }
  // Insert new text
  if text != "" {
    self.insert_text(id, 0, text)!
  }
}
```

Then `BlockDoc::set_text` becomes:

```moonbit
pub fn BlockDoc::set_text(
  self : BlockDoc,
  id : @container.TreeNodeId,
  text : String,
) -> Unit {
  try { self.tree.replace_text(id, text) } catch { _ => () }
}
```

Note: `replace_text` accesses the block's `FugueTree` directly to snapshot LVs, then uses the public `insert_text` for the insertion. This keeps the delete-by-LV logic inside the container package where it has access to `TextBlock.tree`.

- [ ] **Step 3: Run moon check**

```bash
moon check
cd examples/block-editor && moon check
```

- [ ] **Step 4: Run tests**

```bash
cd examples/block-editor && moon test
```

Expected: All block editor tests pass.

- [ ] **Step 5: moon info && moon fmt**

```bash
cd examples/block-editor && moon info && moon fmt
```

- [ ] **Step 6: Commit (in canopy repo)**

```bash
git add event-graph-walker examples/block-editor/
git commit -m "feat(block-editor): use Document text ops instead of per-block TextState

Block editor now uses @container.Document for both tree and text ops.
Per-block TextState map removed."
```

---

## Task 5: Verify and finalize

- [ ] **Step 1: Run all test suites**

```bash
cd event-graph-walker && moon test
cd .. && moon test
cd examples/block-editor && moon test
```

Expected: All pass.

- [ ] **Step 2: Verify no stale @text references in block-editor**

```bash
grep -rn "@text\." examples/block-editor/main/*.mbt
```

Expected: Zero matches.

- [ ] **Step 3: Check mbti interface changes**

```bash
cd event-graph-walker && moon info && git diff -- '*.mbti'
```

Review: `container/` should show new public API methods (`TextBlock`, `insert_text`, `delete_text`, `replace_text`, `get_text`, `text_len`, `TextBlockNotFound`). No changes expected in `fugue/`, `branch/`, or `document/`.

- [ ] **Step 4: Ask user about submodule push**

Before pushing event-graph-walker, ask: "Push to event-graph-walker main, or create a PR?"

---

## Acceptance Criteria

- [ ] `TextBlock` wraps `FugueTree[String]` with text cache (no LvTable)
- [ ] `Document::insert_text` / `delete_text` / `replace_text` / `get_text` / `text_len` work
- [ ] Position validation: insert rejects `pos < 0` or `pos > len`; delete rejects `pos < 0` or `pos >= len`
- [ ] Text ops allocate global LVs from the shared CausalGraph
- [ ] Block editor uses Document text ops (no independent TextState)
- [ ] All existing tests pass (no regression)
- [ ] `moon check` passes across event-graph-walker and canopy

## Validation

```bash
cd event-graph-walker && moon check && moon test
cd .. && moon check && moon test
cd examples/block-editor && moon check && moon test
```

## Risks

- **Sparse array overhead**: With global LVs, a block's FugueTree is O(max_global_lv) across both `items: Array[Item[T]?]` AND `children: Array[Array[Lv]]` arrays, not just items. For a 1000-op document with 10 blocks of ~100 chars each, each block allocates ~1000 slots per array instead of ~100. This is the known Path A tradeoff — measure when it becomes a real bottleneck, then apply the internal refactoring (dense ItemIds via LvTable).
- **Position-to-origins mapping**: `TextBlock::insert_at` resolves origins via `FugueTree::get_visible_items()` — O(n) per insert where n = visible items in the block. Acceptable for Path A (per-block text is typically small). If needed later, add an OrderTree position cache per block.
- **CausalGraph double-allocation**: The existing `next_timestamp()` already calls `graph.add_version()` but discards the LV. `insert_text` needs both LV and timestamp. Refactor to `next_version() -> (Int, Int)` to avoid allocating two CausalGraph entries per text character.
- **Standalone TextState**: Not affected — it doesn't touch the container package. Verify with `cd event-graph-walker && moon test -p dowdiness/event-graph-walker/text`.

## What's NOT in this plan

- **No fugue::Lv → fugue::ItemId rename** — Path A uses global LVs directly
- **No LvTable** — no ID translation layer needed
- **No internal pipeline refactoring** — oplog/, branch/, fugue/ unchanged
- **No Op enum** — local ops go directly to TextBlock without oplog serialization (needed for Phase 3 sync)
- **No remote text sync** — deferred to Phase 3
- **No document-level undo** — deferred to Phase 4

## Notes

- The internal text pipeline refactoring (dense per-block ItemIds, `Lv` → `ItemId` rename, LvTable) is tracked separately in TODO §16 as "Internal text pipeline refactoring." It becomes relevant when sparse overhead is measured as a real bottleneck.
- Remote text sync (Phase 3) works with global LVs — Branch and MergeContext already operate on global LVs. The container just routes per-block FugueTree operations.
- `InsertOp` is defined in `internal/fugue/item.mbt` (not a separate `insert_op.mbt` file).
