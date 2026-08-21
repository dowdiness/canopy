# Gate R0 undelete after paper-branch restore

**Date:** 2026-08-21

**Wayfinder:** [#1316](https://github.com/dowdiness/canopy/issues/1316)

**Depends on:** [restore architecture](2026-08-19-egwalker-r0-restore-architecture-reassessment.md), [capture receipt](2026-08-20-r0-capture-receipt-reassessment.md), [cold capability boundary](2026-08-20-r0-cold-event-graph-capability-boundary.md), [positional-event/Unicode contract](2026-08-20-r0-canonical-positional-event-unicode-contract.md), Wayfinder [#1315](https://github.com/dowdiness/canopy/issues/1315)

**Status:** accepted. Integrated into the canonical R0 research set.

## Question

What is the canonical R0 behavior of `Undelete` after a paper-branch restore, and how does the cold/pre-snapshot planner resolve the undelete target without adding persistent tombstone or reverse-index state to the normal branch?

## Decision

### D1 — Canonical undelete target identity

`Undelete(target_identity)` targets the original Insert `RawVersion` of the revived scalar. `RequiredReferencedKind = Insert`. The canonical event body carries the dedicated target identity; it does not overload `origin_left`, Fugue left/right origins, or a visible position.

The target semantic reference is **not a causal edge**. It does not enter the declared-parent set and does not extend the causal frontier by itself. Instead, the target Insert is an **explicit planner seed** alongside the current exact heads and the complete incoming heads. The planner receives three inputs:

1. The current exact heads (from the snapshot commit).
2. The complete incoming heads (from the current hot batch or session).
3. The target Insert identity (from the undelete event's semantic reference).

If the target Insert identity cannot be resolved against the current exact heads, the complete incoming heads, or the cold metadata provider, the planner preserves existing pending/fallback semantics — it does not unconditionally reject as corruption.

This follows the existing internal EGW contract:

- `Op::undelete` stores the target in `origin_left` and sets `content = Undelete` (`internal/core/operation.mbt:143-160`).
- `Op::get_delete_target` returns `origin_left` for both `Delete` and `Undelete` (`internal/core/operation.mbt:190`).
- Admission rejects any undelete whose target is not an Insert via `OriginTargetNotInsert` (`internal/oplog/errors.mbt:16-19`, `internal/oplog/remote_admission_planner.mbt:482`, `internal/oplog/remote_admission_planner.mbt:960`, `internal/oplog/remote_admission_planner.mbt:1163`).
- The container `TextUndeleteOp` carries an explicit `target : RawVersion` (`container/text_block.mbt:26-29`).
- The positional-event/Unicode contract already narrows `EventMetaV2.semantic_references` to the undelete target for canonical events and binds `RequiredReferencedKind` in the role-tagged semantic-reference record ([positional-event/Unicode contract](2026-08-20-r0-canonical-positional-event-unicode-contract.md)).

### D2 — Authority-accepted remote undelete event

Every cold/pre-snapshot remote undelete outcome — target visible, target deleted with undelete winning, target deleted with concurrent delete winning — requires the same **indexed bounded replay**. A single target metadata read never determines visibility or effect. The planner cannot short-circuit on resident text alone because the resident paper branch holds no per-character causal metadata.

The remote event is always admitted when its causal parents, implicit predecessor, and target-Insert kind are valid. The causal frontier advances. The visible text effect depends on the bounded replay outcome:

- **Target already visible:** the replay resolves the winner; the effect is empty because the target is already present.
- **Target deleted, undelete wins:** the replay resolves the winner; the text gains the scalar.
- **Target deleted, concurrent delete wins (higher-ts):** the replay resolves the winner; the effect is empty because the delete prevails.

All three paths traverse the same replay mechanism. The planner does not branch on a preliminary visibility check.

Source: `Document::apply_remote` routes through `admit_remote` and `project_remote_ops`; remote projection calls `FugueTree::undelete_with_ts`, gated by `should_win_delete` LWW (`internal/document/document.mbt:588-658`, `internal/fugue_projection/projection.mbt:105-141`, `internal/fugue/tree.mbt:246-270`). `commit_undelete_by_lv` is the separate local path.

### D3 — Local `undelete_if_deleted` is legacy full-Document oracle behavior

The local `Document::undelete_if_deleted` API checks current visibility against the resident Fugue tree. If the target is already visible, it returns `Stale` and emits no event. If deleted, it commits an undelete op and returns `Applied`.

Source: `Document::undelete_if_deleted` returns `Stale` when `lv_to_position` returns `Some(_)` and commits only on `None` (`internal/document/document.mbt:571-583`).

This is **legacy full-Document oracle behavior**: it requires a live `Document` with a resident Fugue tree, an OpLog, and a causal graph. After a bytes-only paper-branch restore, no such live Document exists. The local API path is not available on a restored paper branch without first rebuilding the full Document state.

The R0 planner must preserve this distinction. A restored branch that receives a remote undelete event uses the indexed bounded replay mechanism (D2). The local `undelete_if_deleted` path is not a zero-cost shortcut on a restored paper branch.

### D4 — Cross-process pre-snapshot local undo is bounded negative

No public target receipt or undo stack crosses the restore boundary. The container `UndoItem::TextDelete(block, id)` captures the block `TreeNodeId` and the target `RawVersion` of the deleted Insert (`container/undo_types.mbt:10`). The undo stack is process-local mutable state; it is not part of the `R0SnapshotCommitV2` and does not survive a bytes-only handoff.

After restore, the new process has:

- verified resident text and exact heads;
- no undo stack, no transaction buffer, no `tracking_enabled` state;
- no knowledge of which scalars were deleted by which local undo groups before capture.

Therefore cross-process **pre-capture** local undo is **bounded negative**: the restored branch cannot replay a pre-capture undo because the undo group that named the target does not exist in the new process. The planner must never guess a target identity from resident text alone.

**Post-restore** local undo is zero-read only when an authority-owned hot undo receipt names the target **and** the complete hot replay evidence (target Insert plus all competing delete/undelete events) was created or supplied in the current hot post-restore batch/session input. Without both conditions, post-restore local undo follows the indexed bounded replay path or is bounded negative.

Source: `Document::undo` pops from `self.undo_stack` (`container/undo.mbt:342-380`), and `clear_undo` clears the process-local stack (`container/undo.mbt:480-482`). The snapshot commit contains no undo fields ([capture receipt reassessment](2026-08-20-r0-capture-receipt-reassessment.md)).

### D5 — Cold/pre-snapshot undelete cannot be direct strict-forward

A restored paper branch holds resident text, exact heads, writer commitments, and the snapshot commit. It does **not** hold:

- the target's kind (Insert vs Delete vs Undelete);
- the target's scalar position in any parent text;
- the target's inserted scalar text;
- the current delete/undelete winner state (`timestamp`, `is_undelete`, `agent`) for the target.

Therefore a cold undelete request whose target predates the snapshot cannot be classified as closed strict-forward. The resident head digest lacks the target kind, position, scalar, and winner state needed to decide whether the undelete has a visible effect.

This is not a gap in the receipt; it is the paper-aligned boundary. The normal branch intentionally holds no per-character causal metadata. This decision narrows the earlier U3 wording: causal head coverage alone does not make an undelete closed strict-forward. The zero-read strict-forward label additionally requires that every semantic-reference fact and every payload needed to determine the visible effect is already supplied by the incoming/hot region.

### D6 — Classification: indexed semantic-reference replay

Undelete after restore is classified as **indexed semantic-reference replay**:

1. The planner receives the target Insert identity as an explicit seed (D1).
2. It reads authenticated `EventMetaV2` for the target identity from the cold metadata provider; V2 includes the `kind` field and adds the rank required by #1315.
3. It verifies the target's authenticated `kind` is `Insert` (satisfying `RequiredReferencedKind = Insert`). A proven non-Insert is a semantic reject; the oracle is checked for confirmation.
4. It runs #1315's backward L11 scan from the union of current exact heads, complete incoming heads, and the explicit target seed. It accepts only a single-head critical lower bound of that complete union that is **strictly causally before** the target Insert. If the scan first reaches the target itself, it expands the target instead of accepting it; if the target is a root, the base is empty. A concurrent target/undelete branch that has no such single-head cut falls back rather than using a target-only ancestor.
5. The same backward scan enumerates every current, incoming, and target-seed event strictly above the union-critical base; no forward/reverse provider query is needed. This includes concurrent delete/undelete contenders because they are reached from the current or complete incoming heads even though their target reference is not a causal edge. Any event outside those versions cannot affect that branch.
6. During replay, `DeleteScalar` position-to-identity mapping is resolved before grouping winners; no reverse query is needed.
7. It fetches exact selected payloads for the replay set.
8. It initializes #1315's disposable splitting-placeholder tracker at the union-critical base. Replaying the target Insert reconstructs its scalar identity/content; replaying each `DeleteScalar` resolves position to identity before winner grouping.
9. It reproduces the current EGW winner precedence (D8), emits the transformed text effect against resident text, and disposes the tracker. The placeholder represents all pre-base text without materializing its identities.

True zero-read is achieved only when the target Insert **and** the complete anchor-to-frontier replay evidence/payloads were created or supplied in the current hot post-restore batch/session input. Merely "already admitted" plain-text state is insufficient — the replay evidence must be present in the hot incoming/session region.

### D7 — No new persistent state

The following are explicitly **not** added to the normal branch:

| Rejected addition | Reason |
|---|---|
| Kind field in resident head record | Replay-set selection is causal-only; kind is verified from the target's own authenticated metadata, not asserted by the referring event ([positional-event/Unicode contract](2026-08-20-r0-canonical-positional-event-unicode-contract.md)). |
| Reverse provider query (target → delete/undelete ops) | The provider exposes named-point metadata lookup only; it does not answer "which ops target this identity" ([cold capability boundary](2026-08-20-r0-cold-event-graph-capability-boundary.md)). |
| Resident tombstone map | Persists per-character CRDT metadata contrary to the paper branch ([restore architecture](2026-08-19-egwalker-r0-restore-architecture-reassessment.md)). |
| Reverse index (target → delete/undelete LVs) | Same objection as tombstone map; also duplicates the `DeleteIndex` responsibility into the normal branch. |

The existing internal `DeleteIndex` (`internal/branch/delete_index.mbt:5-22`) is a merge-time-only structure built from a full OpLog scan. It is evidence for the winner algorithm, not a persistent resident structure.

### D8 — Winner precedence reproduction

The disposable tracker reproduces the current EGW `should_win_delete` precedence:

```text
(GraphEntry.timestamp, is_undelete, agent)
```

with sentinel initialization (`cur_ts = 0`, `cur_agent = ""`, `cur_is_undelete = false`) matching the existing `should_win_delete` sentinel check (`internal/fugue/tree.mbt:187-207`):

- higher `GraphEntry.timestamp` (Lamport timestamp) wins;
- at equal timestamp, `is_undelete = true` beats `is_undelete = false` (add-wins);
- at equal timestamp and equal kind, the agent tie-break calls/reuses the current `should_win_delete` MoonBit `String` comparison (`new_agent > cur_agent`), not canonical UTF-8 ordering. This LWW comparator is intentionally different from #1315's canonical UTF-8 raw-identity ordering used only to make the replay scan heap deterministic; implementations must not unify them.

Source: `should_win_delete` in `internal/fugue/tree.mbt:187-207`:

```text
if cur_ts == 0 && cur_agent == "" { return true }  // sentinel: no previous winner
if new_ts != cur_ts { return new_ts > cur_ts }
if new_is_undelete != cur_is_undelete { return new_is_undelete }
new_agent > cur_agent
```

The `DeleteIndex::recompute_winner` method scans all delete/undelete ops targeting one item, skips the retreat set, and applies this same precedence (`internal/branch/delete_index.mbt:61-100`). The R0 disposable tracker must reproduce this exact algorithm over the bounded replay set, not invent a different rule.

### D9 — `causal_rank_timestamp` in V2 sidecar

The V2 sidecar types (`EventMetaV2`, `R0HeadRecordV2`) carry a `causal_rank_timestamp` field. The [capture receipt](2026-08-20-r0-capture-receipt-reassessment.md) owns V2 event/graph/snapshot digests, while the [cold capability boundary](2026-08-20-r0-cold-event-graph-capability-boundary.md) owns `EventMetaV2`, `R0HeadRecordV2`, `WriterCommitmentV2`, and MMR framing; rank-specific semantics (extraction, binding obligations, first-local allocation, verifier obligations) are in [#1315](2026-08-21-r0-concurrency-replay-base-proof.md). Gate R0 itself is test-only: every candidate provider/read path in this decision consumes V2, while no production provider or storage schema is authorized.

The planner verifies:

- **bounds:** every replay-set entry's timestamp is a non-negative MoonBit `Int`, and rank increment overflow falls back before emitting an event;
- **parent-rank monotonicity:** every traversed entry's timestamp is strictly greater than every declared parent's timestamp used by the scan;
- **oracle gate:** the full-history Loomark/internal `Document` + `DeleteIndex` oracle independently rebuilds ranks and computes the same winner for every target in the replay set.

This refinement is test-only. The production wire timestamp is a separate compatibility profile (D10).

### D10 — Container TextOp wire timestamp: no-adapter/no-equivalence compatibility profile

The container `TextUndeleteOp` carries its own `timestamp : Int` field (`container/text_block.mbt:26-29`). This is the container-level wire timestamp used by the `TextBlock` Fugue LWW comparison. It is a **no-adapter/no-equivalence compatibility profile** — it is not adapted to or equivalent to the R0 canonical `GraphEntry.timestamp`.

The R0 canonical event uses the dedicated target identity and the authenticated `GraphEntry.timestamp` from the causal graph, not the container wire timestamp. The container `TextUndeleteOp` wire-protocol tests (`container/text_undelete_wbtest.mbt`) are **not canonical evidence** for R0 undelete semantics; they test a separate container-level compatibility profile.

### D11 — Fallback contract

Missing, corrupt, target-kind mismatch, or budget-exceeded conditions trigger explicit fallback. The missing-target path is resolved in stages, not by unconditional corruption reject:

| Condition | Behavior |
|---|---|
| Target identity unresolved against incoming/hot | First resolve against the incoming/hot batch; if found there, proceed with hot replay |
| Target identity unresolved against snapshot range | Then resolve against the snapshot range via cold metadata provider |
| Target identity unresolved after both stages | Follow existing pending semantics and candidate fallback/oracle; not unconditional corruption reject |
| Target metadata unavailable (`Unavailable`) after provider lookup | Full-history fallback |
| Target metadata corrupt (`Corrupt`) | Full-history fallback |
| Target `kind` proven not `Insert` | Semantic reject; oracle checked for confirmation |
| Target identity absent from authenticated range | Follow existing pending semantics; candidate fallback/oracle |
| Replay-set payload read exceeds budget | Full-history fallback |
| Replay-set metadata traversal exceeds budget | Full-history fallback |
| Parent-rank monotonicity violation | Full-history fallback; evidence of corruption |

The full-history Loomark/internal `Document` + `DeleteIndex` oracle determines reject/pending/result on the full-history path. The candidate path never silently degrades to a partial or trusted-unauthenticated lookup.

## Behavior matrix

| Case | Resident state | Cold reads | Visible effect | Frontier advance |
|---|---|---|---|---|
| Remote undelete, target visible (cold) | text + heads | metadata: 1 + bounded replay, payload: bounded replay set | empty | yes |
| Remote undelete, target deleted, undelete wins (cold) | text + heads | metadata: 1 + bounded replay, payload: bounded replay set | text gains scalar | yes |
| Remote undelete, target deleted, concurrent delete wins (cold) | text + heads | metadata: 1 + bounded replay, payload: bounded replay set | empty | yes |
| Remote undelete, hot (target Insert + complete replay evidence in current session) | text + heads + hot evidence | 0 | winner-dependent | yes |
| Local `undelete_if_deleted` (legacy full-Document oracle) | live Document | N/A — requires live Fugue tree | legacy behavior | legacy behavior |
| Cold undelete, target in snapshot | text + heads | metadata: 1 + bounded replay, payload: bounded replay set | winner-dependent | yes |
| Cold undelete, target missing/unresolved | text + heads | staged resolution: incoming/hot → snapshot range → pending/fallback | oracle-dependent | oracle-dependent |
| Pre-capture undo of pre-capture delete | no undo stack | N/A | bounded negative; no event | no |
| Post-restore undo with hot undo receipt + complete hot replay evidence | text + heads + hot receipt | 0 | text gains scalar (if winner) | yes |
| Post-restore request names target but lacks complete hot evidence | text + heads + target receipt | metadata: 1 + bounded replay, payload: bounded replay set | winner-dependent | yes if admitted |
| Post-restore undo lacks any authority-owned target receipt | text + heads | N/A | bounded negative; target is never guessed | no |

## Functional core / imperative shell

### Pure functional core (reducer)

- Target identity resolution: pure. Takes the target seed, current exact heads, and complete incoming heads; returns resolved target metadata or pending/fallback.
- Target metadata verification: pure. Reads authenticated `EventMetaV2`, verifies `kind = Insert`, and verifies the #1315 rank conditions.
- Replay-base selection: pure. Runs #1315's union scan and accepts only a single-head critical lower bound of current heads, complete incoming heads, and target seed that is strictly causally before the target; empty base if the target is a root.
- Replay-set construction: pure. Uses that same backward scan's visited region to select every current/incoming/target-seed event strictly above the base, including concurrent semantic-reference contenders.
- DeleteScalar position-to-identity resolution: pure. Resolved during replay before grouping winners.
- Winner precedence computation: pure. Reproduces `should_win_delete` over the bounded replay set with sentinel initialization.
- Text effect emission: pure. Given the replay set and winner results, computes the transformed scalar effect.

### Imperative shell (I/O)

- Cold metadata/payload provider I/O: shell only. Fetches batched metadata and exact payloads; performs no semantic decisions.
- Disposable tracker lifecycle: shell allocates and disposes. The tracker is not retained across operations. The tracker is test-only/package-local; it is not part of the production public API.
- Full-history fallback invocation: shell calls the provider's `read_full_history` when the pure core returns `FallbackRequired`.
- Hot-batch evidence assembly: shell supplies the current incoming events and payloads to the pure core; performs no winner decisions.

## Acceptance obligations

1. The canonical undelete event body carries the dedicated target identity and nothing else. No Fugue origins enter canonical event digest.
2. Remote undelete admission is unconditional on local visibility when causal/semantic validation passes.
3. All cold/pre-snapshot remote undelete outcomes traverse the same indexed bounded replay; one target metadata read never determines visibility or effect.
4. No persistent tombstone map, reverse index, kind field in resident head record, or reverse provider query is added to the normal branch.
5. The disposable tracker reproduces the exact `should_win_delete` precedence with sentinel initialization and MoonBit `String` comparison for agent tie-break.
6. `causal_rank_timestamp` uses the #1315 V2 sidecar (`EventMetaV2`/`R0HeadRecordV2`).
7. Full-history Loomark/internal `Document` + `DeleteIndex` oracle independently rebuilds ranks and matches candidate winner/text/frontier on every case.
8. Missing/unresolved target follows staged resolution (incoming/hot → snapshot range → pending/fallback), not unconditional corruption reject.
9. Proven non-Insert target is a semantic reject; oracle checked.
10. Container TextOp wire timestamp remains a no-adapter/no-equivalence compatibility profile; its tests are not canonical evidence.
11. Pre-capture cross-process undo records a bounded negative; post-restore undo is zero-read only with an authority-owned hot undo receipt plus complete hot replay evidence.
12. Pure reducer requests are split from the I/O shell.
13. The target semantic reference is not a causal edge; the target Insert is an explicit planner seed alongside current exact heads and complete incoming heads.

## Read accounting

Undelete after restore follows the concurrent-path accounting from the [cold capability boundary](2026-08-20-r0-cold-event-graph-capability-boundary.md):

- Metadata requests are batched by traversal frontier.
- Payload identities equal the planner-selected replay set; extra payloads are unexpected read amplification.
- `planner_metadata_nodes_visited` includes the target verification and every replay-set metadata record.
- `payload_bytes` counts exactly the replay-set operation bodies.
- The disposable tracker is not a provider read; its construction and disposal are planner-local.
- Full-history fallback emits a separate `read_full_history` observation.
- Hot-batch evidence supplied in the current session is not a cold-provider read.

## Integrated cross-decision refinements

The [positional-event/Unicode contract](2026-08-20-r0-canonical-positional-event-unicode-contract.md) defines `Undelete(target_identity)` and previously deferred its lookup/replay behavior to this decision. This decision freezes that behavior:

- The target is the original Insert `RawVersion`.
- `RequiredReferencedKind = Insert`.
- The target semantic reference is not a causal edge; the target Insert is an explicit planner seed.
- Lookup uses authenticated metadata; replay uses bounded conflict-region replay with a disposable tracker.
- The winner algorithm reproduces existing `should_win_delete`.
- Replay base is a single-head critical lower bound of the complete current/incoming/target-seed union and is strictly causally before the target; if the target is a root, the base is empty.

The [restore architecture reassessment](2026-08-19-egwalker-r0-restore-architecture-reassessment.md) now records this accepted result: the dedicated target is the original Insert identity and resolution uses indexed bounded replay with a disposable tracker, without a resident tombstone map. This document owns the detailed mechanism.

## Existing API First

### Reused

- `Op::undelete` and `Op::get_delete_target` — existing target identity construction and extraction (`internal/core/operation.mbt:143-160`, `internal/core/operation.mbt:190`).
- `should_win_delete` — existing LWW winner precedence with sentinel initialization and MoonBit `String` comparison (`internal/fugue/tree.mbt:187-207`).
- `DeleteIndex::build` and `DeleteIndex::recompute_winner` — existing winner algorithm evidence (`internal/branch/delete_index.mbt:22-100`). Used as oracle, not as resident state.
- `CausalGraph::get_entry` — accessor at `internal/causal_graph/graph.mbt:99`; its returned `GraphEntry.timestamp` field is defined at `internal/core/graph_types.mbt:99-113`.
- `OpLogError::OriginTargetNotInsert` — existing target-kind validation error (`internal/oplog/errors.mbt:16-19`).
- `Document::undelete_if_deleted` — existing local target-aware undelete with `Stale`/`Applied` result; legacy full-Document oracle behavior (`internal/document/document.mbt:571-583`).
- `EventMetaV2` and `RequiredReferencedKind` — authenticated metadata and semantic-reference role from the cold capability boundary and positional-event contract.
- Authenticated metadata batch lookup — existing provider capability from the cold capability boundary.

### Checked but not used as the primary mechanism

- `DeleteIndex::build` as resident state: rejected because it persists O(history) scan results in the normal branch.
- `FugueTree::delete_with_ts` / `undelete_with_ts` directly on resident state: correct for the legacy full-Document oracle path; the cold path must replay through a disposable tracker because the resident Fugue tree does not exist after a bytes-only restore.
- `Op::origin_left()` as the canonical target: rejected because it conflates Fugue positional origin with semantic reference; the canonical event uses a dedicated target field.
- `CausalSnapshot`: live alias that reflects mutation; not a frozen provider.

### New helper required

- A pure planner reducer that takes authenticated target metadata, current exact heads, and complete incoming heads, then returns the next metadata/payload request, replay commands, or `FallbackRequired`. A package-local pure tracker fold consumes verified payloads with `should_win_delete` precedence and returns text effects. Neither component owns provider I/O or exposes tracker state.

## Alternatives rejected

| Alternative | Reason |
|---|---|
| Resident tombstone map | Persists per-character CRDT metadata contrary to the paper branch. |
| Reverse index (target → ops) | Same objection; duplicates `DeleteIndex` into the normal branch. |
| Kind field in resident head record | Replay-set selection must be causal-only; kind is verified from the target's own metadata. |
| Reverse provider query | Provider contract exposes named-point lookup only; "which ops target this" is not a provider decision. |
| Guess target from resident text | Resident text has no causal identity; violates the bytes-only handoff. |
| Overload `origin_left` as canonical target | Conflates Fugue positional origin with semantic reference; breaks the canonical event digest. |
| Always full-history replay for undelete | Defeats the paper branch advantage; bounded replay is provably sufficient. |
| Zero-read undelete for cold targets | Cold target lacks kind/position/scalar/winner in resident state; zero reads would require inventing state. |
| Persistent `DeleteIndex` on the normal branch | O(history) scan result; same objection as tombstone map. |
| Unconditional corruption reject for unresolved target | Staged resolution (incoming/hot → snapshot range → pending/fallback) preserves existing pending semantics. |

## Unresolved product capability

Whether the product should support post-restore undo of pre-capture deletes is a product decision, not an R0 mechanism decision. The current architecture makes pre-capture undo bounded negative: no undo stack crosses the bytes-only handoff. Post-restore undo is zero-read only when an authority-owned hot undo receipt names the target and the complete hot replay evidence is present in the current session. If the product requires broader capability, it must either:

1. Re-record pre-capture deletes as new undo groups after restore (requires an undo-group receipt in the snapshot commit, which is not part of either the prior V1 or proposed V2 R0 snapshot); or
2. Accept that pre-capture undo is unavailable after cross-process restore.

This decision records the bounded negative and does not authorize a new receipt field.

## Sources inspected

- `deps/event-graph-walker/internal/core/operation.mbt` — `OpContent`, `Op::undelete`, `Op::get_delete_target`, `Op::is_undelete`
- `deps/event-graph-walker/internal/core/graph_types.mbt` — `GraphEntry` with `timestamp`
- `deps/event-graph-walker/internal/fugue/tree.mbt` — `should_win_delete`, `FugueTree::delete_with_ts`, `FugueTree::undelete_with_ts`
- `deps/event-graph-walker/internal/branch/delete_index.mbt` — `DeleteIndex`, `DeleteWinner`, `recompute_winner`, `retreat_operations`
- `deps/event-graph-walker/internal/branch/branch_merge.mbt` — merge retreat/advance with `DeleteIndex`
- `deps/event-graph-walker/internal/document/document.mbt` — `Document::undelete`, `Document::undelete_if_deleted`, `Document::commit_undelete_by_lv`, `TargetEditResult`
- `deps/event-graph-walker/internal/document/document_admission.mbt` — remote undelete target preflight
- `deps/event-graph-walker/internal/document/document_test.mbt` — `OriginTargetNotInsert` rejection test
- `deps/event-graph-walker/internal/document/document_wbtest.mbt` — cache coherence after undelete
- `deps/event-graph-walker/internal/oplog/errors.mbt` — `OriginTargetNotInsert` error variant
- `deps/event-graph-walker/internal/oplog/remote_admission_planner.mbt` — semantic validation raising `OriginTargetNotInsert`
- `deps/event-graph-walker/internal/causal_graph/graph.mbt` — Lamport timestamp construction
- `deps/event-graph-walker/container/text_block.mbt` — `TextUndeleteOp`, `TextOp::Undelete`, container wire timestamp
- `deps/event-graph-walker/container/text_ops.mbt` — `Document::delete_text` capturing target LV before delete
- `deps/event-graph-walker/container/text_undelete_wbtest.mbt` — wire-protocol tests (not canonical evidence for R0)
- `deps/event-graph-walker/container/undo.mbt` — `apply_undo`/`apply_redo` synthesizing `Undelete`/`Delete`
- `deps/event-graph-walker/container/undo_types.mbt` — `UndoItem::TextDelete(block, id)`
- `docs/research/2026-08-19-egwalker-r0-restore-architecture-reassessment.md` — paper branch, undelete as Canopy extension
- `docs/research/2026-08-20-r0-capture-receipt-reassessment.md` — snapshot commit fields, no undo state
- `docs/research/2026-08-20-r0-cold-event-graph-capability-boundary.md` — provider contract, `EventMetaV2`, accounting
- `docs/research/2026-08-20-r0-canonical-positional-event-unicode-contract.md` — canonical `Undelete(target_identity)`, `RequiredReferencedKind`
- `docs/plans/2026-08-19-loomark-editable-branch-restore-feasibility.md` — R0 gate scope and acceptance criteria
