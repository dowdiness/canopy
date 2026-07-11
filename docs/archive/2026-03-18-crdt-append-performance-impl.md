# CRDT Text Append Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce 1000-char sequential append from 3.79s to under 1s by adding a children index, cursor fast-path, batch cache invalidation, and LCA index to the FugueTree/Document in event-graph-walker.

**Architecture:** Four optimization layers applied bottom-up in event-graph-walker submodule. Step 1 (children index) eliminates O(n) child scans. Step 2 (cursor) + Step 3 (batch invalidation) eliminate per-char cache rebuilds for sequential appends. Step 4 (LCA index) accelerates concurrent/remote ancestor queries. Each step is benchmarked independently.

**Tech Stack:** MoonBit, `@immut/hashmap.HashMap`, `@rle.Rle`, `@qc` for property tests

**Spec:** `docs/plans/2026-03-18-crdt-append-performance.md`

---

### Task 0: Capture Baseline Benchmark

- [ ] **Step 1: Run baseline benchmark before any code changes**

Run: `cd event-graph-walker && moon bench --release 2>&1 | tee /tmp/bench-baseline.txt`
Record the key metrics (especially `text - insert append (1000 chars)`, `text - insert append (100 chars)`, `text - insert prepend (100 chars)`) as the baseline for comparison.

---

### Task 1: Children Index

**Files:**
- Modify: `event-graph-walker/internal/fugue/tree.mbt` (struct + add_item + get_children + traverse_tree)
- Test: `event-graph-walker/internal/fugue/tree_test.mbt`
- Test: `event-graph-walker/internal/fugue/tree_properties_test.mbt`

- [ ] **Step 1: Write failing test — children index matches filtered scan**

Add to `event-graph-walker/internal/fugue/tree_test.mbt`:

```moonbit
///|
test "children index matches filtered scan" {
  let tree : @fugue.FugueTree[String] = @fugue.FugueTree::new()
  // Build a tree: A -> B -> C, with D also child of A
  tree.insert(ins(0, "A", -1, -1, 0, "agent0"))
  tree.insert(ins(1, "B", 0, -1, 1, "agent0"))
  tree.insert(ins(2, "C", 1, -1, 2, "agent0"))
  tree.insert(ins(3, "D", 0, -1, 3, "agent1"))
  // A (id=0) should have children: B (id=1) and D (id=3)
  let children_of_a = tree.get_children_index(@fugue.Lv(0))
  inspect(children_of_a.length(), content="2")
  // B (id=1) should have child: C (id=2)
  let children_of_b = tree.get_children_index(@fugue.Lv(1))
  inspect(children_of_b.length(), content="1")
  // C has no children
  let children_of_c = tree.get_children_index(@fugue.Lv(2))
  inspect(children_of_c.length(), content="0")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd event-graph-walker && moon test --package internal/fugue -f "children index matches filtered scan"`
Expected: FAIL — `get_children_index` method does not exist

- [ ] **Step 3: Add children field to FugueTree struct**

Modify `event-graph-walker/internal/fugue/tree.mbt` lines 7-11. Add `children` field:

```moonbit
pub struct FugueTree[T] {
  mut items : @immut/hashmap.HashMap[Lv, Item[T]]
  mut length : Int
  mut visible : Int
  mut children : @immut/hashmap.HashMap[Lv, Array[Lv]]
} derive(Show)
```

Update `FugueTree::new()` (lines 25-27) and `FugueTree::make()` (lines 33-45) to initialize `children`:

```moonbit
// In new():
children: @immut/hashmap.HashMap::new()

// In make(): add root_lv entry
children: @immut/hashmap.HashMap::new().add(root_lv, [])
```

- [ ] **Step 4: Update add_item to maintain children index**

Modify `event-graph-walker/internal/fugue/tree.mbt` `add_item` (lines 327-337):

```moonbit
fn[T] FugueTree::add_item(self : FugueTree[T], item : Item[T]) -> Unit {
  self.items = self.items.add(item.id, item)
  self.length = self.length + 1
  self.visible = self.visible + 1
  // Maintain children index
  match item.parent {
    Some(parent_lv) =>
      match self.children.get(parent_lv) {
        Some(arr) => arr.push(item.id)
        None => self.children = self.children.add(parent_lv, [item.id])
      }
    None => ()
  }
  // Ensure this node has an entry (even if no children yet)
  match self.children.get(item.id) {
    Some(_) => ()
    None => self.children = self.children.add(item.id, [])
  }
}
```

- [ ] **Step 5: Add get_children_index public method**

Add to `event-graph-walker/internal/fugue/tree.mbt`:

```moonbit
///|
/// Returns a copy of the children array for a given parent.
/// Returns empty array if the parent has no children or is unknown.
pub fn[T] FugueTree::get_children_index(
  self : FugueTree[T],
  parent_id : Lv,
) -> Array[Lv] {
  match self.children.get(parent_id) {
    Some(arr) => arr.copy()
    None => []
  }
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `cd event-graph-walker && moon test --package internal/fugue -f "children index matches filtered scan"`
Expected: PASS

- [ ] **Step 7: Write test — same-parent different-side children**

Add to `event-graph-walker/internal/fugue/tree_test.mbt`:

```moonbit
///|
test "children index: same parent, different sides" {
  let tree : @fugue.FugueTree[String] = @fugue.FugueTree::new()
  // "AC" then insert B between A and C
  tree.insert(ins(0, "A", -1, -1, 0, "agent0"))
  tree.insert(ins(2, "C", 0, -1, 2, "agent0"))
  // B: origin_left=A, origin_right=C -> Left child of C (since A is ancestor of C)
  tree.insert(ins(1, "B", 0, 2, 1, "agent1"))
  // Text should be ABC
  inspect(tree.to_text(), content="ABC")
  // C (id=2) has left child B; A (id=0) has right child C
  let children_of_c = tree.get_children_index(@fugue.Lv(2))
  inspect(children_of_c.length(), content="1")
}
```

- [ ] **Step 8: Run test**

Run: `cd event-graph-walker && moon test --package internal/fugue -f "children index: same parent, different sides"`
Expected: PASS

- [ ] **Step 9: Refactor partition_children to accept Array and replace get_children in traverse_tree**

The current `partition_children` (lines 492-504) takes `@immut/hashmap.HashMap[Lv, Item[T]]`. Refactor it to accept `Array[(Lv, Item[T])]` instead, since both the children index path and the old path can produce arrays:

**Replace `partition_children` (lines 492-504):**
```moonbit
///|
/// Partition children into left and right sides
fn[T] partition_children(
  children : Array[(Lv, Item[T])],
) -> (Array[(Lv, Item[T])], Array[(Lv, Item[T])]) {
  let left = []
  let right = []
  for child in children {
    let (_, item) = child
    match item.side {
      Left => left.push(child)
      Right => right.push(child)
    }
  }
  (left, right)
}
```

**Replace `traverse_tree` line 516 (`let children = self.get_children(node_id)`) and line 519 (`let (left_children, right_children) = partition_children(children)`):**
```moonbit
  // Use children index instead of filtering entire HashMap (O(1) vs O(n))
  let child_lvs = self.get_children_index(node_id)
  let children_with_items : Array[(Lv, Item[T])] = []
  for lv in child_lvs {
    match self[lv] {
      Some(item) => children_with_items.push((lv, item))
      None => ()
    }
  }

  // Split into left and right children
  let (left_children, right_children) = partition_children(children_with_items)
```

The rest of `traverse_tree` (sorting, recursion, node visit) remains unchanged — it already works with `Array[(Lv, Item[T])]`.

**Note:** After this change, `get_children()` is no longer called anywhere. It can be kept for debugging or removed. Do not remove it yet — verify all tests pass first.

- [ ] **Step 10: Run all existing tests**

Run: `cd event-graph-walker && moon test`
Expected: All 291 tests pass

- [ ] **Step 11: Run all parent repo tests**

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy && moon test`
Expected: All tests pass

- [ ] **Step 12: Benchmark baseline before children index**

Run: `cd event-graph-walker && moon bench --release 2>&1 | tee /tmp/bench-pre-step1.txt`
Save results to `event-graph-walker/docs/benchmarks/2026-03-18-step1-children-index.md` with "Before" section.

- [ ] **Step 13: Benchmark after children index**

Run: `cd event-graph-walker && moon bench --release 2>&1 | tee /tmp/bench-post-step1.txt`
Append results to `event-graph-walker/docs/benchmarks/2026-03-18-step1-children-index.md` with "After" section.
Compute deltas for key benchmarks: `text - insert append (1000 chars)`, `text - insert append (100 chars)`, `text - insert prepend (100 chars)`.

- [ ] **Step 14: Commit**

```bash
cd event-graph-walker
git add internal/fugue/tree.mbt internal/fugue/tree_test.mbt docs/benchmarks/2026-03-18-step1-children-index.md
moon info && moon fmt
git add -A
git commit -m "perf(fugue): add children index to FugueTree for O(1) child lookup"
```

---

### Task 2: Cursor Fast-Path

