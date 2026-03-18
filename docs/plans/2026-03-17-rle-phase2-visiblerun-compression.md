# RLE Phase 2: VisibleRun Compression Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compress Document.position_cache using Rle[VisibleRun] for O(log n) position lookups and reduced memory.

**Architecture:** Define VisibleRun in document package. Build compressed cache during tree traversal. Use Rle::find for O(log n) position_to_lv and lv_to_position. Keep get_visible_items() returning uncompressed array for external consumers.

**Tech Stack:** MoonBit, dowdiness/rle library

**Spec:** `docs/plans/2026-03-15-rle-library-integration.md` (Phase 2 section)

**Important:** `event-graph-walker/` is a git submodule. All source changes are inside it.

---

### Task 1: Add `dowdiness/rle` import to document package

**Files:**
- Modify: `event-graph-walker/internal/document/moon.pkg`

- [ ] **Step 1: Add rle import**

Edit `event-graph-walker/internal/document/moon.pkg`:

```
import {
  "dowdiness/event-graph-walker/internal/core",
  "dowdiness/event-graph-walker/internal/causal_graph",
  "dowdiness/event-graph-walker/internal/oplog",
  "dowdiness/event-graph-walker/internal/fugue",
  "dowdiness/event-graph-walker/internal/branch",
  "dowdiness/rle",
}

options(
  is_main: false,
)
```

- [ ] **Step 2: Verify compilation**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker && moon check
```

Expected: Clean check. The `@rle` alias will be available as `@rle`.

---

### Task 2: Define VisibleRun type with trait implementations

**Files:**
- Create: `event-graph-walker/internal/document/visible_run.mbt`
- Create: `event-graph-walker/internal/document/visible_run_wbtest.mbt`

- [ ] **Step 1: Create VisibleRun struct and trait impls**

Create `event-graph-walker/internal/document/visible_run.mbt`:

```moonbit
///| VisibleRun — compressed representation of consecutive visible items
/// in document order. Used as the element type for Rle[VisibleRun] in
/// the position cache.

///|
/// A run of consecutive visible items in document order.
///
/// **Merge condition:** Two runs merge when they are adjacent in document
/// order AND have consecutive LVs (`a.start_lv + a.count == b.start_lv`).
/// Document-order adjacency is guaranteed by the build order (tree
/// traversal emits items in document order, so two successive visible
/// items that also have consecutive LVs must be adjacent).
struct VisibleRun {
  start_lv : Int // First LV in this visible run
  text : String // Concatenated visible text
  count : Int // Number of items in run
} derive(Show, Eq)

///|
pub impl @rle.HasLength for VisibleRun with length(self) -> Int {
  self.count
}

///|
/// span = count (one item per position in the item space).
/// This is the coordinate space for Rle::find — position-based lookup.
pub impl @rle.Spanning for VisibleRun with span(self) -> Int {
  self.count
}

///|
/// logical_length = text.length() (visible character count in UTF-16 code units).
/// For single-byte characters, this equals count. For multi-byte characters
/// (emoji etc.), this may differ.
pub impl @rle.Spanning for VisibleRun with logical_length(self) -> Int {
  self.text.length()
}

///|
/// Two runs can merge when they have consecutive LVs.
/// Document-order adjacency is guaranteed by build order (tree traversal).
/// Safety: this merge condition is valid only when runs are appended in document order (tree traversal). Do not use with arbitrary insertion into the Rle.
pub impl @rle.Mergeable for VisibleRun with can_merge(self, other) -> Bool {
  self.start_lv + self.count == other.start_lv
}

///|
pub impl @rle.Mergeable for VisibleRun with merge(self, other) -> VisibleRun {
  { start_lv: self.start_lv, text: self.text + other.text, count: self.count + other.count }
}

