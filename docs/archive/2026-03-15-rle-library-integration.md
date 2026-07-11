# Plan: RLE Library Integration for Event Graph Walker

**Status:** Proposed
**Date:** 2026-03-15
**Related:** [dowdiness/rle](https://github.com/dowdiness/rle), [Architecture](../architecture/README.md)

---

## Context

The `event-graph-walker/internal/rle/` package (~2,600 lines including tests)
is an earlier version of the standalone `dowdiness/rle` library. The two share
identical algorithms (stack-based merge, lazy prefix sums, cursor staleness
detection) but have diverged:

| Feature | Internal RLE | dowdiness/rle |
|---------|-------------|---------------|
| Trait naming | `HasCausalLength`, `causal_len`, `visible_len` | `Spanning`, `span`, `logical_length` |
| `Sliceable::slice` return | `Self` | `Result[Self, RleError]` |
| `Slice::to_inner` return | `T` | `Result[T, RleError]` |
| Error variants | `RleError` (basic) | `RleError` + `InvalidSlice(SliceError)` |
| `insert`/`delete`/`splice` | Not implemented | Implemented |
| `value_at(pos)` | Not implemented | Implemented |
| `extend` version bump | Conservative (false positives) | Tightened (compares last-run span) |
| UTF-16 surrogate validation | None | Built-in via `slice_string_view` |
| Property tests | None | 18 QuickCheck properties |
| `HasLength::is_empty` default | Not present | Present |
| `logical_length` default | Not present (`visible_len` required) | Defaults to `span()` |

**Important:** No package in `event-graph-walker` currently imports
`internal/rle`. The internal package is self-contained with its own tests and
benchmarks but has zero external consumers. This means Phase 0 is simply
deleting dead code and adding a dependency. Phases 1–3 introduce RLE into
packages that currently have no RLE dependency at all.

This plan covers four improvements, ordered by dependency:

1. **Phase 0** — Replace internal RLE with `dowdiness/rle`
2. **Phase 1** — RLE-compress the operation log
3. **Phase 2** — RLE-compress document position mappings
4. **Phase 3** — RLE-compress graph traversal result sets

---

## Phase 0: Replace Internal RLE

### Goal

Delete `event-graph-walker/internal/rle/` (~2,600 lines) and add
`dowdiness/rle` as a dependency. No other package in event-graph-walker needs
updating (the internal RLE has zero consumers).

### Migration Map

For reference when Phases 1–3 implement `Spanning`/`Sliceable` for new types:

| Internal | External (`dowdiness/rle`) |
|----------|---------------------------|
| `HasCausalLength` | `Spanning` |
| `causal_len()` | `span()` |
| `visible_len()` | `logical_length()` |
| `Runs::count()` | `Runs::length()` |
| `Runs::len()` | `Runs::span()` |
| `Rle::count()` | `Rle::length()` |
| `Rle::len()` | `Rle::span()` |
| `PrefixSums.atoms` | `PrefixSums.spans` |
| `PrefixSums::len()` | `PrefixSums::span()` |
| `PrefixSums::visible_len()` | `PrefixSums::logical_length()` |
| `PrefixSums::atom_at()` | `PrefixSums::span_at()` |
| `PrefixSums::atom_before()` | `PrefixSums::span_before()` |
| `Sliceable::slice(...) -> Self` | `Sliceable::slice(...) -> Result[Self, RleError]` |
| `Slice::to_inner() -> T` | `Slice::to_inner() -> Result[T, RleError]` |

### Steps

1. Add `dowdiness/rle` as a git submodule in the monorepo root (consistent
   with how `event-graph-walker`, `loom`, `graphviz`, etc. are managed):
   ```bash
   git submodule add https://github.com/dowdiness/rle.git rle
   ```
2. Add path dependency in `event-graph-walker/moon.mod.json`:
   ```json
   "dowdiness/rle": { "path": "../rle" }
   ```
3. Delete `event-graph-walker/internal/rle/` directory
4. Run all tests (no consumer code changes needed — zero importers)
5. Update `docs/architecture/modules.md` dependency diagram

### Risk

Negligible. The internal RLE has zero consumers. Phase 0 is deleting dead
code and adding a dependency that Phases 1–3 will consume.

### Behavioral note

The external library's `extend` uses a tighter version-bump heuristic
(compares last-run span) than the internal library's conservative approach.
If any future code relies on the bump being conservative, this difference
matters. Document in the commit message.

---

## Phase 1: RLE-Compress the Operation Log

### Problem

`OpLog.operations : Array[Op]` stores every operation individually. When a
user types "hello world", 11 separate `Op` structs are created with nearly
identical metadata. These share the same agent, have sequential LVs and seq
numbers, and each parent is the previous op. This is the dominant pattern
during normal typing.

### Design

Define an `OpRun` type that compresses consecutive operations from the same
agent:

```moonbit
struct OpRun {
  start_lv : Int                  // First LV in this run
  agent : String                  // All ops share this agent
  start_seq : Int                 // First seq number
  content : OpRunContent          // Compressed content
  parents : Array[RawVersion]     // Parents of the FIRST op in the run
  origin_left : RawVersion?       // Origin left of first op
  origin_right : RawVersion?      // Origin right of first op
  count : Int                     // Number of ops in run
}

enum OpRunContent {
  Inserts(String)   // Concatenated inserted text (e.g., "hello world")
  Deletes           // count consecutive deletes
  Undeletes         // count consecutive undeletes
}
```

**Merge condition** (`can_merge`): Two ops merge when:
- Same `agent`
- Sequential `seq` numbers (`a.start_seq + a.count == b.start_seq`)
- Sequential LVs (`a.start_lv + a.count == b.start_lv`)
- Same content type (both Insert, both Delete, or both Undelete)
- The second op's only parent is the end of the first run
  (`b.parents == [RawVersion(a.agent, a.start_seq + a.count - 1)]`)
- For inserts: the second op's `origin_left` is the previous op's LV, and
  `origin_right` equals the first op's `origin_right` (cursor hasn't moved
  past a different item). This ensures linear left-to-right typing only.