**Files:**
- Modify: `event-graph-walker/internal/document/document.mbt` (struct + insert)
- Test: `event-graph-walker/internal/document/document_wbtest.mbt` (whitebox — needs struct access)

- [ ] **Step 1: Write failing test — cursor produces same result as cache lookup**

Add to `event-graph-walker/internal/document/document_wbtest.mbt`:

```moonbit
///|
test "cursor fast-path: sequential append matches cache lookup" {
  let doc = Document::new("alice")
  // Insert 10 chars sequentially
  for i = 0; i < 10; i = i + 1 {
    ignore(try! doc.insert(i, "x"))
  }
  inspect(doc.to_text(), content="xxxxxxxxxx")
  // Verify cursor is populated after sequential inserts
  match doc.cursor {
    Some(c) => {
      inspect(c.position, content="9")
      inspect(c.at_end, content="true")
    }
    None => fail("Expected cursor to be set after sequential append")
  }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd event-graph-walker && moon test --package internal/document -f "cursor fast-path"`
Expected: FAIL — `cursor` field does not exist on Document

- [ ] **Step 3: Add InsertCursor struct and cursor field to Document**

Add to `event-graph-walker/internal/document/document.mbt`:

```moonbit
///|
/// Cursor for fast sequential append. Caches the last insert position
/// and LV to skip position_to_lv() on the next sequential insert.
struct InsertCursor {
  position : Int    // last insert position (0-based)
  lv : Int          // LV of last inserted item
  at_end : Bool     // whether origin_right was None (end of document)
}
```

Add `cursor` field to Document struct (lines 9-16):

```moonbit
pub struct Document {
  priv tree : @fugue.FugueTree[String]
  priv oplog : @oplog.OpLog
  agent_id : String
  priv mut position_cache : @rle.Rle[VisibleRun]?
  priv mut cursor : InsertCursor?
} derive(Show)
```

Initialize `cursor: None` in `Document::new()` and `Document::from_oplog()`.

- [ ] **Step 4: Implement cursor logic in Document.insert()**

Modify `event-graph-walker/internal/document/document.mbt` `insert()` (lines 131-192) **incrementally** — do not rewrite the function. Only change the `origin_left` and `origin_right` computation at the top of the loop body. Keep the existing oplog/tree insert code, error handling, and empty-string handling unchanged.

**Before (existing code, lines ~141-149):**
```moonbit
    let origin_left = self.position_to_lv(current_pos)
    let origin_right = match self.lv_at_position(current_pos) {
      Some(lv) => lv
      None => -1
    }
```

**After (replace those lines with cursor check):**
```moonbit
    // Cursor fast-path: skip cache lookup for sequential append
    let (origin_left, origin_right) = match self.cursor {
      Some(c) if current_pos == c.position + 1 => {
        let ol = c.lv
        let or = if c.at_end {
          -1  // origin_right = None (end of document)
        } else {
          // Partial hit: still need cache for origin_right
          self.invalidate_cache()  // stale from prior iteration
          match self.lv_at_position(current_pos) {
            Some(lv) => lv
            None => -1
          }
        }
        (ol, or)
      }
      _ => {
        // Cursor miss: full cache lookup (existing code)
        let ol = self.position_to_lv(current_pos)
        let or = match self.lv_at_position(current_pos) {
          Some(lv) => lv
          None => -1
        }
        (ol, or)
      }
    }
```

**Also add cursor update after the existing `self.invalidate_cache()` call (line ~179):**
```moonbit
    self.invalidate_cache()
    // Update cursor
    self.cursor = Some({
      position: current_pos,
      lv: op.lv(),
      at_end: origin_right == -1,
    })
```

**Important:** Keep all existing code (oplog insert, causal graph lookup, tree insert, error handling, empty-string case) exactly as-is. Only add the cursor check around origin computation and the cursor update after cache invalidation.

Note: The cursor partial-hit path calls `self.invalidate_cache()` before `lv_at_position()` to prevent reading a stale cache from the prior iteration's insert.

- [ ] **Step 5: Invalidate cursor on non-insert mutations**

Add `self.cursor = None` at the start of these methods in `document.mbt`:
- `delete_range()` (line ~238)
- `replace_range()` (line ~289)
- `apply_remote()` (line ~354)
- `undelete()` / `delete_by_lv()` if they exist

Search for all calls to `invalidate_cache()` and add `self.cursor = None` alongside them for any non-insert path.

- [ ] **Step 6: Run test to verify it passes**

Run: `cd event-graph-walker && moon test --package internal/document -f "cursor fast-path"`
Expected: PASS

