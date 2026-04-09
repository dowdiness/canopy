# Generic B-tree Library Extraction

## Why

OrderTree's B-tree implementation is ~4,500 lines with a clean internal split: ~1,150 lines
of generic B-tree machinery (types, navigation, balancing, propagation) and ~3,300 lines of
RLE-specific logic (leaf splice computation, public API, tests). The generic portion has
**zero type-level coupling** to rle — all rle dependencies are function-level via trait bounds
on leaf computation functions.

Extracting `lib/btree/` gives us a reusable counted B-tree with balanced mutations,
usable by any consumer that needs O(log n) indexed access with insert/delete — not just
OrderTree with its RLE semantics.

## Scope

In:
- `order-tree/src/types.mbt` — node/cursor/splice type definitions
- `order-tree/src/walker_types.mbt` — internal cursor types
- `order-tree/src/walker_descend.mbt` — descent engine (except `each_slice_in_range`)
- `order-tree/src/walker_propagate.mbt` — split/merge/propagate
- `order-tree/src/walker_range.mbt` — height, LCA, shared prefix
- `order-tree/src/walker_range_delete.mbt` — most of it (most or all of 510 lines):
  generic helpers (boundary chain rebuild/merge, rightmost descent, leaf count)
  + BTreeElem-dependent functions (boundary slicing/merging, gap absorption,
  `plan_delete_range` orchestrator)
- `order-tree/src/navigate.mbt` — `OrderNode::navigate`
- `order-tree/src/utils.mbt` — generic array helpers, slot finding (except `must_slice`)
- `order-tree/src/iter.mbt` — `OrderNode::each` (node-level only)
- Root lifecycle: empty root, overflow wrapping, delete normalization

Out:
- RLE leaf logic: `walker_insert.mbt`, `walker_delete.mbt`
- `delete_range_needs_merge_rebuild` canonicalization (~60 lines, stays in order-tree)
- Public OrderTree API: `order_tree.mbt`, `insert.mbt`, `delete.mbt`, `bulk_build.mbt`
- rle submodule (no dependency from lib/btree)

## Current State

- OrderTree's cursor types (`Cursor[T]`, `PathFrame[T]`, etc.) are all `priv`
- All generic B-tree code lives interleaved with rle-specific code in `order-tree/src/`
- No consumer other than OrderTree exists yet
- `lib/zipper/` (rose tree) established the pattern for extracted tree libraries
- `walker_range_delete.mbt` interleaves generic subtree surgery (~250 lines) with
  rle-dependent boundary slicing/merging (~260 lines)
- `delete_range` has a rebuild fallback (`delete_range_needs_merge_rebuild` in
  `order_tree.mbt`) that forces full rebuild when prefix/suffix are mergeable outside
  the local splice window

## Desired State

- `lib/btree/` is a standalone MoonBit module (`dowdiness/btree`), depends only on `dowdiness/rle`
  (for trait definitions: `Spanning`, `Mergeable`, `Sliceable`)
- OrderTree depends on `dowdiness/btree` and provides RLE-specific leaf logic via callbacks
- Generic B-tree tests (structural invariants, balancing, navigation) live in lib/btree,
  including ported white-box walker tests from order-tree
- `order-tree/` tests continue passing unchanged

## Key Design Decision: Consumer Integration

The central question: how does order-tree plug in RLE-specific leaf logic?

**Chosen approach: Callback-based high-level API + pub types as escape hatch.**

```text
                    lib/btree (generic)
                    ┌──────────────────────────────────────┐
                    │  BTreeNode[T], Cursor[T]             │
                    │  descend, propagate, split/merge      │
                    │  root lifecycle (empty/wrap/normalize) │
High-level API ───► │  mutate_at(pos, mode, callback)       │
                    │  seek(pos) -> LeafContext[T]          │
                    └────────────┬─────────────────────────┘
                                 │ callback receives LeafContext[T]
                                 │ callback returns (Splice[T], R)
                    ┌────────────┴─────────────────────────┐
                    │  order-tree (rle-specific)            │
                    │  compute_insert_splice()              │
                    │  compute_delete_splice()              │
                    │  plan_delete_range() rle portions     │
                    │  delete_range_needs_merge_rebuild()   │
                    └──────────────────────────────────────┘
```