**Decompression** (`get_op(lv)`): Given a run containing LV `k` at offset
`j = k - start_lv`:
- `parents`: if `j == 0`, use `self.parents`; otherwise `[RawVersion(agent, start_seq + j - 1)]`
- `origin_left`: if `j == 0`, use `self.origin_left`; otherwise `Some(RawVersion(agent, start_seq + j - 1))`
- `origin_right`: always `self.origin_right` (all ops in a linear typing run
  share the same right neighbor)
- `content`: for `Inserts(s)`, extract the single character at position `j`
  using `slice_string_view` for UTF-16 safety

**Span**: `span(self) = self.count` (one position per op in the causal space)

**Logical length**: `logical_length(self) = self.count` (number of ops, not
text length — the position space is ops, not characters)

**Sliceable**: `OpRun::slice` must use `slice_string_view` when slicing
`Inserts(String)` content to correctly handle UTF-16 surrogate pair
boundaries. For `Deletes`/`Undeletes`, slicing only adjusts `count`.

### Storage Change

```
Before: OpLog { operations : Array[Op], ... }
After:  OpLog { operations : Rle[OpRun], ... }
```

### Impact on Existing APIs

| Function | Current | After |
|----------|---------|-------|
| `get_op(lv)` | `operations[lv]` O(1) | `operations.find(lv)` + decompress, O(log n) |
| `op_count()` | `operations.length()` | `operations.span()` O(1) with cache |
| `get_all_ops()` | `operations.copy()` | Iterate and expand runs |
| `insert(text, ...)` | Push single Op | `operations.append(OpRun)` — auto-merges with previous |
| `walk_and_collect` | Linear scan of Array[Op] | `operations.range(start, end)` — O(log n + k) |

### Trade-off

`get_op(lv)` goes from O(1) to O(log n). This is acceptable because:
- `get_op` is called during merge (which is already O(n) in the number of ops being merged)
- The O(log n) cost is amortized over the massive memory savings
- Diamond Types (the reference Rust implementation) makes the same trade-off

### Estimated Compression

| Scenario | Ops | Runs | Ratio |
|----------|-----|------|-------|
| Single user types 10,000 chars | 10,000 | ~1 | 10,000:1 |
| Single user types then deletes 100 chars | 200 | ~2 | 100:1 |
| Two users alternating single chars | 100 | ~100 | 1:1 (worst case) |
| Two users typing paragraphs in turns | 1,000 | ~20 | 50:1 |

### Risk

Medium. The merge condition must be precisely correct — an over-eager merge
that drops `origin_right` information causes silent data corruption during
concurrent merges. Thorough property testing against the uncompressed
representation is essential.

---

## Phase 2: RLE-Compress Document Position Mappings

### Problem

`Document.position_cache : Array[(Lv, Item[String])]?` stores every visible
item individually. Two hot-path operations are affected:

- `lv_to_position(lv)` — O(n) linear search through visible items array
- `position_to_lv(pos)` — O(1) via array index after cache is built, but cache rebuild is O(n) tree traversal

For a 50,000-character document, the position cache holds 50,000 tuples.
Every mutation invalidates it, triggering a full tree traversal.

### Design

Define a `VisibleRun` type for consecutive visible items:

```moonbit
struct VisibleRun {
  start_lv : Int    // First LV in this visible run
  text : String     // Concatenated visible text
  count : Int       // Number of items in run
}
```

**Merge condition**: Adjacent in document order, consecutive LVs, both
visible (not deleted). Note: two items with consecutive LVs may be
non-adjacent in document order if concurrent edits interleaved between them.
The merge condition must check document-order adjacency, not just LV
adjacency.

**Note**: The `agent` field is intentionally omitted — the position cache
only cares about document order and LV identity, not which agent created the
items. This improves compression in multi-agent documents.

**Span**: `span(self) = self.count` (one item per position in the item space)
**Logical length**: `logical_length(self) = self.text.length()` (visible
character count in UTF-16 code units)