///|
/// Sliceable enables split/insert/delete on Rle[VisibleRun].
/// Uses @rle.slice_string_view for UTF-16 safe string slicing.
pub impl @rle.Sliceable for VisibleRun with slice(
  self,
  start~ : Int,
  end~ : Int,
) -> Result[VisibleRun, @rle.RleError] {
  if start < 0 || end > self.count || start > end {
    return Err(
      @rle.RleError::InvalidSlice(reason=@rle.SliceError::IndexOutOfBounds),
    )
  }
  // For VisibleRun, each item contributes exactly one character to text,
  // so slicing [start, end) in item space corresponds to [start, end) in text.
  // However, multi-byte characters (emoji) occupy 2 UTF-16 code units but
  // still count as 1 item. So we need to walk the string to find correct
  // character boundaries.
  //
  // Since each item is one character (one insert op = one char), and MoonBit's
  // string indexing is UTF-16, we need to map item offsets to UTF-16 offsets.
  // Each character was inserted as a single String via text[i:i+1], which is
  // 1 or 2 UTF-16 code units depending on the character.
  //
  // For now, we use a simple approach: since each character in the CRDT is
  // stored as a single inserted character, we compute UTF-16 offsets by
  // walking the string character by character.
  let text_start = item_offset_to_utf16(self.text, start)
  let text_end = item_offset_to_utf16(self.text, end)
  match @rle.slice_string_view(self.text, start=text_start, end=text_end) {
    Ok(sliced_text) =>
      Ok(
        {
          start_lv: self.start_lv + start,
          text: sliced_text,
          count: end - start,
        },
      )
    Err(e) => Err(@rle.RleError::InvalidSlice(reason=e))
  }
}

///|
/// Convert an item offset (0-based character index) to a UTF-16 code unit offset.
///
/// Each CRDT item is one character. Characters may be 1 or 2 UTF-16 code units.
/// This walks the string to find the byte position of the n-th character.
fn item_offset_to_utf16(text : String, item_offset : Int) -> Int {
  if item_offset == 0 {
    return 0
  }
  let mut chars_seen = 0
  let mut utf16_pos = 0
  while utf16_pos < text.length() && chars_seen < item_offset {
    // Check if this is a high surrogate (start of a surrogate pair)
    let code_unit = text[utf16_pos].to_int()
    if code_unit >= 0xD800 && code_unit <= 0xDBFF {
      // Surrogate pair: 2 UTF-16 code units = 1 character
      utf16_pos = utf16_pos + 2
    } else {
      utf16_pos = utf16_pos + 1
    }
    chars_seen = chars_seen + 1
  }
  utf16_pos
}
```

- [ ] **Step 2: Create whitebox tests for VisibleRun**

Create `event-graph-walker/internal/document/visible_run_wbtest.mbt`:

```moonbit
///| Whitebox tests for VisibleRun type and trait implementations

///|
test "VisibleRun: span returns count" {
  let run : VisibleRun = { start_lv: 0, text: "hello", count: 5 }
  inspect(@rle.Spanning::span(run), content="5")
}

///|
test "VisibleRun: logical_length returns text length" {
  let run : VisibleRun = { start_lv: 0, text: "hello", count: 5 }
  inspect(@rle.Spanning::logical_length(run), content="5")
}

///|
test "VisibleRun: can_merge consecutive LVs" {
  let a : VisibleRun = { start_lv: 0, text: "ab", count: 2 }
  let b : VisibleRun = { start_lv: 2, text: "cd", count: 2 }
  inspect(@rle.Mergeable::can_merge(a, b), content="true")
}

///|
test "VisibleRun: cannot merge non-consecutive LVs" {
  let a : VisibleRun = { start_lv: 0, text: "ab", count: 2 }
  let b : VisibleRun = { start_lv: 5, text: "cd", count: 2 }
  inspect(@rle.Mergeable::can_merge(a, b), content="false")
}

///|
test "VisibleRun: merge concatenates text and counts" {
  let a : VisibleRun = { start_lv: 0, text: "ab", count: 2 }
  let b : VisibleRun = { start_lv: 2, text: "cd", count: 2 }
  let merged = @rle.Mergeable::merge(a, b)
  inspect(merged.start_lv, content="0")
  inspect(merged.text, content="abcd")
  inspect(merged.count, content="4")
}

