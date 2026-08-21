# Gate R0 cold event-graph capability boundary

**Date:** 2026-08-20

**Question:** Which event-graph metadata queries must be available to a restored paper branch, which operation payloads remain cold, and how does Gate R0 count every query, scan, event, and byte?

## Decision

Use a **batched authenticated metadata provider plus a separate batched payload provider**, with all causal and replay decisions kept in a deterministic EGW functional core.

The authenticated identity index is a two-level structure tailored to EGW's stable `RawVersion(agent, sequence)` identity:

1. the snapshot commit retains a canonically sorted O(replica-count) array of writer commitments; and
2. each writer commitment authenticates its contiguous sequence of `EventMeta` leaves with an append-only Merkle accumulator (a per-writer MMR is the R0 reference scheme).

The structural reason for this scheme is canonical per-writer sequence order; it is not an unmeasured speed claim. Gate evidence must report index/proof bytes and query latency, and may record a negative if a generic authenticated map is smaller or faster on the measured corpus. The scheme avoids the fatal ambiguity of using `@text.Version` as an exact frontier: writer commitments provide authenticated membership ranges, while canonically sorted raw head records remain the exact frontier.

The provider exposes primitive bytes and proofs only. It does not answer `is_ancestor`, strict-forward, critical-version, conflict-region, or semantic-equivalence questions. Those belong to EGW's deterministic planner so storage cannot duplicate or hide authority semantics.

**Historical note on versioning:** The initial draft of this decision used V1 type names and domain tags (`R0SnapshotCommitV1`, `EventMetaV1`, `:v1` domains). V1 is unimplemented and uninterpreted; it is superseded in every active schema, code block, and prose reference below before Gate R0 implementation. All new R0 sidecar and snapshot-commit artifacts use V2. Body/algebra bytes are unchanged, so `EventPayloadV1` and `body_digest` (domain `loomark-r0-event-body:v1`) remain the active names for the payload tier. The exact-head identity hash (`loomark-r0-heads:v1`) also remains `:v1` because head identity bytes are unchanged; the separate `R0PublicationRefV1` provenance pointer is unchanged.

## State tiers

### Tier 0 — resident paper branch and snapshot commit

Loaded with the candidate, independent of history size:

```text
R0SnapshotCommitV2 {
  document_id_sha256
  graph_root_v2
  exact_raw_heads_sorted
  exact_raw_heads_sha256
  exact_head_records_sorted : Array[R0HeadRecordV2]
  writer_commitments_sorted : Array[WriterCommitmentV2]
  document_text_byte_length
  document_text_scalar_length
  document_text_sha256
  snapshot_commit_id
}

R0HeadRecordV2 = (RawVersion, EventDigestV2, causal_rank_timestamp : Int)

WriterCommitmentV2 {
  agent
  leaf_count             // max admitted sequence + 1; empty writers omitted
  tip_event_digest_v2    // digest at sequence leaf_count - 1
  event_meta_mmr_root_v2
}
```

Rules:

- Head and writer arrays use canonical raw-identity order: unsigned bytewise lexical order of preflight-validated UTF-8 agent bytes, then numeric sequence where applicable. MoonBit `String::compare` is not this comparator.
- Test-only canonical preflight rejects malformed UTF-16 in every string field, including document/agent IDs, before UTF-8 encoding or hashing; this prevents JS replacement behavior from diverging from native failure.
- Writer records are unique by agent and empty writer commitments are never emitted. R0 preflight rejects a sequence above `0x7fff_fffe`, because `leaf_count = max_sequence + 1` must remain a positive signed 32-bit `Int`. Admitted sequences must be exactly `0..<leaf_count`; any negative sequence, duplicate sequence, gap, or count overflow refuses capture.
- `exact_raw_heads_sorted` is the identity projection of `exact_head_records_sorted`; length, order, and identities must match exactly. `exact_raw_heads_sha256 = SHA-256(domain("loomark-r0-heads:v1") || canonical_exact_raw_heads_encoding)`, where the canonical encoding is head count followed by canonical raw identities in stored order.
- Every exact head must equal that writer commitment's tip identity `(agent, leaf_count - 1)` and `tip_event_digest_v2`. Writers whose tips are causally dominated need not appear in the exact head set. Their tip digest is integrity-bound by `snapshot_commit_id`; the O(heads + writers) fast path does not fetch the MMR tip leaf merely to cross-check it. Full-history capture/oracle validation proves each omitted writer tip and digest belong to the graph and that the tip is in the ancestry of an exact head.
- `graph_root_v2` is verified directly against the resident exact `R0HeadRecordV2` head records; the fast path never rebuilds it from cold payloads.
- `snapshot_commit_id` is `SHA-256(domain("loomark-r0-snapshot:v2") || canonical preceding fields)` over every preceding `R0SnapshotCommitV2` field except itself: document ID, graph root, exact raw heads, exact-head hash, exact head records, writer commitments, text byte length, text scalar length, and text hash. The resident text bytes are transitively bound by recomputing their byte length/hash before accepting the commit. No field may be loaded or substituted independently from another snapshot; a publication ref selects one immutable commit ID and advances only after the complete candidate object is durable.
- The exact head digests, not only head identities, are resident. They allow the first local event and a closed strict-forward region to extend the Merkle-DAG without a provider read.
- Resident size is O(text bytes + exact heads + writers), never O(history).