- [ ] **Step 7: Write test — cursor invalidation on delete**

Add to `event-graph-walker/internal/document/document_wbtest.mbt`:

```moonbit
///|
test "cursor invalidated on delete" {
  let doc = Document::new("alice")
  for i = 0; i < 5; i = i + 1 {
    ignore(try! doc.insert(i, "x"))
  }
  // Cursor should be set
  inspect(doc.cursor.is_empty(), content="false")
  // Delete clears cursor
  try! doc.delete_range(2, 3)
  inspect(doc.cursor.is_empty(), content="true")
}
```

- [ ] **Step 8: Run test**

Run: `cd event-graph-walker && moon test --package internal/document -f "cursor invalidated on delete"`
Expected: PASS

- [ ] **Step 9: Write test — mid-document sequential insert (partial cursor hit)**

Add to `event-graph-walker/internal/document/document_wbtest.mbt`:

```moonbit
///|
test "cursor partial hit: mid-document sequential insert" {
  let doc = Document::new("alice")
  // Insert "abcde"
  ignore(try! doc.insert(0, "a"))
  ignore(try! doc.insert(1, "b"))
  ignore(try! doc.insert(2, "c"))
  ignore(try! doc.insert(3, "d"))
  ignore(try! doc.insert(4, "e"))
  inspect(doc.to_text(), content="abcde")
  // Now delete at position 3 to break cursor
  try! doc.delete_range(3, 4)
  inspect(doc.to_text(), content="abce")
  // Insert at position 2 (not sequential from last)
  ignore(try! doc.insert(2, "X"))
  inspect(doc.to_text(), content="abXce")
  // Insert at position 3 (sequential from position 2)
  ignore(try! doc.insert(3, "Y"))
  inspect(doc.to_text(), content="abXYce")
}
```

- [ ] **Step 10: Run all tests**

Run: `cd event-graph-walker && moon test`
Expected: All tests pass

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy && moon test`
Expected: All tests pass

- [ ] **Step 11: Benchmark**

Run: `cd event-graph-walker && moon bench --release 2>&1 | tee /tmp/bench-post-step2.txt`
Save results to `event-graph-walker/docs/benchmarks/2026-03-18-step2-cursor-fast-path.md`.
Compare with Step 1 results.

- [ ] **Step 12: Commit**

```bash
cd event-graph-walker
moon info && moon fmt
git add internal/document/document.mbt internal/document/document_wbtest.mbt docs/benchmarks/2026-03-18-step2-cursor-fast-path.md
git add -A
git commit -m "perf(document): add cursor fast-path for sequential append"
```

---

### Task 3: Batch Cache Invalidation

**Files:**
- Modify: `event-graph-walker/internal/document/document.mbt` (insert loop)
- Test: `event-graph-walker/internal/document/document_test.mbt`

- [ ] **Step 1: Write failing test — multi-char insert at non-end position**

Add to `event-graph-walker/internal/document/document_test.mbt`:

```moonbit
///|
test "multi-char insert at non-end position" {
  let doc = @document.Document::new("alice")
  // Insert "hello"
  for i = 0; i < 5; i = i + 1 {
    let ch = "hello"[i:i+1].to_string()
    ignore(try! doc.insert(i, ch))
  }
  inspect(doc.to_text(), content="hello")
  // Insert "XY" at position 2 (between 'l' and 'l')
  ignore(try! doc.insert(2, "X"))
  ignore(try! doc.insert(3, "Y"))
  inspect(doc.to_text(), content="heXYllo")
}
```

- [ ] **Step 2: Run test — should pass (establishes correctness baseline)**

Run: `cd event-graph-walker && moon test --package internal/document -f "multi-char insert at non-end position"`
Expected: PASS (this test establishes correctness before we change the invalidation pattern)

- [ ] **Step 3: Move invalidate_cache() out of the insert loop**

Modify `Document.insert()` in `event-graph-walker/internal/document/document.mbt`. The cursor logic from Task 2 already handles the per-char flow. Now change the invalidation:

```moonbit
// In the insert loop, replace:
//   self.invalidate_cache()
// with:
//   // On cursor miss, invalidate before next iteration's cache read
//   // On cursor hit, skip invalidation (cache not read)