///|
test "VisibleRun: slice extracts subrange" {
  let run : VisibleRun = { start_lv: 10, text: "abcde", count: 5 }
  let sliced = @rle.Sliceable::slice(run, start=1, end=4)
  inspect(sliced is Ok(_), content="true")
  match sliced {
    Ok(s) => {
      inspect(s.start_lv, content="11")
      inspect(s.text, content="bcd")
      inspect(s.count, content="3")
    }
    Err(_) => ()
  }
}

///|
test "VisibleRun: Rle append merges consecutive runs" {
  let rle : @rle.Rle[VisibleRun] = @rle.Rle::new()
  let _ = rle.append({ start_lv: 0, text: "a", count: 1 })
  let _ = rle.append({ start_lv: 1, text: "b", count: 1 })
  let _ = rle.append({ start_lv: 2, text: "c", count: 1 })
  // All three should merge into one run
  inspect(@rle.HasLength::length(rle), content="1")
  inspect(@rle.Spanning::span(rle), content="3")
}

///|
test "VisibleRun: Rle append keeps non-consecutive runs separate" {
  let rle : @rle.Rle[VisibleRun] = @rle.Rle::new()
  let _ = rle.append({ start_lv: 0, text: "ab", count: 2 })
  let _ = rle.append({ start_lv: 5, text: "cd", count: 2 })
  // Non-consecutive LVs — two separate runs
  inspect(@rle.HasLength::length(rle), content="2")
  inspect(@rle.Spanning::span(rle), content="4")
}

///|
test "VisibleRun: Rle find locates correct position" {
  let rle : @rle.Rle[VisibleRun] = @rle.Rle::new()
  let _ = rle.append({ start_lv: 0, text: "abc", count: 3 })
  let _ = rle.append({ start_lv: 10, text: "de", count: 2 })
  // Position 0 → run 0, offset 0
  inspect(rle.find(0), content="Some({run: 0, offset: 0})")
  // Position 2 → run 0, offset 2
  inspect(rle.find(2), content="Some({run: 0, offset: 2})")
  // Position 3 → run 1, offset 0
  inspect(rle.find(3), content="Some({run: 1, offset: 0})")
  // Position 4 → run 1, offset 1
  inspect(rle.find(4), content="Some({run: 1, offset: 1})")
}

///|
test "item_offset_to_utf16: basic ASCII" {
  inspect(item_offset_to_utf16("hello", 0), content="0")
  inspect(item_offset_to_utf16("hello", 3), content="3")
  inspect(item_offset_to_utf16("hello", 5), content="5")
}
```

- [ ] **Step 3: Verify compilation and run tests**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker && moon check && moon test -p dowdiness/event-graph-walker/internal/document
```

- [ ] **Step 4: Format and update interfaces**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker && moon info && moon fmt
```

- [ ] **Step 5: Commit inside submodule**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker
git add internal/document/moon.pkg internal/document/visible_run.mbt internal/document/visible_run_wbtest.mbt internal/document/pkg.generated.mbti
git commit -m "feat(document): define VisibleRun type with RLE trait impls (Phase 2, Task 1-2)

Add VisibleRun struct for compressed position cache representation.
Implements Spanning, Mergeable, and Sliceable traits for dowdiness/rle.
Add dowdiness/rle import to document package."
```

---

### Task 3: Build compressed position cache from tree traversal

**Files:**
- Modify: `event-graph-walker/internal/document/document.mbt`

This task changes the Document struct to store `Rle[VisibleRun]` instead of `Array[(Lv, Item[String])]` and adds the cache build logic.

- [ ] **Step 1: Change position_cache type in Document struct**

In `event-graph-walker/internal/document/document.mbt`, change the struct definition.

