# Incremental LCA via Binary Lifting (Jump Pointers)

**Date:** 2026-03-24
**Status:** Design
**Depends on:** Phase 2b (Array-backed FugueStore) — complete

## Problem

`FugueTree::is_ancestor(x, y)` is the single largest per-keystroke CRDT cost during live collaboration (~3-5ms at 1000 items). The current implementation builds an Euler Tour + Sparse Table (O(n log n)) from scratch on every tree mutation, then discards it. A `batch_inserting` flag avoids the rebuild during merges by falling back to O(height) naive parent-walks, but individual remote ops arriving during live editing trigger a full rebuild each time.

### Per-keystroke cost at 1000 items

| Component | Current cost | After this change |
|-----------|-------------|-------------------|
| LCA index rebuild | ~3-5ms (O(n log n)) | **0ms** (no rebuild) |
| is_ancestor query | ~10ns (O(1) sparse table) | ~100ns (O(log n) jump) |
| Jump pointer setup per insert | 0 | ~50ns (O(log n)) |

## Key Invariant

**FugueTree is structurally append-only.** `add_item()` only adds leaves. There is no `remove_item()`, no `move_item()`, no rebalancing. Delete/undelete are tombstone flags — they don't alter the parent-child tree structure. A node's parent, once set, **never changes**.

**Consequence:** Any precomputed ancestry information is permanent. Jump pointers computed at insertion time are valid for the lifetime of the document.

## Design: Binary Lifting

### Data Structure

```moonbit
struct JumpAncestors {
  depth : Array[Int]         // depth[lv.0] = depth in FugueTree. -1 = not a tree node (gap).
  jump : Array[Array[Lv]]   // jump[lv.0][k] = 2^k-th ancestor of lv. [] = gap.
}
```

Both arrays are indexed by `lv.0` (non-negative). Root (`Lv(-1)`) is handled by early returns in `is_ancestor()`, never accessed in the arrays.

**Sparse LV handling:** LV space is shared with the oplog — delete/undelete operations consume LVs that have no FugueTree item. The arrays contain gaps at these positions. `depth` uses `-1` as sentinel for non-tree LVs. `jump` uses `[]` (empty array). This matches the existing pattern in `FugueTree.items : Array[Item[T]?]` which uses `None` for gaps. When growing arrays to reach a new LV index, pad with sentinel/empty values.

**Memory:** O(oplog_size × log(max_depth)), not O(tree_size × log(max_depth)). The gap overhead is proportional to the number of delete/undelete operations. In typical editing, inserts dominate (~60-80% of ops), so the overhead is modest.

Each tree node's entry is written once at insertion time and never modified.

**Precondition:** `add(lv, parent)` requires that `parent` was already added (or is `root_lv`). This is guaranteed because the oplog replays operations in causal/topological order — a child's insert operation always has a higher LV than its parent's. This ordering is enforced by `walk_from_frontier()` in the causal graph walker and by the sequential LV assignment in local inserts. An assertion `depth[parent.0] != -1 || parent == root_lv` should guard against violations.

### API

```moonbit
fn JumpAncestors::new() -> JumpAncestors
fn JumpAncestors::add(self, lv : Lv, parent : Lv) -> Unit       // O(log depth)
fn JumpAncestors::is_ancestor(self, x : Lv, y : Lv) -> Bool     // O(log depth)
```

### Insert: `add(lv, parent)`

```
// Grow arrays with sentinel padding for any gap LVs
while depth.length() <= lv.0: depth.push(-1)
while jump.length() <= lv.0: jump.push([])

// Assert precondition: parent already added (or is root)
assert(parent == root_lv || depth[parent.0] != -1)

depth[lv.0] = if parent == root_lv { 1 } else { depth[parent.0] + 1 }

jumps = [parent]                          // jump[0] = direct parent
k = 1
while k-1 < jumps.length():
  prev = jumps[k-1]
  if prev == root_lv: break               // reached root, stop
  if k-1 >= jump[prev.0].length(): break  // ancestor doesn't have this level
  jumps.push(jump[prev.0][k-1])           // jump[k] = 2^k-th ancestor
  k += 1

jump[lv.0] = jumps
```

Produces `⌊log₂(depth)⌋ + 1` entries. O(log depth) time and space.

### Query: `is_ancestor(x, y)`

