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

**Answer: NO. Two axes suffice ONLY for same-variant divergence; mixed-variant divergence breaks `(doc_id, node_id)` identity across replicas.**

Evidence from Part B assertions:

| Assertion | Finding |
|-----------|---------|
| B1 | After A→B sync from a common base, NodeId sets are identical on both replicas. Two axes suffice for the no-divergence case. |
| B1' | Divergent SAME-VARIANT edits (both replicas insert `Number` elements) converge to IDENTICAL `NodeId → JsonValue` maps on both replicas (`kind_mismatches = 0`, verified by byte-identical diagnostic snapshot). |
| B1'' | Divergent MIXED-VARIANT edits (A inserts `String`, B inserts `Bool` at the same cursor) **diverge**: `kind_mismatches = 2`. NodeIds 5 and 10 are *swapped* between replicas (A: 5=String, 10=Bool; B: 5=Bool, 10=String). |
| B2 | Standard multi-session convergence passes (text only — does not address NodeId identity). |

**B1' / B1'' juxtaposed.** B1' is a null finding that depends on a structural symmetry: when both replicas' old trees contain children of the SAME variant in matching positions, the right-biased LCS in `reconcile_children` (`core/reconcile.mbt`) preserves NodeIds symmetrically. The moment that symmetry breaks — and any mixed-variant divergence breaks it — each replica's old NodeId stays attached to the position its LOCAL old variant matched, leaving the *same logical post-merge node* with different NodeIds on each replica.

**Implication for Q2.** The workspace's `NodeIdQ { doc_id, node_id }` design assumes `(doc_id, n)` refers to the same logical node across replicas. B1'' refutes this for the realistic mixed-variant case. A third identity axis is required — concretely:

- **Option a (Grove-level structural identity):** mint a content-/position-stable identity per logical node, separate from the per-editor counter. Costly but principled.
- **Option b (reconciliation-aware id scheme):** seed the per-editor counter from a canonical traversal of the post-merge tree, so all replicas mint identical NodeIds regardless of intermediate divergence. Cheaper but fragile under further edits.
- **Option c (don't claim cross-replica identity):** scope `NodeIdQ` to *local* references only; require a separate cross-replica anchor mechanism (e.g. text-position-based) for any cross-document link the workspace exposes to users.

**What B1'' did NOT test (named follow-ups, not blockers for the Q2 verdict above):**
- Asymmetric insertion positions (A inserts at start, B at end of array)
- Nested-array divergence (edits within a sub-array, both replicas mutate the same parent)
- Delete + insert combinations (one replica deletes a node the other replica modifies)

These cases can produce additional failure modes (e.g. divergence of structural NodeIds for the array itself, not just leaf children). Promote to P0a gate #4 alongside the option-a/b/c decision before any production workspace work.

### Q3 — What shape should DocumentId take?

**Answer (scoped): At the editor layer, any stable string is accepted. Persistence shape is Phase-2 work.**

Evidence from Part C assertions:

| Assertion | String embedded in agent_id | Result |
|-----------|------------------------------|--------|
| C_uuid | `550e8400-e29b-41d4-a716-446655440000` | Accepted, text roundtrips correctly |
| C_hash | `sha256:abc123` | Accepted |
| C_path | `file:///workspace/doc.json` | Accepted |

**Scope (Codex review on PR #326):** Part C does NOT exercise a separate DocumentId field — `new_json_editor(agent_id : String)` accepts only an `agent_id`. The tests show the CRDT, transport, and presence layers treat their string identifier opaquely. That establishes one lower bound — when a real DocumentId is added in §P0b (either as a separate axis or embedded in agent_id), these layers will impose no shape constraint. It does NOT establish anything about serialization, persistence, or workspace-API round-trips, which the workspace design hasn't ranged on yet.

**Recommendation:** Use a simple scheme for now (e.g. `"<doc_path>:<replica_uuid>"`) and avoid over-engineering until the workspace concept is stable. Revisit when the persistence shape is chosen in Phase 2.

---

## Summary Table

| Question | Verdict | Confidence |
|----------|---------|------------|
| Q1: Separation required? | Yes — three independent failure modes | High (A1/A2/A3 all pass) |
| Q2: Two axes enough? | **No.** Three failure shapes confirmed: B1''-swap on mixed-variant, C2-swap on nested same-variant (at base-inherited NodeIds), C4-swap on object-member mixed variant, C3-key-asymmetry on delete+modify. Refined recommendation: option (c) scope-reduction is now the principled near-term path; option (a) Grove-level identity remains the principled long-term path. See §"Q2 follow-through" below. | High (B1' null + B1'' positive + gate #4: 4 additional cases) |
| Q3: DocumentId shape? | At the agent_id layer (the only string identifier today): any stable scheme works. Real DocumentId shape, persistence, and workspace-API round-trip deferred to Phase 2. | Medium-bounded (C×3 prove agent_id string opacity in-memory; nothing exercised against a real DocumentId field, which doesn't exist yet) |

---

## Assertion Verdicts

| ID | Test name | Result | Key finding |
|----|-----------|--------|-------------|
| A1 | `shared peer_id — broadcast is skipped` | PASS | Self-addressed messages dropped; transport layer requires distinct peer IDs |
| A2 | `shared agent_id — duplicate RawVersion is silently dropped` | PASS | CRDT dedup at oplog level; 3 ops (3-char insert) silently ignored |
| A3 | `shared agent_id — cross-broadcast collapses two presences into one` | PASS | Hash collision in EphemeralHub; only 1 presence slot per agent. Cross-broadcast via `encode_ephemeral_all`/`apply_ephemeral` between two editors sharing `agent_id` collapses 2 → 1 slots, while a paired control (`A3 control: distinct agent_ids — cross-broadcast preserves both presences`) shows 2 distinct slots survive the same broadcast — the collapse is the shared `agent_id`, not a broken broadcast path. (Revision after PR #326 Codex review; the earlier A3 only called `set_local_presence` on each editor without any cross-broadcast, so a passing length=1 was satisfiable by absence of broadcast rather than by collision.) |
| B1 | `distinct agent_ids + sync — NodeIds are identical post-sync` | PASS | Synced replicas produce identical projection identity |
| B1' | `same-variant divergence — NodeId→kind mapping is stable` | PASS (null finding) | No kind mismatch after divergent number inserts; reconcile is deterministically right-biased |
| B1'' | `mixed-variant divergence — NodeId mapping diverges across replicas` | PASS (positive divergence) | `kind_mismatches = 2`. NodeIds 5 and 10 swap variants between A and B (A: 5=String, 10=Bool; B: 5=Bool, 10=String) |
| B2 | `multi-session convergence — text matches after B→A sync` | PASS | Standard Fugue convergence works with distinct replica IDs |
| C_uuid | `UUID-shaped agent_id string is opaque to the editor` | PASS | UUID string accepted via `new_json_editor(agent_id)`; editor code paths impose no shape constraint. Does NOT exercise a separate DocumentId field (none exists today). |
| C_hash | `hash-shaped agent_id string is opaque to the editor` | PASS | Hash string accepted without error |
| C_path | `path-shaped agent_id string is opaque to the editor` | PASS | Path string accepted without error |

---

## Notable Finding: B1' / B1'' juxtaposition

`reconcile_children` (`core/reconcile.mbt`) uses an LCS over `same_kind()`, which for `JsonValue` compares variant only (`Number(x) ~ Number(y) = true` regardless of values), with a right-biased backtrack.

**B1' (same-variant, null finding).** When BOTH replicas' old trees contain children of the same variant, LCS preserves NodeIds symmetrically across replicas. Diagnostic snapshot showed A and B converge to byte-identical NodeId→JsonValue maps including the integer NodeId values.

**B1'' (mixed-variant, positive divergence).** When each replica's old tree contains a DIFFERENT variant at the divergent position, LCS preserves each replica's old NodeId at the structural position that matches its OWN local variant — leaving the same logical post-merge node with a *different* NodeId on each replica. Concrete observation for `A.insert(",\"abc\"")` + `B.insert(",true")` from base `[1]`, converging to `[1,"abc",true]`:

```text
A's registry: 0 → Number(1), 1 → Array, 5 → String("abc"), 10 → Bool(true)
B's registry: 0 → Number(1), 1 → Array, 5 → Bool(true),    10 → String("abc")
                                          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                          NodeId 5 and 10 swapped
```

**Implication.** NodeIds preserve structural-position identity *post-reconcile within one replica*, NOT cross-replica logical-node identity. A workspace design that exposes `NodeIdQ { doc_id, node_id }` as "the same node across replicas" cannot rest on the current per-editor counter + reconcile pipeline alone — it needs either a Grove-level structural id (mint a content/position-stable id separate from the counter), a deterministic-seed scheme (canonical traversal of the post-merge tree determines counter assignments), or a scope reduction (only intra-replica references are durable; cross-replica anchors use a different mechanism).

---

## Q2 follow-through — P0a gate #4 (2026-05-23)

Gate #4 probed the three open follow-up cases B1'' did not cover, plus an
object-member case added on Codex review. Probe file:
`workspace/probe/gate4_divergence_wbtest.mbt`. All 4 tests pass.

### Verdict table (gate #4)

| ID | Scenario | `kind_mismatches` | `keys_only_in_a` / `keys_only_in_b` | Verdict |
|----|----------|-------------------|--------------------------------------|---------|
| C1 | Asymmetric position, same variant (A appends `,4` / B prepends `0,` to `[1,2,3]`) | **0** | 0 / 0 | **NULL FINDING.** Flat same-variant asymmetric-position divergence preserves NodeId identity. |
| C2 | Nested-array divergence, same variant (A inserts `,9` in inner[0] / B in inner[1] of `[[1],[2]]`) | **2** | 0 / 0 | **POSITIVE DIVERGENCE.** Inner-leaf NodeIds 11 and 19 swap meanings (A: 11=Num(1), 19=Num(2); B: 11=Num(2), 19=Num(1)). Outer Array containers stable. |
| C3 | Delete + insert (A deletes `,2` from `[1,2,3]` / B inserts `,9` after 2) | **0** | 1 / 1 | **REGISTRY-KEY ASYMMETRY.** Converges to `[1,9,3]`. A has NodeId(11)=Num(1); B has NodeId(0)=Num(1). Same logical value, different NodeIds across replicas — distinct failure mode from C2/B1''. |
| C4 | Object-member, mixed variant (A inserts `"x":"foo",` / B inserts `"y":true,` into `{"a":1,"b":2}`) | **2** | 0 / 0 | **POSITIVE DIVERGENCE.** NodeIds 12 and 22 swap variants (A: 12=String, 22=Bool; B: 12=Bool, 22=String). Same B1''-style swap, now inside object members where `same_kind` ignores keys entirely. |

### Refined Q2 verdict

The Q2 third-axis requirement is **confirmed** and is now characterized at higher
resolution:

1. **The breakage surface is broader than B1''.** B1'' showed mixed-variant
   produces a swap (NodeIds 5/10). C2 shows that *even same-variant divergence*
   produces a swap when the edits are *nested* — the swapped NodeIds (11/19)
   are **base-inherited** (created during the common base setup, before any
   divergence). This is a strictly stronger failure mode than B1''.
2. **Object-member identity is as fragile as array identity, possibly more.**
   C4 confirmed Codex's pre-implementation prediction: `same_kind` for `Object`
   ignores keys entirely (`loom/examples/json/src/proj_traits.mbt:14-25`), so
   object members swap by *value variant* across replicas. This is directly
   load-bearing for the §3.2 design — spec anchors are likely to be object
   members (e.g. `{"id": "node-42", "kind": "definition"}`).
3. **Delete + insert is a different failure shape.** C3 produced registry-key
   asymmetry (`keys_only_in_a = keys_only_in_b = 1`) rather than a swap. The
   "same logical value" Num(1) carries NodeId(11) on A and NodeId(0) on B.
   `kind_mismatches = 0` on shared keys, but the shared-key set itself is
   missing entries on each side. A `NodeIdQ`-keyed cache would silently miss
   on lookups across replicas even when both replicas hold the value.
4. **C1 narrows the breakage surface.** Flat same-variant asymmetric-position
   divergence is a **null finding** — identity preserved. So same-variant
   divergence in itself is not the trigger; the combination of *same-variant*
   with *nesting* (C2) is.

### Updated third-axis option recommendations

The three options from §Q2 above remain on the table; gate #4 changes their
relative scope:

- **(a) Grove-level structural identity.** Now the most clearly load-bearing
  path because it would address all four failure shapes simultaneously
  (B1'', C2, C3, C4). Required for any workspace feature that wants
  `(doc_id, node_id)` to refer to the same logical node across replicas
  including object members and through delete-plus-modify history.
- **(b) Deterministic-seed scheme.** Plausible for B1''/C2/C4 (re-seed
  counter from canonical post-merge traversal so both replicas produce the
  same NodeId for the same post-merge position). Does not solve C3
  (registry-key asymmetry across delete histories) on its own.
- **(c) Scope reduction (intra-replica references only).** Cheapest option.
  Cross-document anchors become *content-addressed* references resolved at
  query-time (e.g. `[ref:doc.json#a]` resolved by walking the document) rather
  than `NodeIdQ` lookups. Avoids the third-axis problem entirely at the cost
  of giving up "stable handle to a node" as a workspace primitive.

**Recommendation update (post gate #4):** the case for (c) — scope reduction —
strengthens. C2 shows that even base-inherited NodeIds drift under nested
edits; C3 shows that delete histories produce key-set asymmetry. Any cache or
graph keyed on `NodeIdQ` will produce surprising query results across replicas.
A content-addressed anchor scheme (option c) sidesteps the entire failure
surface and is implementable without a Grove-level rewrite of identity. Option
(a) remains the principled long-term answer; option (c) is the principled
*near-term* answer.

### Notes on the C2 mechanism

The C2 swap is at NodeIds **11 and 19** — these were minted during the common
base setup `[[1],[2]]` (before any divergent edits). On A: NodeId 11 was the
inner-array `[1]`'s child Number(1); NodeId 19 was the inner-array `[2]`'s
child Number(2). After A's local edit + B's local edit + cross-sync, the
positions of those original leaves swap in the post-reconcile registry.

The exact LCS mechanism producing the swap depends on the right-biased
backtrack in `core/reconcile.mbt:62-75` interacting with variant-only
`same_kind` (`loom/examples/json/src/proj_traits.mbt:14-25`) across the
divergent intermediate trees on each replica. The empirical observable
(`kind_mismatches = 2` at base-inherited NodeIds) is the load-bearing
finding; the detailed LCS step-by-step is not.

### Out of scope for gate #4 (not run)

- Concurrent edits at the SAME node (e.g. both replicas modify the same
  value). Unrelated to nesting/divergence; covered by FugueMax's tombstone
  + insert anchoring semantics.
- Structural restructuring (e.g. wrap a node in another container). Higher
  cost to test; the same_kind variant change would dominate the result
  and not add a new failure mode beyond B1''.
- Core-level synthetic unit test (Codex's Q-D suggestion: construct two
  fake `old` trees with shared NodeIds and reconcile against same `new`).
  Treated as nice-to-have; the four scenario probes above demonstrate the
  failure through the real sync+parse+reconcile pipeline, which is more
  convincing.
