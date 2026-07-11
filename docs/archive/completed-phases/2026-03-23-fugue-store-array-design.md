# Phase 2b: Replace FugueTree HashMaps with Array-Backed Storage

**Date:** 2026-03-23
**Status:** Design
**Depends on:** Phase 2a (OrderTree position cache) — complete

## Problem

FugueTree uses `@immut/hashmap.HashMap` for both `items` (Lv → Item) and `children` (Lv → Array[Lv]). Each insert creates new HAMT nodes (copy-on-write), costing ~20ms per keystroke at 1000 items — 67% of the total pipeline cost.

### Per-keystroke breakdown at 1000 defs (~39ms)

| Component | Cost | Phase 2b target |
|-----------|------|-----------------|
| CRDT data structure ops (HashMap) | ~20ms | ~0ms (Array) |
| Position cache rebuild | ~5ms | O(log n) incremental for local ops |
| LCA index rebuild | ~5ms | Faster rebuild (Array access) |
| Parser incremental | ~2ms | unchanged |
| Projection pipeline | ~5ms | unchanged |
| SourceMap token spans | ~2ms | unchanged |

**Target:** ~1-2ms local ops, ~7ms remote batch at 1000 items.

## Design

### Rejected alternative: Unified OrderTree[DocRun]

Considered collapsing FugueTree + position cache + LCA index into a single OrderTree storing CRDT items in document order (Loro's `generic-btree` model). Rejected because:

1. **Impedance mismatch** — FugueMax operates on a logical parent-child tree; OrderTree is a flat position-indexed sequence. Converting (parent, side, sibling_index) → document position requires walking the FugueMax tree anyway.
2. **O(n) ancestor chains** — FugueMax trees can be O(n) deep (sequential typing creates long right-child chains), making subtree-size caching O(n) per insert on the common path.
3. **Overkill** — The bottleneck is immutable HashMap allocation overhead, not data structure shape. Array replacement addresses 67% of cost with minimal complexity.

Recorded as future work in TODO.md §5 for 10K+ item scale.

### Chosen approach: Array replacement + incremental position cache

Replace backing stores while keeping FugueMax algorithm unchanged. The public `FugueTree[T]` generic wrapper is preserved during migration — FugueStore is an internal specialization for `String`. Removing the generic API is deferred to avoid unnecessary churn; the hot-path improvement comes from the internal storage change, not from the public type signature.

### Data structures

#### 1. `Array[ItemMeta]` — indexed by LV

Replaces `@immut/hashmap.HashMap[Lv, Item[T]]`. LVs are sequential integers starting from 0, so a dense array gives O(1) access.

```
struct ItemMeta {
  content : String            // The character
  parent : Int                // Parent LV (-1 = root)
  side : Side                 // Left or Right
  timestamp : Int             // Lamport timestamp for sibling ordering
  agent : String              // Replica ID for tiebreaker
  mut deleted : Bool          // Tombstone flag
  mut deleted_ts : Int        // Lamport timestamp of winning Delete/Undelete
  mut deleted_agent : String  // Agent ID of winning op
  mut deleted_is_undelete : Bool  // True if winner was Undelete
}
```

- **Invariant: `lv == items.length()` at push time.** A item's LV equals its index in the array. This must be asserted on every `items.push()`. If an op is replayed out of LV order or duplicated, array storage corrupts immediately — unlike a map which would silently overwrite. Callers that need the LV (e.g., `compare_children` tiebreaker, `get_visible_items` return tuples) pass the index alongside the struct.
- Immutable fields (content, parent, side, timestamp, agent) set at insertion time
- Mutable fields (deleted_*) updated by delete/undelete operations.
- **MoonBit mutability caveat:** The assumption that `items[target].deleted = true` mutates in-place (struct stored by reference in array) must be verified with a spike test before implementation begins. If array element field mutation is unreliable, use explicit read-modify-write: `let item = items[target]; item.deleted = true`.
- Pre-allocate with `Array::new(capacity=1024)` to avoid resize overhead for typical documents

**Phase 3 extension point:** Add `state : ItemState` field for retreat/advance state machine without structural changes.

#### 2. `Array[Array[Int]]` — children index, indexed by LV

Replaces `@immut/hashmap.HashMap[Lv, Array[Lv]]`. Mutable arrays; children pushed on insert.

- Index = item's LV (same as items array)
- Each entry is the array of child LVs (unsorted; sorted on demand for sibling ordering)
- On insert: `children.push([])` to initialize new item's empty children entry, then `children[parent].push(lv)` to register as child
- `traverse_tree` creates a local copy for sorting — never sorts the stored array in-place

#### 3. `OrderTree[VisibleRun]` — position cache (from Phase 2a)

Kept from Phase 2a. Now incrementally maintained for local operations instead of rebuilding from scratch.

- Local sequential insert (cursor fast-path): merge into existing VisibleRun — O(1)
- Local non-sequential insert: invalidate, full rebuild on next access — O(n)
- Local delete: `OrderTree.delete_at(position)` — O(log n)
- Remote batch / undelete / delete_range: full rebuild via `traverse_tree` + `OrderTree.from_array()` — O(n)

#### 4. `LcaIndex` — unchanged algorithm, Array-backed internals

Same Euler Tour + Sparse Table algorithm. Three changes:
- **Build input:** DFS uses `children` array (O(1) access) instead of HashMap (O(log₃₂ n))
- **`first` field:** Replace `@immut/hashmap.HashMap[Lv, Int]` with `Array[Int]` indexed by LV, plus a separate `root_first : Int` field for the root's first Euler tour occurrence. Root has LV=-1 and cannot index into a non-negative array. Required to fully remove `@immut/hashmap`.
- **Root in Euler tour:** The LCA build includes root in the Euler tour (current behavior). With separate root, the DFS starts from `root_children` and records root depth/occurrence via `root_first`.

### FugueStore struct

New struct encapsulating the array-backed storage:

```
struct FugueStore {
  mut items : Array[ItemMeta]       // Dense array indexed by LV
  mut children : Array[Array[Int]]  // Children index indexed by LV
  root_children : Array[Int]        // Root's children (root is not in items array)
  mut length : Int                  // Total items (including deleted)
  mut visible : Int                 // Visible (non-deleted) count
  mut lca_index : LcaIndex?        // Lazy-built, invalidated on mutation
  mut batch_inserting : Bool        // Skip LCA during batch ops
}
```

## Operations

### Local insert at position P

1. Read both origins from position cache **before mutation**:
   - `origin_left = position_to_lv(P)` — O(log n) via position cache
   - `origin_right = lv_at_position(P)` (item at position P, or None if P == end) — O(log n)
2. `oplog.insert(ch, origin_left, origin_right)` → Op with LV
3. `find_parent_and_side(origin_left, origin_right)` → parent, side — O(1) with LCA index
4. Assert `lv == items.length()`, then `items.push(ItemMeta { ... })` — O(1) amortized
5. `children.push([])` — initialize new item's empty children entry
6. `get_children(parent).push(lv)` — O(1) amortized
7. `length += 1; visible += 1`
8. Position cache update (see Incremental Position Cache Detail):
   - **Cursor fast-path (sequential append):** merge into existing VisibleRun — O(1)
   - **Non-sequential insert:** invalidate cache (full rebuild on next access)
9. Invalidate LCA index (structural change: new parent-child edge)

### Local delete at position P

1. `lv_at_position(P)` → target LV — O(log n) via position cache
2. LWW check: `should_win_delete(items[target], new_ts, new_agent)`
3. `items[target].deleted = true` (+ update deleted_ts, deleted_agent) — O(1)
4. `visible -= 1`
5. Position cache: `cache.delete_at(P)` — O(log n)
6. LCA index: **not invalidated** (delete does not change parent-child structure)

### Local delete_range (start, end)

1. Collect all target LVs from position cache **before** any mutation (same as current code)
2. For each collected LV: `items[lv].deleted = true`, `visible -= 1`
3. Invalidate position cache (full rebuild on next access)
4. LCA index: **not invalidated** (deletes don't change tree structure)

### Undelete (by LV)

1. `items[lv].deleted = false` (+ update winner metadata) — O(1)
2. `visible += 1`
3. Invalidate position cache — full rebuild required because the document position of the revived item is not known from the LV alone
4. LCA index: **not invalidated** (undelete doesn't change tree structure)

### Remote batch (k ops)

1. Buffer ops in OpLog pending queue (existing mechanism)
2. `drain_pending()` → resolved ops in causal order
3. `set_batch_inserting(true)` — skip LCA rebuild during batch
4. For each resolved op:
   - Insert: `items.push(meta)`, `children.push([])`, `children[parent].push(lv)` — O(1) each
   - Delete/Undelete: `items[target].deleted = ...` — O(1)
5. `set_batch_inserting(false)`
6. Position cache: full rebuild — O(n log n)
7. LCA index: invalidated, rebuilt lazily on next ancestor query

### Ancestor check (is_ancestor)

- Same algorithm: LCA index with Euler Tour + Sparse Table
- Built from `children` array (DFS traversal) + `items` array (depth tracking)
- O(n log n) build, O(1) per query
- During `batch_inserting`: naive parent-walk via `items[lv].parent` chain, terminating when `parent == -1` (root sentinel, replacing the current `None` check on `Lv?`)

### traverse_tree (document-order traversal)

Same iterative 3-phase algorithm, but with O(1) array lookups:

```
// Before: self.items[lv] → O(log₃₂ n) HashMap lookup
// After:  self.items[lv]  → O(1) array index

// Before: self.children[lv] → O(log₃₂ n) HashMap lookup
// After:  self.children[lv]  → O(1) array index
```

Used for: full position cache rebuild, get_text, get_visible_items.

### lv_to_position (reverse lookup)

`FugueTree::lv_to_position` does a linear scan over visible items. After migration, this method delegates to the position cache's `iter()` with early termination (same algorithm, array-backed). This is O(n) worst case but acceptable — it is not on the local-edit hot path.

## LV Indexing Convention

Current: `root_lv = Lv(-1)`, item LVs start at 0.

**Choice: Separate root.** Root is handled as a special case (already is in current code — `delete(root_lv)` is a no-op, root never appears in visible items). The `items` and `children` arrays are indexed directly by LV with no offset. Root's children stored in the `root_children` field on FugueStore.

Helper for children access:

```
fn get_children(self : FugueStore, lv : Int) -> Array[Int] {
  if lv == -1 { self.root_children } else { self.children[lv] }
}
```

## Incremental Position Cache Detail

### Incremental strategy: cursor fast-path only

The `VisibleRun` `Mergeable` contract is only valid for sequential append-like usage (consecutive LVs merge). Arbitrary positional insert into the OrderTree cache would violate this: a mid-document insert produces a non-consecutive LV run that cannot merge with neighbors, and the resulting cache state may not match a full rebuild.

**Therefore, incremental cache update is limited to the cursor fast-path:**

- **Cursor fast-path (sequential append):** The `InsertCursor` from Phase 2a detects sequential typing. When triggered, the new character merges into the existing VisibleRun via `Mergeable` — O(1), no OrderTree structural change.
- **Local delete at known position:** `cache.delete_at(P)` — O(log n). Safe because deletion only removes/splits an existing run; no merge invariant is violated.
- **All other mutations:** Invalidate cache (full rebuild on next access). This includes: non-sequential local inserts, remote ops, undelete, delete_range.

Empty document edge case: `position_to_lv(0)` returns -1 (root), which is correct for the first insert.

### Why full rebuild for non-cursor inserts

Remote inserts determine document position via FugueMax (parent/side/sibling ordering), not from a caller-specified position. Non-sequential local inserts produce non-consecutive LV runs that break `VisibleRun::can_merge`. Full rebuild is simpler and correct.

Undelete revives a tombstoned item at its original tree position. The document position is not known without a reverse LV → position lookup, so full rebuild is required.

### Future: broader incremental updates

If profiling shows the rebuild is a bottleneck after Array replacement, we could:
1. Extend `VisibleRun` to support non-consecutive runs (weaker merge condition)
2. Add targeted tests for mid-insert, mid-delete, and interleaved local/remote cache states
3. Gradually broaden incremental updates with test-driven verification

## Migration Strategy

Port and test one method at a time. Run the full test suite after each method port.

### Step 1: Introduce FugueStore

Create `FugueStore` struct with Array-backed storage alongside existing FugueTree. Both coexist during migration.

### Step 0: Spike test for MoonBit struct mutability

Before any migration, verify that `items[idx].deleted = true` mutates the struct in-place in a MoonBit Array. Write a minimal test:
```
struct Foo { mut x : Bool }
let arr : Array[Foo] = [{ x: false }]
arr[0].x = true
assert_true!(arr[0].x)
```
If this fails, use explicit read-modify-write pattern throughout.

### Step 2: Port FugueTree methods

Rewrite FugueTree methods to delegate to FugueStore. The public `FugueTree[T]` wrapper is preserved; internal dispatch changes. Port one method at a time, running full test suite after each.

**Core storage:**
- `new` / `make` → initialize arrays with pre-allocated capacity
- `add_item` → assert `lv == items.length()`, array push + children push
- `get(lv)` / `op_index[]` → array index (root handled separately)
- `visible_count` → read `visible` counter

**Mutation:**
- `insert` → same FugueMax algorithm, delegates to `add_item`
- `delete` / `delete_with_ts` / `undelete` / `undelete_with_ts` → mutable field update on `items[lv]`
- `set_delete_winner` → mutable field update (used by retreat in branch merge)

**Tree structure:**
- `get_children_raw` / `get_children_index` → `get_children(lv)` helper
- `set_batch_inserting` → set flag
- `is_ancestor_of` / `is_ancestor_naive` → LCA from arrays; naive walk terminates at `parent == -1` (not `None`)
- `build_lca_index` → DFS from children array, `first` as Array[Int] + `root_first`

**Traversal & query:**
- `traverse_tree` → same iterative 3-phase algorithm with array access
- `get_visible_items` / `get_all_items` → delegate to traverse_tree
- `fold` / `iter` / `to_text` → delegate to traverse_tree
- `lv_to_position` → delegate to position cache iter

### Step 3: Incremental position cache in Document

Update Document to incrementally maintain the position cache for local insert/delete instead of invalidating it. Undelete and remote ops continue to invalidate.

### Step 4: Remove FugueTree wrapper

Once all tests pass with FugueStore, remove the FugueTree struct. FugueStore becomes the sole implementation.

### Step 5: Clean up

- Remove `@immut/hashmap` dependency from fugue package (requires LcaIndex.first → Array[Int])
- Update `.mbti` interfaces
- Run benchmarks to verify performance improvement

## Testing

### Existing tests (must pass unchanged)
- All FugueTree tests (same observable behavior)
- All Document tests
- All convergence property tests (multi-agent fuzz)

### New tests required before implementation lands
- **MoonBit struct mutability spike:** Verify `items[idx].field = value` mutates in-place (Step 0)
- **LV invariant:** Assert `lv == items.length()` on every push; test that out-of-order replay is caught
- **Middle local delete with warm cache:** delete at non-end position, verify cache correctness
- **Cursor fast-path insert → non-sequential insert:** verify cache invalidation triggers correctly
- **delete_range across multiple VisibleRuns:** after prior splits/merges
- **Undo/redo paths:** `undelete`, `delete_by_lv`, and branch retreat recomputation
- **LCA/root edge cases:** root with `Lv(-1)`, empty document, single-node document, `root_first` field
- **LCA not invalidated on delete/undelete:** verify index survives delete + undelete sequence
- **Benchmark comparison:** before (HashMap) vs after (Array) at 100, 500, 1000 items

## Performance Expectations

| Operation | Before (HashMap) | After (Array) |
|-----------|-------------------|---------------|
| Item insert (single) | O(log₃₂ n) + alloc | O(1) amortized |
| Item lookup (single) | O(log₃₂ n) | O(1) |
| Children lookup (single) | O(log₃₂ n) | O(1) |
| Local insert (end-to-end per keystroke) | ~25ms (20ms CRDT + 5ms cache) | ~1ms (O(1) store + O(log n) cache) |
| Local delete (end-to-end per keystroke) | ~25ms (20ms CRDT + 5ms cache) | ~1ms (O(1) store + O(log n) cache) |
| Remote batch (k ops, end-to-end) | k × O(log₃₂ n) store + O(n) cache | k × O(1) store + O(n) cache rebuild |
| LCA build | O(n log n) from HashMap | O(n log n) from Array (lower constant) |

## Files Affected

- `event-graph-walker/internal/fugue/tree.mbt` — FugueTree → FugueStore migration
- `event-graph-walker/internal/fugue/item.mbt` — ItemMeta struct (replaces generic Item[T])
- `event-graph-walker/internal/fugue/lca_index.mbt` — Build from arrays, `first` field → Array[Int]
- `event-graph-walker/internal/document/document.mbt` — Incremental cache updates
- `event-graph-walker/internal/document/visible_run.mbt` — Unchanged
- `event-graph-walker/internal/branch/branch.mbt` — `Branch` holds `FugueTree[String]` → update to FugueStore
- `event-graph-walker/internal/branch/branch_merge.mbt` — `MergeContext` holds `FugueTree[String]` → update to FugueStore; `set_delete_winner` calls update
- `event-graph-walker/moon.pkg.json` — Remove `@immut/hashmap` dep (after full migration)

## Resolved Questions

1. **Undo snapshots:** UndoManager uses LV-based inverse ops via `Document.undelete`/`Document.delete_by_lv`. Retreat uses `set_delete_winner` to recompute state. No tree snapshots are taken. Array storage is compatible.
2. **Memory layout:** Pre-allocate arrays with `capacity=1024` in FugueStore constructor. MoonBit's `Array` doubles capacity on resize; 1024 initial capacity avoids ~10 resize+copy cycles for typical documents.
3. **Root children sorting:** Sorting on demand in `traverse_tree` is sufficient. It only runs during full cache rebuilds, which are already O(n log n). Maintaining sorted insert order would add complexity to every insert for no measurable benefit.