```
// Caller (FugueTree::is_ancestor) handles: x==y, x==root, y==root

// Bounds + gap checks: absent LVs are not ancestors of anything
if x.0 >= depth.length() || depth[x.0] == -1: return false
if y.0 >= depth.length() || depth[y.0] == -1: return false

depth_x = depth[x.0]
depth_y = depth[y.0]
if depth_x > depth_y: return false        // deeper node can't be ancestor

// Lift y up to depth_x using binary decomposition
diff = depth_y - depth_x
current = y
k = jump[current.0].length() - 1
while diff > 0 && k >= 0:
  if diff >= (1 << k) && k < jump[current.0].length():
    current = jump[current.0][k]
    diff -= (1 << k)
  k -= 1

return current == x
```

O(log depth) — at most 17 iterations for 100K items. Returns `false` for absent or out-of-bounds LVs, preserving the current API contract (tested at `tree_test.mbt:487,522`).

### Correctness argument

Lifting `y` by exactly `depth[y] - depth[x]` levels follows the unique path from `y` to root, stopping at the depth of `x`. If `x` is an ancestor of `y`, this path passes through `x`, so `current == x`. If not, `current` is a different node at the same depth — so `current != x`.

Edge case: since both `x` and `y` are non-root (depth ≥ 1), the lift never reaches `root_lv` (depth 0). This is guaranteed because `diff = depth[y] - depth[x]` lifts `y` to `depth[x] ≥ 1`.

## Integration with FugueTree

### FugueTree struct changes

```diff
 pub struct FugueTree[T] {
   items : Array[Item[T]?]
   mut length : Int
   mut visible : Int
   root_children : Array[Lv]
   children : Array[Array[Lv]]
-  mut lca_index : LcaIndex?
-  mut batch_inserting : Bool
+  jump_ancestors : JumpAncestors
 }
```

### add_item() changes

`item.parent` is `Some(root_lv)` for root's children, never `None` in practice (`None` means no parent registered — a defensive guard in the current code). Match only `Some(p)`:

```diff
 fn add_item(self, item) {
   // ... existing array append logic ...
-  self.lca_index = None
+  match item.parent {
+    Some(p) => self.jump_ancestors.add(item.id, p)
+    None => ()  // No parent — skip jump pointer setup
+  }
 }
```

### is_ancestor() simplification

```diff
 pub fn is_ancestor(self, ancestor_id, descendant_id) -> Bool {
   if ancestor_id == descendant_id { return true }
-  if self.batch_inserting {
-    return self.is_ancestor_naive(ancestor_id, descendant_id)
-  }
-  match self.lca_index {
-    Some(idx) => idx.is_ancestor(ancestor_id, descendant_id)
-    None => {
-      self.build_lca_index()
-      match self.lca_index {
-        Some(idx) => idx.is_ancestor(ancestor_id, descendant_id)
-        None => self.is_ancestor_naive(ancestor_id, descendant_id)
-      }
-    }
-  }
+  if ancestor_id == root_lv { return true }
+  if descendant_id == root_lv { return false }
+  self.jump_ancestors.is_ancestor(ancestor_id, descendant_id)
 }
```

### Merge path behavior

The merge path (`apply_operations` in `branch_merge.mbt`) calls `tree.insert()` → `find_parent_and_side()` → `is_ancestor()`. Currently, this runs under `set_batch_inserting(true)`, so it uses the naive O(height) walk — which can be O(n) on degenerate trees (sequential typing creates long right-child chains). After this change, the same code path uses binary lifting at O(log n) unconditionally. This is an improvement for batch merges, not just live collaboration.

### Deletions

| File | What to remove |
|------|---------------|
| `internal/fugue/lca_index.mbt` | Entire file (~150 lines) |
| `internal/fugue/tree.mbt` | `build_lca_index()`, `set_batch_inserting()`, `is_ancestor_naive()` (move to test file as reference), `lca_index` field, `batch_inserting` field |
| `internal/branch/branch.mbt:67,71,116,120` | `set_batch_inserting(true/false)` calls |
| `internal/branch/branch_merge.mbt:34,122` | `set_batch_inserting(true/false)` calls |
| `internal/document/document.mbt:431,503` | `set_batch_inserting(true/false)` calls |
| `internal/fugue/tree_test.mbt:490,571` | `build_lca_index()` calls in unit tests |
| `internal/fugue/tree_properties_test.mbt:239` | `build_lca_index()` call in property test |

After all removals, run `moon info && moon fmt` to update `.mbti` interface files.

### New file

| File | Content |
|------|---------|
| `internal/fugue/jump_ancestors.mbt` | `JumpAncestors` struct + `new()`, `add()`, `is_ancestor()` (~50-60 lines) |

## Testing

### Existing tests (should pass unchanged)

