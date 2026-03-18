# RLE Phase 3: LvRange Compression Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compress graph traversal results (topological_sort, walk_from_frontier, diff_frontiers_lvs) using Rle[LvRange].

**Architecture:** Define LvRange in core package, implement RLE traits, change return types of topological_sort/walk_from_frontier/diff_frontiers_lvs to Rle[LvRange], update all consumers to iterate compressed results.

**Spec deviation:** The spec proposes changing `graph_diff` return type to `Rle[LvRange]`, but we keep it as `(Array[Int], Array[Int])` since the data comes from unsorted HashSet iteration. Compression is applied at the `diff_frontiers_lvs` layer instead, which already handles topological sorting.

**Tech Stack:** MoonBit, dowdiness/rle library

**Spec:** `docs/plans/2026-03-15-rle-library-integration.md` (Phase 3 section)

**Deferred:** `Sliceable` is not implemented for `LvRange` in this phase (not needed for append/find/iterate patterns).

**Important:** `event-graph-walker/` is a git submodule. All source changes are inside it.

---

### Task 1: Define LvRange type with RLE trait impls in core/

**Files:**
- Create: `event-graph-walker/internal/core/lv_range.mbt`
- Create: `event-graph-walker/internal/core/lv_range_test.mbt`
- Modify: `event-graph-walker/internal/core/moon.pkg`

LvRange goes in `internal/core/` because it is consumed by causal_graph, oplog, and branch.

- [ ] **Step 1: Add `dowdiness/rle` to core's moon.pkg**

Edit `/home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker/internal/core/moon.pkg`:

```
import {
  "moonbitlang/core/json",
  "moonbitlang/core/hashset",
  "dowdiness/rle",
}

options(
  is_main: false,
)
```

- [ ] **Step 2: Create LvRange type and trait impls**

Create `/home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker/internal/core/lv_range.mbt`:

```moonbit
///|
/// A contiguous range of local versions [start, start+count).
///
/// Used to compress graph traversal results (topological_sort,
/// walk_from_frontier, diff_frontiers_lvs) where consecutive LVs
/// are common in linear editing sessions.
pub(all) struct LvRange {
  start : Int
  count : Int
} derive(Eq, Show)

///|
pub impl @rle.HasLength for LvRange with length(self) {
  self.count
}

///|
pub impl @rle.Spanning for LvRange with span(self) {
  self.count
}

///|
pub impl @rle.Spanning for LvRange with logical_length(self) {
  self.count
}

///|
pub impl @rle.Mergeable for LvRange with can_merge(a, b) {
  a.start + a.count == b.start
}

///|
pub impl @rle.Mergeable for LvRange with merge(a, b) {
  { start: a.start, count: a.count + b.count }
}

///|
pub impl @rle.FromRange for LvRange with from_range(start, count) {
  { start, count }
}

///|
pub impl @rle.Addressable for LvRange with address(self, _global_start, offset) {
  self.start + offset
}

///|
/// Check if a given LV falls within this range.
pub fn LvRange::contains(self : LvRange, lv : Int) -> Bool {
  lv >= self.start && lv < self.start + self.count
}

///|
/// Get the end (exclusive) of this range.
pub fn LvRange::end(self : LvRange) -> Int {
  self.start + self.count
}
```

- [ ] **Step 3: Create tests for LvRange**

Create `/home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker/internal/core/lv_range_test.mbt`:

```moonbit
///|
test "LvRange - basic construction" {
  let r = @core.LvRange::{ start: 0, count: 5 }
  inspect(r.start, content="0")
  inspect(r.count, content="5")
  inspect(r.end(), content="5")
}

///|
test "LvRange - contains" {
  let r = @core.LvRange::{ start: 3, count: 4 }
  // Contains 3, 4, 5, 6
  inspect(r.contains(2), content="false")
  inspect(r.contains(3), content="true")
  inspect(r.contains(6), content="true")
  inspect(r.contains(7), content="false")
}

///|
test "LvRange - HasLength and Spanning" {
  let r = @core.LvRange::{ start: 10, count: 3 }
  inspect(@rle.HasLength::length(r), content="3")
  inspect(@rle.Spanning::span(r), content="3")
  inspect(@rle.Spanning::logical_length(r), content="3")
}

///|
test "LvRange - Mergeable contiguous ranges" {
  let a = @core.LvRange::{ start: 0, count: 3 }
  let b = @core.LvRange::{ start: 3, count: 2 }
  inspect(@rle.Mergeable::can_merge(a, b), content="true")
  let merged = @rle.Mergeable::merge(a, b)
  inspect(merged.start, content="0")
  inspect(merged.count, content="5")
}

///|
test "LvRange - Mergeable non-contiguous ranges" {
  let a = @core.LvRange::{ start: 0, count: 3 }
  let b = @core.LvRange::{ start: 5, count: 2 }
  inspect(@rle.Mergeable::can_merge(a, b), content="false")
}

///|
test "LvRange - FromRange" {
  let r : @core.LvRange = @rle.FromRange::from_range(10, 5)
  inspect(r.start, content="10")
  inspect(r.count, content="5")
}

///|
test "LvRange - Addressable" {
  let r = @core.LvRange::{ start: 10, count: 5 }
  // global_start is ignored for index-carrying types
  inspect(@rle.Addressable::address(r, 0, 0), content="10")
  inspect(@rle.Addressable::address(r, 0, 2), content="12")
  inspect(@rle.Addressable::address(r, 0, 4), content="14")
}

///|
test "LvRange - Rle from_sorted_ints" {
  let rle : @rle.Rle[@core.LvRange] = @rle.Rle::from_sorted_ints(
    [0, 1, 2, 5, 6, 7],
  )
  // 2 runs: [0..3) and [5..8)
  inspect(@rle.HasLength::length(rle), content="2")
  inspect(@rle.Spanning::span(rle), content="6")
}

///|
test "LvRange - Rle from_sorted_ints consecutive" {
  let rle : @rle.Rle[@core.LvRange] = @rle.Rle::from_sorted_ints(
    [0, 1, 2, 3, 4],
  )
  // 1 run: [0..5)
  inspect(@rle.HasLength::length(rle), content="1")
  inspect(@rle.Spanning::span(rle), content="5")
}

///|
test "LvRange - Rle iter_units roundtrip" {
  let ints = [0, 1, 2, 5, 6, 7]
  let rle : @rle.Rle[@core.LvRange] = @rle.Rle::from_sorted_ints(ints)
  let expanded = rle.iter_units().collect()
  inspect(expanded, content="[0, 1, 2, 5, 6, 7]")
}

///|
test "LvRange - Rle from_sorted_ints empty" {
  let rle : @rle.Rle[@core.LvRange] = @rle.Rle::from_sorted_ints([])
  inspect(@rle.HasLength::is_empty(rle), content="true")
  inspect(@rle.Spanning::span(rle), content="0")
}

///|
test "LvRange - Rle from_sorted_ints single" {
  let rle : @rle.Rle[@core.LvRange] = @rle.Rle::from_sorted_ints([42])
  inspect(@rle.HasLength::length(rle), content="1")
  inspect(@rle.Spanning::span(rle), content="1")
  let expanded = rle.iter_units().collect()
  inspect(expanded, content="[42]")
}
```

- [ ] **Step 4: Build and test**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker
moon check && moon test -p dowdiness/event-graph-walker/internal/core
```

- [ ] **Step 5: Update interfaces and format**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker
moon info && moon fmt
```

- [ ] **Step 6: Commit inside the submodule**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker
git add internal/core/lv_range.mbt internal/core/lv_range_test.mbt internal/core/moon.pkg internal/core/pkg.generated.mbti
git commit -m "feat(core): add LvRange type with RLE trait impls

Define LvRange { start, count } in core package for compressing
graph traversal results. Implements Mergeable, Spanning, FromRange,
Addressable traits from dowdiness/rle.

Part of RLE Phase 3: LvRange compression."
```

---

### Task 2: Update topological_sort to return Rle[LvRange]

**Files:**
- Modify: `event-graph-walker/internal/causal_graph/walker.mbt`
- Modify: `event-graph-walker/internal/causal_graph/moon.pkg`
- Modify: `event-graph-walker/internal/causal_graph/walker_test.mbt`

topological_sort produces output in LV order, which for linear histories is ascending and consecutive. Converting the output to `Rle[LvRange]` via `from_sorted_ints` compresses linear ranges efficiently.

- [ ] **Step 1: Add `dowdiness/rle` to causal_graph's moon.pkg**

Edit `/home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker/internal/causal_graph/moon.pkg`:

```
import {
  "dowdiness/event-graph-walker/internal/core",
  "dowdiness/rle",
  "moonbitlang/core/bench",
  "moonbitlang/core/queue",
  "moonbitlang/core/json",
  "moonbitlang/core/immut/hashmap" @immut/hashmap,
  "moonbitlang/core/immut/hashset" @immut/hashset,
  "moonbitlang/core/quickcheck",
  "moonbitlang/quickcheck" @qc,
}