// After the loop:
self.invalidate_cache()
```

Specifically: if the cursor was hit (sequential append), the cache was never read, so no per-iteration invalidation needed. If the cursor missed, `position_to_lv()` / `lv_at_position()` already triggered `get_compressed_cache()` which rebuilds from `None`. The key change: only call `invalidate_cache()` once after the loop.

For safety on cursor miss: the `get_compressed_cache()` call rebuilds the cache from the current tree state. After inserting a char and before the next iteration's cache read, the cache is stale. But `get_compressed_cache()` checks `self.position_cache` — if it's `Some`, it returns the cached version (stale!). So on cursor miss, we must still invalidate before the next read.

The cursor logic from Task 2 Step 4 already handles invalidation correctly for all three cases:

- **Cursor full hit** (`at_end = true`): No cache read → no invalidation needed inside loop
- **Cursor partial hit** (`at_end = false`): Calls `self.invalidate_cache()` before `lv_at_position()` (added in Task 2 Step 4) → stale cache cleared before read
- **Cursor miss**: Calls `position_to_lv()` and `lv_at_position()` which read the cache via `get_compressed_cache()` — the existing `self.invalidate_cache()` call (which was after the tree insert) ensures freshness for the next iteration

**Change:** Remove the per-iteration `self.invalidate_cache()` call that currently happens after every tree insert (line ~179). Replace with a single call after the loop:

```moonbit
    // REMOVE this line from inside the loop:
    // self.invalidate_cache()  // <-- delete this

    // Keep the cursor update (added in Task 2):
    self.cursor = Some({ ... })

    last_op = Some(op)
    current_pos = current_pos + 1
  }
  // Single invalidation after the loop
  self.invalidate_cache()
```

This is safe because:
- Cursor full hit: cache never read, stale cache is irrelevant
- Cursor partial hit: explicitly invalidates before `lv_at_position()` (Task 2 Step 4)
- Cursor miss: explicitly invalidates before `position_to_lv()` / `lv_at_position()` in the miss branch (the miss branch falls through to existing cache-reading code which calls `get_compressed_cache()` — but the cache is stale from the prior iteration). **Fix:** Also add `self.invalidate_cache()` at the top of the cursor-miss branch:

```moonbit
      _ => {
        // Cursor miss: invalidate stale cache from prior iteration
        self.invalidate_cache()
        let ol = self.position_to_lv(current_pos)
        let or = match self.lv_at_position(current_pos) {
          Some(lv) => lv
          None => -1
        }
        (ol, or)
      }
```

This ensures all three paths invalidate before any cache read. The final `self.invalidate_cache()` after the loop ensures the cache reflects the final state for any subsequent external read.

- [ ] **Step 4: Run the multi-char non-end test**

Run: `cd event-graph-walker && moon test --package internal/document -f "multi-char insert at non-end position"`
Expected: PASS

- [ ] **Step 5: Run all tests**

Run: `cd event-graph-walker && moon test`
Expected: All tests pass

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy && moon test`
Expected: All tests pass

- [ ] **Step 6: Benchmark**

Run: `cd event-graph-walker && moon bench --release 2>&1 | tee /tmp/bench-post-step3.txt`
Save to `event-graph-walker/docs/benchmarks/2026-03-18-step3-batch-invalidation.md`.
Compare with Step 2 results. **This + Step 2 together should show the biggest improvement on the append benchmark.**

- [ ] **Step 7: Commit**

```bash
cd event-graph-walker
moon info && moon fmt
git add internal/document/document.mbt internal/document/document_test.mbt docs/benchmarks/2026-03-18-step3-batch-invalidation.md
git add -A
git commit -m "perf(document): batch cache invalidation in insert loop"
```

---

### Task 4: LCA Index

**Files:**
- Create: `event-graph-walker/internal/fugue/lca_index.mbt`
- Create: `event-graph-walker/internal/fugue/lca_index_wbtest.mbt`
- Modify: `event-graph-walker/internal/fugue/tree.mbt` (is_ancestor, batch_inserting flag)
- Modify: `event-graph-walker/internal/branch/branch.mbt` (checkout, advance — set flag)
- Modify: `event-graph-walker/internal/branch/branch_merge.mbt` (apply_operations — set flag)
- Modify: `event-graph-walker/internal/document/document.mbt` (apply_remote — set flag)
- Test: `event-graph-walker/internal/fugue/tree_properties_test.mbt`

- [ ] **Step 1: Write failing test — LCA is_ancestor matches naive walk**

Add to `event-graph-walker/internal/fugue/tree_properties_test.mbt`:

```moonbit
///|
/// Property: LCA-based is_ancestor matches naive parent-walk
fn prop_lca_matches_naive(chain : ChainLen) -> Bool {
  let tree : @fugue.FugueTree[String] = @fugue.FugueTree::new()
  // Build a chain: 0 -> 1 -> 2 -> ... -> (len-1)
  tree.insert({
    id: @fugue.Lv(0),
    content: "A",
    origin_left: None,
    origin_right: None,
    timestamp: @fugue.Timestamp(0),
    agent: @fugue.ReplicaId("agent0"),
  })
  for i = 1; i < chain.len; i = i + 1 {
    tree.insert({
      id: @fugue.Lv(i),
      content: "A",
      origin_left: Some(@fugue.Lv(i - 1)),
      origin_right: None,
      timestamp: @fugue.Timestamp(i),
      agent: @fugue.ReplicaId("agent0"),
    })
  }
  // Force LCA index build
  tree.build_lca_index()
  // Check all pairs (a, b) where a <= b
  // Compare is_ancestor_lca() against is_ancestor_naive() (the original parent-walk)
  // NOT is_ancestor() which after Step 8 will also use LCA — that would be tautological
  for a = 0; a < chain.len; a = a + 1 {
    for b = a; b < chain.len; b = b + 1 {
      let lca_result = tree.is_ancestor_lca(@fugue.Lv(a), @fugue.Lv(b))
      let naive_result = tree.is_ancestor_naive(@fugue.Lv(a), @fugue.Lv(b))
      if lca_result != naive_result {
        return false
      }
    }
  }
  true
}

///|
test "property: LCA is_ancestor matches naive walk" {
  @qc.quick_check_fn(prop_lca_matches_naive)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd event-graph-walker && moon test --package internal/fugue -f "property: LCA is_ancestor matches naive walk"`
Expected: FAIL — `build_lca_index` and `is_ancestor_lca` don't exist

- [ ] **Step 3: Create LcaIndex struct and build function**

Create `event-graph-walker/internal/fugue/lca_index.mbt`:

```moonbit
///| LCA Index — Euler Tour + Sparse Table for O(1) ancestor queries.
///
/// Build: O(n log n) — DFS producing Euler tour, then sparse table.
/// Query: O(1) — range minimum query on the tour.

///|
struct LcaIndex {
  euler_tour : Array[Lv]          // node at each tour step
  depth : Array[Int]              // depth at each tour step
  first : @immut/hashmap.HashMap[Lv, Int]  // first occurrence in tour
  sparse : Array[Array[Int]]     // sparse table for RMQ (stores indices)
  tour_len : Int
} derive(Show)

///|
/// Build LCA index from a FugueTree using the children index.
/// Prerequisite: FugueTree must have a populated children index (Step 1).
fn[T : Eq] LcaIndex::build(tree : FugueTree[T]) -> LcaIndex {
  let n = tree.length + 1  // +1 for virtual root
  let euler_tour : Array[Lv] = []
  let depth_arr : Array[Int] = []
  let mut first = @immut/hashmap.HashMap::new()

  // DFS from root
  fn dfs(node_id : Lv, d : Int) {
    let idx = euler_tour.length()
    euler_tour.push(node_id)
    depth_arr.push(d)
    match first.get(node_id) {
      None => first = first.add(node_id, idx)
      Some(_) => ()  // already recorded
    }
    // Visit children using children index
    let child_lvs = tree.get_children_index(node_id)
    for child_lv in child_lvs {
      dfs(child_lv, d + 1)
      euler_tour.push(node_id)
      depth_arr.push(d)
    }
  }

  dfs(root_lv, 0)

  // Build sparse table
  let tour_len = euler_tour.length()
  let log_n = if tour_len <= 1 { 1 } else { log2_floor(tour_len) + 1 }
  let sparse : Array[Array[Int]] = []

  // Level 0: each element is its own minimum
  let level0 : Array[Int] = Array::make(tour_len, 0)
  for i = 0; i < tour_len; i = i + 1 {
    level0[i] = i
  }
  sparse.push(level0)

  // Higher levels
  for k = 1; k < log_n; k = k + 1 {
    let prev = sparse[k - 1]
    let range = 1 << k  // 2^k
    let len = if tour_len >= range { tour_len - range + 1 } else { 0 }
    let level : Array[Int] = Array::make(len, 0)
    let half = range / 2
    for i = 0; i < len; i = i + 1 {
      let left = prev[i]
      let right = prev[i + half]
      level[i] = if depth_arr[left] <= depth_arr[right] { left } else { right }
    }
    sparse.push(level)
  }

  { euler_tour, depth: depth_arr, first, sparse, tour_len }
}

///|
/// Floor of log base 2.
fn log2_floor(n : Int) -> Int {
  let mut result = 0
  let mut val = n
  while val > 1 {
    val = val >> 1
    result = result + 1
  }
  result
}

///|
/// Query: is ancestor_id an ancestor of descendant_id?
fn LcaIndex::is_ancestor(self : LcaIndex, ancestor_id : Lv, descendant_id : Lv) -> Bool {
  if ancestor_id == descendant_id {
    return true
  }
  // Check both nodes exist in the tour
  let a_idx = match self.first.get(ancestor_id) {
    Some(idx) => idx
    None => return false
  }
  let b_idx = match self.first.get(descendant_id) {
    Some(idx) => idx
    None => return false
  }
  // RMQ to find LCA
  let lo = if a_idx < b_idx { a_idx } else { b_idx }
  let hi = if a_idx > b_idx { a_idx } else { b_idx }
  let lca_idx = self.rmq(lo, hi)
  // ancestor_id is an ancestor of descendant_id iff LCA(a, b) == ancestor_id
  self.euler_tour[lca_idx] == ancestor_id
}

///|
/// Range minimum query on depth array. Returns index in euler_tour with minimum depth.
fn LcaIndex::rmq(self : LcaIndex, lo : Int, hi : Int) -> Int {
  if lo == hi {
    return lo
  }
  let range = hi - lo + 1
  let k = log2_floor(range)
  let left = self.sparse[k][lo]
  let right = self.sparse[k][hi - (1 << k) + 1]
  if self.depth[left] <= self.depth[right] { left } else { right }
}
```