- `prop_lca_matches_naive` — rename to `prop_jump_matches_naive`, keep `is_ancestor_naive` as test-only reference
- `prop_fugue_ancestor_reflexive` — `is_ancestor(x, x) == true`
- `prop_fugue_ancestor_transitivity` — `(a,b) ∧ (b,c) → (a,c)`
- Unit tests in `tree_test.mbt` — ancestor check correctness, edge cases

### New tests

- `test_jump_root_children` — items with parent=root have depth=1, one jump pointer
- `test_jump_deep_chain` — chain of 100 nodes, verify all ancestor pairs
- `test_jump_wide_tree` — root with 100 direct children, verify non-ancestry
- `test_jump_branching_tree` — tree with 3+ branches of different depths, verify `is_ancestor(a, b) == false` across branches and `== true` within a branch. This is the critical topology where depth-lifting logic is fully exercised.
- `prop_jump_depth_consistency` — `depth[x] == depth[parent] + 1` for all non-root items
- `prop_jump_matches_naive_branching` — generate random tree topologies (each new node picks a random existing node as parent), verify binary lifting agrees with naive walk for all pairs. Wider coverage than chain-only property tests.
- `test_jump_absent_lv` — `is_ancestor(absent_lv, x)` and `is_ancestor(x, absent_lv)` both return `false`. Preserves existing behavior (tree_test.mbt:487,522).
- `test_jump_sparse_lv` — add items at non-consecutive LVs (simulating gaps from delete/undelete ops), verify correct ancestry across gaps.
- `prop_jump_via_insert` — generate operations through `FugueTree::insert()` (not raw `add_item`), including concurrent ops that trigger `find_parent_and_side`, verify ancestry matches naive walk. Integration-level property test.

## Benchmarks

### Before/after comparison

| Benchmark | What it measures | Scale |
|-----------|-----------------|-------|
| `bench_concurrent_insert_1k` | 1 remote op into 1K doc (triggers is_ancestor) | 1,000 items |
| `bench_concurrent_insert_10k` | Same at larger scale | 10,000 items |
| `bench_batch_merge_1k` | 100 concurrent ops merged into 1K doc | 1,000 + 100 ops |
| `bench_sequential_append_1k` | Regression check: sequential typing (no is_ancestor) | 1,000 items |
| `bench_degenerate_chain_remote` | Adversarial: sequential chain + remote inserts forcing is_ancestor on O(n)-deep tree | 1,000 items |
| `bench_sparse_lv_insert` | Inserts interleaved with delete/undelete ops (sparse LV space) | 1,000 items |

### Methodology

1. Run on `main` — capture baseline
2. Implement binary lifting
3. Run same benchmarks — compare

### Success criteria

| Benchmark | Expected |
|-----------|----------|
| Concurrent insert | **>100x improvement** (ms → µs) |
| Batch merge | **Measurable improvement** (O(height) → O(log n)) |
| Sequential append | **No regression** (< 5% variance) |

## Alternatives Considered

### Euler Tour + OrderTree (Approach A, initially proposed)

Store Euler Tour in an `OrderTree[EulerEntry]` with min-depth augmentation for O(log n) RMQ. Rejected because maintaining `first_occurrence[lv] → position` requires O(n) updates on splice (all positions after insertion shift). Would need parent pointers in OrderTree or a doubly-indexed structure — significantly more complex for no benefit over binary lifting.

### Euler Tour + Segment Tree (Approach B)

Replace static Sparse Table with a dynamic Segment Tree. Rejected because Euler Tour entries must be spliced mid-sequence (not appended), requiring O(n) array shift or a balanced tree — converges to Approach A.

### Depth + naive walks (Approach C)

Maintain `depth[lv]` incrementally, use depth-based early exit in naive walks. Rejected because FugueMax trees can be O(n) deep (sequential typing creates long right-child chains), so worst-case query is still O(n).

### DFS intervals with order-maintenance

Assign `[enter, exit]` intervals, check ancestry via `enter[x] ≤ enter[y] ∧ exit[y] ≤ exit[x]` in O(1). Rejected because FugueMax trees can be O(n) deep, exhausting integer gaps quickly, and order-maintenance relabeling adds 100-200 lines of complexity for negligible benefit (O(1) vs O(log n) at our scale is ~10ns difference).

## Why Binary Lifting Wins

1. **Exploits the key invariant** — append-only tree means jump pointers are permanent
2. **Simplest implementation** — ~50 lines, two arrays, three functions
3. **O(log n) everything** — insert and query, unconditionally
4. **No rebuild, ever** — each node's data computed once at insertion
5. **No special modes** — eliminates `batch_inserting` and the batch/non-batch code split
6. **No new dependencies** — no changes to order-tree submodule
7. **Well-understood algorithm** — textbook binary lifting, easy to verify and maintain
