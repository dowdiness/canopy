# CRDT Text Append Performance Optimization

**Date:** 2026-03-18
**Status:** Approved
**Scope:** `event-graph-walker` submodule (internal/fugue, internal/document)

## Problem

Sequential text append is O(n²). Inserting 1000 characters takes 3.79 seconds.

**Root causes (per-character insert):**

| Bottleneck | Location | Cost |
|-----------|----------|------|
| Position cache rebuilt after every char | `Document.insert()` loop | O(n) rebuild × n chars |
| `get_children()` scans entire HashMap | `FugueTree.get_children()` | O(n) per call |
| `is_ancestor()` walks linear parent chain | `FugueTree.is_ancestor()` | O(tree height) ≈ O(n) |
| Full tree traversal for cache rebuild | `Document.build_position_cache()` | O(n) per rebuild |
| Position lookup on every char | `Document.position_to_lv()` | O(n) cache rebuild |

**Cumulative:** 1 + 2 + ... + n = O(n²) for n sequential inserts.

**Key observation:** For sequential appends, `find_parent_and_side()` takes the `(Some(left), None)` branch which does **not** call `is_ancestor()`. The `is_ancestor()` bottleneck affects concurrent/remote operations, not sequential append.

## Constraints

- **FugueMax semantics must be preserved.** Same outputs for same inputs.
- Maximal non-interleaving property is required.
- All existing tests must pass after each step.
- Changes are data-structure-level, not semantic-level.
- FugueMax items never change parents after creation (no reparenting). This invariant makes auxiliary indices safe for incremental maintenance.

## Design: Four Optimization Steps

Each step is independently benchmarked. Steps are reordered based on dependency analysis: the cursor fast-path (Step 2) must come before batch cache invalidation (Step 3) because the insert loop reads the position cache on every iteration — batch invalidation only works once cursor eliminates per-char cache reads. Step 4 (LCA index) depends on Step 1 (children index) for its Euler tour DFS — without the children index, the DFS would use `get_children()` which scans the full HashMap, making the LCA build O(n²) instead of O(n log n).

### Step 1: Children Index

**File:** `internal/fugue/tree.mbt`

**Change:** Add `children: HashMap[Lv, Array[Lv]]` field to `FugueTree`.

**Maintenance:**
- On `add_item()`: append new item's Lv to `children[parent_id]`
- On delete/undelete: no change (tombstone model — items never change parents)

No other mutation paths create items or change parent pointers. The no-reparenting invariant of FugueMax guarantees the children index stays valid once an entry is added.

**`get_children()` becomes:** `self.children[parent_id]` — O(1) lookup.

**Sorting:** Sort on read. `get_children()` returns a **copy** of the children array (to prevent mutation during traversal/sorting), then sorts into left/right by `compare_children`. O(k log k) where k = children count (typically 1-3). The copy is necessary because traversal code and the LCA builder (Step 4) may hold references to children arrays while the tree is being read.

**HashMap type:** Use the same `@immut/hashmap.HashMap` as the existing `items` field for consistency. The inner `Array[Lv]` is mutable; on insert, look up the array and append in-place.

**Invariant:** The children map reference is always replaced atomically via `self.children = self.children.add(...)` when adding a new parent entry. In-place Array mutation (append) is safe only because the old map reference is never retained — `FugueTree` always reads from `self.children` which points to the latest version. No code path holds a reference to a previous version of the children map during mutation. If this invariant is violated (e.g., iterating children while inserting), use copy-on-write Arrays instead.

**Semantics:** Unchanged. Same children, same order.

**Risk:** Low. Must keep children map in sync with item map on `add_item()`.

**Tests:**
- Verify children map matches filtered HashMap scan for random trees
- Test items with same parent on different sides (Left and Right children)
- Test same-parent, same-side sibling ordering via `compare_children()` (correctness-sensitive for concurrent siblings)

### Step 2: Cursor Fast-Path

**Rationale:** This must come before batch cache invalidation. The insert loop in `Document.insert()` calls `position_to_lv()` and `lv_at_position()` on every iteration, which trigger cache rebuilds. The cursor eliminates this dependency for sequential appends, enabling Step 3.

**Change:** Add an insert cursor to `Document` to skip position lookup on sequential appends.

```
struct InsertCursor {
  position: Int     // last insert position
  lv: Lv            // Lv of last inserted item
  at_end: Bool      // whether the cursor is at end of document
}
```

**On insert:**
1. If `insert_position == cursor.position + 1`:
   - Use `cursor.lv` as `origin_left` directly — skip `position_to_lv()`
   - If `cursor.at_end`: `origin_right = None` — skip `lv_at_position()` entirely
   - If not `cursor.at_end`: still need `lv_at_position()` for `origin_right` (cursor partial hit)
2. Otherwise: normal path (position cache lookup for both `origin_left` and `origin_right`)
3. Update cursor: `position = insert_position`, `lv = new_item_lv`, `at_end = (origin_right == None)` (derived from the actual origin_right used for this insert, not from a count comparison — this avoids off-by-one between pre/post-insert visible_count)