This explicitly refines the closed capture-receipt decision: it preserves `exact_raw_heads_sorted`/`exact_raw_heads_sha256`, adds authenticated exact head records, and adds writer commitments required by cold lookup. The capture-receipt ticket receives a linked correction comment when this decision closes. No per-event metadata becomes resident.

Tier-0 head ranks preserve first-local zero-read: root rank 0, otherwise max head rank + 1, max `Int` → `rank_exhausted` fallback.

### Tier 1 — authenticated event metadata, indexed but not resident

One logical metadata leaf is:

```text
EventMetaV2 {
  identity
  kind
  event_digest_v2
  body_digest
  causal_rank_timestamp          // GraphEntry.timestamp (non-negative Int)
  declared_parents : Array[(RawVersion, EventDigestV2)]
  implicit_predecessor : (RawVersion, EventDigestV2)?
  semantic_references : Array[(ReferenceKind, RawVersion, EventDigestV2, RequiredReferencedKind)]
  payload_byte_length
}
```

- `declared_parents` contains only the operation's declared causal parents. These are the only edges replayed into `CausalGraph`. Canonical R0 preflight rejects duplicate declared-parent identities rather than deduplicating them, because EGW preserves duplicate-parent multiplicity in operation identity.
- `implicit_predecessor` is present exactly when sequence is greater than zero. It is a readiness/sequence proof, not silently converted into a declared graph edge. Admission additionally proves that predecessor is reachable through the declared-parent closure; mere predecessor presence is insufficient.
- For canonical positional events, `semantic_references` contains only operation-model roles needed for validation but not declared causal traversal: currently the dedicated undelete target. A reference is retained with its role and required kind even when the same identity also appears as a declared parent or predecessor; identity deduplication must never erase semantic role evidence. Legacy left/right Fugue origins belong to a separately tagged compatibility/oracle metadata profile and never enter canonical event identity.
- `kind` and `RequiredReferencedKind` are authenticated metadata because current admission must reject references whose target is not an insert. The planner fetches the referenced `EventMetaV2` and verifies its authenticated `kind` satisfies the required kind; the referring record cannot assert the target's actual kind by itself. Inserted text, scalar position, and other operation body fields stay cold.
- All arrays use stable identity ordering.
- `body_digest` is SHA-256 of the positional decision's domain-separated exact canonical body bytes. The [capture receipt](2026-08-20-r0-capture-receipt-reassessment.md#event-digest-overlay) owns the exact `event_digest_v2` composition over the `:v2` event domain, canonical raw identity, `body_digest`, `causal_rank_timestamp`, parents, predecessor, and semantic references; this boundary consumes that digest and does not redefine its framing.
- The metadata leaf hash binds the complete `EventMetaV2` value at leaf position `sequence` in that writer's accumulator.
- The verifier checks Int bounds (non-negative MoonBit `Int`) and strict parent-rank monotonicity on every traversed declared edge; the independent full-history oracle rebuilds ranks and rejects any V2 sidecar mismatch. A provider may retain additional derived hints (outdegree, etc.), but they remain optional acceleration beyond the required V2 rank.

Why per-writer accumulators work:

- Local writer sequences start at zero and advance contiguously.
- Remote readiness includes `(agent, sequence - 1)`; incomplete sequences remain pending.
- Capture validates contiguity before publishing writer commitments.
- A lookup for an absent writer or `sequence >= leaf_count` is an authenticated non-membership result from Tier 0 alone.
- A lookup inside `0..<leaf_count` must return a leaf and Merkle proof; absence or invalid proof is corruption/fallback.

