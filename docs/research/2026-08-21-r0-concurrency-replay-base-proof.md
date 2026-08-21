# Gate R0 concurrency replay-base proof

**Date:** 2026-08-21

**Status:** pending morning acceptance. Issue [#1315](https://github.com/dowdiness/canopy/issues/1315) remains open until acceptance.

**Wayfinder:** [#1315](https://github.com/dowdiness/canopy/issues/1315)

**Depends on:** [restore architecture](2026-08-19-egwalker-r0-restore-architecture-reassessment.md), [capture receipt](2026-08-20-r0-capture-receipt-reassessment.md), [cold capability boundary](2026-08-20-r0-cold-event-graph-capability-boundary.md), [positional-event/Unicode contract](2026-08-20-r0-canonical-positional-event-unicode-contract.md)

**Linked refinements:** [#1312](https://github.com/dowdiness/canopy/issues/1312), [#1313](https://github.com/dowdiness/canopy/issues/1313), [#1314](https://github.com/dowdiness/canopy/issues/1314) — those issues may remain closed; the V2 sidecar refinement is a substantive linked refinement, not a reopen.

## Decision

Freeze the corrected concurrency decision. The genuine-concurrency path uses a **Loro-L11-style one-colour waterline scan over individual raw events from the union of current and incoming heads**, not a simplified planner that shortcuts entry-point coverage.

### Corrected decision summary

1. **Strict-forward entry-point coverage stays zero-read for fully hot-resolved effects.** Every declared parent and nonzero implicit predecessor resolves inside incoming events or resident exact head records; each predecessor is proven reachable through declared-parent closure; coverage reaches every resident head. A semantic reference whose target kind, identity-to-text mapping, or effect requires cold evidence is not called closed strict-forward even when its causal parents cover the heads; #1316 classifies cold undelete as indexed semantic-reference replay. The zero-read label applies only when all semantic-reference evidence needed for the effect is supplied in the incoming/hot region.

2. **Genuine concurrency uses a one-colour waterline scan.** The planner descends from the union of current exact heads and incoming heads over individual raw events, using the Loro `latest_single_head_critical_version` pattern (Loro `dag.rs` L11 scan; `/tmp/loro/crates/loro-internal/docs/critical-version-spec.md` L11). The scan is single-colour — there is no red/blue distinction; all entries descend from the same union frontier. The scan operates strictly per-event: each heap entry is one raw identity; duplicates (same agent and sequence) are deduped by identity, not by span/alignment vocabulary.

3. **Priority is by a V2 sidecar `causal_rank_timestamp` with identity secondary.** The heap orders entries by:
   - Primary: `causal_rank_timestamp = GraphEntry.timestamp` (Lamport timestamp, extracted exactly from the graph entry by the producer).
   - Secondary: canonical UTF-8 raw identity (unsigned bytewise lexical order of validated UTF-8 agent bytes, then numeric sequence) — the existing bound identity, not a second field.

   `causal_rank_timestamp` is not a Lamport timestamp alias. It is a substantive linked refinement to #1312/#1313/#1314: it is included in the V2 sidecar types (`EventMetaV2`, `R0HeadRecordV2`) and bound through V2 domain-separated leaf/head/graph/snapshot digests. The V1 event digest and `EventMetaV1` are unchanged. The verifier checks `Int` bounds (MoonBit signed 32-bit, `0..0x7fff_ffff` for canonical positions; Lamport timestamp is a non-negative `Int`) and strict parent-rank monotonicity for every fetched declared edge: every declared parent's `causal_rank_timestamp` is strictly less than the child's `causal_rank_timestamp`. The producer extracts the exact `GraphEntry.timestamp` value. The pure verifier checks strict rank decrease on every declared edge it actually traverses; this local topological-rank property is sufficient for the waterline ordering and does not require walking below the selected base. At the selected base, the committed rank is accepted as a boundary certificate. The independent full-history oracle rebuilds `GraphEntry.timestamp` values from the complete operation graph and rejects any V2 sidecar rank mismatch. No production schema, API, or wire format changes; the V2 refinement is test-only sidecar/storage/receipt, and V1 is superseded before implementation.

4. **Dedup identical events.** When the heap top entries share the same raw identity (same agent and sequence), pop all of them and merge. This is the Loro aggregation step: identical positions in the descent coalesce into one entry.

5. **If the heap empties, the popped event is a single-head critical base.** When the last dedup leaves the heap empty, the popped raw identity is a single-head critical version of the union graph. Under EGW's canonical antichain-parent invariant it is the latest single-head cut found by L11. If malformed/redundant parent sets violate that invariant, the gate rejects or may conservatively over-retreat but never accepts a non-critical base. The pending heap is a cut of the unexplored region; narrowing to one event establishes that every replayed event is causally after it.

6. **If root/trim/missing/corrupt/resource bound occurs while the heap is nonempty, explicit full-history fallback.** Root death proves no singleton is possible: if any chain dies at a root while other chains remain, its endpoint is concurrent with everything below the current level, so no later single-event cut can be critical. The same conservative reasoning applies to trimmed history, missing dependencies, corrupt proofs, and configured resource bounds. The planner returns an explicit `FallbackRequired` decision. The runner invokes `read_full_history`. Do not accept a meet or any non-critical base as the replay base.

7. **Do not accept a meet or any non-critical base.** The candidate replay base must be critical in the union graph. The meet of current and incoming versions is only a candidate; if it is not critical, the algorithm must retreat to the latest single-head critical version or fall back to full history. This follows Eg-walker §3.5's critical version definition and Loro's strengthened entry-point coverage. Separately, Loro PR #1058 fixed a redundant-path classification bug that retreated the replay base to the beginning of history, causing a 124-byte update to replay all history at hundreds of times normal cost (`/tmp/loro/crates/loro-internal/docs/critical-version-spec.md` §1.3); it is performance evidence for preserving the tips/dedup discipline, not the proof that a non-critical meet is unsafe.

### V2 sidecar refinement

The V2 refinement is a test-only sidecar over the existing V1 types. V1 canonical event body, `event_digest`, `EventMetaV1`, and the V1 domain-separated leaf/head/graph/snapshot digests are unchanged. The V2 types add `causal_rank_timestamp` without altering any production schema, API, or wire format. V1 is superseded before implementation; all new R0 test sidecar, storage, and receipt artifacts use V2.

```text
EventMetaV2 {
  identity
  kind
  event_digest_v2                // V2 digest, see below
  body_digest                    // unchanged from V1
  causal_rank_timestamp          // NEW: GraphEntry.timestamp (non-negative Int)
  declared_parents : Array[(RawVersion, EventDigestV2)]
  implicit_predecessor : (RawVersion, EventDigestV2)?
  semantic_references : Array[(ReferenceKind, RawVersion, EventDigestV2, RequiredReferencedKind)]
  payload_byte_length
}
```

```text
R0HeadRecordV2 = (RawVersion, EventDigestV2, causal_rank_timestamp : Int)
```

V2 digest composition:

```text
event_digest_v2 = SHA-256(
  domain("loomark-r0-event:v2")
  || canonical raw identity
  || body_digest
  || causal_rank_timestamp        // uvarint
  || sorted declared-parent identity/digest records
  || optional implicit-predecessor identity/digest record
  || sorted role-tagged semantic-reference records
)
```

V2 domain-separated types:

```text
meta_leaf_hash_v2    = SHA-256(domain("loomark-r0-meta-leaf:v2") || canonical EventMetaV2)
writer_root_v2       = SHA-256(domain("loomark-r0-writer-root:v2") || ...)
graph_root_v2        = SHA-256(domain("loomark-r0-graph:v2") || ...)
snapshot_commit_v2   = R0SnapshotCommitV2 { ... }   // includes R0HeadRecordV2 array
```

The V2 snapshot commit retains every V1 field and additionally binds `causal_rank_timestamp` in each head record. The V2 `snapshot_commit_id` is SHA-256 over the complete canonical V2 field set.

V2 binding obligations:

- **Meta-leaf:** `meta_leaf_hash_v2` commits the complete `EventMetaV2` including `causal_rank_timestamp`.
- **Writer root:** `writer_root_v2` transitively commits every leaf's `causal_rank_timestamp` through the Merkle accumulator.
- **Graph root:** `graph_root_v2` commits sorted `(RawVersion, EventDigestV2, causal_rank_timestamp)` head records.
- **Snapshot commit:** `snapshot_commit_v2` commits the V2 graph root and V2 head records, transitively binding every head's `causal_rank_timestamp`.

Tier-0 head ranks preserve zero-read first local event. With no resident heads, a new root receives rank `0`. Otherwise `new_rank = max(resident head causal_rank_timestamps) + 1`. If the maximum head rank is already `0x7fff_ffff`, rank allocation returns an explicit pure `rank_exhausted` rejection/fallback before event emission; arithmetic never wraps. No provider read is required.

Verifier obligations for `causal_rank_timestamp`:

- **Int bounds:** `GraphEntry.timestamp` is a non-negative MoonBit `Int` (signed 32-bit). The verifier rejects negative timestamps or timestamps at or above `0x8000_0000`.
- **Strict parent-rank monotonicity:** For every fetched declared edge `parent → child`, `parent.causal_rank_timestamp < child.causal_rank_timestamp`. Equal timestamps with different identities are resolved by the secondary raw-identity ordering; equal timestamps with equal identities are duplicates.
- **Producer extraction:** The producer reads `GraphEntry.timestamp` directly from `CausalGraph::get_entry(lv)` (`deps/event-graph-walker/internal/core/graph_types.mbt` L111: `timestamp : Int`). No recomputation, no approximation.
- **Local rank verification:** For every declared edge traversed above the base, the pure verifier checks `parent.causal_rank_timestamp < child.causal_rank_timestamp`. When a popped non-base event is expanded, all of its declared parents enter the scan; no separate below-base rank-witness query exists.
- **Boundary certificate:** Heap-empty detection occurs before expanding the selected base. Its committed `causal_rank_timestamp` is accepted as a boundary certificate, and its parents are not read.
- **Oracle independence:** The full-history oracle reconstructs the complete operation graph, recomputes its `GraphEntry.timestamp` values, and compares every candidate V2 sidecar rank it used.

### Implicit predecessor remains separate

The implicit predecessor `(agent, sequence - 1)` is present in `EventMetaV2` when sequence > 0. It is a readiness/sequence proof, not a declared graph edge. The planner verifies that the implicit predecessor is reachable through the declared-parent closure; it is not inserted into the graph as an additional edge. This follows the cold capability boundary decision and Loro's distinction between explicit deps and implicit same-peer predecessors (Loro `dag.rs` `deps_to_ord_id_spans` adds the implicit predecessor to the traversal set without modifying stored deps).

### Declared-edge scan obligation

The one-colour waterline scan traverses declared-parent edges only. The planner verifies predecessor reachability via declared closure for every scanned event. The proof may advance incrementally with metadata traversal, but no scan result is accepted until every relevant predecessor proof is complete; an unavailable or over-budget proof falls back. A regression test must verify that removing the declared-closure proof causes the scan to produce an incorrect replay set on a graph with implicit-predecessor redundancy.

### Replay protocol

After the waterline scan selects the critical base:

1. **The scan fetches the selected base's metadata but never its payload or recursively walks its ancestry.** The base's `EventMetaV2` (including `causal_rank_timestamp`) is fetched to obtain the boundary certificate. The base's payload bytes are not fetched. Heap-empty detection occurs before expanding the base, so no below-base parent metadata is requested.

2. **The payload identity set is exactly the events visited/popped by the scan strictly above the base.** Every event the scan pops from the heap at a rank strictly greater than the base's `causal_rank_timestamp` contributes its raw identity to the replay set. No events at or below the base are included.

3. **Classify only the above-base set as current/shared/incoming-only.** After the replay set is fixed, classify each event as:
   - **current-only:** in the ancestry of current heads but not incoming heads.
   - **shared:** in the ancestry of both current and incoming heads, strictly above the critical base.
   - **incoming-only:** in the ancestry of incoming heads but not current heads.

   The heap entries propagate a two-bit current/incoming provenance label while the criticality algorithm otherwise remains one-colour; dedup merges the labels. Classification therefore uses the already visited metadata and requires no second provider traversal.

4. **Fetch exactly these payloads, excluding bytes already supplied.** After the replay set is fixed, fetch payloads for exactly the events in the replay set in stable topological order/batches. Cold payload requests exclude payload bytes already supplied by the incoming batch or hot input; only bytes not already available are counted as cold provider payload reads.

5. **Replay current and shared-above-base without output in a new executable-local disposable unbounded-placeholder tracker.** Initialize a temporary tracker with a single unbounded placeholder representing the unknown document content at the critical base. Correctness requires the complete Eg-walker §3.6 placeholder machinery: insert/delete positions split placeholder ranges, replayed identities remain addressable, and transformed offsets are derived from the split runs. A single opaque blob that cannot split is not an accepted implementation. Replay current and shared-above-base events through the tracker without producing output. No events at or below the base are replayed. The tracker is executable-local, disposable, and unbounded-placeholder — it does not persist, does not alias any Fugue tree, OpLog, live LV, or CausalSnapshot.

6. **Transform incoming-only effects onto resident text.** Apply incoming-only events through the tracker, producing transformed positional effects. Apply those effects to the resident paper-branch text.

7. **Discard the tracker.** After producing text effects, the tracker is discarded. No CRDT internal state persists.

### What this is not

- **No Fugue/OpLog/live LV alias.** The temporary tracker is not a `FugueTree`, `OpLog`, `CausalGraph`, `CausalSnapshot`, or any live mutable structure. It is a disposable placeholder-backed merge context.
- **No meet acceptance.** The meet of current and incoming is not the replay base unless it is independently proven critical.
- **No non-critical base.** If the scan cannot produce a critical base, the result is explicit full-history fallback, not a degraded acceptance.
- **No simplified planner.** The earlier simplified planner that skipped entry-point coverage is explicitly rejected. The scan operates over individual raw events from the union frontier with full dedup.
- **No span/alignment/id_last vocabulary in the EGW scan.** The EGW scan operates strictly per-event with raw-identity dedup. Loro's span/alignment machinery is an implementation optimization for change-granular storage; the EGW scan's correctness argument does not depend on it.
- **No production schema/API/wire change.** The V2 refinement is test-only sidecar/storage/receipt. V1 types and digests are unchanged; V1 is superseded before implementation.

### Budget dimensions

Budget dimensions (maximum metadata nodes, proof bytes, payload events, payload bytes, elapsed time) are configured by [#1317](https://github.com/dowdiness/canopy/issues/1317). Exceeding any configured limit returns a pure `FallbackRequired` decision. Any limit → fallback/negative. This decision does not set specific numeric bounds; #1317 owns that configuration.

## Functional Core / Imperative Shell boundary

### Functional core

- `causal_rank_timestamp` verification: pure Int-bounds and strict parent-rank monotonicity checks over verified V2 records.
- Waterline scan planner: pure function consuming verified `EventMetaV2` records and returning the replay identity set, critical base, or `FallbackRequired`.
- Colour classification: pure function over the visited set and two input frontiers.
- Replay-set payload selection: pure function returning the exact above-base identity set in stable topological order, excluding bytes already supplied by incoming/hot input.
- Event digest V2 composition: pure function including `causal_rank_timestamp`.
- Declared-closure predecessor proof: pure function over authenticated metadata.

### Imperative shell

- Capture extraction: read `GraphEntry.timestamp` from the live EGW graph and encode the V2 sidecar record.
- Provider I/O: metadata batch fetches (batching all newly revealed parent identities per reducer step), payload batch fetches, full-history fallback.
- Tracker lifecycle: allocate the disposable placeholder tracker, feed it events, extract transformed effects, discard.
- Resident text mutation: apply transformed incoming-only effects to the paper-branch text.
- Accounting emission: merge provider physical-read counters with planner accounting into JSONL observations. Cache hits count logically (the logical query and planner-visit counts are retained even when physical calls/bytes are zero).
- Oracle invocation: call `read_full_history` on fallback; compare results including rank comparison.

The core performs no provider I/O, no text mutation, no tracker allocation, and no clock/random reads. The shell performs I/O only and translates effects into core inputs.

## Boundary matrix

| Path | Scan type | Metadata reads | Payload reads | Tracker | Text mutation | Fallback |
|---|---|---|---|---|---|---|
| Receipt validation | none | 0 | 0 | none | none | hash mismatch → reject |
| First local paper event | none | 0 | 0 | none | append to resident | N/A |
| Closed strict-forward | none | 0 existing | 0 | none | apply incoming directly | coverage fail → concurrent or fallback |
| Genuine concurrency (critical base found) | L11 one-colour waterline | bounded metadata for scan (base metadata included; base parents and payload excluded) | exactly above-base replay-set payloads (excluding incoming/hot-supplied bytes) | disposable unbounded-placeholder | transform incoming-only onto resident | scan failure → full-history |
| Genuine concurrency (no critical base) | L11 scan aborts | bounded metadata | 0 | none | none | explicit full-history |
| Full fallback/oracle | N/A | N/A | N/A | N/A | N/A | complete history replay |

## Proof obligations

| ID | Obligation | Method |
|---|---|---|
| P1 | `causal_rank_timestamp` is deterministic across JS and native for the same identity/declared-parent graph | Cross-target property test: the same validated graph entry → the same V2 rank bytes and head record |
| P2 | Strict parent-rank monotonicity holds for every declared edge in authenticated metadata | Verifier check on every `Found` metadata result; reject on violation |
| P3 | The waterline scan produces a critical base or explicit fallback | Unit tests against known graph shapes: linear, diamond, concurrent branches, multi-root |
| P4 | If the heap empties, the popped event is critical in the union graph | Oracle comparison: scan result matches full-history critical version |
| P5 | If root/trim/missing/corrupt/resource bound occurs with nonempty heap, fallback is triggered | Negative tests: inject each failure mode, verify `FallbackRequired` |
| P6 | The replay identity set equals exactly the events above the critical base in the union graph | Compare scan output with oracle-computed conflict region |
| P7 | The disposable tracker produces the same text effects as full-history replay for the same input | Differential test: tracker effects vs. oracle effects |
| P8 | No Fugue/OpLog/live LV alias escapes the tracker lifecycle | Code review; no public API returns tracker internals |
| P9 | V2 leaf/head/snapshot binding: `causal_rank_timestamp` is bound through `meta_leaf_hash_v2`, `writer_root_v2`, `graph_root_v2`, and `snapshot_commit_v2` | Digest comparison: different timestamps → different V2 digests at each layer |
| P10 | Implicit predecessor is verified reachable via declared-parent closure, not inserted as a graph edge | Unit test: predecessor presence ≠ graph edge; reachability proven separately |
| P11 | Declared-edge scan is permitted only after predecessor-via-declared-closure proof | Regression test: removing the closure proof causes incorrect replay set on implicit-predecessor redundancy graph |

## Counters

The existing accounting contract from the cold capability boundary decision applies. Additional counters for this decision:

- `scan_events_visited`: number of individual raw events the waterline scan pops from the heap (including deduped duplicates).
- `scan_dedups`: number of times multiple heap entries with the same raw identity are coalesced.
- `scan_critical_base_found`: boolean; true when the heap empties with a single event, false when fallback is triggered.
- `scan_fallback_reason`: one of `root_death`, `trim_death`, `missing_dependency`, `corrupt_proof`, `resource_bound`, `rank_exhausted`, `no_critical_base`.
- `replay_set_current_count`, `replay_set_shared_count`, `replay_set_incoming_count`: classification counts after colour derivation (above-base only).
- `tracker_events_replayed`: total events fed to the disposable tracker (current + shared-above-base + incoming-only).
- `tracker_events_output`: events whose transformed effects are applied to resident text (incoming-only only).

These are reported in the per-phase JSONL observation alongside the existing counters.

## Existing API First — concrete candidates

### Reused

| API | Location | Use |
|---|---|---|
| `GraphEntry.timestamp` | `deps/event-graph-walker/internal/core/graph_types.mbt` L111 | Producer extracts exact Lamport timestamp for `causal_rank_timestamp` |
| `CausalGraph::get_entry(lv)` | `deps/event-graph-walker/internal/causal_graph/graph.mbt` L99 | Producer reads graph entry by LV |
| `CausalGraph::raw_to_lv` | `deps/event-graph-walker/internal/causal_graph/graph.mbt` L90 | Resolve raw identity to LV for entry access |
| `Op::parents_iter()` | `deps/event-graph-walker/internal/core/operation.mbt` L45 | Iterate declared parents without allocation |
| `AdmissionReceipt::committed()` | `deps/event-graph-walker/internal/oplog/typed_admission.mbt` | Producer builds sidecar from committed operations |
| `OpLog::get_frontier_raw()` | `deps/event-graph-walker/internal/oplog` | Exact raw head authority |
| `@priority_queue.PriorityQueue` | MoonBit core | Scan heap ordering by `(causal_rank_timestamp, raw_identity)` |
| `@hashset.HashSet` | MoonBit core | Visited-set dedup during scan |
| `Map`, `Array::sort_by`, `Buffer` | MoonBit core | Canonical ordering, batch construction |
| `Option`/`Result` | MoonBit core | Explicit invalid/missing handling |
| `@encoding/utf8.encode/decode` | MoonBit core | Strict canonical UTF-8 |

### Checked but not used for the scan

| API | Reason not used |
|---|---|
| `@text.Version` | Version vector, not exact frontier or scan input |
| `SyncSession::export_all()` / `OpLog::get_all_ops()` | Full-copy oracle/fallback only |
| `CausalSnapshot` | Live LV-indexed alias; not a frozen bytes-only provider |
| `CausalGraph::graph_diff` / `diff_frontiers_lvs` | Combine metadata traversal with payload expansion; hides tier accounting |
| `walk_and_collect()` / `diff_and_collect()` | Same: hide tier accounting |
| `FugueTree` / `IndexedState` | Persistent CRDT state; the tracker is disposable, not these |
| `Branch::checkout` | Full rebuild; fallback only |

### Unavoidable new helper

No existing public helper implements the one-colour waterline scan over individual raw events with `causal_rank_timestamp` ordering. An executable-local scan helper is required; its sole responsibility is the L11 descent with identity dedup and fallback detection. Property tests compare its output with the oracle-computed critical version.

## Required coordinated edits

This decision requires linked changes in the following areas when implemented:

1. **`EventMetaV2`**: new test-only type adding `causal_rank_timestamp` field. V1 `EventMetaV1` and V1 event digest are unchanged and superseded before implementation.
2. **V2 domain-separated types**: `meta_leaf_hash_v2`, `writer_root_v2`, `graph_root_v2`, `R0SnapshotCommitV2` with V2 domains. V1 domains are unchanged.
3. **EGW producer/oracle**: extract `GraphEntry.timestamp` for `causal_rank_timestamp`; the candidate verifies Int bounds and strict traversed-edge monotonicity, while the full-history oracle independently rebuilds and compares complete graph ranks.
4. **Waterline scan helper**: new executable-local package implementing the L11 one-colour descent with `causal_rank_timestamp` ordering and identity dedup. No span/alignment vocabulary.
5. **Disposable tracker**: new executable-local unbounded-placeholder tracker for conflict-zone replay. No Fugue/OpLog/LV alias.
6. **Colour classification**: pure function deriving current/shared/incoming-only from the scan visited set (above-base only) and two input frontiers.
7. **Accounting**: add scan-specific counters to the JSONL observation schema.
8. **Oracle**: recompute `causal_rank_timestamp` independently; compare scan result with full-history critical version including rank comparison.
9. **#1317**: configure budget dimensions for the scan (metadata nodes, proof bytes, payload events, payload bytes, elapsed time).

## Alternatives

| Alternative | Decision | Reason |
|---|---|---|
| Meet as replay base | Reject | Meet is not necessarily critical under Eg-walker §3.5/D8b; Loro's S4 counterexamples motivate explicit entry-point coverage. PR #1058 is separate performance evidence about redundant-path over-retreat. |
| Version-inclusion fast path without entry-point coverage | Reject | Multi-head frontiers can have new branches concurrent with old heads through one head while entering through another |
| Red/blue two-colour scan for critical base | Reject | The L11 single-colour descent is simpler and sufficient for the single-head critical version; two-colour is the main walk's replay-base search, not the fallback scan |
| Persistent placeholder tracker | Reject | Contradicts the paper's disposable internal state model |
| Fugue/OpLog as tracker | Reject | Persistent CRDT state; the paper explicitly discards internal state |
| `causal_rank_timestamp` as Lamport timestamp only | Reject | Lamport timestamps alone do not provide a total order for concurrent events; the secondary raw-identity ordering (existing bound identity, not a second field) is needed for deterministic heap behavior |
| `causal_rank_timestamp` as production wire field | Reject | Test-only V2 sidecar; production wire/storage is unchanged |
| Modifying V1 `EventMetaV1` or V1 event digest | Reject | V1 stays unchanged; the V2 sidecar refinement supersedes V1 before implementation |
| Provider-owned critical-version RPC | Reject | Duplicates EGW authority semantics; the provider performs I/O only |
| Multi-head critical version scan | Defer | Loro's L11 finds single-head only; multi-head critical versions require a different criterion and are not yet needed |
| Simplified planner skipping entry-point coverage | Reject | Proven incorrect; the cold capability boundary decision already requires full coverage proof |
| Span/alignment/id_last scan vocabulary for EGW | Reject | EGW events are individual raw operations, not change-granular spans; the scan deduplicates by raw identity |

## Unresolved questions

1. **Measured feasibility of the unbounded-placeholder tracker.** The paper describes placeholders for range `[0, ∞]`; the tracker must handle arbitrary document sizes without materializing the full content at the critical base. Whether MoonBit's memory model and the executable-local allocation strategy can sustain this for large documents without excessive overhead is unmeasured. This is a feasibility question, not a correctness question: the algorithm is correct by construction; the question is whether the placeholder representation is practical at scale.

2. **Multi-head critical version detection.** The L11 scan finds the latest single-head critical version. If the union graph has a multi-head critical version that is later than any single-head one, the scan will not find it and will fall back further than necessary. Whether this matters for the measured corpus is untested.

3. **Budget dimension values (#1317).** The specific numeric bounds for metadata nodes, proof bytes, payload events, payload bytes, and elapsed time are deferred to #1317. Until configured, any limit triggers fallback.

## Consequences

- Production APIs, wire formats, and storage schemas are unchanged. The V2 refinement is test-only sidecar/storage/receipt.
- V1 `EventMetaV1` and V1 event digest are unchanged. V1 is superseded before implementation; all new R0 artifacts use V2.
- The cold capability boundary's types are refined to V2 (`EventMetaV2`, `R0HeadRecordV2`, `WriterCommitmentV2`, V2 domain-separated leaf/head/graph/snapshot digests).
- The strict-forward path remains zero-read; this decision only affects the genuine-concurrency path.
- Issues #1312, #1313, #1314 may remain closed; the V2 sidecar refinement is a linked refinement.
- Issue #1315 remains open pending morning acceptance.
- Issue #1317 owns budget dimension configuration.
- No Fugue/OpLog/live LV alias is introduced.
- The disposable tracker is executable-local and does not affect any public API.

## Sources inspected

- Eg-walker paper §3.5–3.7 (`/tmp/egwalker-paper.txt` L1785–L2134): critical version definition, internal state clearing, partial replay with placeholders, algorithm complexity.
- Loro critical-version-spec.md (`/tmp/loro/crates/loro-internal/docs/critical-version-spec.md`): L11 latest single-head critical version scan, critical version definition (D8b), meet vs. critical distinction, entry-point coverage (L12/S4), PR #1058 bug description (§1.3).
- Loro `dag.rs` (`/tmp/loro/crates/loro-internal/src/dag.rs` L487–L836): `_find_common_ancestor_new` contract, `latest_single_head_critical_version` implementation (L730), `new_region_after_all_left_heads` entry-point coverage check.
- EGW `GraphEntry` (`deps/event-graph-walker/internal/core/graph_types.mbt` L99–L113): `timestamp : Int` field, Lamport timestamp semantics.
- EGW `CausalGraph::get_entry` (`deps/event-graph-walker/internal/causal_graph/graph.mbt` L99): entry access by LV.
- EGW `pkg.generated.mbti` (`deps/event-graph-walker/internal/core/pkg.generated.mbti` L29–L33): public `GraphEntry` shape confirmation.
- Four coordinated R0 docs:
  - `docs/research/2026-08-19-egwalker-r0-restore-architecture-reassessment.md`: paper branch model, ordinary/concurrent path split, #1315 deferral.
  - `docs/research/2026-08-20-r0-capture-receipt-reassessment.md`: content-addressed snapshot commit, event digest overlay, `EventMetaV1` shape.
  - `docs/research/2026-08-20-r0-cold-event-graph-capability-boundary.md`: authenticated metadata provider, `EventMetaV1` fields, path contracts, accounting schema, strict-forward zero-read rule.
  - `docs/research/2026-08-20-r0-canonical-positional-event-unicode-contract.md`: canonical event algebra, scalar positions, digest composition, #1315 dependency for replay-set proof.