### Storage Change

```
Before: position_cache : Array[(Lv, Item[String])]?
After:  position_cache : Rle[VisibleRun]?
```

### Performance Gains

| Operation | Current | After |
|-----------|---------|-------|
| `lv_to_position(lv)` | O(n) linear scan | O(log n) binary search via `find()` |
| `position_to_lv(pos)` | O(1) array index | O(log n) via `find()` |
| Cache memory (50K chars, single author) | 50,000 tuples | ~1 run |
| Cache rebuild | O(n) tree traversal, 50K pushes | O(n) traversal, ~k appends |

### Scope

Phase 2 is **compression-only**: the cache is still fully rebuilt on every
mutation (O(n) tree traversal). The improvement is that the rebuilt cache is
smaller in memory and enables O(log n) lookups via prefix sums.

### Incremental Cache Updates (Future, not in this plan)

With RLE, partial cache invalidation becomes feasible: instead of rebuilding
the entire cache on mutation, insert/delete a single run at the mutation
point using `Rle::insert`/`Rle::delete`. This would make cache maintenance
O(log n) per mutation instead of O(n). This is a separate effort that builds
on Phase 2's data structure change.

### Data source

The position cache is built from `self.tree.get_visible_items()` (FugueTree
traversal), not from the OpLog. Phase 2 is independent of Phase 1's OpRun
compression.

### Risk

Medium. The merge condition requires document-order adjacency checking during
cache construction, which couples the compression logic to the FugueTree's
iteration order. Incorrect merging would silently corrupt position lookups.

---

## Phase 3: RLE-Compress Graph Traversal Results

### Problem

The three-phase merge algorithm produces arrays of LVs for retreat and
advance:

```moonbit
let (retreat_lvs, advance_lvs) = oplog.causal_graph().graph_diff(current_frontier, target_frontier)
```

For a linear editing session, `advance_lvs` is `[0, 1, 2, ..., 999]` — 1,000
integers for what could be a single range `{start: 0, count: 1000}`.

### Design

Define an `LvRange` type for consecutive local versions:

```moonbit
struct LvRange {
  start : Int
  count : Int
}
```

**Merge condition**: `a.start + a.count == b.start` (contiguous ranges)
**Span**: `span(self) = self.count`
**Logical length**: Same as span (no tombstones at this level)

### Prerequisite: Sort before compress

`graph_diff` currently returns unsorted arrays from hashset iteration (see
`graph.mbt` line 246: "Both sets are returned as unsorted arrays"). Converting
to `Rle[LvRange]` requires sorting first. The sort is O(n log n) but runs
once per merge, and the subsequent iteration over compressed ranges is cheaper
than iterating n individual integers.

`topological_sort` already returns results in topological order, which for
linear histories is ascending LV order. For concurrent histories, the output
interleaves LVs from different agents, producing fragmented ranges — the
compression benefit depends on the concurrency pattern.

### Storage Change

```
Before: topological_sort() -> Array[Int]
After:  topological_sort() -> Rle[LvRange]

Before: graph_diff() -> (Array[Int], Array[Int])
After:  graph_diff() -> (Rle[LvRange], Rle[LvRange])
```

### Performance Gains

| Operation | Current | After |
|-----------|---------|-------|
| Diff for linear 10K ops | 10,000-element array | ~1 LvRange run |
| Memory for linear merge | O(n) integers | O(1) single run |
| Slicing diff result | O(n) array copy | O(log n) `Rle::split` |

Note: The retreat/advance phases still iterate through individual LVs (each
LV maps to a distinct tree operation), so the per-op iteration cost is
unchanged. The gains are in memory allocation and diff computation for common
non-concurrent editing patterns.

### Risk

Low for `topological_sort` (already ordered). Medium for `graph_diff`
(requires sorting unsorted hashset output). The sort cost is acceptable but
should be benchmarked against the current approach to verify net benefit,
especially for highly concurrent traces where runs are short.

---

## Implementation Order and Dependencies

```
Phase 0: Delete internal RLE, add dowdiness/rle dependency
    ↓
    ├── Phase 1: OpRun compression (oplog package)
    ├── Phase 2: VisibleRun compression (document package, independent of Phase 1)
    └── Phase 3: LvRange compression (causal_graph + branch packages, independent of Phase 1)
```

**Phase 0** is prerequisite for all others (provides the `Rle` container
type). Phases 1, 2, and 3 are independent of each other and can be
implemented in any order or in parallel. Phase 2 reads from FugueTree, not
OpLog, so it does not depend on Phase 1.

## Validation

Each phase should be validated by:
1. All existing tests pass after migration
2. Memory usage comparison on the existing test editing traces
3. Benchmark `position_to_lv` and `lv_to_position` before/after Phase 2
4. Property test: uncompressed and compressed representations produce
   identical results for all operations (critical for Phase 1)
5. Update `docs/architecture/modules.md` dependency diagram after Phase 0