### High-level operations (primary API)

```moonbit
// Read — no callback needed
fn BTree::seek[T](self, pos : Int) -> LeafContext[T]?

// Single-position mutation — consumer provides leaf logic
// Callback returns (Splice[T], R) so caller can extract side-channel data
// (e.g., deleted element, leaf_delta)
fn BTree::mutate_at[T, R](
  self,
  pos : Int,
  mode : DescentMode,          // ForInsert | ForDelete
  f : (LeafContext[T]) -> (Splice[T], R),
) -> (BTree[T], R)
```

The generic return type `R` is critical: `delete_at` needs to return the deleted element
via `DeleteLeafResult.deleted`, and `insert_at` needs to return `leaf_delta`. Without `R`,
consumers lose access to these payloads.

### Range mutation

Range delete splits into three layers by where they live:

```text
lib/btree (no trait bound)     lib/btree (T : BTreeElem)     order-tree
─────────────────────────      ─────────────────────────      ──────────────
descend to start/end           slice boundary elements        delete_range_needs_merge_rebuild
find LCA                       build boundary subtrees          (post-canonicalization check)
boundary chain rebuild/merge   attempt gap absorption
path suffix extraction         fallback: rebuild if underfull
rightmost descent              plan_delete_range orchestrator
leaf count helpers
```

**The key boundary:** `plan_delete_range` (the ~100-line orchestrator) lives in lib/btree
with `T : BTreeElem` bound. It calls rle trait methods directly via the super trait.
Order-tree's sole addition is the `delete_range_needs_merge_rebuild` post-check, which
detects prefix/suffix mergeability *outside* the splice window and forces a full rebuild.

### BTreeElem as super trait

`BTreeElem` extends rle's traits via MoonBit super traits — no method duplication,
no bridge impl, no signature mismatch:

```moonbit
// lib/btree — BTreeElem is a super trait over rle's traits
pub trait BTreeElem : @rle.Spanning + @rle.Mergeable + @rle.Sliceable {}

// lib/btree calls rle trait methods directly
fn plan_delete_range[T : BTreeElem](...) {
  let s = @rle.Spanning::span(elem)           // inherited
  let ok = @rle.Mergeable::can_merge(a, b)    // inherited
  let merged = @rle.Mergeable::merge(a, b)    // inherited
  let sliced = @rle.Sliceable::slice(elem, start~, end~)  // inherited, same signature
  ...
}
```

**Orphan rule:** `order-tree` is generic over `T` — it does not define or know about
concrete element types. The `impl BTreeElem for VisibleRun` declaration goes in
`event-graph-walker` (the type owner), not in order-tree. Order-tree simply changes
its trait bounds from `T : @rle.Spanning + @rle.Mergeable + @rle.Sliceable` to
`T : @btree.BTreeElem`.

```moonbit
// event-graph-walker — VisibleRun already impls all rle traits
impl @btree.BTreeElem for VisibleRun
```

**Cost:** lib/btree depends on `dowdiness/rle` for trait definitions (`Spanning`,
`Mergeable`, `Sliceable`). This is a dependency on interfaces, not on the `Rle` data
structure. Both libraries are in the same repo. `event-graph-walker` adds a dependency
on `dowdiness/btree` for the `BTreeElem` impl.

**Benefit:** Eliminates the previous plan's 4-method trait duplication and bridge impl.

### Sliceable::slice error handling policy

`Sliceable::slice` returns `Result[Self, RleError]`. Inside lib/btree, positions are
computed from known spans and are structurally guaranteed valid. Policy:

**lib/btree provides `must_slice` (abort on impossible error).** This mirrors the current
`must_slice` in `order-tree/src/utils.mbt` — same contract, moved to lib/btree. All
internal callers use `must_slice`, not raw `slice`. The abort is an invariant violation
(bug in lib/btree), not a user-facing error.

```moonbit
// lib/btree/utils.mbt — internal helper
fn must_slice[T : BTreeElem](elem : T, start : Int, end : Int) -> T {
  @rle.Sliceable::slice(elem, start~, end~).unwrap()
}
```

lib/btree's public API (`delete_range`, `each_in_range`, `mutate_at`) remains infallible
with respect to slice errors. If a slice fails, it's a lib/btree bug, not a consumer error.

### Range delete layers

```moonbit
// Layer 1: Generic range primitives (no trait bound)
fn BTree::find_lca[T](self, start : Int, end : Int) -> AncestorRange[T]
fn BTree::apply_node_splice[T](self, splice : NodeSplice[T]) -> BTree[T]

// Layer 2: Full range delete orchestrator (needs BTreeElem for boundary ops)
fn BTree::delete_range[T : BTreeElem](self, start : Int, end : Int) -> DeleteRangeResult[T]

// Layer 3: Consumer adds canonicalization (order-tree only)
```

Order-tree wraps `delete_range` with one post-check:
```moonbit
fn OrderTree::delete_range(self, start, end) {
  let result = self.tree.delete_range(start, end)
  if delete_range_needs_merge_rebuild(result) {
    rebuild_canonical(result)  // full rebuild fallback
  } else {
    result
  }
}
```

This means **most of `walker_range_delete.mbt` moves to lib/btree** — both the generic
helpers (Layer 1) and the BTreeElem-dependent functions (Layer 2). Only
`delete_range_needs_merge_rebuild` and any rle-specific canonicalization logic stay
in order-tree.

### Escape hatch

All types (`BTreeNode[T]`, `BTreeCursor[T]`, `PathFrame[T]`, `Splice[T]`, etc.) are `pub`
so advanced consumers can build custom operations. But the typical path is through
`seek`, `mutate_at`, and `delete_range`.

Note: `LeafContext::left_neighbor`/`right_neighbor` assume sibling leaves in the immediate
parent frame. This holds under the current descent contract but should be documented.

## Naming

| order-tree (current) | lib/btree (new) |
|---|---|
| `OrderNode[T]` | `BTreeNode[T]` |
| `OrderTree[T]` | stays in order-tree (wraps `BTree[T]`) |
| `Cursor[T]` (priv) | `BTreeCursor[T]` (pub) |
| `PathFrame[T]` (priv) | `PathFrame[T]` (pub) |
| `LeafContext[T]` (priv) | `LeafContext[T]` (pub) |
| `Splice[T]` (priv) | `Splice[T]` (pub) |
| `FindResult[T]` | `FindResult[T]` (pub) |
| — | `BTree[T]` (new top-level struct, owns root + min_degree + size) |

## Steps

### Step 1: Scaffold lib/btree module

Create `lib/btree/` with `moon.mod.json` (dep: `dowdiness/rle`), `moon.pkg.json`, and
empty source files matching the extraction plan. Verify `moon check` passes.

### Step 2: Extract types + root lifecycle

Move to lib/btree:
- `BTreeNode[T]`, `BTree[T]`, `FindResult[T]`, cursor types, splice types
- Rename `OrderNode` -> `BTreeNode`
- Add `BTreeElem` super trait: `pub trait BTreeElem : @rle.Spanning + @rle.Mergeable + @rle.Sliceable {}`
- Add `dowdiness/rle` as dependency in `lib/btree/moon.mod.json`
- **Root lifecycle**: empty root construction, root overflow wrapping (when propagation
  produces an overflow, wrap in new root), delete root normalization (unwrap single-child
  root). These currently live in `insert.mbt` and `delete.mbt` — extract the generic
  parts early to avoid duplicated root logic.

Run `moon check` in lib/btree. order-tree will break — expected.

### Step 3: Extract generic operations