Replace (line 9-16):
```moonbit
pub struct Document {
  priv tree : @fugue.FugueTree[String]
  priv oplog : @oplog.OpLog
  agent_id : String
  // Position cache: maps position -> (Lv, Item[String]) for O(1) lookup
  // Invalidated on any modification (set to None)
  priv mut position_cache : Array[(@fugue.Lv, @fugue.Item[String])]?
} derive(Show)
```

With:
```moonbit
pub struct Document {
  priv tree : @fugue.FugueTree[String]
  priv oplog : @oplog.OpLog
  agent_id : String
  // Compressed position cache: maps position -> VisibleRun via O(log n) lookup.
  // Invalidated on any modification (set to None). Rebuilt lazily on demand.
  priv mut position_cache : @rle.Rle[VisibleRun]?
} derive(Show)
```

- [ ] **Step 2: Add build_position_cache function**

Replace the existing `get_position_cache` function (lines 60-72) with a new version that builds the compressed Rle:

Replace:
```moonbit
///|
/// Get or build the position cache (lazy initialization)
fn Document::get_position_cache(
  self : Document,
) -> Array[(@fugue.Lv, @fugue.Item[String])] {
  match self.position_cache {
    Some(cache) => cache
    None => {
      let cache = self.tree.get_visible_items()
      self.position_cache = Some(cache)
      cache
    }
  }
}
```

With:
```moonbit
///|
/// Build the compressed position cache from visible tree items.
///
/// Walks the FugueTree's visible items in document order and appends
/// VisibleRun entries to an Rle. Adjacent items with consecutive LVs
/// are automatically merged by the Rle's append logic (via can_merge).
fn Document::build_position_cache(
  self : Document,
) -> @rle.Rle[VisibleRun] {
  let items = self.tree.get_visible_items()
  let rle : @rle.Rle[VisibleRun] = @rle.Rle::new()
  for i = 0; i < items.length(); i = i + 1 {
    let (lv, item) = items[i]
    let _ = rle.append({ start_lv: lv.0, text: item.content, count: 1 })
  }
  rle
}

///|
/// Get or build the compressed position cache (lazy initialization).
fn Document::get_compressed_cache(self : Document) -> @rle.Rle[VisibleRun] {
  match self.position_cache {
    Some(cache) => cache
    None => {
      let cache = self.build_position_cache()
      self.position_cache = Some(cache)
      cache
    }
  }
}
```

- [ ] **Step 3: Verify compilation**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker && moon check
```

Expected: Compilation errors in functions that still reference the old cache type. These will be fixed in subsequent steps.

---

### Task 4: Update position_to_lv to use Rle::find

**Files:**
- Modify: `event-graph-walker/internal/document/document.mbt`

- [ ] **Step 1: Rewrite position_to_lv using compressed cache**

Replace the existing `position_to_lv` function (lines 80-105):

Replace:
```moonbit
///|
/// Map a user position (0-based cursor position) to the LV at that position.
///
/// Returns the LV of the item before the cursor position,
/// or -1 if at the start of the document.
fn Document::position_to_lv(self : Document, position : Int) -> Int {
  if position == 0 {
    return -1
  }

  // Use cached visible items for O(1) lookup after first access
  let items_list = self.get_position_cache()

  // Find the LV at position - 1
  if position > items_list.length() {
    // Position beyond end, use last item
    if items_list.length() > 0 {
      let (id, _) = items_list[items_list.length() - 1]
      return id.0
    } else {
      return -1
    }
  }
  let (id, _) = items_list[position - 1]
  id.0
}
```

With:
```moonbit
///|
/// Map a user position (0-based cursor position) to the LV at that position.
///
/// Returns the LV of the item before the cursor position,
/// or -1 if at the start of the document.
///
/// Uses O(log n) binary search via Rle::find on the compressed position cache.
fn Document::position_to_lv(self : Document, position : Int) -> Int {
  if position == 0 {
    return -1
  }

  let cache = self.get_compressed_cache()
  let total = @rle.Spanning::span(cache)

  // Find the LV at position - 1 (the item before the cursor)
  if position > total {
    // Position beyond end, use last item
    if total > 0 {
      match cache.find(total - 1) {
        Some(rp) =>
          match cache.get(rp.run) {
            Some(run) => return run.start_lv + rp.offset
            None => return -1
          }
        None => return -1
      }
    } else {
      return -1
    }
  }
  match cache.find(position - 1) {
    Some(rp) =>
      match cache.get(rp.run) {
        Some(run) => run.start_lv + rp.offset
        None => -1
      }
    None => -1
  }
}
```

- [ ] **Step 2: Verify compilation**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker && moon check
```

