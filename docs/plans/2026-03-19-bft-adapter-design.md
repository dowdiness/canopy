# BFT Adapter — Byzantine Fault Tolerance for CRDT Operations

**Date:** March 19, 2026
**Status:** Draft (design only — implement after basic sync is working)
**Scope:** `editor/` (parent crdt repo)
**Builds on:** [Ephemeral Store v2](2026-03-19-ephemeral-store-v2-design.md) sync protocol
**References:**
- [Making CRDTs Byzantine Fault Tolerant (Kleppmann, PaPoC 2022)](https://dl.acm.org/doi/10.1145/3517209.3524042)
- [mizchi/converge BFT implementation](https://github.com/mizchi/converge) — adapter pattern in MoonBit

## Goal

Add a Byzantine fault tolerance layer that protects CRDT document operations against tampering, impersonation, and equivocation — without modifying the eg-walker CRDT or the existing sync protocol.

## Priority & Prerequisites

**This design is intentionally deferred.** Prerequisites before implementation:

1. Ephemeral Store v2 sync protocol working (transport, relay, message demuxing)
2. Multi-peer editing functional end-to-end
3. Relay server deployed and stable

The v2 wire format includes a `flags` byte that reserves space for BFT fields, so BFT can be enabled without a protocol version bump.

4. **eg-walker public API prerequisite:** The BFT adapter needs access to `OpRun` and `RawVersion` from eg-walker, but these types live in `internal/core/` (not accessible from `editor/`), and `SyncMessage.runs`/`.heads` are `priv` fields. Before implementation, eg-walker's `text/` package must expose: (a) getter methods on `SyncMessage` for `runs()` and `heads()`, and (b) re-export `OpRun` and `RawVersion` types. This is a public API addition, not an internal change.

## Threat Model

**Byzantine peers may:**
- Send operations with tampered content (modify text, change positions)
- Equivocate — send conflicting operations with the same `(agent, seq)` to different peers
- Impersonate another peer (forge the agent ID)
- Replay old operations
- Withhold operations (refuse to forward)

**Honest peers are assumed to:**
- Correctly execute the protocol
- Have access to the public keys of all peers in the room
- Have reliable local storage (not corrupted)

**Out of scope:**
- Denial of service (flooding with valid operations)
- Sybil attacks (creating many fake identities) — requires external identity management
- Relay server compromise (relay can drop messages but not forge — TLS assumed)
- Ephemeral state (cursors, presence) — low-value, short-lived, not worth protecting

## Design

### Architecture: Adapter Pattern

The BFT adapter sits between the sync transport and CrdtDoc. It is a pre-filter — operations pass through BFT validation before reaching the CRDT. The CRDT is completely unaware of BFT.

```
Outbound:
  CrdtDoc.insert/delete
    → BFTAdapter.sign(op)           — hash + sign
    → transport.send(signed_bytes)

Inbound:
  transport.on_receive(bytes)
    → BFTAdapter.deliver(signed_event)  — 3-step validation
    → CrdtDoc.apply_remote(op)          — only if accepted
```

**Why 4 steps, not 5:** Converge's BFT adapter has 5 steps including causal delivery buffering. eg-walker's `OpLog.apply_remote_ops()` already handles causal delivery (buffers ops waiting for parents via the `pending` array). The BFT adapter does NOT duplicate this. It only adds:

1. Hash integrity check
2. Signature verification
3. Equivocation detection
4. Dep digest verification (all referenced predecessors are accepted)

Causal ordering is eg-walker's responsibility.

### Crypto Traits (Capability Pattern)

Three traits, each with a single capability. Multiple implementations per trait.

```moonbit
///| Cryptographic hash function
pub(open) trait Hasher {
  hash(Self, Bytes) -> Digest
}

///| Signs a digest with the local peer's private key
pub(open) trait Signer {
  sign(Self, Digest) -> Signature
  public_key(Self) -> PublicKey
}

///| Verifies a signature against a public key
pub(open) trait Verifier {
  verify(Self, PublicKey, Digest, Signature) -> Bool
}
```

**Implementations:**

| Trait | Mock (testing) | WebCrypto (browser) | Native (server) |
|-------|---------------|---------------------|-----------------|
| Hasher | FNV-1a 32-bit | SHA-256 via SubtleCrypto FFI | SHA-256 native |
| Signer | HMAC("secret_" + peer) | Ed25519 via SubtleCrypto FFI | Ed25519 native |
| Verifier | Recompute mock HMAC | Ed25519 verify via SubtleCrypto | Ed25519 verify |

`pub(open)` allows downstream packages to provide production crypto without modifying the BFT package.

### Canonical Serialization

```moonbit
///| Deterministic serialization for hashing — any event type can be hashed
pub(open) trait ToCanonicalBytes {
  to_canonical_bytes(Self) -> Bytes
}
```

eg-walker's `OpRun` implements this. The serialization must be deterministic:
- Fields in fixed order
- Sorted maps/arrays where order is not semantic
- No floating-point ambiguity (use canonical byte representation)
- Dependency hashes included in the canonical form

Format: **binary canonical form** (not text-based, to avoid delimiter escaping issues):

```
[agent_len: uvarint][agent: utf8_bytes]
[start_seq: uvarint]
[start_lv: uvarint]
[count: uvarint]
[op_content_tag: u8][op_content_payload: ...]
[origin_left_present: u8][origin_left: agent_len+agent+seq if present]
[origin_right_present: u8][origin_right: agent_len+agent+seq if present]
[heads_count: uvarint][sorted_heads: (agent_len+agent+seq)*]
[dep_count: uvarint][sorted_dep_digests: 32_bytes*]
```

Fields are in fixed order. `origin_left`/`origin_right` are included (positioning is part of semantic meaning — without this, a Byzantine peer could insert text at a different position than claimed). Heads and dep_digests are sorted for determinism. `None` values use `present = 0x00`.

### Newtype Wrappers (Pattern 6)

```moonbit
pub(all) struct Digest(Bytes)       derive(Eq, Compare, Hash, Show)
pub(all) struct Signature(Bytes)    derive(Eq, Show)
pub(all) struct PublicKey(Bytes)    derive(Eq, Hash, Show)
```

Newtypes prevent accidentally mixing digests, signatures, and public keys. The inner `Bytes` holds the raw binary value (32 bytes for SHA-256 digest, 64 bytes for Ed25519 signature, 32 bytes for Ed25519 public key). Use `to_hex()` methods for display/serialization. Raw `Bytes` halves memory and comparison cost vs hex-encoded strings.

### SignedEvent

```moonbit
pub(all) struct SignedEvent {
  op_runs : Array[OpRun]          // the CRDT operations (eg-walker OpRun)
  heads : Array[RawVersion]       // frontier at time of creation
  digest : Digest                 // hash(canonical_bytes(op_runs + heads + dep_digests))
  signature : Signature           // sign(digest)
  author_key : PublicKey          // signer's public key
  dep_digests : Array[Digest]     // hashes of causally preceding SignedEvents
}
```

`dep_digests` parallels eg-walker's causal deps but uses content-addressed hashes instead of LV indices. This creates a hash chain that makes tampering with history detectable.

### BFTAdapter

```moonbit
pub struct BFTAdapter {
  hasher : &Hasher
  verifier : &Verifier
  accepted_digests : @hashset.HashSet[Digest]  // set of accepted digests
  event_digests : Map[String, Digest]          // "agent:seq" → first-seen digest
  alerts : Array[BFTAlert]                     // accumulated fault reports
}
```

**Note:** No `pending_buffer`. Causal delivery is eg-walker's job. The `Signer` is not stored — only needed for outbound signing, passed as parameter to `sign()`.

### Validation Pipeline (4 Steps)

```moonbit
pub enum DeliveryResult {
  Accepted(Array[OpRun], Array[RawVersion])   // ops + heads, ready for eg-walker
  Rejected(BFTAlert)
}

pub enum BFTAlertKind {
  HashMismatch
  InvalidSignature
  Equivocation
  MissingDepDigest
}

pub(all) struct BFTAlert {
  kind : BFTAlertKind
  peer : String
  digest : Digest
  detail : String
}
```

**`deliver(signed : SignedEvent) -> DeliveryResult`:**

**Step 1 — Hash integrity:**
```
canonical = canonical_bytes(signed.op_runs, signed.heads, signed.dep_digests)
expected = hasher.hash(canonical)
if expected != signed.digest → Rejected(HashMismatch)
```
Catches: tampered operations, corrupted messages in transit.

**Step 2 — Signature verification:**
```
if !verifier.verify(signed.author_key, signed.digest, signed.signature) → Rejected(InvalidSignature)
```
Catches: forged operations, impersonation.

**Step 3 — Equivocation detection:**
```
for each op in signed.op_runs:
  for seq in op.start_seq .. (op.start_seq + op.count):
    eq_key = op.agent + ":" + seq.to_string()
    match event_digests.get(eq_key):
      Some(existing) if existing != signed.digest → Rejected(Equivocation)
      Some(_) → skip (idempotent, already accepted)
      None → record event_digests[eq_key] = signed.digest
```
Catches: peer sending different operations with the same identity to different peers. All sequence numbers in the run `[start_seq, start_seq + count)` are indexed, preventing equivocation on subsequences within a batch.

**Step 4 — Dep digest verification:**
```
for each dep in signed.dep_digests:
  if !accepted_digests.contains(dep) → Rejected(MissingDepDigest)
```
Catches: Byzantine peer referencing nonexistent predecessors to create a fabricated causal history. Note: the first event by a peer has empty `dep_digests`, which passes trivially. For late-joining peers, see "Dep digest bootstrap" in Open Questions.

**On acceptance:**
- Store `signed.digest` in `accepted_digests`
- Store per-op equivocation entries
- Return `Accepted(signed.op_runs, signed.heads)` for eg-walker to process

### Signing Outbound Operations

```moonbit
pub fn sign(
  self : BFTAdapter,
  signer : &Signer,
  op_runs : Array[OpRun],
  heads : Array[RawVersion],
  dep_digests : Array[Digest],
) -> SignedEvent
```

1. Compute canonical bytes from op_runs + heads + dep_digests
2. Hash to get digest
3. Sign digest
4. Return `SignedEvent { op_runs, heads, digest, signature, author_key: signer.public_key(), dep_digests }`

### Wire Format Integration

The v2 sync protocol wire format (from ephemeral store v2 design) is extended:

```
WebSocket message:
  [version: u8][message_type: u8][flags: u8][payload]

flags (bit field):
  bit 0 = has_bft          (all BFT fields follow payload)
  bits 1-7 = reserved for future use

Without BFT (flags = 0x00):
  [0x01][0x01][0x00][crdt_ops_payload]

With BFT (flags = 0x01):
  [0x01][0x01][0x01][crdt_ops_payload][digest:32][signature:64][author_key:32][dep_count:uvarint][dep_digests:32*n]
```

**Backward compatible:** Peers with `flags = 0x00` send unsigned operations. The BFT adapter can be configured to accept unsigned ops (permissive mode) or reject them (strict mode).

### Key Management

**For the near-term (trusted relay):**
- Relay server assigns session keys on WebSocket connect
- Public keys distributed via room control messages (`PeerJoined` includes public key)
- No PKI or certificate authority needed

**For the future (untrusted peers):**
- Self-signed keypairs generated per device
- Public key = peer identity (no separate username)
- Trust-on-first-use (TOFU) model — first-seen public key for an agent ID is trusted
- Equivocation detection catches identity conflicts

### Relationship to eg-walker

**eg-walker is completely unaware of BFT.** The adapter pattern means:

| Responsibility | Owner |
|---------------|-------|
| Hash integrity | BFT adapter |
| Signature verification | BFT adapter |
| Equivocation detection | BFT adapter |
| Causal delivery / buffering | eg-walker OpLog (existing) |
| FugueMax merge / conflict resolution | eg-walker (existing) |
| Topological sort | eg-walker CausalGraph (existing) |
| Operation storage | eg-walker OpLog (existing) |

No internal eg-walker logic is modified. The only change is adding public accessors to `text/` package: `SyncMessage::runs()`, `SyncMessage::heads()`, and re-exporting `OpRun`/`RawVersion` types (see Prerequisites). The BFT adapter receives `SignedEvent`, validates it, extracts `op_runs` + `heads`, and passes them to `TextState.sync().apply()`.

### What About Shared Types?

The analysis of eg-walker's internals showed:

- **CausalGraph extraction is unnecessary.** BFT doesn't need a DAG — it uses a flat `accepted_digests` set and an equivocation index. eg-walker handles all graph operations.
- **RawVersion could be shared** if the sync protocol needs it. But for now, the BFT adapter only reads `OpRun.agent` and `OpRun.start_seq` — it doesn't need to import eg-walker's internal types.
- **VersionVector is useful for sync** but not for BFT.

Decision: No type extraction for BFT. The adapter depends on eg-walker's public API (`OpRun`, `RawVersion`, `TextState.sync()`) only. These types must be re-exported from `text/` package (see Prerequisites).

## What Changes

**New files:**
- `editor/bft_types.mbt` — `Digest`, `Signature`, `PublicKey`, `SignedEvent`, `BFTAlert`, `BFTAlertKind`, `DeliveryResult`
- `editor/bft_crypto.mbt` — `Hasher`, `Signer`, `Verifier` traits + `MockHasher`, `MockSigner`, `MockVerifier`
- `editor/bft_adapter.mbt` — `BFTAdapter` struct with `sign()`, `deliver()` (4-step pipeline)
- `editor/bft_serialize.mbt` — `ToCanonicalBytes` trait + impl for `OpRun`
- `editor/bft_adapter_test.mbt` — tests (see below)

**Modified files:**
- `editor/sync_protocol.mbt` — add `flags` byte to wire format, BFT field encoding/decoding

**Unchanged:**
- `event-graph-walker/` — entire submodule untouched
- `editor/ephemeral.mbt` — ephemeral state unprotected (by design)
- `editor/ephemeral_hub.mbt` — no BFT for ephemeral

## Testing Strategy

**Unit tests (MockHasher + MockSigner + MockVerifier):**

1. **Happy path** — sign and deliver a single event, assert `Accepted`
2. **Hash tamper** — sign event, modify op content, keep original digest/signature, assert `Rejected(HashMismatch)`
3. **Invalid signature** — sign as peer A, replace author_key with peer B's key, assert `Rejected(InvalidSignature)`
4. **Equivocation** — deliver two different events with same `(agent, seq)`, assert second is `Rejected(Equivocation)`
5. **Idempotent delivery** — deliver same signed event twice, assert both `Accepted` (same digest)
6. **Multiple ops in one SignedEvent** — sign a batch of OpRuns, deliver, assert all accepted
7. **Dep digest chain** — sign event with dep_digests referencing prior event, verify hash includes deps
8. **Permissive mode** — deliver unsigned message (flags=0x00), assert accepted when adapter is permissive
9. **Strict mode** — deliver unsigned message, assert rejected when adapter is strict
10. **Missing dep digest** — sign event with dep_digests referencing unknown digest, assert `Rejected(MissingDepDigest)`
11. **OpRun batch equivocation** — deliver OpRun with count=3 covering seqs 5-7, then deliver conflicting op at seq 6, assert `Rejected(Equivocation)`

**Integration tests (with InMemoryTransport from v2):**

12. **Two-peer signed sync** — Peer A signs and sends ops, peer B validates and applies. Verify documents converge.
13. **Tampered relay** — Inject a modified message between peers. Verify BFT adapter rejects it.
14. **Alert accumulation** — Multiple faults from same peer. Verify alerts array records all incidents.
15. **Mixed BFT/non-BFT peers** — Peer A sends signed (flags=0x01), peer B sends unsigned (flags=0x00). In permissive mode, both accepted. In strict mode, B rejected.

**Benchmarks:**

13. **Sign throughput** — sign 1000 events, measure time
14. **Deliver throughput** — deliver 1000 valid signed events (linear chain), measure time
15. **Deliver no-deps** — deliver 1000 independent signed events, measure time

## Performance Considerations

**Per-operation overhead (SHA-256 + Ed25519):**
- Hash: ~1μs per operation (SHA-256 on small payload)
- Sign: ~50μs per operation (Ed25519)
- Verify: ~100μs per operation (Ed25519)

**Mitigation:**
- Batch signing: sign a batch of OpRuns as one `SignedEvent` rather than per-op
- eg-walker already batches ops into `OpRun` (RLE compressed), so typical sign/verify is per-batch, not per-character
- Ephemeral state is excluded (no crypto overhead on cursor movements)
- BFT can be disabled entirely (flags=0x00) for trusted environments

**Memory overhead:**
- `accepted_digests`: O(n) where n = total operations received
- `event_digests`: O(n) for equivocation index
- Both can be bounded by pruning entries older than the last common frontier (future optimization)

## Implementation Order

0. **eg-walker API additions** — add `SyncMessage::runs()`, `SyncMessage::heads()` getters and re-export `OpRun`/`RawVersion` from `text/` package
1. **Newtype wrappers + crypto traits** — `Digest(Bytes)`, `Signature(Bytes)`, `PublicKey(Bytes)`, `Hasher`, `Signer`, `Verifier`
2. **Mock implementations** — `MockHasher` (FNV-1a), `MockSigner`, `MockVerifier`
3. **Canonical serialization** — `ToCanonicalBytes` binary format for `OpRun`
4. **BFTAdapter core** — `sign()` + `deliver()` with 4-step pipeline
5. **Unit tests** — all 11 scenarios with mock crypto
6. **Wire format extension** — add `flags` byte to v2 sync protocol
7. **Integration tests** — with InMemoryTransport
8. **WebCrypto implementations** — SHA-256 + Ed25519 via JS FFI (deferred to web integration phase)

## What This Does NOT Change

- The eg-walker CRDT internals (public API additions only: getter methods + type re-exports in `text/`)
- The incremental parser / loom framework
- Ephemeral state handling (cursors, presence, drag, edit mode)
- The EphemeralHub design
- The PeerCursorView
- FugueMax merge semantics
- Causal delivery (eg-walker's responsibility)

## Open Questions (To Resolve Before Implementation)

1. **OpRun canonical form:** eg-walker's `OpRun` contains `origin_left`/`origin_right` (FugueMax metadata). Should these be included in the canonical hash? Including them means BFT verifies positioning integrity. Excluding them means only content is verified. **Recommendation:** include them — positioning is part of the operation's semantic meaning.

2. **Dep digest bootstrap:** The first operation has no deps. Its `dep_digests` is empty. When a new peer joins and receives historical ops, how does it build the `accepted_digests` set? **Recommendation:** full history replay with verification, or trust-on-first-sync (accept the initial batch without dep verification, verify all subsequent ops).

3. **Pruning strategy:** `accepted_digests` grows unboundedly. When can entries be pruned? **Recommendation:** after all peers have advanced past a frontier, digests below that frontier can be pruned. This requires knowing all peers' frontiers (available from the sync protocol).

4. **Alert response:** When a BFT alert fires, what happens? Options: log and continue, reject the operation, ban the peer, notify the user. **Recommendation:** reject the operation + notify the user. Banning requires consensus among peers (out of scope for v1).