Move to lib/btree in order:
1. `utils.mbt` — array helpers, slot finding, node queries (`total`, `is_full`, etc.)
2. `navigate.mbt` — `BTreeNode::navigate`
3. `walker_descend.mbt` — descent engine, prepare hooks, cursor movement.
   Includes `descend_leaf_at` and `descend_leaf_at_end_boundary` (needed by range delete).
   Leave `each_slice_in_range` — it needs `BTreeElem::slice`.
4. `walker_propagate.mbt` — split, merge, propagate (100% generic)
5. `walker_range.mbt` — height, LCA, shared prefix
6. **Most of `walker_range_delete.mbt`** (most or all of 510 lines):
   Generic helpers (no trait bound):
   - `path_suffix_after_target`
   - `rebuild_boundary_chain`, `merge_boundary_chain`
   - `descend_rightmost`
   - `leftmost_leaf_in_subtree`, `rightmost_leaf_in_subtree`
   - `leaf_count` helpers
   BTreeElem-dependent functions (with `T : BTreeElem` bound):
   - `left_boundary_keep`, `right_boundary_keep`
   - `left_boundary_subtree`, `right_boundary_subtree`
   - `merged_boundary_subtree`, `merge_leaf_nodes`
   - `absorb_leaf_level_gap_merge`, `absorb_subtree_gap_merge`
   - `promote_empty_child_gap_merge`
   - `plan_delete_range` (the orchestrator)
   Leave in order-tree: only `delete_range_needs_merge_rebuild` and any
   rle-specific canonicalization/rebuild logic.
7. `iter.mbt` — `BTreeNode::each`

Run `moon check` after each file. Fix breakage incrementally.

### Step 4: Build high-level API

Implement in lib/btree:
- `BTree::new(min_degree~)`, `BTree::seek(pos)`, `BTree::span()`, `BTree::size()`
- `BTree::mutate_at[T, R](pos, mode, fn(LeafContext[T]) -> (Splice[T], R))` — wraps
  descend + callback + propagate + root lifecycle
- `BTree::plan_range(start, end)` — generic LCA + boundary chain primitives
- `BTree::apply_node_splice(splice)` — generic structural rebuild
- `BTree::delete_range[T : BTreeElem](start, end)` — convenience for BTreeElem types
  (structural only, no canonicalization)
- `BTree::each_in_range[T : BTreeElem](start, end, f)` — slice-aware iteration
- `BTree::from_sorted(Array[(T, Int)])` — bulk build without merging (generic)

### Step 5: Refactor order-tree to depend on lib/btree

- Update `order-tree/moon.mod.json` to add `dowdiness/btree` dep
- Replace internal types with `@btree.*` imports
- Change trait bounds from `T : @rle.Spanning + @rle.Mergeable + @rle.Sliceable`
  to `T : @btree.BTreeElem` where appropriate
- `walker_insert.mbt`, `walker_delete.mbt` become callbacks for `BTree::mutate_at`:
  - Insert callback returns `(Splice[T], Int)` where `Int` is `leaf_delta`
  - Delete callback returns `(Splice[T], DeletePayload[T])` with deleted element + leaf_delta
- Keep `delete_range_needs_merge_rebuild` canonicalization in `order_tree.mbt`
- In `event-graph-walker`: add `dowdiness/btree` dep, declare
  `impl @btree.BTreeElem for VisibleRun` (empty — existing rle impls satisfy it)
- Keep `order_tree.mbt` public API — now delegates to `BTree` methods
- Run `moon test` in order-tree — all existing tests must pass

### Step 6: Write lib/btree tests

Port and create tests in two categories:

**White-box tests (ported from `walker_wbtest.mbt`):**
- Cursor descent and slot finding
- LCA computation
- Boundary chain rebuild/merge
- Propagation and split/merge behavior
- Gap absorption (structural portion)

These exercise the exact generic seam being extracted. Without them, lib/btree's
internals are only tested indirectly through order-tree.