---

### Task 5: Update lv_to_position to use compressed cache (O(n) to O(log n))

**Files:**
- Modify: `event-graph-walker/internal/document/document.mbt`

Currently `Document::lv_to_position` delegates to `FugueTree::lv_to_position` which does an O(n) linear scan through `get_visible_items()`. We replace it with an O(log n) search on the compressed cache.

**Note:** We do NOT modify `FugueTree::lv_to_position` — it stays as-is for non-Document callers. We override the Document-level method.

- [ ] **Step 1: Rewrite Document::lv_to_position**

Replace (lines 457-460):
```moonbit
///|
/// Map a local version to its visible position in the document.
pub fn Document::lv_to_position(self : Document, lv : Int) -> Int? {
  self.tree.lv_to_position(@fugue.Lv(lv))
}
```

With:
```moonbit
///|
/// Map a local version to its visible position in the document.
///
/// Uses O(log n) search on the compressed position cache: binary search
/// for the run containing the LV, then compute position from prefix sums.
pub fn Document::lv_to_position(self : Document, lv : Int) -> Int? {
  let cache = self.get_compressed_cache()
  // Search through runs to find the one containing this LV.
  // Since runs are in document order (not LV order), we must scan.
  // However, within each run LVs are consecutive, so we can check
  // start_lv <= lv < start_lv + count for each run.
  //
  // For now, use each_with_position which gives us (run, start_pos, end_pos)
  // for each run. This is O(k) where k = number of runs, which is
  // much better than O(n) for compressed documents.
  let mut result : Int? = None
  cache.each_with_position(fn(run, start_pos, _end_pos) {
    if lv >= run.start_lv && lv < run.start_lv + run.count {
      let offset = lv - run.start_lv
      result = Some(start_pos + offset)
    }
  })
  result
}
```

**Design note:** `lv_to_position` searches by LV value, not by span position. The Rle is indexed by span (document position), not by LV. Since LVs within a run are consecutive but runs in the Rle are ordered by document position (not LV), we cannot use binary search on the LV dimension directly. We use `each_with_position` which is O(k) where k = number of runs, significantly better than O(n) for well-compressed documents. A future optimization could build a secondary LV index.

**Spec deviation:** The spec claims O(log n) for lv_to_position, but this implementation is O(k) where k = number of runs, because the Rle is indexed by document position (span), not by LV value. A secondary LV index could achieve O(log n) but is deferred as a future optimization.

