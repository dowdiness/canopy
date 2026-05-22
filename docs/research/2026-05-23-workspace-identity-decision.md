# Workspace Identity Probe — Decision Record

**Date:** 2026-05-23  
**Branch:** `worktree-research-from-main`  
**Probe package:** `workspace/probe/identity_probe_wbtest.mbt`  
**Research basis:** `docs/research/2026-05-22-spec-aware-workspace.md` §3.2, §3.5, Appendix B P0a #3, Appendix C #8–9

---

## Three Questions

### Q1 — Is (DocumentId, ReplicaId) separation required?

**Answer: YES. Single `agent_id` is unsafe for multi-document workspace.**

Evidence from three orthogonal failure modes when two editors share `agent_id = "shared_agent"`:

| Assertion | Failure mode | Code path |
|-----------|-------------|-----------|
| A1 | Transport broadcast skipped — B never receives A's messages | `InMemoryRoom::broadcast` skips sender's slot by `peer_id` equality |
| A2 | CRDT op dedup — A's seq-0 ops silently dropped when applied to B | `oplog.mbt:327-330` `raw_to_lv` dedup |
| A3 | Presence collision — last writer wins, only 1 slot per `wire_peer_id` | `EphemeralHub` keyed on `wire_peer_id = hash(agent_id)` |

All three failures are structural — they cannot be worked around without adding a separate per-document identity axis. The minimum safe model is `agent_id = doc_id + ":" + replica_id`.

### Q2 — Are two identity axes (DocumentId, ReplicaId) enough?

**Answer: YES for the currently tested scope; structural-edit identity needs a third axis (Grove-level).**

Evidence from Part B assertions:

| Assertion | Finding |
|-----------|---------|
| B1 | After A→B sync from a common base, NodeId sets are identical on both replicas. Two axes suffice for stable identity in the sync case. |
| B1' | After divergent same-variant edits (both replicas insert Number elements) and cross-sync, NodeId→kind mappings are IDENTICAL on both replicas (`kind_mismatches = 0`). |
| B2 | Standard multi-session convergence passes. Two axes are sufficient for the edit→sync→converge cycle. |

**B1' null finding — scope and implication:**  
The identity divergence predicted by Appendix C #8 does NOT occur for same-variant divergence. The `reconcile_children` LCS uses `same_kind()` (variant-only comparison, not value comparison), and the backtrack is right-biased and deterministic. Both replicas produce identical `NodeId → kind` assignments even after divergent numeric-value edits.

The threat in Appendix C #8 is real but narrower than originally scoped: it applies to **structural edits** (edits that change a node's variant — e.g., replacing a `Number` with an `Array`) not to value edits within the same variant. Structural edits are uncommon in typical JSON editing. For the current canopy scope (text-based CRDT + projection reconciliation), two axes are sufficient.

A third axis (Grove-level structural identity) is only required when:
- A user replaces a node's structural type across replicas concurrently
- The workspace needs to track "this JSON node was an Array, then became an Object" as a named identity, not just a new node

This can be addressed as a separate workstream after the workspace concept ships.

### Q3 — What shape should DocumentId take?

**Answer: String; shape is irrelevant to current code paths.**

Evidence from Part C assertions:

| Assertion | Doc ID shape tested | Result |
|-----------|--------------------|-|
| C_uuid | `550e8400-e29b-41d4-a716-446655440000` | Accepted, text roundtrips correctly |
| C_hash | `sha256:abc123` | Accepted |
| C_path | `file:///workspace/doc.json` | Accepted |

The CRDT, transport, and presence layers treat `agent_id` as an opaque string. No current code path inspects the shape of the string. The workspace implementation can choose any stable string scheme — UUID, content hash, or path-derived — and the editor layer will accept it.

**Recommendation:** Use a simple scheme for now (e.g. `"<doc_path>:<replica_uuid>"`) and avoid over-engineering until the workspace concept is stable.

---

## Summary Table

| Question | Verdict | Confidence |
|----------|---------|------------|
| Q1: Separation required? | Yes — three independent failure modes | High (A1/A2/A3 all pass) |
| Q2: Two axes enough? | Yes for current scope; Grove-level id needed only for structural edits | Medium-high (B1' null finding narrows the threat) |
| Q3: DocumentId shape? | Opaque string; any stable scheme works | High (C×3 all pass) |

---

## Assertion Verdicts

| ID | Test name | Result | Key finding |
|----|-----------|--------|-------------|
| A1 | `shared peer_id — broadcast is skipped` | PASS | Self-addressed messages dropped; transport layer requires distinct peer IDs |
| A2 | `shared agent_id — duplicate RawVersion is silently dropped` | PASS | CRDT dedup at oplog level; 3 ops (3-char insert) silently ignored |
| A3 | `shared agent_id — presence is silently overwritten` | PASS | Hash collision in EphemeralHub; only 1 presence slot per agent |
| B1 | `distinct agent_ids + sync — NodeIds are identical post-sync` | PASS | Synced replicas produce identical projection identity |
| B1' | `same-variant divergence — NodeId→kind mapping is stable` | PASS (null finding) | No kind mismatch after divergent number inserts; reconcile is deterministically right-biased |
| B2 | `multi-session convergence — text matches after B→A sync` | PASS | Standard Fugue convergence works with distinct replica IDs |
| C_uuid | `UUID-shaped DocumentId is shape-agnostic` | PASS | UUID string accepted without error |
| C_hash | `content-hash-shaped DocumentId is shape-agnostic` | PASS | Hash string accepted without error |
| C_path | `path-shaped DocumentId is shape-agnostic` | PASS | Path string accepted without error |

---

## Notable Finding: B1' reconcile_children behavior

The LCS in `reconcile_children` (core/reconcile.mbt) uses `same_kind()` which compares variant names only. For `JsonValue::Number(x)` vs `JsonValue::Number(y)`, `same_kind` returns `true` regardless of x/y. Combined with the right-biased backtrack (matching from the end), the algorithm always produces the same NodeId assignment pattern for same-variant siblings regardless of their values or which replica inserted them. This is by design for structural stability, but it means value-level divergence in identity is not observable via `kind`.

This finding has a follow-up implication: the reconcile algorithm does **not** preserve value-identity (NodeId N does not stably refer to "the node whose value was originally X"). It preserves structural-position identity (NodeId N refers to "the node at structural position P after LCS alignment"). This is the correct behavior for a projectional editor, but callers should not rely on NodeIds for value-tracking across divergent edits.
