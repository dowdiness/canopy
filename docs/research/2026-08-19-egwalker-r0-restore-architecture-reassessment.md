# Eg-walker R0 restore architecture reassessment

**Date:** 2026-08-19

**Question:** What is the fastest paper-aligned state and replay boundary for Gate R0, and is it better than the existing Candidate A/B/C framing?

## Conclusion

A better design exists than persisting a position-to-identity index or treating a retained position-based CRDT branch as Candidate C.

The paper-aligned normal branch is only:

```text
PaperBranch {
  document_text
  event_graph_frontier
  validated_capture_receipt
}
```

`validated_capture_receipt` is the accepted test-only `R0SnapshotCommitV2`: exact ranked head records and writer commitments remain O(heads + writers) resident so the first local event can allocate its causal rank without a provider read. The capture-receipt and cold-boundary decisions own its exact encoding; it does not add per-character identity state.

Canonical history remains an immutable event graph of original position-based operations. The normal branch contains no per-character causal IDs, tombstone table, Fugue tree, or IndexedState. Local edits append original index-based events whose parents are the branch frontier and update the text directly. A remote region may use the same direct path only when every new entry point is causally after every head of the current frontier. Genuine concurrency reads the required event-graph conflict region, builds a placeholder-backed temporary merge tracker, emits transformed index operations, and discards the tracker.

This collapses the previous Candidate A and Candidate C into two runtime paths of one design:

- **ordinary path:** plain text plus frontier, with direct positional event generation/application;
- **concurrent path:** critical-version/conflict-zone partial replay with disposable internal state.

Candidate B remains useful only as a measured legacy migration control. `ClosedTail` and a persistent canonical position-to-identity table are not part of the Eg-walker paper model.

## Primary-source findings

### 1. The paper separates three states

Eg-walker defines replica state as an on-disk event graph, document text without metadata, and temporary CRDT internal state. The internal state is neither persisted nor replicated and is discarded after merge. New local events and events that happened after all existing events require only current document state. Concurrency requires replay only from the latest critical version shared by the current and incoming histories.

Sources:

- [Eg-walker paper §3](https://arxiv.org/html/2409.14252v1#S3)
- [Eg-walker paper §3.1](https://arxiv.org/html/2409.14252v1#S3.SS1)
- [Eg-walker paper §3.5](https://arxiv.org/html/2409.14252v1#S3.SS5)
- [Eg-walker paper §3.6](https://arxiv.org/html/2409.14252v1#S3.SS6)
- [Eg-walker paper §3.8](https://arxiv.org/html/2409.14252v1#S3.SS8)

The paper also explicitly allows caching the final document text beside the event graph for fast loading. It does not require persistent CRDT state to make that text editable.

### 2. The reference implementation stores branch text plus version

The reference `Branch` contains only a snapshot and version. Updating a branch first computes the existing conflict set and new operations, starts a temporary edit context at their common causal base with placeholder items, replays the conflict set without modifying the snapshot, then applies transformed new operations to the snapshot.

Sources at reference commit [`7287f4b`](https://github.com/josephg/eg-walker-reference/tree/7287f4bc2c054984838b3582a27b4fea8f6d8161):

- [`Branch` and checkout](https://github.com/josephg/eg-walker-reference/blob/7287f4bc2c054984838b3582a27b4fea8f6d8161/src/index.ts#L513-L540)
- [conflict-zone branch update](https://github.com/josephg/eg-walker-reference/blob/7287f4bc2c054984838b3582a27b4fea8f6d8161/src/index.ts#L553-L648)

This is direct evidence against persisting a per-character position-to-identity index in the normal branch.

### 3. Diamond Types uses the same deep boundary

Diamond Types represents a `ListBranch` as document content plus a frontier. Local insert/delete methods append positional operations to the oplog and mutate the branch. Merge computes transformed operations from the branch frontier to the incoming frontier; fast-forward spans apply original operations directly, while conflicting spans use a temporary tracker initialized with one underwater placeholder.

Sources at Diamond Types commit [`e143890`](https://github.com/josephg/diamond-types/tree/e143890a596aafdd7ba3e7ae25f9f3749f45acff):

- [`ListBranch` state](https://github.com/josephg/diamond-types/blob/e143890a596aafdd7ba3e7ae25f9f3749f45acff/src/list/mod.rs#L53-L83)
- [local positional edits](https://github.com/josephg/diamond-types/blob/e143890a596aafdd7ba3e7ae25f9f3749f45acff/src/list/branch.rs#L96-L132)
- [placeholder tracker](https://github.com/josephg/diamond-types/blob/e143890a596aafdd7ba3e7ae25f9f3749f45acff/src/listmerge/merge.rs#L40-L72)
- [fast-forward and transformed merge application](https://github.com/josephg/diamond-types/blob/e143890a596aafdd7ba3e7ae25f9f3749f45acff/src/listmerge/merge.rs#L862-L947)

The production precedent therefore supports `text + frontier + event graph`, not a serialized legacy materializer.

### 4. Loro exposes the dangerous fast-path condition

Loro recently corrected a false concurrency-free classification. Version inclusion alone is insufficient when the current frontier has multiple heads: every entry point of the new region must causally cover every current frontier head. Otherwise the implementation must retreat to a proven critical replay base and use conservative replay. The walk must include the implicit same-peer predecessor as well as explicit dependencies.

Sources at Loro commit [`4d3d3f1`](https://github.com/loro-dev/loro/tree/4d3d3f1de107aebcd0b824e53e05d6bb5c6a5974):

- [replay-base and diff-mode contract](https://github.com/loro-dev/loro/blob/4d3d3f1de107aebcd0b824e53e05d6bb5c6a5974/crates/loro-internal/src/dag.rs#L487-L504)
- [latest single-head critical-version search](https://github.com/loro-dev/loro/blob/4d3d3f1de107aebcd0b824e53e05d6bb5c6a5974/crates/loro-internal/src/dag.rs#L715-L789)
- [new-region entry-point coverage rule](https://github.com/loro-dev/loro/blob/4d3d3f1de107aebcd0b824e53e05d6bb5c6a5974/crates/loro-internal/src/dag.rs#L791-L830)
- [release note for the convergence and full-history-replay fixes](https://github.com/loro-dev/loro/blob/4d3d3f1de107aebcd0b824e53e05d6bb5c6a5974/crates/loro-wasm-map/CHANGELOG.md#L74-L101)

R0 should therefore fail closed unless it proves this coverage condition. A small or causally closed-looking tail is not enough.

### 5. Current MoonBit EGW has the graph machinery, but not the paper restore path

The current implementation already has canonical `RawVersion`, causal frontiers, graph walks/diffs, compressed operations, duplicate/conflict handling, pending ownership, partial admission, and disposable planning state. Its `Branch::advance` has a forward-only incremental path but falls back to full checkout when retreat is needed. It has no paper-style placeholder partial replay in production.

The test-only `CausalCut` prototype rebuilds a duplicate full-operation map from `get_all_ops()`. Existing matched benchmarks rejected maintaining this duplicate map per admission. It is evidence, not the retained-state architecture.

The test-only TextEvent baseline is closer to the paper: events carry canonical identity, parent frontier, and parent-relative scalar positions, while Fugue origins are derived only at a compatibility boundary. Gate A retained this as unmerged reference-model evidence: the immutable baseline is at EGW commit `44164cd`, and the issue records later frozen evidence checkpoints. R0 may explicitly fetch/copy that test input, but must not assume it exists in a clean checkout or treat it as accepted production behavior.

Sources:

- [Causal Authority residency decision](../decisions/2026-08-12-causal-authority-residency.md)
- [Gate A plan](../plans/2026-08-12-egw-paper-aligned-text-event-admission.md)
- [Loomark startup history corpus](../performance/2026-08-10-loomark-startup-history-corpus.md)
- event-graph-walker `internal/causal_graph`, `internal/oplog`, and `internal/branch`

### 6. Current Loomark restore cannot demonstrate this architecture directly

The v1 Loomark archive is one JSON envelope. Reopen decodes the embedded full history, admits all operations into the legacy document, refreshes projection, and only then verifies the resulting portable Markdown. Current production has neither an authority-issued text/frontier capture receipt nor an indexed cold-history provider. R0 must therefore remain a bytes-only sidecar experiment and must not claim that the v1 archive can perform partial cold reads.

The archive-reopen phase evidence shows history decode and causal admission dominate reopen; projection refresh measured 2.4 ms before P3 and 2.3 ms after P3 in the 41-operation fixture. This confirms the paper's target mechanism: avoid history hot load and persistent CRDT materialization rather than optimizing projection refresh.

Source: [Loomark P3 archive reopen evidence](../evidence/2026-08-18-loomark-p3-archive-reopen.md).

## Rejected alternatives

| Alternative | Result | Reason |
|---|---|---|
| Plain text alone | Reject | It has no causal version and cannot parent new events safely. |
| Text plus frontier with legacy origin-based `Op` | Negative under current production | Local delete/insert origin construction still needs legacy projection identity state. The paper-native positional TextEvent boundary is required. |
| Persistent position-to-identity/tombstone table | Reject as canonical state | It recreates the steady-state CRDT metadata the paper removes. |
| Serialized Fugue/IndexedState | Keep only as Candidate B control | It may be a bounded migration bridge but is not paper-aligned canonical state. |
| `ClosedTail` with zero cold reads for concurrent work | Reject | Eg-walker concurrency explicitly requires event-graph conflict-region replay and temporary merge state. |
| Full operation-map `CausalCut` resident on every edit | Reject | It duplicates authority and has already failed the matched admission performance gate. |
| Always full replay to validate cached text | Reject as normal path | It defeats the paper's cached-document load advantage. Use the later content-addressed snapshot receipt with separate publication provenance; reserve replay for the test oracle and bounded recovery. |
| Precomputed critical-version list as the primary contract | Do not require | Criticality can become invalid when concurrent history arrives. The contract should be proof of the selected replay base and entry-point coverage, not trust in a stale label. |

## Recommended R0 model

### PaperBranch model — Candidate A ordinary path plus Candidate C extension

Capture and restore an owned `document_text + canonical frontier` branch with the later content-addressed authority snapshot commit; mutable fixture generation remains only in its separate publication ref. Allocate a fresh writer identity. Append local scalar-indexed events directly. No history decode, full graph walk, Fugue hydration, or per-character causal table is allowed on this path.

### Fast-forward remote path

Use original positional operations only when every entry point of the incoming region is causally after every head of the restored branch frontier. Include implicit same-writer predecessors in that proof. This path requires zero operation-payload cold reads beyond the incoming region; metadata/index lookups must be counted separately.

### Concurrent remote path

Select and validate a critical replay base, stream the required conflict region from the cold event graph, build a placeholder-backed temporary merge tracker, emit transformed positional effects, update text/frontier, and discard the tracker. Cold reads are expected and measured here; requiring zero reads would contradict the paper.

### Recovery path

If the capture receipt, frontier, graph membership, replay-base proof, or required history is unavailable or inconsistent, discard the accelerator and run the canonical full-history oracle. The oracle may use the existing full-history defensive-copy accessors in isolated test/recovery processes, but its events and peak bytes must be measured and it must never be reported as a fast path. A candidate-negative result remains a successful R0 finding.

### Legacy control

Measure a disposable serialized Fugue/IndexedState projection only to establish whether it is a useful migration bridge. It cannot win the canonical-state decision merely by being easiest to implement.

## Consequences for existing R0 tickets

The Candidate A/B/C and `ClosedTail` names below refer to the branch plan [`2026-08-19-loomark-editable-branch-restore-feasibility.md`](../archive/plans/2026-08-19-loomark-editable-branch-restore-feasibility.md) and its linked GitHub issues; they are not concepts from the accepted architecture ADR or Eg-walker paper.

1. The oracle/runner ticket should first establish a `PaperBranch` tracer: capture text/frontier/receipt, cross a separate-process byte boundary, restore, append one local positional event, and compare with the full-history oracle.
2. Candidate A should become the paper branch and fast-forward path, not an unspecified minimum authority summary.
3. Candidate C should become critical replay-base proof plus placeholder conflict-zone replay, not a persistent position-based branch.
4. Candidate B remains a legacy migration control and should not block Candidate A or C.
5. The final decision must compare a combined paper path (A ordinary + C concurrency) against the legacy control. A and C are complementary, not competing production architectures.
6. The operation matrix must classify ordinary local and causally-after events as no-replay, and genuine concurrency as bounded cold conflict replay. `ClosedTail` terminology and zero-read closed-concurrent acceptance should be removed.
7. Undelete is an explicit Canopy extension absent from the paper. Its canonical event has a dedicated undelete-target field (the original Insert `RawVersion`) rather than overloading the legacy `origin_left` representation. Resolution uses indexed bounded replay with a disposable tracker and must not force a resident tombstone map into the normal branch. Resolved by [the undelete decision](2026-08-21-r0-undelete-after-paper-branch-restore.md) (#1316).

## Remaining decisions

- Resolved by [the content-addressed capture receipt](2026-08-20-r0-capture-receipt-reassessment.md): an immutable snapshot commit binds text/frontier content, while fixture generation/sequence remains in a separate mutable publication ref.
- Resolved by [the cold event-graph capability boundary](2026-08-20-r0-cold-event-graph-capability-boundary.md): resident exact-head/writer commitments authenticate batched metadata while operation bodies remain cold.
- Resolved by [the concurrency replay-base proof](2026-08-21-r0-concurrency-replay-base-proof.md) (Wayfinder #1315): critical replay base from authenticated causal metadata via one-colour waterline scan, with V2 sidecar `causal_rank_timestamp` and bounded fallback.
- Resolved by [the canonical positional-event and Unicode contract](2026-08-20-r0-canonical-positional-event-unicode-contract.md): canonical events use parent-frontier-relative scalar positions and convert only at the UTF-16 adapter.
- Resolved by [the undelete after paper-branch restore](2026-08-21-r0-undelete-after-paper-branch-restore.md) (Wayfinder #1316): undelete target is the original Insert identity as an explicit planner seed; indexed bounded replay with a disposable tracker; no persistent tombstone map or reverse index.