- [ ] **Step 2: Verify compilation**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker && moon check
```

---

### Task 6: Update get_visible_items to expand from compressed cache

**Files:**
- Modify: `event-graph-walker/internal/document/document.mbt`

External consumers (`TextDoc::delete_and_record`, `TextDoc::delete_range_and_record`) call `get_visible_items()` and access individual `(Lv, Item[String])` tuples by index. We keep this public API returning the same type but rebuild it from the compressed cache.

- [ ] **Step 1: Rewrite get_visible_items**

Replace (lines 448-454):
```moonbit
///|
/// Get visible items from the tree (returns a copy for safety).
pub fn Document::get_visible_items(
  self : Document,
) -> Array[(@fugue.Lv, @fugue.Item[String])] {
  // Return a copy to prevent callers from mutating internal cache
  self.get_position_cache().copy()
}
```

With:
```moonbit
///|
/// Get visible items from the tree.
///
/// Expands the compressed Rle[VisibleRun] cache back into the full
/// Array[(Lv, Item[String])] format that external consumers expect.
/// This is O(n) but only called by external consumers that need
/// per-item access (TextDoc undo helpers).
pub fn Document::get_visible_items(
  self : Document,
) -> Array[(@fugue.Lv, @fugue.Item[String])] {
  // Delegate to tree traversal directly — the compressed cache
  // doesn't store enough information to reconstruct full Item structs
  // (missing parent, side, timestamp, agent fields).
  self.tree.get_visible_items()
}
```

**Design rationale:** The compressed `VisibleRun` only stores `start_lv`, `text`, and `count` — it intentionally omits `parent`, `side`, `timestamp`, `agent`, and `deleted` fields to maximize compression. Reconstructing full `Item[String]` structs from `VisibleRun` would require looking up each item in the FugueTree anyway, which defeats the purpose. Instead, we delegate to the tree traversal directly. This is the same O(n) cost as before, but it's only triggered by external consumers that genuinely need per-item data.

**Known regression:** `delete_and_record` in `undo_helpers.mbt` snapshots items via `get_visible_items()` (tree traversal), then calls `delete()` which rebuilds the compressed cache (another tree traversal). Previously the cache from `get_visible_items` was reused. This 2x traversal regression is acceptable for now but could be mitigated by having `get_visible_items` also populate the compressed cache.

- [ ] **Step 2: Verify compilation**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker && moon check
```

---

### Task 7: Update internal consumers (insert, delete, delete_range)

**Files:**
- Modify: `event-graph-walker/internal/document/document.mbt`

The `insert`, `delete`, and `delete_range` methods currently call `get_position_cache()` and access items by array index for two purposes:
1. **position_to_lv** — already migrated to use compressed cache (Task 4)
2. **origin_right lookup** in `insert` — needs the LV at a specific position
3. **target LV lookup** in `delete`/`delete_range` — needs the LV at a specific position

All of these can be served by a helper that extracts the LV at a given position from the compressed cache.

- [ ] **Step 1: Add lv_at_position helper**

Add this helper function to `event-graph-walker/internal/document/document.mbt` (after the `get_compressed_cache` function):

```moonbit
///|
/// Get the LV at a specific 0-based visible position.
///
/// Returns None if position is out of bounds.
/// Uses O(log n) binary search via Rle::find on the compressed cache.
fn Document::lv_at_position(self : Document, position : Int) -> Int? {
  let cache = self.get_compressed_cache()
  match cache.find(position) {
    Some(rp) =>
      match cache.get(rp.run) {
        Some(run) => Some(run.start_lv + rp.offset)
        None => None
      }
    None => None
  }
}
```

- [ ] **Step 2: Rewrite Document::insert to use compressed cache**

Replace the `insert` function (lines 112-199). The key change is replacing `items_list[0]`, `items_list[current_pos]` with `lv_at_position`:

```moonbit
///|
/// Insert text at a cursor position.
///
/// Splits multi-character strings into individual character operations.
/// Returns the last operation created (or a no-op for empty strings).
pub fn Document::insert(
  self : Document,
  position : Int,
  text : String,
) -> @core.Op raise DocumentError {
  // Insert each character one by one
  let mut current_pos = position
  let mut last_op : @core.Op? = None

  // Iterate through each character in the string
  for i = 0; i < text.length(); i = i + 1 {
    // Extract single character as string
    let ch = text[i:i + 1].to_string()

    // Map position to LV using compressed cache (O(log n))
    let origin_left = self.position_to_lv(current_pos)

    // Find origin_right (the item after the cursor)
    let origin_right = if current_pos == 0 {
      // At start, find first visible item
      match self.lv_at_position(0) {
        Some(lv) => lv
        None => -1
      }
    } else {
      match self.lv_at_position(current_pos) {
        Some(lv) => lv
        None => -1
      }
    }

    // Create and apply the operation for this character
    let op = self.oplog.insert(ch, origin_left, origin_right) catch {
      e => raise DocumentError::OpLog(e)
    }

    // Get Lamport timestamp and agent from causal graph for proper ordering
    let (timestamp, agent) = match self.oplog.causal_graph()[op.lv()] {
      Some(entry) => (entry.timestamp, entry.agent)
      None =>
        raise DocumentError::OpLog(
          @oplog.OpLogError::MissingLocalVersion(lv=op.lv()),
        )
    }

    // Apply to tree and invalidate cache
    self.tree.insert({
      id: @fugue.Lv(op.lv()),
      content: ch,
      origin_left: if origin_left == -1 {
        None
      } else {
        Some(@fugue.Lv(origin_left))
      },
      origin_right: if origin_right == -1 {
        None
      } else {
        Some(@fugue.Lv(origin_right))
      },
      timestamp: @fugue.Timestamp(timestamp),
      agent: @fugue.ReplicaId(agent),
    })
    self.invalidate_cache()

    last_op = Some(op)
    current_pos = current_pos + 1
  }

  // Return the last operation (or create a dummy one if text was empty)
  match last_op {
    Some(op) => op
    None =>
      // Empty string inserted - create a no-op
      // This shouldn't happen in practice, but we need to return something
      self.oplog.insert("", -1, -1) catch {
        e => raise DocumentError::OpLog(e)
      }
  }
}
```

