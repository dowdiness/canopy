# Indexed projection lifecycle

**Date:** 2026-07-22

**Status:** Proposed feasibility hypothesis. The repository currently retains
FugueTree persistently; this record describes a candidate separation, not
completed implementation or an accepted lifecycle change.

**Related:**

- [EGW collaboration responsibility boundary](2026-07-21-egw-collaboration-responsibility-boundary.md)
- [Library API boundary](2026-06-11-library-api-boundary.md)
- [EGW companion and Canopy migration](../plans/2026-07-22-egw-companion-canopy-migration.md)
- [Protocol v3 hard cutover](2026-07-22-protocol-v3-hard-cutover.md)
- [Eg-walker formal specification](../../event-graph-walker/docs/FORMAL_SPECIFICATION.md)
- [Eg-walker paper](https://arxiv.org/abs/2409.14252)

**Reader:** Maintainers designing or reviewing CRDT state management,
projection materialization, merge lifecycle, or indexed-position queries in
EGW and Canopy.

**Hypothesis under evaluation:** Separate canonical state (event graph, oplog,
frontier) from two distinct projections: a lightweight indexed visible state
for normal operations, and a FugueTree materialization used only during
concurrent merge and replay. Normal operations would update indexed state and
oplog directly; merge would materialize FugueTree, then regenerate indexed
state afterward.

**Keep until:** Permanently. ADRs are superseded rather than deleted.

**Disposition:** Supersede this record if implementation evidence shows that
the two-projection separation cannot be maintained without unacceptable
complexity or performance regression.

## Context

The eg-walker CRDT system stores collaborative document state across several
interdependent structures. The [eg-walker paper](https://arxiv.org/abs/2409.14252)
and the [formal specification](../../event-graph-walker/docs/FORMAL_SPECIFICATION.md)
establish that the event graph (causal graph), operation log (oplog), and
frontier together form the canonical, authoritative state. Everything else —
the visible text, the FugueTree ordering, position caches — is derived.

The current implementation retains a FugueTree persistently within the Branch
structure. Every local edit, remote sync, and merge operation maintains this
tree. The FugueTree serves two distinct purposes:

1. **Normal operations:** local edits and causally-forward remote operations
   append to the oplog and update the tree incrementally. Position queries
   use an optional position cache for O(log n) visible-order lookups.

2. **Merge and replay:** concurrent merge requires retreating and advancing
   through operations in causal order, applying each to the FugueTree. This
   is the only path that requires full tree materialization from the oplog.

These two purposes have different lifecycle requirements. Normal operations
need fast indexed queries on visible state. Merge needs a complete, mutable
sequence CRDT that supports retreat and advance. Conflating them couples the
normal-path data structure to merge-only concerns.

## Decision

### Canonical state

The event graph, oplog, and frontier are the single source of truth. They
record every operation, its causal dependencies, and the current version
frontier. No derived structure is authoritative; all projections are
recomputable from canonical state.

This invariant is already established by the eg-walker architecture and the
formal specification's layer model. This decision record does not change it;
it clarifies the projection lifecycle built on top.

### Normal projection: indexed visible state

For normal operations — local edits, causally-forward remote sync, position
queries, visible-text extraction — the system maintains a lightweight indexed
visible state. This projection provides:

- Visible sequence content in causal order
- Position-to-version and version-to-position mappings for O(log n) queries
- Incremental updates on append and delete without full rebuild

The indexed visible state is the working set for interactive editing. It is
updated directly by local edits and by remote operations that extend the
current frontier without requiring retreat.

### Merge projection: FugueTree materialization

FugueTree is a full sequence CRDT materialization that supports the
retreat/advance merge algorithm. It is non-authoritative: its content is
derivable from the oplog by walking operations in topological order.

FugueTree is materialized only when needed for concurrent merge or replay:

- **Merge:** when a remote peer's frontier diverges from the local frontier,
  merge computes retreat and advance sets, applies them to a FugueTree, and
  produces the merged tree state. After merge completes, indexed visible
  state is regenerated from the resulting FugueTree.
- **Replay:** when reconstructing document state at a historical frontier,
  operations are replayed through FugueTree to produce the target state.

Between merges, FugueTree need not be maintained. The indexed visible state
is the persistent working set; FugueTree is a transient merge artifact.

### Lifecycle table

| Event | Canonical state | Indexed visible state | FugueTree |
|---|---|---|---|
| Local edit | Append op, advance frontier | Update in place | Not materialized |
| Causally-forward remote op | Append op, advance frontier | Update in place | Not materialized |
| Concurrent merge | Append remote ops, compute new frontier | Regenerated after merge | Materialize, retreat/advance, then discard or cache |
| Historical replay | Unchanged | Regenerated at target frontier | Materialize, replay ops |
| Position query | Unchanged | O(log n) lookup | Not consulted |

### Invariants

1. **Canonical state is authoritative.** The event graph, oplog, and frontier
   are the single source of truth. All projections are derivable and
   recomputable.

2. **Indexed state is the normal-path working set.** Local edits and
   causally-forward remote operations update indexed state directly. They do
   not require FugueTree materialization.

3. **FugueTree is non-authoritative.** Its content is determined by the oplog
   and frontier. It may be materialized on demand for merge or replay, then
   discarded or cached. It is not the persistent document representation.

4. **Merge regenerates indexed state.** After merge completes and FugueTree
   reflects the merged frontier, indexed visible state is rebuilt from the
   FugueTree. The two projections are not maintained in lockstep during
   merge.

5. **Wire and public APIs are stable.** The separation is internal. External
   consumers observe the same document content, version vectors, and sync
   messages regardless of which projection path produced them.

### Consequences

**Benefits:**

- Normal-path operations avoid the overhead of maintaining a full FugueTree
  when only indexed visible state is needed.
- Merge and replay have a clear, isolated materialization lifecycle. The
  retreat/advance algorithm operates on FugueTree without coupling to the
  normal-path data structure.
- Position queries use indexed state directly, without consulting or
  rebuilding FugueTree.
- The canonical/oplog boundary remains clean: all derived state is
  recomputable, and the merge path is explicit about when and why
  materialization occurs.

**Trade-offs:**

- Merge requires materializing FugueTree from the oplog, which costs time
  proportional to the number of operations since the last common ancestor.
  This is acceptable because merge is infrequent relative to normal edits,
  and the eg-walker merge algorithm already operates in this complexity.
- Regenerating indexed state after merge adds a rebuild step. The rebuild
  is O(n) in the visible sequence length, which is acceptable because merge
  is not on the hot path for interactive editing.
- The two-projection model requires discipline: code paths must not assume
  FugueTree is always available. Normal-path code uses indexed state; merge
  code materializes FugueTree explicitly.

**Risks:**

- If FugueTree materialization becomes a bottleneck for frequent merges
  (e.g., high-concurrency documents with many divergent peers), the
  trade-off may shift toward persistent FugueTree with incremental merge.
  This would supersede the current decision.
- The indexed visible state must support all normal-path queries currently
  served by FugueTree. If a normal-path use case requires FugueTree-specific
  capabilities (e.g., complex origin-based ordering queries), the separation
  may need refinement.

## Scope and non-goals

### In scope

- Text CRDT state management in EGW (event-graph-walker).
- The lifecycle separation between indexed visible state and FugueTree
  materialization.
- Merge and replay as the only paths requiring FugueTree.
- Normal operations (local edits, causally-forward remote sync) as the only
  paths using indexed visible state directly.

### Out of scope

- **Container TextBlock.** The container's per-block text state machines use
  FugueTree with per-block dense item IDs and a shared global LV space. The
  TextBlock lifecycle, LV-to-ItemId mapping, and per-block merge are separate
  concerns. This decision applies to the text CRDT layer, not the container
  layer. Container TextBlock may adopt a similar separation in the future,
  but that is a separate decision.

- **Merge adapter placement.** The merge adapter (which translates between
  EGW's merge algorithm and Canopy's editor layer) remains branch-side to
  avoid dependency inversion. This is an existing architectural constraint,
  not changed by this decision.

- **Wire protocol or sync message format.** The projection lifecycle is
  internal. Wire and public APIs are stable and unaffected.

- **Performance optimization.** This decision records an architectural
  separation, not a performance claim. Benchmarks should validate that the
  separation does not regress normal-path or merge-path performance, but
  optimization is not the goal.

## Migration

The repository currently retains FugueTree persistently within Branch. This
decision describes the target architecture, not the current state. Migration
proceeds in staged steps, each independently verifiable:

### Stage 1: IndexedState extraction

Extract the indexed visible state from the current FugueTree-backed
implementation. The indexed state provides position queries and visible
sequence access. FugueTree remains persistent during this stage; the indexed
state is derived from it.

**Exit criteria:** Indexed state supports all normal-path queries. Tests pass
with indexed state as the normal-path data structure, backed by FugueTree.

### Stage 2: Dual-projection differential verification

Run both FugueTree and indexed state in parallel. Normal-path operations
update both. Merge uses FugueTree. After each operation, verify that indexed
state and FugueTree produce identical visible sequences and position mappings.

**Exit criteria:** Differential tests pass for local edits, remote sync, and
merge. No divergence detected across representative workloads.

### Stage 3: Merge-only materialization

Change merge to materialize FugueTree on demand from the oplog, rather than
using the persistent FugueTree. After merge, regenerate indexed state from
the materialized FugueTree. The persistent FugueTree is no longer maintained
during normal operations.

**Exit criteria:** Merge produces correct results when FugueTree is
materialized from oplog. Indexed state is correctly regenerated after merge.
Normal-path operations no longer touch FugueTree.

### Stage 4: Switch

Remove the persistent FugueTree from Branch. Normal operations use indexed
state exclusively. Merge materializes FugueTree transiently. The indexed
visible state is the sole persistent projection.

**Exit criteria:** All tests pass without persistent FugueTree. Benchmarks
show no regression in normal-path or merge-path performance.

## Adoption gates

This decision is adopted when:

1. Stage 1 exits with indexed state supporting all normal-path queries.
2. Stage 2 exits with differential verification passing across local, remote,
   and merge workloads.
3. Stage 3 exits with merge-only materialization producing correct results.
4. Stage 4 exits with persistent FugueTree removed and no performance
   regression.
5. The container TextBlock layer remains unaffected; its lifecycle is a
   separate decision.
6. Wire and public APIs show no signature drift.

Until all gates pass, this decision remains a target architecture. The
current persistent-FugueTree implementation is correct and supported.

## Cross-repository coordination

This record is the source of truth because the target lifecycle affects both
Canopy and its event-graph-walker submodule. Implementation changes in the
submodule and the parent integration that adopts them must be reviewed and
landed in the same change lifecycle. Do not copy this decision into the
submodule; link to this record from implementation plans or pull requests.

## Rejected alternatives

### Keep FugueTree persistent and add indexed state alongside

Rejected because it maintains two redundant projections in lockstep, increasing
complexity without clear benefit. The merge path does not require persistent
FugueTree; it can materialize on demand.

### Use indexed state for merge

Rejected because the retreat/advance merge algorithm requires a mutable
sequence CRDT with origin-based ordering. Indexed visible state does not
provide this capability. FugueTree is the correct data structure for merge.

### Materialize FugueTree for all operations

Rejected because it couples normal-path operations to a data structure
designed for merge. Normal edits and causally-forward sync do not need
retreat/advance capability; maintaining FugueTree for these paths adds
overhead without benefit.

## References

- [Eg-walker paper](https://arxiv.org/abs/2409.14252) — the CRDT algorithm
  and merge semantics.
- [Eg-walker formal specification](../../event-graph-walker/docs/FORMAL_SPECIFICATION.md)
  — layer model, laws, and merge procedure.
- [EGW collaboration responsibility boundary](2026-07-21-egw-collaboration-responsibility-boundary.md)
  — layer ownership and canonical state invariants.
- [Canopy architecture](../architecture.md) — pipeline and ground-truth
  invariants.
- [Documentation doctrine](../development/documentation-doctrine.md) —
  principles-only architecture prose; no field or line references.