- [ ] **Step 4: Add build_lca_index and is_ancestor_lca to FugueTree**

Add to `event-graph-walker/internal/fugue/tree.mbt`:

```moonbit
///|
/// Build (or rebuild) the LCA index. Called lazily.
pub fn[T : Eq] FugueTree::build_lca_index(self : FugueTree[T]) -> Unit {
  self.lca_index = Some(LcaIndex::build(self))
}

///|
/// Query ancestor relationship using LCA index. Falls back to naive walk if
/// index is not built or during batch insert operations.
pub fn[T : Eq] FugueTree::is_ancestor_lca(
  self : FugueTree[T],
  ancestor_id : Lv,
  descendant_id : Lv,
) -> Bool {
  match self.lca_index {
    Some(idx) => idx.is_ancestor(ancestor_id, descendant_id)
    None => self.is_ancestor(ancestor_id, descendant_id)
  }
}
```

Add fields to FugueTree struct:

```moonbit
pub struct FugueTree[T] {
  mut items : @immut/hashmap.HashMap[Lv, Item[T]]
  mut length : Int
  mut visible : Int
  mut children : @immut/hashmap.HashMap[Lv, Array[Lv]]
  mut lca_index : LcaIndex?
  mut batch_inserting : Bool
} derive(Show)
```

Initialize `lca_index: None` and `batch_inserting: false` in constructors.

- [ ] **Step 5: Run property test**

Run: `cd event-graph-walker && moon test --package internal/fugue -f "property: LCA is_ancestor matches naive walk"`
Expected: PASS

- [ ] **Step 6: Write test — missing node returns false**

Add to `event-graph-walker/internal/fugue/tree_test.mbt`:

```moonbit
///|
test "LCA: missing node returns false" {
  let tree : @fugue.FugueTree[String] = @fugue.FugueTree::new()
  tree.insert(ins(0, "A", -1, -1, 0, "agent0"))
  tree.build_lca_index()
  // Query with absent LV
  inspect(tree.is_ancestor_lca(@fugue.Lv(999), @fugue.Lv(0)), content="false")
  inspect(tree.is_ancestor_lca(@fugue.Lv(0), @fugue.Lv(999)), content="false")
}
```

- [ ] **Step 7: Run test**

Run: `cd event-graph-walker && moon test --package internal/fugue -f "LCA: missing node returns false"`
Expected: PASS

- [ ] **Step 8: Integrate LCA into is_ancestor with lazy build and batch flag**

Modify `FugueTree::is_ancestor()` in `tree.mbt` (lines 355-377) to use LCA when available:

```moonbit
pub fn[T : Eq] FugueTree::is_ancestor(
  self : FugueTree[T],
  ancestor_id : Lv,
  descendant_id : Lv,
) -> Bool {
  if ancestor_id == descendant_id {
    return true
  }
  // During batch inserts, use naive walk (LCA index is stale)
  if self.batch_inserting {
    return self.is_ancestor_naive(ancestor_id, descendant_id)
  }
  // Lazy build LCA index
  match self.lca_index {
    None => {
      self.build_lca_index()
      match self.lca_index {
        Some(idx) => idx.is_ancestor(ancestor_id, descendant_id)
        None => self.is_ancestor_naive(ancestor_id, descendant_id)
      }
    }
    Some(idx) => idx.is_ancestor(ancestor_id, descendant_id)
  }
}
```