**Key change:** Removed the `items_list` variable and the explicit cache rebuild after each character (`items_list = self.get_position_cache()`). Now each iteration calls `position_to_lv` and `lv_at_position` which internally call `get_compressed_cache()`, which lazily rebuilds the compressed cache after `invalidate_cache()`. This is equivalent behavior but uses the compressed cache path.

- [ ] **Step 3: Rewrite Document::delete to use compressed cache**

Replace the `delete` function (lines 205-233):

```moonbit
///|
/// Delete the character at a cursor position.
///
/// Raises `InvalidPosition` if the position is negative or beyond the last character.
pub fn Document::delete(
  self : Document,
  position : Int,
) -> @core.Op raise DocumentError {
  if position < 0 {
    raise DocumentError::InvalidPosition(pos=position)
  }

  // Use compressed cache for O(log n) lookup
  let cache = self.get_compressed_cache()
  let total = @rle.Spanning::span(cache)
  if position >= total {
    raise DocumentError::InvalidPosition(pos=position)
  }

  // Get the LV of the item to delete
  let target_lv = match self.lv_at_position(position) {
    Some(lv) => lv
    None => raise DocumentError::InvalidPosition(pos=position)
  }

  // Create and apply delete operation
  let op = self.oplog.delete(target_lv) catch {
    e => raise DocumentError::OpLog(e)
  }
  self.tree.delete(@fugue.Lv(target_lv)) catch {
    e => raise DocumentError::Fugue(e)
  }

  // Invalidate cache after modification
  self.invalidate_cache()
  op
}
```

- [ ] **Step 4: Rewrite Document::delete_range to use compressed cache**

Replace the `delete_range` function (lines 237-269):

```moonbit
///|
/// Delete the half-open range `[start, end)`.
pub fn Document::delete_range(
  self : Document,
  start : Int,
  end : Int,
) -> Unit raise DocumentError {
  if start < 0 {
    raise DocumentError::InvalidPosition(pos=start)
  }
  if end < start {
    raise DocumentError::InvalidPosition(pos=end)
  }

  let cache = self.get_compressed_cache()
  let total = @rle.Spanning::span(cache)
  if end > total {
    raise DocumentError::InvalidPosition(pos=end)
  }
  if start == end {
    return
  }

  // Collect all LVs in the range before mutating.
  // We need to snapshot them because the cache is invalidated after
  // the first delete.
  let target_lvs : Array[Int] = []
  for i = start; i < end; i = i + 1 {
    match self.lv_at_position(i) {
      Some(lv) => target_lvs.push(lv)
      None => raise DocumentError::InvalidPosition(pos=i)
    }
  }

  // Invalidate before the first mutation so exception paths cannot leave a
  // stale cache behind.
  self.invalidate_cache()
  for lv in target_lvs {
    let _ = self.oplog.delete(lv) catch {
      e => raise DocumentError::OpLog(e)
    }
    self.tree.delete(@fugue.Lv(lv)) catch {
      e => raise DocumentError::Fugue(e)
    }
  }
}
```