**New tests:**
- Structural invariant tests (balanced, sorted counts, correct totals)
- `BTree::mutate_at` with a simple `BTreeElem` impl (e.g., `Int` with span=1)
- `BTree::delete_range` with simple elements
- Property tests (@qc): insert/delete preserves invariants, size tracking, seek correctness
- Benchmarks: insert, delete, range delete at various scales

### Step 7: Cleanup

- `moon info && moon fmt` in both modules
- Verify `moon test` passes everywhere (lib/btree, order-tree, parent canopy)
- Update `docs/TODO.md` to mark Phase 2 done

## Acceptance Criteria

- [ ] `lib/btree/` depends only on `dowdiness/rle` (trait definitions)
- [ ] `order-tree/` depends on `dowdiness/btree` and all existing tests pass
- [ ] `BTreeElem` is a super trait over `Spanning + Mergeable + Sliceable`
- [ ] `event-graph-walker` declares `impl BTreeElem for VisibleRun` (empty, orphan-rule compliant)
- [ ] `order-tree` uses `T : @btree.BTreeElem` bounds (no concrete element type knowledge)
- [ ] `mutate_at` callback returns `(Splice[T], R)` — consumer can extract payloads
- [ ] Root lifecycle (empty/wrap/normalize) lives in lib/btree, not duplicated
- [ ] Most/all of `walker_range_delete.mbt` extracted to lib/btree
- [ ] `must_slice` lives in lib/btree (abort on structurally-impossible slice error)
- [ ] lib/btree has white-box tests ported from walker_wbtest + new structural/property tests

## Validation

```bash
cd lib/btree && moon test                # New btree tests
cd order-tree && moon test               # Existing tests unchanged
cd event-graph-walker && moon test       # CRDT (uses order-tree, declares BTreeElem impl)
moon test                                # Parent module
moon check && moon fmt && moon info      # Lint
```

## Risks

- **Range delete extraction**: Most of `walker_range_delete.mbt` moves to lib/btree.
  The BTreeElem-dependent functions (boundary slicing, gap absorption) use only the 4
  trait methods — verify this holds for each function during extraction. If any function
  turns out to need rle-specific behavior beyond `BTreeElem`, it stays in order-tree.
  The `delete_range_needs_merge_rebuild` post-check is the one clear order-tree-only piece.
  Mitigation: order-tree's existing range delete tests are the regression suite.

- **Visibility change**: Cursor types go from `priv` to `pub`. This exposes internal
  structure that was previously hidden. Mitigation: document that the high-level API
  (`seek`, `mutate_at`, `delete_range`) is the primary interface; cursor types are
  an escape hatch.

- **Performance regression**: Adding a function-call boundary (callback in `mutate_at`)
  where there was previously direct code. Mitigation: MoonBit inlines small closures.
  Benchmark before/after on order-tree's existing benchmarks.

- **Root lifecycle migration**: Moving root handling early (Step 2) means order-tree
  breaks sooner. Mitigation: Step 2 explicitly expects order-tree to break; the fix
  comes in Step 5 when order-tree switches to lib/btree's `BTree[T]`.

## Notes

- Design discussion in conversation 2026-04-08: rose tree -> zipper is the API (persistent
  navigation); B-tree -> tree is the API (balanced mutations, cursor internal).
- Architecture memory updated: `.claude/skills/agent-memory/memories/generic-zipper-library/architecture-design.md`
- Related TODO items: section 5 (B-tree indexing for FugueTree) could be a second consumer.
- Codex review (2026-04-08) identified five issues, all addressed:
  1. delete_range canonicalization semantics — order-tree wraps with post-check
  2. mutate_at return type too narrow — now generic `R`
  3. root lifecycle ownership — now in Step 2
  4. walker_range_delete.mbt needs finer split — now Step 3.6
  5. white-box tests must port to lib/btree — now in Step 6
- Super trait design (2026-04-08): BTreeElem extends rle traits, eliminating 4-method
  duplication and bridge impl. lib/btree depends on rle for trait definitions only.