The reference accumulator is an append-only MMR per writer, not an MMR over global admission order. Global admission order is not canonical under concurrency; each writer's sequence order is canonical.

R0 freezes this MMR framing:

```text
meta_leaf_hash_v2 = SHA-256(domain("loomark-r0-meta-leaf:v2") || canonical EventMetaV2)
meta_node_hash_v2 = SHA-256(domain("loomark-r0-meta-node:v2") || uvarint(height) || left || right)
writer_root_v2    = SHA-256(
  domain("loomark-r0-writer-root:v2")
  || length_prefixed_utf8(agent)
  || uvarint(leaf_count)
  || uvarint(peak_count)
  || peaks_in_descending_height_order(height, digest)
)
```

`WriterCommitmentV2.event_meta_mmr_root_v2` stores exactly the `writer_root_v2` value below. Leaves are height 0 via `meta_leaf_hash_v2`. Append uses binary carry over equal-height peaks; when two child peaks of height `h` merge, the `meta_node_hash_v2` height field is the new internal node's own height `h + 1`. An inclusion proof contains sequence/leaf position, containing peak height, bottom-up sibling digests with left/right direction, and every other peak needed to reconstruct `writer_root_v2`. The verifier rejects wrong leaf position, height, peak order/count, extra bytes, or a root mismatch. Proofs and roots from an unregistered scheme are unsupported rather than heuristically accepted.

### Tier 2 — cold event payload

```text
EventPayloadV1 {
  canonical_event_body_bytes
}
```

`EventPayloadV1.canonical_event_body_bytes` is the encoded form of the positional decision's `CanonicalTextEventBodyV1`; there is one body codec, not a second payload representation. Canonical positional bytes include kind, scalar position/text, or dedicated undelete target; they contain no Fugue origins. A separately tagged legacy compatibility/oracle profile includes origin fields that change legacy semantics. On read, the consumer verifies byte length and `body_digest` from authenticated `EventMetaV2` before using the payload.

Incoming network/test-region payload is counted separately and is not a cold-provider payload read.

### Tier 3 — canonical full history

The complete history remains the oracle and fallback. No candidate path may call it under a metadata or payload query name.

## Provider capability

The snapshot commit arrives in candidate bytes and is not re-read from the cold provider during a candidate phase. The logical test-only provider has exactly three read operations:

```text
lookup_event_meta_batch(snapshot_commit_id, sorted_unique_raw_ids)
  -> Array[MetaLookupResult]

read_event_payload_batch(snapshot_commit_id, sorted_unique_raw_ids)
  -> Array[PayloadReadResult]

read_full_history(snapshot_commit_id)
  -> canonical oracle/fallback bytes
```

`MetaLookupResult` is one of:

- `Found(encoded_meta, writer_mmr_proof)`;
- `MissingInAuthenticatedRange`;
- `Unavailable`;
- `Corrupt`.

`Unavailable` means the provider could not supply an otherwise valid in-range record under the current capability/resource state and requires fallback. `Corrupt` means bytes/proof/framing failed validation and also requires fallback, with a distinct evidence reason.

Absent writers and sequences beyond `leaf_count` are decided from the resident writer array and must not call the provider. Every in-range request must return exactly one result in the same position; returned length must equal deduplicated request length, and each decoded identity must equal its request identity. The consumer verifies every `Found` result against the resident matching writer commitment. `MissingInAuthenticatedRange` is corruption/fallback.

`PayloadReadResult` returns exact bytes or typed missing/unavailable/corrupt evidence. The consumer must already hold authenticated metadata for every requested payload and validates length/hash before decoding.

All requests and results preserve the requested stable identity order. Callers reject negative sequences before query generation, deduplicate, and batch; no required single-item/N+1 API is defined. A one-element batch is valid.

The provider does **not** expose:

- a live `OpLog`, `CausalGraph`, `CausalSnapshot`, storage handle, LV, or mutable collection;
- `has_event` as a separate trusted boolean;
- provider-owned ancestry, coverage, replay-base, or conflict-region decisions;
- whole-history iteration except the explicit fallback/oracle operation.

The provider shell performs I/O only. Pure verification turns encoded responses into owned `VerifiedEventMeta`/`VerifiedEventPayload` values; pure planners consume those values and return the next metadata/payload request or a decision.