**Scope:** The cursor provides full cache bypass (both `origin_left` and `origin_right`) only for end-of-document appends (`at_end = true`). This covers the primary benchmark target (sequential append). Mid-document sequential inserts get a partial benefit (`origin_left` cached, `origin_right` still looked up).

**Placement:** On `Document`, where it has direct access to `origin_left`/`origin_right` values.

**Invalidation:** Set cursor to `None` on delete, merge, `apply_remote()`, `merge_remote()`, or any non-insert operation.

**Semantics:** Unchanged. Same `origin_left`/`origin_right` values, just found via cache hit.

**Risk:** Low. Cursor miss means normal path, not an error.

**Tests:**
- Property test: cursor hit produces same result as full position lookup across random operation sequences
- Test cursor invalidation: after a delete, next insert uses normal path
- Test mid-document sequential insert: verify `origin_right` is correctly computed

### Step 3: Batch Cache Invalidation

**File:** `internal/document/document.mbt`

**Prerequisite:** Step 2 (cursor fast-path). Without the cursor, the insert loop reads the position cache on every iteration via `position_to_lv()`. With the cursor, sequential appends bypass cache reads, making batch invalidation safe.

**Change:** Move `invalidate_cache()` from inside the per-character loop to after the loop.

```
// Before
for i = 0; i < text.length(); i = i + 1 {
    // ... insert char ...
    self.invalidate_cache()  // called n times
}

// After
for i = 0; i < text.length(); i = i + 1 {
    // ... insert char ...
}
self.invalidate_cache()  // called once
```

Same change for `delete_range()` if it has the same pattern.

**Non-sequential insert safety:** When the cursor misses (non-sequential insert), the loop falls back to `position_to_lv()` which reads the cache. For multi-char non-sequential inserts, the cache must still be invalidated per-char. Implementation: on cursor miss within the loop, immediately call `invalidate_cache()` before the cache read (same as current behavior). On cursor hit, skip invalidation. After the loop, call `invalidate_cache()` once unconditionally to ensure the cache reflects the final state. This is safe because: cursor-hit iterations never read the cache (so stale cache is irrelevant), and cursor-miss iterations invalidate before reading (same as current).

**All mutation paths that call `invalidate_cache()`:**
- `insert()` — batched (this step)
- `delete_range()` — batched if same pattern
- `replace_range()` — review and batch if safe
- `undelete()` / `delete_by_lv()` — single ops, keep as-is
- `apply_remote()` / `merge_remote()` — keep as-is (complex, fallback to full invalidation)

**Semantics:** Unchanged. Cache is lazy — only rebuilt on next read.

**Risk:** Low with cursor prerequisite. The cursor-miss fallback preserves correctness.

**Tests:**
- Multi-character insert at non-end position (e.g., insert "abc" at position 2 in a 5-char doc)
- Verify text correctness after mixed sequential and non-sequential inserts

### Step 4: LCA Index

**File:** New file `internal/fugue/lca_index.mbt`

**When it helps:** Concurrent/remote operations where `find_parent_and_side()` takes the `(Some(left), Some(right))` branch and calls `is_ancestor()`. Does **not** help sequential append (which never calls `is_ancestor()`).

**Algorithm:** Euler Tour + Sparse Table for O(1) Lowest Common Ancestor queries.

**Data structure:**
```
struct LcaIndex {
  euler_tour: Array[Lv]       // node visited at each step
  depth: Array[Int]           // depth at each step
  first: HashMap[Lv, Int]    // first occurrence index per node
  sparse: Array[Array[Int]]  // sparse table for RMQ
}
```

**Prerequisite:** Step 1 (children index). The Euler tour DFS needs to enumerate children of each node. Without the children index, this would use `get_children()` which scans the full HashMap — making the build O(n²). With the children index, the DFS visits each node once: O(n) traversal + O(n log n) sparse table construction.

**Build:** O(n log n) — DFS traversal using children index, producing Euler tour of length 2n-1, then sparse table construction.

**Query:** `is_ancestor(a, b)`:
```
if a not in first or b not in first: return false  // missing node → not ancestor
lca = rmq(first[a], first[b])
return lca == a
```
O(1) per query. Missing-node handling preserves current semantics where `is_ancestor()` returns `false` if either node is absent.

**Lifecycle:**
- Built lazily on first `is_ancestor()` call after mutation
- Invalidated when items are inserted (new items added to tree)
- For `apply_remote()` / `merge_remote()`: see merge strategy below

**Rebuild frequency:** In the sequential append case, `is_ancestor()` is never called, so the LCA index is never built or rebuilt — zero overhead.