Rename the old `is_ancestor` to `is_ancestor_naive` (private).

Invalidate LCA index in `add_item()`:

```moonbit
// At end of add_item():
self.lca_index = None
```

- [ ] **Step 9: Add batch_inserting flag to batch-insert paths**

The `batch_inserting` flag must be set before and cleared after these operations. The flag should be on FugueTree, so callers that have access to the tree set it.

In `event-graph-walker/internal/branch/branch.mbt` — `checkout()` (line ~55) and `advance()` fast path (line ~93):

```moonbit
// In checkout(), before the for loop:
tree.set_batch_inserting(true)
// After the for loop:
tree.set_batch_inserting(false)

// In advance() fast path, before the for loop:
tree.set_batch_inserting(true)
// After:
tree.set_batch_inserting(false)
```

In `event-graph-walker/internal/branch/branch_merge.mbt` — `apply_operations()` (line ~27):

```moonbit
// Before the for loop:
self.tree.set_batch_inserting(true)
// After:
self.tree.set_batch_inserting(false)
```

In `event-graph-walker/internal/document/document.mbt` — `apply_remote()` (line ~354):

```moonbit
// Before applying ops to tree:
self.tree.set_batch_inserting(true)
// After:
self.tree.set_batch_inserting(false)
```

Add `set_batch_inserting` method to FugueTree:

```moonbit
///|
pub fn[T] FugueTree::set_batch_inserting(self : FugueTree[T], value : Bool) -> Unit {
  self.batch_inserting = value
  if not(value) {
    // Clear stale LCA index when batch ends
    self.lca_index = None
  }
}
```

**Error safety:** MoonBit uses `raise` for errors. Ensure the flag is cleared even if an error is raised. Use a helper or ensure `set_batch_inserting(false)` is called in all exit paths (including error paths). If MoonBit has `guard`/`defer`/`finally`, use it. Otherwise, wrap in try/catch:

```moonbit
self.tree.set_batch_inserting(true)
try {
  // ... batch insert loop ...
} catch {
  e => {
    self.tree.set_batch_inserting(false)
    raise e
  }
}
self.tree.set_batch_inserting(false)
```

- [ ] **Step 10: Run all tests**

Run: `cd event-graph-walker && moon test`
Expected: All tests pass (including convergence fuzz tests)

Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy && moon test`
Expected: All tests pass

- [ ] **Step 11: Benchmark**

Run: `cd event-graph-walker && moon bench --release 2>&1 | tee /tmp/bench-post-step4.txt`
Save to `event-graph-walker/docs/benchmarks/2026-03-18-step4-lca-index.md`.
**Expected: No change on append benchmark (is_ancestor not called for sequential append). Improvement on sync/checkout benchmarks that involve concurrent ops.**

- [ ] **Step 12: Commit**

```bash
cd event-graph-walker
moon info && moon fmt
git add internal/fugue/lca_index.mbt internal/fugue/lca_index_wbtest.mbt internal/fugue/tree.mbt internal/fugue/tree_test.mbt internal/fugue/tree_properties_test.mbt internal/branch/branch.mbt internal/branch/branch_merge.mbt internal/document/document.mbt docs/benchmarks/2026-03-18-step4-lca-index.md
git add -A
git commit -m "perf(fugue): add LCA index for O(1) ancestor queries"
```

---

### Task 5: Final Benchmark + Checkpoint

**Files:**
- Create: `event-graph-walker/docs/benchmarks/2026-03-18-performance-summary.md`

- [ ] **Step 1: Run full benchmark suite**

Run: `cd event-graph-walker && moon bench --release 2>&1 | tee /tmp/bench-final.txt`

- [ ] **Step 2: Run full test suite (both repos)**

Run: `cd event-graph-walker && moon test`
Run: `cd /home/antisatori/ghq/github.com/dowdiness/canopy && moon test`

- [ ] **Step 3: Write performance summary**

Create `event-graph-walker/docs/benchmarks/2026-03-18-performance-summary.md` with:
- Baseline vs final numbers for all tracked benchmarks
- Per-step deltas
- Assessment: is further optimization (incremental position cache) needed?

- [ ] **Step 4: Commit and push**

```bash
cd event-graph-walker
git add docs/benchmarks/2026-03-18-performance-summary.md
git commit -m "docs: add performance optimization summary"
git push origin main

cd /home/antisatori/ghq/github.com/dowdiness/canopy
git add event-graph-walker
git commit -m "chore: update event-graph-walker submodule (performance optimizations)"
git push origin main
```