## Path contracts

### Receipt validation and read-only text

- Recompute text byte length/scalar length/hash, exact-head identity projection/hash, head↔writer-tip invariants, and graph root, then recompute `snapshot_commit_id` over the complete canonical field set. Reject any mixed-snapshot substitution before observing text or planning an edit.
- Provider metadata queries: zero.
- Provider payload reads: zero.
- Full-history reads/walks: zero.

The read-only observation is harness behavior, not a public Markdown API.

### First local paper event

- Allocate a fresh writer.
- Parent from resident exact head records.
- Compute the new event digest and initialize/append its writer accumulator.
- Provider metadata queries: zero.
- Provider payload reads: zero.
- Full-history reads/walks: zero.

Legacy origin/target-based operations may fail this contract and remain a Candidate B control or bounded negative. The positional-event decision owns that distinction.

### Closed strict-forward region

A region is `closed_strict_forward` only when every incoming declared parent and semantic reference needed by the region resolves from another incoming event or the resident exact head records, every nonzero implicit predecessor resolves **and is proven reachable through the declared-parent closure**, every incoming entry point proves coverage of every prior exact head, and every semantic-reference fact needed to determine the visible effect is supplied in the incoming/hot region. A semantic reference whose target kind, identity-to-text mapping, or effect requires cold evidence is not closed strict-forward even when its causal parents cover the heads; #1316 classifies cold undelete as indexed semantic-reference replay.

- Existing-provider metadata queries: zero.
- Existing-provider payload reads: zero.
- Incoming event bytes are recorded separately.

If the proof needs an older event, classify `indexed_forward`, not closed strict-forward. It may use authenticated metadata batches but still requires zero existing payload reads. If coverage remains unprovable, use concurrent planning or fallback.

### Duplicate/conflicting identity and pending dependency

- Tier 0 writer ranges answer obvious non-membership without I/O.
- In-range identity checks use one or more authenticated metadata batches.
- Recompute and compare the incoming body digest, declared parents, predecessor, semantic references/kinds, and complete event digest with the verified metadata.
- Existing payload reads: zero on the positive metadata path.
- Invalid/missing proof is corruption/fallback, never permission to accept the incoming operation.

### Genuine concurrency

- The pure planner walks only authenticated metadata needed to prove a replay base and conflict region.
- Metadata requests are batched by traversal frontier.
- Every planning request carries explicit maximum metadata nodes, proof bytes, payload events, payload bytes, and elapsed time. Exceeding any limit returns a pure `FallbackRequired` decision.
- After the replay set is fixed within those limits, fetch payloads for exactly that set in stable topological order/batches.
- Temporary placeholder merge state is discarded after producing text effects.
- Metadata and payload reads are expected and bounded by the selected region, not required to be zero.
- An unavailable proof, missing payload, exceeded resource policy, or unprovable replay base causes explicit full-history fallback.

