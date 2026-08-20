# Gate R0 capture receipt reassessment

**Date:** 2026-08-20

**Question:** Is there a faster or safer validated text/frontier receipt than the previously selected full-history SHA-256 plus publisher generation?

## Result

Yes. The previous decision should be superseded.

The better R0 design is a **Git/Automerge-style content-addressed snapshot commit over a test-only Merkle-DAG commitment of the canonical event graph**, with fixture epoch/sequence kept in a separate mutable publication ref.

This fixes two problems in the previous resolution:

1. `@text.Version` is a version vector, not the exact event-graph frontier. Exact frontier authority is the raw `SyncMessage.heads` set returned from `get_frontier_raw()`.
2. SHA-256 over `SyncMessage::to_canonical_bytes()` requires full `export_all()` and full-history serialization at every capture. It is O(history) and detects byte mismatch, but does not prove that cached text is the semantic replay result.

The recommended receipt makes repeated capture O(new events × dependency-sort cost + frontier + text bytes) **when authority-owned committed-event and exact-head evidence is available**, keeps restore independent of history size, and leaves semantic equivalence to a trusted atomic authority transition plus the independent full-history R0 oracle. Current EGW does not expose enough committed-event identity evidence to maintain this overlay for every remote/pending/partial path, and its public Text façade obtains raw heads only as part of `export_all()` with a full operation copy. R0 must measure one-time rebuild/full export and record incremental or head-only capture as a bounded negative where those seams are absent.

## Correct state vocabulary

Current EGW exposes two different summaries that must not be conflated:

- **Version vector:** `@text.Version` stores the maximum sequence for every replica. `Version::from_ops` scans all operations and records per-replica maxima.
- **Exact raw frontier:** `SyncSession::export_all` obtains `get_frontier_raw()` and serializes those raw heads into `SyncMessage.heads`.

For a causal chain `A1 → B1` (notation names each writer and its shown sequence), the exact frontier is `[B1]`, while the version vector contains `{A:1, B:1}`. The version vector is useful membership metadata; it is not an exact head set or snapshot identity.