**Merge path strategy:** During `MergeContext::apply_operations()`, the merge loop calls `tree.insert()` repeatedly, and each insert may call `is_ancestor()` for concurrent ops. If the LCA index is invalidated on every insert and rebuilt on the next `is_ancestor()`, this is O(n × n log n) — worse than no index. Solution: **fall back to the naive parent-walk during active batch-insert operations.** Add a `batch_inserting: Bool` flag on FugueTree; when true, `is_ancestor()` uses the direct parent-walk (current behavior) instead of the LCA index. The LCA index is rebuilt lazily on the first `is_ancestor()` call after the batch completes.

**All batch-insert paths that need the flag:**
- `MergeContext::apply_operations()` — merge loop
- `Branch::checkout()` — applies buffered ops
- `Branch::advance()` — fast path
- `Document::apply_remote()` — flushes buffered remote ops

**Error safety:** The flag must be cleared in a `finally` block (or equivalent) to prevent a failed merge from leaving ancestor checks permanently in fallback mode. Pattern: `self.batch_inserting = true; try { ... } finally { self.batch_inserting = false; self.lca_index = None }`

**Must handle:**
- Virtual root node (parent = None)
- Tombstoned items (still in tree with parent pointers)
- All nodes including deleted ones must appear in the Euler tour

**Integration:**
- New field on FugueTree: `lca_index: LcaIndex?` (lazy, nullable)
- `FugueTree.is_ancestor()` checks index, rebuilds if stale, then O(1) query

**Semantics:** Unchanged. `is_ancestor(a, b)` returns the same boolean.

**Risk:** Medium. Core algorithm correctness is well-understood (textbook LCA), but integration with FugueTree's specific structure needs careful testing.

**Tests:**
- Property test: for random trees, LCA-based `is_ancestor()` == naive parent-walk `is_ancestor()`
- Edge cases: root node, single-node tree, deep chain, wide fan-out
- Missing node: `is_ancestor(absent_lv, x)` and `is_ancestor(x, absent_lv)` both return `false`
- Invalidation test: build tree, query `is_ancestor()`, insert new item, query again, verify new item is correctly included
- Batch-insert paths: test `Branch::checkout()`, `Branch::advance()`, `Document::apply_remote()` with concurrent ops
- Error safety: verify `batch_inserting` flag is cleared after failed merge (exception during apply_operations)

### Checkpoint: Measure and Decide

After Steps 1-4, benchmark and assess whether further optimization is needed.

**Remaining O(n) path:** `build_position_cache()` does a full tree traversal via `get_visible_items()` → `traverse_tree()`. With Steps 2+3, this only runs once per `Document.insert()` call (not per char). For 1000-char append, this is a single O(n) rebuild.

**If performance is sufficient:** Stop here. A single O(n) cache rebuild per insert call is acceptable for interactive editing.

**If further optimization is needed:** Consider incremental position cache updates. However, this is blocked by `VisibleRun.can_merge()` which is explicitly documented as unsafe for arbitrary insertion — it only checks consecutive LVs, not document-order adjacency. Options:
- **Strengthen `can_merge`:** Add a `doc_position` field to `VisibleRun` and verify adjacency
- **Skip merge on splice:** Don't merge after incremental updates (less compressed but correct)
- **Different cache structure:** Replace `Rle[VisibleRun]` with a structure designed for incremental updates

This decision is deferred until benchmarks show it's needed.

## Expected Performance Progression

| Step | Eliminates | Expected time (1000 chars) |
|------|-----------|---------------------------|
| Baseline | — | 3.79s |
| 1. Children index | O(n) get_children scans | ~2.5-3.0s |
| 2. Cursor fast-path | Position lookup on sequential append | ~1.0-1.5s |
| 3. Batch invalidation | Remaining cache rebuilds (cursor misses) | ~0.8-1.2s |
| 4. LCA index | O(n) ancestor walks → O(1) (concurrent ops) | ~0.8-1.2s (no change for append) |
| Checkpoint | Measure and decide on further optimization | — |

Note: Steps 2+3 together provide the largest win for sequential append. Step 4 primarily benefits concurrent/remote operations and may show no improvement on the append benchmark. After Step 4, a single O(n) cache rebuild per `Document.insert()` call remains — acceptable for most interactive use cases.

## Benchmark Protocol

After each step:

```bash
cd event-graph-walker && moon bench --release
```

**Track:**
- `text - insert append (1000 chars)` — primary target
- `text - insert append (100 chars)` — small doc sanity check
- `text - insert prepend (100 chars)` — non-append regression check (cursor should not hurt this path)
- All existing walker/merge benchmarks — regression check

**Record results** in `event-graph-walker/docs/benchmarks/` after each step.

## Testing Strategy

Each step must pass:
1. `moon test` in event-graph-walker (all existing tests including convergence fuzz tests)
2. `moon test` in parent crdt repo (integration regression check)
3. New unit tests for new structures (see per-step test sections)
4. Property tests where `@qc` is available (LCA correctness, cache consistency)
5. Convergence fuzz tests must be explicitly verified after each step to ensure FugueMax semantics are preserved