**Key change:** Instead of accessing `items_list[i]` in a loop (which relied on the old uncompressed cache), we collect target LVs first using `lv_at_position` (O(log n) each, O(k log n) total for k deletes), then perform all mutations. This avoids relying on a stale snapshot array.

- [ ] **Step 5: Verify compilation**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker && moon check
```

- [ ] **Step 6: Format and update interfaces**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker && moon info && moon fmt
```

- [ ] **Step 7: Commit inside submodule**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker
git add internal/document/document.mbt internal/document/pkg.generated.mbti
git commit -m "feat(document): use Rle[VisibleRun] for compressed position cache (Phase 2)

Replace Array[(Lv, Item[String])] position_cache with Rle[VisibleRun].
- position_to_lv: O(1) → O(log n) via Rle::find
- lv_to_position: O(n) → O(k) where k = number of runs
- insert/delete/delete_range: use lv_at_position helper
- get_visible_items: delegates to tree traversal for external consumers
- Cache memory reduced for single-author documents (50K items → ~1 run)"
```

---

### Task 8: Run full test suite and verify correctness

**Files:** (no changes — verification only)

- [ ] **Step 1: Run document package tests**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker && moon test -p dowdiness/event-graph-walker/internal/document
```

Expected: All tests pass, including:
- `position_to_lv returns -1 at start of empty document`
- `position_to_lv returns correct LV for positions`
- `position_to_lv handles position beyond end`
- `cache coherent after insert: position_to_lv reflects new character`
- `cache coherent after delete: position_to_lv skips deleted character`
- `cache coherent after undelete: revived item appears in position_to_lv`
- `cache coherent after delete_by_lv: deleted item absent from positions`
- `cache coherent: position_to_lv matches get_visible_items after each op`
- All blackbox tests in `document_test.mbt`
- All VisibleRun tests in `visible_run_wbtest.mbt`

- [ ] **Step 2: Run full event-graph-walker test suite**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker && moon test
```

Expected: All tests pass. Key packages to watch:
- `internal/document` — position cache changes
- `text` — uses `get_visible_items()` in undo helpers
- `undo` — calls `lv_to_position()` via Undoable trait

- [ ] **Step 3: Run root crdt module tests**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0 && moon test
```

Expected: All tests pass.

- [ ] **Step 4: Update snapshots if needed**

If any snapshot tests show changed output (e.g., `Show` output for Document which now contains `Rle[VisibleRun]?` instead of `Array[...]?`):

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker && moon test --update
```

Then review the snapshot diffs to verify they are expected:
```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker && git diff
```

- [ ] **Step 5: Verify .mbti interface**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker && moon info
```

Check that the public API of `document` package is unchanged:
```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker && git diff internal/document/pkg.generated.mbti
```

The public API should be identical — `Document::get_visible_items` still returns `Array[(@fugue.Lv, @fugue.Item[String])]`, `Document::lv_to_position` still returns `Int?`. The only expected change is the new `dowdiness/rle` import in the mbti header.

- [ ] **Step 6: Commit snapshot updates if any**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker
git add internal/document/*.mbt internal/document/*.mbti
git diff --cached --stat
git commit -m "test(document): update snapshots for Rle[VisibleRun] position cache"
```

Only run this if Step 4 produced changes.

---

### Task 9: Final commit in parent repo

**Files:**
- Modify: parent repo submodule pointer for `event-graph-walker`

- [ ] **Step 1: Stage and commit in parent repo**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0
git add event-graph-walker
git commit -m "chore: update event-graph-walker submodule (Phase 2: VisibleRun compression)"
```

- [ ] **Step 2: Verify final state**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0
git status
git submodule status event-graph-walker
```

Expected: Clean working tree, submodule pointer updated.