Sources at EGW commit [`3640bfa`](https://github.com/dowdiness/event-graph-walker/tree/3640bfa314ca29c14146ceb8fe1ab49223578b70):

- [`Version` and `Version::from_ops`](https://github.com/dowdiness/event-graph-walker/blob/3640bfa314ca29c14146ceb8fe1ab49223578b70/text/types.mbt#L66-L118)
- [`Version::to_json_string`](https://github.com/dowdiness/event-graph-walker/blob/3640bfa314ca29c14146ceb8fe1ab49223578b70/text/sync.mbt#L480-L501)
- [`current_heads` and `SyncSession::export_all`](https://github.com/dowdiness/event-graph-walker/blob/3640bfa314ca29c14146ceb8fe1ab49223578b70/text/sync.mbt#L808-L835)

## What a digest can and cannot prove

A digest can prove that bytes match a previously trusted commitment, under its collision-resistance assumption. It cannot prove that plain text was computed correctly from event history. A producer can consistently hash an incorrect text/history pair.

Therefore R0 still needs both:

- a trusted authority capture boundary that emits text, exact heads, and graph commitment from one settled transition; and
- an independent full-history differential oracle that catches authority/capture implementation bugs.

Signing or MACing the same tuple authenticates the producer but does not add semantic replay proof. A zero-knowledge transition proof could do that in principle, but no reviewed implementation or measured need justifies that complexity in this test-only gate.

## Primary-source precedents

### Eg-walker

The paper keeps an event graph durable, plain document text metadata-free, and internal CRDT state temporary. Cached final text is allowed, but the paper does not prescribe a cryptographic receipt or require persisted merge state.

Sources:

- [Eg-walker paper §3](https://arxiv.org/html/2409.14252v1#S3)
- [Eg-walker paper §3.5–3.6](https://arxiv.org/html/2409.14252v1#S3.SS5)

A sidecar integrity index over the durable graph is compatible with this model because it is not per-character merge state and can be rebuilt from canonical history.

### Automerge

Automerge makes each change content-addressed with SHA-256, records dependency change hashes, and exposes current heads as sorted `ChangeHash` values. Its incremental save emits only changes after the previous saved heads. Document loading validates chunk checksums and independently derives/compares heads from reconstructed changes.

Sources at Automerge commit [`47908d6`](https://github.com/automerge/automerge/tree/47908d6c04a0ce3fea0fa1d6b7f5ce6ba3e5792e):

- [chunk SHA-256 and checksum](https://github.com/automerge/automerge/blob/47908d6c04a0ce3fea0fa1d6b7f5ce6ba3e5792e/rust/automerge/src/storage/chunk.rs#L180-L311)
- [change dependency hashes and hash accessor](https://github.com/automerge/automerge/blob/47908d6c04a0ce3fea0fa1d6b7f5ce6ba3e5792e/rust/automerge/src/change.rs#L73-L89)
- [content-hash heads](https://github.com/automerge/automerge/blob/47908d6c04a0ce3fea0fa1d6b7f5ce6ba3e5792e/rust/automerge/src/automerge.rs#L1401-L1408)
- [incremental save cursor](https://github.com/automerge/automerge/blob/47908d6c04a0ce3fea0fa1d6b7f5ce6ba3e5792e/rust/automerge/src/autocommit.rs#L546-L575)
- [independent derived-head verification](https://github.com/automerge/automerge/blob/47908d6c04a0ce3fea0fa1d6b7f5ce6ba3e5792e/rust/automerge/src/storage/document.rs#L293-L340)

Canopy cannot adopt Automerge's change hashes as operation identities without a wire/history migration. R0 can, however, add a discardable hash overlay whose head digests provide the same integrity property without changing canonical identities.

### Git

Git separates immutable content-addressed objects from mutable refs. A commit points to a content-addressed tree and parent commits; an atomic ref update moves the active name only after verifying the expected old object ID.

Sources at Git commit [`dea0ea3`](https://github.com/git/git/tree/dea0ea3582e6980ddbc1173cc8e3e9f9db91cde0):

- [Git object model](https://github.com/git/git/blob/dea0ea3582e6980ddbc1173cc8e3e9f9db91cde0/Documentation/user-manual.adoc#L2944-L2996)
- [`update-ref` compare-and-swap and transaction](https://github.com/git/git/blob/dea0ea3582e6980ddbc1173cc8e3e9f9db91cde0/Documentation/git-update-ref.adoc#L17-L34)
- [`update-ref` prepare/commit semantics](https://github.com/git/git/blob/dea0ea3582e6980ddbc1173cc8e3e9f9db91cde0/Documentation/git-update-ref.adoc#L139-L162)

The useful lesson is the role split: content identity belongs in the immutable receipt; store epoch/sequence belongs in the publication ref, not in cross-run content equality.

### Loro

Loro's exported snapshot/update envelope uses a checksum and rejects corruption before import. Its snapshot includes oplog and materialized state and import validates/rolls back on malformed state. This is valuable integrity precedent but not proof that an independently cached plain-text branch matches history without decoding the snapshot.

Sources at Loro commit [`4d3d3f1`](https://github.com/loro-dev/loro/tree/4d3d3f1de107aebcd0b824e53e05d6bb5c6a5974):

- [envelope checksum validation](https://github.com/loro-dev/loro/blob/4d3d3f1de107aebcd0b824e53e05d6bb5c6a5974/crates/loro-internal/src/encoding.rs#L294-L369)
- [encoding and checksum production](https://github.com/loro-dev/loro/blob/4d3d3f1de107aebcd0b824e53e05d6bb5c6a5974/crates/loro-internal/src/encoding.rs#L444-L470)
- [corrupt snapshot import atomicity tests](https://github.com/loro-dev/loro/blob/4d3d3f1de107aebcd0b824e53e05d6bb5c6a5974/crates/loro-internal/src/tests/import_atomicity.rs#L614-L660)

## Alternatives

| Alternative | Capture/update cost | Restore validation | Main problem | Decision |
|---|---:|---:|---|---|
| Full history replay | O(H) | O(H) semantic proof | Defeats cold-open goal | Oracle/fallback only |
| Flat full-history SHA-256 | O(H) bytes and allocation | O(1) metadata + O(T) text hash | No semantic proof; repeats full export | Baseline only |
| Text hash + version vector | O(R + T) | O(R + T) | Version is not exact frontier; no history-content binding | Reject |
| Trusted opaque generation certificate | O(T) | O(T) | Correct only under trusted atomic producer; poor corruption localization and cross-run equality | Minimal negative/control |
| Atomic co-storage without hashes | O(T) | O(1) structure | Provider atomicity does not detect logical corruption or mixed copied records | Reject as R0 positive |
| Append hash chain | O(new events) | O(1) head | Admission-order-dependent and awkward for concurrent DAGs | Reject |
| MMR over admission order | O(log H) append | O(log H) proofs | Commits storage order, not canonical causal graph; replicas may use different topological orders | Reject for graph identity |
| Signed/MAC receipt | Adds signing cost | O(T) plus verify | Authenticates the same assertion; no semantic proof in trusted-local threat model | Reject |
| Serialized Fugue/IndexedState | Potentially O(H) state | Fast load | Persists merge metadata contrary to paper target | Legacy control only |
| Merkle-DAG event overlay + snapshot commit | Rebuild O(H); incremental O(Σ d log d) when committed-event evidence exists; capture O(F log F + T) | O(F log F + T), no payload replay | Adds digest/index metadata per event; current remote/pending seam may be negative; still needs oracle | **Recommend** |

`H` is history size, `R` replica count, `F` exact frontier size, and `T` text bytes.

## Recommended test-only commitment

### Event digest overlay

For each canonical event `e`, compute:

```text
event_digest(e) = SHA-256(
  domain("loomark-r0-event:v1")
  || canonical_event_identity_and_payload(e)
  || sorted(
       explicit_parent_identity_and_digest
       ∪ implicit_same-writer_predecessor_identity_and_digest
     )
)
```

The test codec reuses the shape of EGW's canonical sync encoding: unsigned varints for nonnegative integers and lengths, length-prefixed UTF-8 strings, one-byte variant/optional tags, and stable raw identities. It must freeze exact tags for insert/delete/undelete, payload, left/right origin or dedicated target, and any paper TextEvent positional field before implementation. Dependency count is encoded before dependency records.

Requirements:

- Canonical event bytes include identity, kind, payload, positional/target fields, and every field that changes admission semantics.
- The implicit predecessor `(agent, sequence - 1)` is included even when not repeated in explicit parents. Sequence `0` has no implicit predecessor; the encoded dependency count makes that case total and unambiguous.
- Missing dependency digest means the event remains pending and no exact capture can be issued.
- Parent dependencies are sorted and deduplicated by stable `(agent UTF-8 lexical order, sequence numeric order)` identity before hashing. An EGW-local implementation should iterate with `Op::parents_iter()` rather than allocate `Op::parents()` merely for hashing.
- Sorting costs O(d log d) for an event with `d` unique dependencies unless a canonical sorted representation is retained.
- The overlay is derived, discardable sidecar metadata. Canonical operation identities and wire bytes do not change.
- SHA-256 may be supplied by the test executable's explicit `moonbitlang/x/crypto` dependency or by Nushell over emitted canonical event records; production EGW packages gain no implicit crypto dependency.

### Graph commitment

```text
graph_root = SHA-256(
  domain("loomark-r0-graph:v1")
  || head_count
  || sorted(exact_raw_head_identity_and_event_digest)
)
```

The exact raw head identities come from the authority event graph, not `@text.Version`. Head records use the same stable identity ordering. The empty root is exactly SHA-256 of the graph domain followed by encoded head count `0`; there is no second ad-hoc empty constant.

Because each event digest includes dependency digests, the root transitively commits to all history reachable from the exact heads. It is independent of valid topological admission order and can converge across replicas holding the same canonical graph.

### Immutable snapshot commit

```text
R0SnapshotCommitV1 {
  document_id_sha256
  graph_root
  exact_raw_heads_sorted
  exact_raw_heads_sha256
  document_text_byte_length
  document_text_sha256
  snapshot_commit_id = SHA-256(canonical preceding fields)
}
```

`document_id_sha256` is SHA-256 over the exact UTF-8 `LoomarkDocumentId::value()` bytes without normalization. `document_text_byte_length` and `document_text_sha256` use the exact UTF-8 document-text bytes without Unicode or line-ending normalization. `exact_raw_heads_sorted` is encoded as a count followed by raw identities sorted by `(agent UTF-8 lexical order, sequence numeric order)`; count `0` is the unique empty encoding. Snapshot fields use the same domain-separated, length-prefixed/uvarint test codec rather than JSON object order.

The content commit contains no store epoch, mutable generation counter, active marker, writer identity, or destination-local LV. Equivalent graph/text captures produce the same commit ID across runs.

### Separate publication ref

```text
R0PublicationRefV1 {
  fixture_epoch
  fixture_sequence
  previous_snapshot_commit_id?
  active_snapshot_commit_id
}
```

These are test-fixture provenance fields, not a production storage schema. Nushell owns this mutable test ref and advances it last with compare-and-swap behavior after writing and reading back the immutable snapshot commit and cold sidecar metadata. Publication provenance is checked for staleness but is never part of content equality.

## Capture and validation lifecycle

1. The producer builds the event-digest overlay from canonical history once, or maintains it from authority-owned committed-event evidence when that evidence is available. Current EGW's Text façade exposes counts but not the complete identity set committed by remote/pending/partial admission, and exposes exact raw heads only through full `export_all()`. A fixture producer that already owns the canonical input stream may compute test heads/digests, but that does not prove a production capture seam. Incremental and head-only capabilities must not duplicate admission logic and record bounded negatives unless accepted authority receipts supply them.
2. At capture, pending must be zero; exact raw heads, overlay root, and plain document text must describe one settled authority state.
3. The EGW producer emits owned canonical event/head/text records and exits. Before any publication-ref fields exist, Nushell independently derives event digests, graph root, component hashes, and `snapshot_commit_id`, writes immutable commit/sidecar fixtures, reads them back, then advances the test publication ref last.
4. A separate Markdown/JS harness consumer re-hashes the immutable snapshot framing, document text, and sorted heads through existing test/black-box surfaces. It does not independently recompute `graph_root` from cold event payloads on the fast path.
5. The candidate fast path may report receipt validation and read-only hash-valid text. Gate-level `editable_ready` acceptance is granted only after the independent oracle case for the same `run_id`/`case_id` has succeeded; this ordering is test evidence and does not introduce a public read-only Markdown API.
6. The full-history oracle independently rebuilds the event-digest overlay, replays canonical history, and compares graph root, text, raw heads, normalized first local event, and later trace behavior. Mismatch invalidates the candidate even when all fast-path hashes are internally consistent.
7. Non-head event payload/parent corruption is detected by oracle rebuild or later authenticated cold reads, not by the O(F + T) fast-path check. The fast path detects altered text, sorted heads, snapshot framing, commit ID, and publication-ref mismatch.

## Performance and evidence requirements

- Report one-time overlay rebuild and full-export/head-discovery cost for an authority that lacks the index or a head-only receipt.
- Report steady-state digest maintenance per new event and serialized side-index bytes only for paths where authority-owned committed-event identities are available; otherwise record the exact missing receipt capability as negative.
- Report capture time separately from restore and first edit.
- Restore/first edit must not compute `export_all`, `to_canonical_bytes` over full history, or walk all event digests.
- Strict-forward tests require zero operation-payload cold reads; metadata root/head lookup is counted separately.
- Corruption tests alter event payload, parent digest, implicit predecessor, head set, graph root, text, snapshot commit, publication ref, and mixed fixture sequences. Each artifact states whether the fast receipt check, oracle rebuild, or authenticated cold read detected it.
- A receipt whose overlay cannot be constructed through the test-only producer without production interface changes records a bounded candidate negative.

## Impact on the map

The capture receipt decision should be reopened and replaced. The cold event-graph capability ticket should decide where event digests/head metadata reside and how their reads are counted, but it should not replace the receipt's content/provenance split.