options(
  is_main: false,
)
```

- [ ] **Step 2: Change topological_sort return type to Rle[LvRange]**

In `/home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker/internal/causal_graph/walker.mbt`, change the `topological_sort` function signature and compress the result:

Replace the return type and final lines of `topological_sort`. The function currently builds `result : Array[Int]` via Kahn's algorithm (lines 88-177). Change only the signature and the return value.

Replace:

```moonbit
fn topological_sort(
  graph : CausalGraph,
  versions : @immut/hashset.HashSet[Int],
) -> Array[Int] {
```

with:

```moonbit
fn topological_sort(
  graph : CausalGraph,
  versions : @immut/hashset.HashSet[Int],
) -> @rle.Rle[@core.LvRange] {
```

And at the end of the function, replace:

```moonbit
  result
```

with:

```moonbit
  @rle.Rle::from_sorted_ints(result)
```

Note: The result array from Kahn's algorithm is already in topological order (ascending LV for linear histories). `from_sorted_ints` groups consecutive integers into compressed `LvRange` runs. For linear histories, the entire output becomes a single run.

- [ ] **Step 3: Build and verify — expect compilation errors in downstream consumers**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker
moon check 2>&1 | head -30
```

Expected: Type errors in `walk_from_frontier`, `diff_frontiers_lvs`, and possibly walker_test.mbt. These are fixed in the next steps.

---

### Task 3: Update walk_from_frontier and diff_frontiers_lvs

**Files:**
- Modify: `event-graph-walker/internal/causal_graph/walker.mbt`
- Modify: `event-graph-walker/internal/causal_graph/walker_test.mbt`

Now that `topological_sort` returns `Rle[LvRange]`, update the two public functions that call it.

- [ ] **Step 1: Update walk_from_frontier**

In `/home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker/internal/causal_graph/walker.mbt`, replace:

```moonbit
pub fn CausalGraph::walk_from_frontier(
  self : CausalGraph,
  frontier : @core.Frontier,
) -> Array[Int] {
  // Get all versions reachable from frontier
  let reachable = collect_reachable_versions(self, frontier.0)

  // Sort them in topological order (respecting causal dependencies)
  topological_sort(self, reachable)
}
```

with:

```moonbit
pub fn CausalGraph::walk_from_frontier(
  self : CausalGraph,
  frontier : @core.Frontier,
) -> @rle.Rle[@core.LvRange] {
  // Get all versions reachable from frontier
  let reachable = collect_reachable_versions(self, frontier.0)

  // Sort them in topological order (respecting causal dependencies)
  topological_sort(self, reachable)
}
```

- [ ] **Step 2: Update diff_frontiers_lvs**

Replace the entire `diff_frontiers_lvs` function:

```moonbit
pub fn CausalGraph::diff_frontiers_lvs(
  self : CausalGraph,
  from_frontier : @core.Frontier,
  to_frontier : @core.Frontier,
) -> (@rle.Rle[@core.LvRange], @rle.Rle[@core.LvRange]) {
  // Use existing graph_diff to get the unsorted sets
  let (retreat_set, advance_set) = self.graph_diff(from_frontier, to_frontier)

  // Walk (topological sort) the retreat set, then reverse for undo order
  let retreat_rle = if retreat_set.length() > 0 {
    let reachable = @immut/hashset.from_array(retreat_set)
    let sorted = topological_sort(self, reachable)
    // Reverse the retreat LVs for undo order:
    // expand, reverse, re-compress
    let expanded = sorted.iter_units().collect()
    let reversed : Array[Int] = []
    for i = expanded.length() - 1; i >= 0; i = i - 1 {
      reversed.push(expanded[i])
    }
    // Note: reversed LVs are in descending order, so from_sorted_ints
    // won't merge them (each is a singleton). We build runs manually.
    // Descending consecutive LVs [5,4,3,1,0] stay as individual ranges.
    // This is correct — the consumer iterates units anyway.
    @rle.Rle::from_array(
      reversed.map(fn(lv) { @core.LvRange::{ start: lv, count: 1 } }),
    )
  } else {
    @rle.Rle::new()
  }

  // Walk (topological sort) the advance set
  let advance_rle = if advance_set.length() > 0 {
    let reachable = @immut/hashset.from_array(advance_set)
    topological_sort(self, reachable)
  } else {
    @rle.Rle::new()
  }
  (retreat_rle, advance_rle)
}
```

**Design note on retreat reversal:** Retreat LVs must be in reverse topological order (newest first) for undo. After reversing, the LVs are descending, so they can't form contiguous ascending ranges. Each reversed LV becomes a singleton `LvRange { start: lv, count: 1 }`. This is acceptable because:
1. Retreat sets are typically small (they only occur during concurrent merges).
2. The consumer iterates units anyway — the compressed container adds no overhead.
3. A future optimization could define a `ReversedLvRange` that compresses descending sequences, but this is not needed now.

- [ ] **Step 3: Update walker_test.mbt**

The tests access results via array indexing (`result[0]`, `result.length()`, `result.contains()`). Update them to use `iter_units()` expansion.

Replace the entire contents of `/home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker/internal/causal_graph/walker_test.mbt` with:

```moonbit
// Tests for Event Graph Walker

///|
test "walk empty frontier" {
  let graph = CausalGraph::new()
  let frontier = @core.Frontier::from_array([])
  let result = graph.walk_from_frontier(frontier)
  inspect(@rle.Spanning::span(result), content="0")
}

///|
test "walk single operation" {
  let graph = CausalGraph::new()

  // Add single operation with no parents
  let lv0 = try! graph.add_version([], "agent-1")
  let result = graph.walk_from_frontier(@core.Frontier::from_array([lv0]))
  let expanded = result.iter_units().collect()
  inspect(expanded.length(), content="1")
  inspect(expanded[0], content="0")
}

///|
test "walk linear history" {
  let graph = CausalGraph::new()

  // Create linear chain: 0 -> 1 -> 2 -> 3
  let lv0 = try! graph.add_version([], "agent-1")
  let lv1 = try! graph.add_version([lv0], "agent-1")
  let lv2 = try! graph.add_version([lv1], "agent-1")
  let lv3 = try! graph.add_version([lv2], "agent-1")
  let result = graph.walk_from_frontier(@core.Frontier::from_array([lv3]))

  // Linear history should compress to 1 run
  inspect(@rle.HasLength::length(result), content="1")
  inspect(@rle.Spanning::span(result), content="4")

  let expanded = result.iter_units().collect()
  inspect(expanded[0], content="0")
  inspect(expanded[1], content="1")
  inspect(expanded[2], content="2")
  inspect(expanded[3], content="3")
}

///|
test "walk diamond pattern (concurrent operations)" {
  let graph = CausalGraph::new()

  // Create diamond:
  //     0
  //    / \
  //   1   2
  //    \ /
  //     3
  let lv0 = try! graph.add_version([], "agent-1")
  let lv1 = try! graph.add_version([lv0], "agent-1")
  let lv2 = try! graph.add_version([lv0], "agent-2")
  let lv3 = try! graph.add_version([lv1, lv2], "agent-1")
  let result = graph.walk_from_frontier(@core.Frontier::from_array([lv3]))
  let expanded = result.iter_units().collect()

  // Should get all 4 operations
  inspect(expanded.length(), content="4")

  // lv0 must come first
  inspect(expanded[0], content="0")

  // lv1 and lv2 can be in any order (concurrent)
  // but both must come after lv0 and before lv3
  let has_lv1 = expanded.contains(1)
  let has_lv2 = expanded.contains(2)
  if not(has_lv1) {
    abort("Result should contain lv1")
  }
  if not(has_lv2) {
    abort("Result should contain lv2")
  }

  // lv3 must come last
  inspect(expanded[3], content="3")
}

///|
test "walk complex branching" {
  let graph = CausalGraph::new()

  // Create complex graph:
  //       0
  //      / \
  //     1   2
  //     |   |\
  //     3   4 5
  //      \ /
  //       6
  let lv0 = try! graph.add_version([], "agent-1")
  let lv1 = try! graph.add_version([lv0], "agent-1")
  let lv2 = try! graph.add_version([lv0], "agent-2")
  let lv3 = try! graph.add_version([lv1], "agent-1")
  let lv4 = try! graph.add_version([lv2], "agent-2")
  let _lv5 = try! graph.add_version([lv2], "agent-3")
  let lv6 = try! graph.add_version([lv3, lv4], "agent-1")
  let result = graph.walk_from_frontier(@core.Frontier::from_array([lv6]))
  let expanded = result.iter_units().collect()

  // Should get operations 0,1,2,3,4,6 (not 5, as it's not in the path to 6)
  inspect(expanded.length(), content="6")

  // Verify lv0 is first
  inspect(expanded[0], content="0")

  // Verify lv6 is last
  inspect(expanded[5], content="6")

  // Verify all expected versions are present
  if not(expanded.contains(0)) {
    abort("Should contain lv0")
  }
  if not(expanded.contains(1)) {
    abort("Should contain lv1")
  }
  if not(expanded.contains(2)) {
    abort("Should contain lv2")
  }
  if not(expanded.contains(3)) {
    abort("Should contain lv3")
  }
  if not(expanded.contains(4)) {
    abort("Should contain lv4")
  }

  // lv5 should NOT be present (not in path to lv6)
  if expanded.contains(5) {
    abort("Should NOT contain lv5")
  }
}

///|
test "walk with multiple frontier versions" {
  let graph = CausalGraph::new()

  // Create divergent branches:
  //     0
  //    / \
  //   1   2
  //   |   |
  //   3   4
  let lv0 = try! graph.add_version([], "agent-1")
  let lv1 = try! graph.add_version([lv0], "agent-1")
  let lv2 = try! graph.add_version([lv0], "agent-2")
  let lv3 = try! graph.add_version([lv1], "agent-1")
  let lv4 = try! graph.add_version([lv2], "agent-2")

  // Walk from frontier [3, 4] (both branches)
  let result = graph.walk_from_frontier(
    @core.Frontier::from_array([lv3, lv4]),
  )
  let expanded = result.iter_units().collect()

  // Should get all operations
  inspect(expanded.length(), content="5")

  // lv0 should be first
  inspect(expanded[0], content="0")

  // All versions should be present
  for i = 0; i < 5; i = i + 1 {
    if not(expanded.contains(i)) {
      abort("Should contain lv\{i}")
    }
  }
}

///|
test "diff_frontiers_lvs for incremental update" {
  let graph = CausalGraph::new()

  // Create initial operations
  let _lv0 = try! graph.add_version([], "agent-1")
  let _lv1 = try! graph.add_version([0], "agent-1")
  let frontier1 = graph.get_frontier()

  // Add more operations
  let _lv2 = try! graph.add_version([1], "agent-1")
  let _lv3 = try! graph.add_version([2], "agent-1")
  let frontier2 = graph.get_frontier()

  // Calculate diff
  let (retreat_rle, advance_rle) = graph.diff_frontiers_lvs(
    frontier1, frontier2,
  )

  // No retreat LVs (moving forward)
  inspect(@rle.Spanning::span(retreat_rle), content="0")

  // Should have 2 advance LVs, compressed to 1 run (consecutive)
  inspect(@rle.HasLength::length(advance_rle), content="1")
  inspect(@rle.Spanning::span(advance_rle), content="2")

  // Verify advance LVs are correct (2 and 3)
  let advance_expanded = advance_rle.iter_units().collect()
  inspect(advance_expanded[0], content="2")
  inspect(advance_expanded[1], content="3")
}

///|
test "topological sort determinism" {
  // Test that concurrent operations have deterministic ordering
  let graph = CausalGraph::new()

  // Create concurrent operations with same parent
  let lv0 = try! graph.add_version([], "agent-1")
  let lv1 = try! graph.add_version([lv0], "agent-2")
  let lv2 = try! graph.add_version([lv0], "agent-3")
  let lv3 = try! graph.add_version([lv0], "agent-1")
  let result = graph.walk_from_frontier(
    @core.Frontier::from_array([lv1, lv2, lv3]),
  )
  let expanded = result.iter_units().collect()

  // lv0 must be first
  inspect(expanded[0], content="0")

  // Concurrent operations (1, 2, 3) should be sorted by LV for determinism
  inspect(expanded[1], content="1")
  inspect(expanded[2], content="2")
  inspect(expanded[3], content="3")
}

///|
test "walk_from_frontier linear compression" {
  let graph = CausalGraph::new()

  // Create linear chain: 0 -> 1 -> 2 -> ... -> 9
  let _lv0 = try! graph.add_version([], "agent-1")
  for i = 1; i < 10; i = i + 1 {
    let _ = try! graph.add_version([i - 1], "agent-1")

  }
  let result = graph.walk_from_frontier(graph.get_frontier())

  // 10 consecutive LVs should compress to exactly 1 run
  inspect(@rle.HasLength::length(result), content="1")
  inspect(@rle.Spanning::span(result), content="10")
}

///|
test "diff_frontiers_lvs compression ratio" {
  let graph = CausalGraph::new()

  // Build 100 linear operations
  let _lv0 = try! graph.add_version([], "agent-1")
  for i = 1; i < 100; i = i + 1 {
    let _ = try! graph.add_version([i - 1], "agent-1")

  }
  let empty = @core.Frontier::from_array([])
  let full = graph.get_frontier()
  let (retreat_rle, advance_rle) = graph.diff_frontiers_lvs(empty, full)

  // No retreat
  inspect(@rle.Spanning::span(retreat_rle), content="0")

  // 100 consecutive advance LVs -> 1 run
  inspect(@rle.HasLength::length(advance_rle), content="1")
  inspect(@rle.Spanning::span(advance_rle), content="100")
}
```

- [ ] **Step 4: Build and test causal_graph (expect downstream errors)**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker
moon check 2>&1 | head -30
moon test -p dowdiness/event-graph-walker/internal/causal_graph
```

Expected: causal_graph tests pass. oplog and branch packages will have type errors (fixed in Tasks 4-5).

- [ ] **Step 4b: Verify walker_benchmark.mbt compiles without changes**

Verify `walker_benchmark.mbt` compiles without changes (it uses `b.keep(result)` which is type-agnostic).

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker
moon check 2>&1 | grep -i walker_benchmark || echo "No benchmark errors"
```

- [ ] **Step 5: Commit inside the submodule**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker
git add internal/causal_graph/walker.mbt internal/causal_graph/walker_test.mbt internal/causal_graph/moon.pkg internal/causal_graph/pkg.generated.mbti
git commit -m "feat(causal_graph): return Rle[LvRange] from topological_sort/walk/diff

Change topological_sort, walk_from_frontier, and diff_frontiers_lvs to
return Rle[LvRange] instead of Array[Int]. Linear histories now compress
to a single run instead of N individual integers.

Part of RLE Phase 3: LvRange compression."
```

---

### Task 4: Update OpLog walker functions

**Files:**
- Modify: `event-graph-walker/internal/oplog/walker.mbt`
- Modify: `event-graph-walker/internal/oplog/oplog.mbt`
- Modify: `event-graph-walker/internal/oplog/moon.pkg`

The oplog walker functions call `walk_from_frontier` and `diff_frontiers_lvs`, which now return `Rle[LvRange]`. We need to update `get_ops` to accept `Rle[LvRange]` and update the walker functions.

- [ ] **Step 1: Add `dowdiness/rle` to oplog's moon.pkg**

Edit `/home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker/internal/oplog/moon.pkg`:

```
import {
  "dowdiness/event-graph-walker/internal/core",
  "dowdiness/event-graph-walker/internal/causal_graph",
  "dowdiness/rle",
  "moonbitlang/core/bench",
  "moonbitlang/core/json",
  "moonbitlang/core/immut/hashset" @immut/hashset,
}

options(
  is_main: false,
)
```

- [ ] **Step 2: Add get_ops_rle overload**

In `/home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker/internal/oplog/oplog.mbt`, add a new function after the existing `get_ops`:

```moonbit
///|
/// Collect operations for an RLE-compressed list of LV ranges.
///
/// Expands the compressed ranges and looks up each LV, silently skipping
/// any invalid index. This is the compressed counterpart of `get_ops`.
pub fn OpLog::get_ops_rle(
  self : OpLog,
  lvs : @rle.Rle[@core.LvRange],
) -> Array[@core.Op] {
  let result : Array[@core.Op] = []
  for lv in lvs.iter_units() {
    match self.get_op(lv) {
      Some(op) => result.push(op)
      None => ()
    }
  }
  result
}
```

- [ ] **Step 3: Update walker.mbt functions**

Replace the entire contents of `/home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker/internal/oplog/walker.mbt` with:

```moonbit
///| OpLog-specific walker functions
/// Wraps the generic causal graph walker with operation collection

///|
/// Walk the operation log from a frontier, collecting operations in causal order
///
/// # Arguments
/// * `frontier` - Starting frontier
///
/// # Returns
/// Array of operations in topological (causal) order
pub fn OpLog::walk_and_collect(
  self : OpLog,
  frontier : @core.Frontier,
) -> Array[@core.Op] {
  // Use the causal graph walker
  self.get_ops_rle(self.graph.walk_from_frontier(frontier))
}

///|
/// Walk the operation log from a frontier, returning only operations that
/// satisfy `predicate`.
///
/// Equivalent to `walk_and_collect(frontier).filter(predicate)`.
/// Useful for replaying a subset of operation types — for example,
/// insert-only or delete-only passes during diff computation.
///
/// # Arguments
/// * `frontier` - Starting frontier
/// * `predicate` - Filter function; return `true` to include an operation
///
/// # Returns
/// Matching operations in topological (causal) order
pub fn OpLog::walk_filtered(
  self : OpLog,
  frontier : @core.Frontier,
  predicate : (@core.Op) -> Bool,
) -> Array[@core.Op] {
  self.walk_and_collect(frontier).filter(predicate)
}

///|
/// Calculate diff between two frontiers and return operations to apply
///
/// # Returns
/// (retreat_ops, advance_ops) - operations to undo and redo
///
/// retreat_ops are in reverse order (for undo)
/// advance_ops are in forward order (for redo)
pub fn OpLog::diff_and_collect(
  self : OpLog,
  from_frontier : @core.Frontier,
  to_frontier : @core.Frontier,
) -> (Array[@core.Op], Array[@core.Op]) {
  // Use the causal graph diff
  let (retreat_rle, advance_rle) = self.graph.diff_frontiers_lvs(
    from_frontier, to_frontier,
  )

  // (in reverse order, in forward order)
  (self.get_ops_rle(retreat_rle), self.get_ops_rle(advance_rle))
}
```

- [ ] **Step 4: Build and test oplog**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker
moon check 2>&1 | head -30
moon test -p dowdiness/event-graph-walker/internal/oplog
```

Expected: oplog tests pass. Branch tests may still fail (fixed in Task 5).

- [ ] **Step 5: Update interfaces and format**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker
moon info && moon fmt
```

- [ ] **Step 6: Commit inside the submodule**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker
git add internal/oplog/walker.mbt internal/oplog/oplog.mbt internal/oplog/moon.pkg internal/oplog/pkg.generated.mbti
git commit -m "feat(oplog): add get_ops_rle, update walker to use Rle[LvRange]

Add OpLog::get_ops_rle that accepts Rle[LvRange] and expands ranges
to look up individual ops. Update walk_and_collect and diff_and_collect
to use the new Rle-based causal_graph APIs.

Part of RLE Phase 3: LvRange compression."
```

---

### Task 5: Update branch consumers (checkout, advance)

**Files:**
- Modify: `event-graph-walker/internal/branch/branch.mbt` (no changes needed — already calls `walk_and_collect` and `diff_and_collect` which return `Array[Op]`)
- Verify: `event-graph-walker/internal/branch/branch_test.mbt`

**Important check:** `Branch::checkout` calls `oplog.walk_and_collect(frontier)` which returns `Array[@core.Op]` (unchanged). `Branch::advance` calls `self.oplog.diff_and_collect(...)` which returns `(Array[@core.Op], Array[@core.Op])` (unchanged). These are **not affected** because the oplog walker functions still return `Array[Op]` — the RLE compression is internal to the causal_graph/oplog boundary.

- [ ] **Step 1: Verify branch compiles and tests pass without changes**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker
moon check && moon test -p dowdiness/event-graph-walker/internal/branch
```

Expected: All branch tests pass. No code changes needed in branch.mbt because `walk_and_collect` and `diff_and_collect` still return `Array[Op]`.

---

### Task 6: Update merge() to use diff_frontiers_lvs instead of raw graph_diff

**Files:**
- Modify: `event-graph-walker/internal/branch/branch_merge.mbt`
- Modify: `event-graph-walker/internal/branch/moon.pkg`
- Modify: `event-graph-walker/internal/branch/branch_merge_test.mbt`

The `merge()` function currently calls `graph_diff()` directly, which returns **unsorted** arrays. It passes these unsorted arrays to `retreat_operations` and `apply_operations`. While `apply_operations` does an internal sort, `retreat_operations` iterates the array as-is — meaning retreat order is non-deterministic (depends on HashSet iteration order). This is a latent bug.

Switching to `diff_frontiers_lvs` (which returns topologically sorted, Rle-compressed results) fixes this issue and integrates the RLE compression.

- [ ] **Step 1: Add `dowdiness/rle` to branch's moon.pkg**

Edit `/home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker/internal/branch/moon.pkg`:

```
import {
  "dowdiness/event-graph-walker/internal/core",
  "dowdiness/event-graph-walker/internal/causal_graph",
  "dowdiness/event-graph-walker/internal/oplog",
  "dowdiness/event-graph-walker/internal/fugue",
  "dowdiness/rle",
  "moonbitlang/core/bench",
}

options(
  is_main: false,
)
```

- [ ] **Step 2: Update MergeContext methods to accept Rle[LvRange]**

In `/home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker/internal/branch/branch_merge.mbt`, replace `apply_operations` and `retreat_operations`:

Replace:

```moonbit
pub fn MergeContext::apply_operations(
  self : MergeContext,
  operations : Array[Int],
) -> Unit raise BranchError {
  // Sort operations by LV (which gives us topological order due to the way LVs are assigned)
  let sorted_ops = operations.copy()
  sorted_ops.sort()

  let cg = self.oplog.causal_graph()

  // Apply each operation in order
  for lv in sorted_ops {
```

with:

```moonbit
pub fn MergeContext::apply_operations(
  self : MergeContext,
  operations : @rle.Rle[@core.LvRange],
) -> Unit raise BranchError {
  let cg = self.oplog.causal_graph()

  // Apply each operation in order (Rle is already topologically sorted)
  for lv in operations.iter_units() {
```

Keep the body of the for-loop (lines 39-103) unchanged.

Replace:

```moonbit
pub fn MergeContext::retreat_operations(
  self : MergeContext,
  operations : Array[Int],
) -> Unit raise BranchError {
  // For simplicity, we mark retreated items as deleted
  // A more sophisticated implementation would actually remove them
  for lv in operations {
    self.tree.delete(@fugue.Lv(lv)) catch {
      e => raise BranchError::Fugue(e)
    }
  }
}
```

with:

```moonbit
pub fn MergeContext::retreat_operations(
  self : MergeContext,
  operations : @rle.Rle[@core.LvRange],
) -> Unit raise BranchError {
  // Mark retreated items as deleted (in reverse topological order,
  // as provided by diff_frontiers_lvs)
  for lv in operations.iter_units() {
    self.tree.delete(@fugue.Lv(lv)) catch {
      e => raise BranchError::Fugue(e)
    }
  }
}
```

- [ ] **Step 3: Update merge() to use diff_frontiers_lvs**

Replace:

```moonbit
pub fn merge(
  tree : @fugue.FugueTree[String],
  oplog : @oplog.OpLog,
  current_frontier : @core.Frontier,
  target_frontier : @core.Frontier,
) -> Unit raise BranchError {
  // Calculate retreat and advance sets
  let (retreat_ops, advance_ops) = oplog
    .causal_graph()
    .graph_diff(current_frontier, target_frontier)
  let ctx = MergeContext::new(tree, oplog)

  // Phase 1: Retreat - remove operations not in target
  ctx.retreat_operations(retreat_ops)

  // Phase 2: Advance - apply operations in target
  ctx.apply_operations(advance_ops)
}
```

with:

```moonbit
pub fn merge(
  tree : @fugue.FugueTree[String],
  oplog : @oplog.OpLog,
  current_frontier : @core.Frontier,
  target_frontier : @core.Frontier,
) -> Unit raise BranchError {
  // Calculate retreat and advance sets (topologically sorted, RLE-compressed)
  let (retreat_rle, advance_rle) = oplog
    .causal_graph()
    .diff_frontiers_lvs(current_frontier, target_frontier)
  let ctx = MergeContext::new(tree, oplog)

  // Phase 1: Retreat - remove operations not in target (reverse topo order)
  ctx.retreat_operations(retreat_rle)

  // Phase 2: Advance - apply operations in target (topo order)
  ctx.apply_operations(advance_rle)
}
```

- [ ] **Step 4: Update branch_merge_test.mbt**

The tests that call `apply_operations` and `retreat_operations` directly pass `Array[Int]`. Convert those to `Rle[LvRange]`.

In `/home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker/internal/branch/branch_merge_test.mbt`:

Replace every direct call to `ctx.apply_operations([...])` and `ctx.retreat_operations([...])` to wrap the array as `Rle[LvRange]`:

Replace:
```moonbit
    ctx.apply_operations([999])
```
with:
```moonbit
    ctx.apply_operations(
      @rle.Rle::from_array([@core.LvRange::{ start: 999, count: 1 }]),
    )
```

Replace:
```moonbit
    ctx.apply_operations([op2.lv()])
```
with:
```moonbit
    ctx.apply_operations(
      @rle.Rle::from_array([@core.LvRange::{ start: op2.lv(), count: 1 }]),
    )
```

Replace:
```moonbit
    ctx.retreat_operations([999])
```
with:
```moonbit
    ctx.retreat_operations(
      @rle.Rle::from_array([@core.LvRange::{ start: 999, count: 1 }]),
    )
```

There are 4 occurrences total across 4 test functions:
1. `"merge error - missing op during apply"` — `ctx.apply_operations([999])`
2. `"merge error - apply operations succeeds for valid ops"` — `ctx.apply_operations([op2.lv()])`
3. `"merge error - state unchanged after failure"` — `ctx.apply_operations([999])`
4. `"retreat then apply with missing item"` — `ctx.retreat_operations([999])`

- [ ] **Step 5: Build and test the full suite**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker
moon check && moon test
```

Expected: All tests pass.

- [ ] **Step 6: Update interfaces and format**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker
moon info && moon fmt
```

- [ ] **Step 7: Commit inside the submodule**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker
git add internal/branch/branch_merge.mbt internal/branch/branch_merge_test.mbt internal/branch/moon.pkg internal/branch/pkg.generated.mbti
git commit -m "feat(branch): use Rle[LvRange] in merge context, fix unsorted retreat bug

Switch merge() from graph_diff (unsorted) to diff_frontiers_lvs
(topologically sorted, RLE-compressed). This fixes a latent bug where
retreat_operations received operations in non-deterministic HashSet
iteration order.

MergeContext::apply_operations and retreat_operations now accept
Rle[LvRange] and iterate via iter_units(). apply_operations no longer
needs an internal sort since the input is already ordered.

Part of RLE Phase 3: LvRange compression."
```

---

### Task 7: Full test suite, snapshot updates, final formatting

**Files:**
- All modified `.mbti` files
- Any snapshot files that need updating

- [ ] **Step 1: Run full test suite in event-graph-walker**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker
moon test
```

- [ ] **Step 2: Update snapshots if any behavior changed**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker
moon test --update
```

- [ ] **Step 3: Run full test suite in root crdt module**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0
moon test
```

- [ ] **Step 4: Final moon info and moon fmt**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker
moon info && moon fmt
```

- [ ] **Step 5: Verify no unexpected API changes**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker
git diff *.mbti
```

Expected changes:
- `internal/core/pkg.generated.mbti` — new `LvRange` struct and methods
- `internal/causal_graph/pkg.generated.mbti` — `walk_from_frontier` and `diff_frontiers_lvs` return types changed to use `Rle[LvRange]`
- `internal/oplog/pkg.generated.mbti` — new `get_ops_rle` method
- `internal/branch/pkg.generated.mbti` — `MergeContext` methods accept `Rle[LvRange]`

- [ ] **Step 6: Commit any remaining changes inside submodule**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0/event-graph-walker
git add -A
git status
```

If there are any remaining uncommitted changes (snapshot updates, etc.):

```bash
git commit -m "chore: update snapshots and interfaces for RLE Phase 3"
```

---

### Task 8: Commit parent repo submodule pointer

**Files:**
- Modify: `event-graph-walker` (submodule pointer)

- [ ] **Step 1: Stage and commit the submodule pointer in parent repo**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0
git add event-graph-walker
git status
```

```bash
git commit -m "chore: update event-graph-walker submodule (RLE Phase 3: LvRange compression)

Compresses graph traversal results using Rle[LvRange]:
- topological_sort, walk_from_frontier, diff_frontiers_lvs return Rle[LvRange]
- Linear editing sessions compress N integers to 1 run
- merge() now uses diff_frontiers_lvs (fixes unsorted retreat bug)"
```

- [ ] **Step 2: Verify final state**

```bash
cd /home/antisatori/ghq/github.com/dowdiness/canopy/.worktrees/rle-phase0
git status
git submodule status event-graph-walker
```

Expected: Clean working tree, submodule showing updated commit hash.