The [#1315 replay-base decision](2026-08-21-r0-concurrency-replay-base-proof.md) fixes the exact planner algorithm. #1317 still owns numeric metadata/proof/payload/time budgets. The provider never selects the critical version itself.

### Full fallback and oracle

The runner invokes the provider's distinct `read_full_history` operation. It cannot be implemented by repeatedly calling metadata/payload APIs while labeling the path partial. Oracle reads are recorded separately from candidate reads but never omitted.

## Existing API reuse

### Reused in the EGW producer/oracle

- `AdmissionReceipt::committed()` and `AdmissionOutcome::{Complete,Partial}` maintain the sidecar from operations actually committed, including committed partial prefixes.
- `AdmissionReceipt::frontier_before/after()` plus `CausalGraph::lv_to_raw()` update exact head records.
- `AdmissionReceipt::pending_after_count()` prevents exact capture with unresolved work.
- Local `OpLog::{insert,delete,undelete}` return the committed operation directly.
- `OpLog::get_frontier_raw()` supplies head-only authority evidence without `get_all_ops()` at the internal package seam.
- `OpLog::{get_op,get_ops,get_ops_rle}` back test payload reads without expanding the complete log. For arbitrary raw IDs, the provider resolves every ID with `CausalGraph::raw_to_lv()`, rejects any missing mapping, calls `get_ops` with the aligned LV array, and verifies result count/identity alignment. `get_ops_rle` is reserved for an already range-shaped replay set.
- `CausalGraph::{raw_to_lv,lv_to_raw,get_entry,graph_diff,diff_frontiers_lvs,is_ancestor}` remain white-box oracle/reference APIs.
- `Op::parents_iter()`, identity/content accessors, `Map`, `Bytes`, and `Buffer` support canonical sidecar construction. `origin_left()`/`origin_right()` are used only by the separately tagged legacy compatibility/oracle profile.
- No public helper exposes the required declared-parent/predecessor/semantic-reference split. `EventMetaV2`, `R0HeadRecordV2`, and their named constructors live in the executable-local test package so no cross-package writable fields or `.mbti` surface are needed. A new package-local canonicalization helper is unavoidable; its sole responsibility is constructing those values, and property tests compare it with existing admission readiness/target validation.
- `moonbitlang/x/crypto` is not currently an EGW dependency. Gate R0 selects an explicit probe dependency for native/JS hashing and uses Nushell only as an independent verifier; a Nushell-only candidate boundary is not accepted. The EGW submodule review and publish preflight must prove the probe/crypto dependency is excluded from the production archive, or candidate support records bounded negatives without widening production packages.

### Checked but not used as the provider boundary

- `@text.Version`: useful version vector, not exact frontier or authenticated event lookup.
- `SyncSession::export_all()` / `OpLog::get_all_ops()`: full-copy oracle/rebuild only.
- `CausalSnapshot`: live LV-indexed alias that reflects future mutation; not a frozen bytes-only provider.
- `OpLog::causal_graph()`: live internal reference; oracle only.
- `walk_and_collect()` / `diff_and_collect()`: combine metadata traversal with payload expansion and therefore hide tier accounting; use only as oracle comparisons.
- `CausalCut`: wbtest prototype built from a full operation copy; not retained provider state.

The producer is the planned executable package `deps/event-graph-walker/internal/restore_feasibility_probe/` inside the EGW module and imports the intentionally public `internal/oplog`, `internal/causal_graph`, and `internal/core` packages. This creates only an executable/test-package boundary and reviewed internal `.mbti` dependencies, not a Canopy or Markdown façade. If publish preflight cannot prove exclusion from production package exports, use the plan's package-local test-stdout fallback and record the boundary result.

## Read accounting contract

The provider/consumer process emits one JSONL observation per operation to stdout. The pure planner returns phase-local `PlannerAccounting` with its decision; the shell merges that value with provider physical-read counters into the observation. Nushell only captures, validates, and aggregates records—it neither owns nor resets hidden provider counters.

Every provider operation emits one JSONL event with:

```text
schema_version
run_id
case_id
candidate
phase
logical_query_id
query_kind
requested_id_count
returned_record_count
cache_status
physical_read_calls
physical_bytes
framing_bytes
metadata_bytes
proof_bytes
payload_bytes
index_nodes_read
planner_metadata_nodes_visited
resident_records_visited
resident_text_code_units_visited
resident_text_scalars_visited
scan_records_visited
full_history_events
full_history_bytes
result
fallback_reason?
elapsed_us
```

### Definitions

- A **logical query** is counted even on cache hit.
- A **physical read call** is one provider/backend byte-read operation, not one requested event.
- `physical_bytes` is the exact raw byte count crossing the provider boundary and must equal framing + metadata + proof + payload + full-history bytes or explain provider overhead explicitly.
- `payload_bytes` counts operation body bytes; read amplification remains visible in `physical_bytes`.
- `index_nodes_read` counts Merkle/MMR nodes fetched for proof generation/verification. Their encoded bytes are included in `proof_bytes`; the node count is an additional structural metric, not an uncharged byte category.
- `planner_metadata_nodes_visited` counts verified event records inspected by the deterministic planner, including cache hits.
- `resident_records_visited` counts O(heads/writers) candidate-header records inspected. Scanning all prior exact heads for strict-forward coverage is allowed and visible here; it is not a provider scan.
- `resident_text_code_units_visited` and `resident_text_scalars_visited` count verified resident/temporary plain-text traversal for UTF-16↔scalar conversion. They are independent of provider scans and remain visible on a zero-provider-read path.
- `scan_records_visited` is nonzero whenever the provider sequentially examines cold records not named in the request. A batch of named point lookups is not a scan. This provider-scan counter is distinct from #1315's `scan_events_visited`, which counts identities deliberately popped by the pure replay-base planner.
- `full_history_events/bytes` are nonzero only for the explicit fallback/oracle operation.
- Incoming-region bytes, candidate bytes, capture/rebuild bytes, and oracle bytes are separate artifact fields.
- Cache hits retain the logical query and planner-visit counts while physical calls/bytes may be zero. They never make a metadata-dependent algorithm qualify as zero-query.
- Candidate and oracle counters are separate. Gate summaries may exclude oracle cost from candidate latency but must retain the raw oracle records.

Each phase receives a fresh phase-local accounting value rather than mutating/resetting a shared global counter: capture/rebuild, receipt validation, restore, first edit, strict-forward, duplicate/conflict, pending, concurrent planning, concurrent payload replay, fallback, and oracle. A helper that performs work after a phase clock but before observation emission is part of that phase.

### Positive controls

Before any zero assertion can pass, preflight must independently prove detection of:

1. one metadata lookup and proof read;
2. one payload batch read;
3. one sequential metadata scan produced by an intentionally naive/misbehaving provider implementation, proving `scan_records_visited` detects work outside the three-operation semantic boundary;
4. one explicit full-history read;
5. one resident UTF-16↔scalar conversion that proves both text-visit counters are wired.

Each control verifies logical calls, physical calls, records/events, and byte counters.

## Acceptance rules

- Receipt validation: zero metadata queries, payload reads, scans, and full-history reads.
- First local paper event: zero provider queries of every tier.
- Closed strict-forward: zero existing-provider metadata/payload queries and cold scans; O(exact-head count) resident coverage checks are reported in `resident_records_visited`.
- Indexed forward: metadata queries allowed and reported; zero existing payload/full-history reads.
- Duplicate/conflict positive path: authenticated metadata only; zero payload/full-history reads.
- Concurrent path: payload identities must equal the planner-selected replay set; any extra payload is unexpected read amplification.
- No fast path may call `export_all`, `get_all_ops`, `walk_and_collect`, `diff_and_collect`, or `Branch::checkout` under another name.
- Provider/candidate metadata whose serialized size or restore query cost loses to the full-history oracle remains a valid negative.
- Missing authenticated-index/MMR capability is a candidate negative, not justification for a trusted unauthenticated lookup.

## Alternatives rejected

| Alternative | Why rejected |
|---|---|
| Root + heads only | Cannot authenticate arbitrary identity lookup, duplicate/conflict, or replay metadata. |
| Full metadata map in the candidate | O(history) hot load and retained authority duplication. |
| Trusted `has_event`/payload locator | Raw identity is not content-addressed; corruption or mixed generations could authorize the wrong event. |
| Provider-owned ancestry/critical-version RPC | Duplicates EGW authority semantics and hides traversal/read cost. |
| Generic global sparse Merkle map | Correct alternate authenticated index. Not selected as the reference because it ignores canonical contiguous writer order; no speed/size inferiority is claimed until measured. |
| Global MMR/hash chain | Global admission order differs under concurrency and is not canonical graph identity. |
| Graph-root ancestry path for every identity lookup | Correct but may require O(history) witness paths for old duplicate identities. |
| Full payload with every metadata query | Defeats the metadata/payload separation and duplicate/forward zero-payload paths. |

## Consequences

- The snapshot receipt owns and preserves its raw-head identity/hash, exact head event digests, writer commitments, and derived document scalar length; this boundary consumes that field set rather than independently adding the scalar length. `snapshot_commit_id` directly commits the full canonical resident field set and transitively commits resident text through its verified byte length/scalar length/hash, preventing valid pieces from different snapshots from being mixed. This linked decision explicitly refines the capture-receipt field set.
- The cold provider capability is storage-neutral but not integrity-neutral: positive results require proof verification against the snapshot commit.
- Current typed internal admission receipts are sufficient to evaluate incremental sidecar maintenance in the test-only EGW producer; the public Text façade still does not expose this capability, which R0 records rather than widening.
- The provider contract establishes data access and accounting only. Unicode positional event fields remain a separate decision. Critical replay-base selection is resolved by the [concurrency replay-base proof](2026-08-21-r0-concurrency-replay-base-proof.md) (#1315) with V2 sidecar `causal_rank_timestamp`. Undelete semantics are resolved by the [undelete after paper-branch restore](2026-08-21-r0-undelete-after-paper-branch-restore.md) (#1316). Production storage is unchanged; V2 is test-only sidecar/storage/receipt.
