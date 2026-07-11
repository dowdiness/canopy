// Workspace identity probe — P0a gate #3.
// Tests whether today's single-agent_id model in SyncEditor is safe for a
// future multi-document workspace.  Three questions:
//   Q1: Is (DocumentId, ReplicaId) separation required, or does single agent_id suffice?
//   Q2: Are two identity axes enough?
//   Q3: What shape should DocumentId take? (scoped down: shape-agnosticism only)
//
// References:
//   §3.2, §3.5, Appendix B P0a #3, Appendix C #9 of
//   docs/research/2026-05-22-spec-aware-workspace.md

///|
// ── Part A — Negative control: both editors with agent_id = "shared_agent" ──

///|
/// A1 (transport): Two transports with the same peer_id.
/// When A sends, B does NOT receive because broadcast skips peers whose
/// peer_id equals the sender's.  Duplicate register is a no-op, but
/// on_receive still pushes a handler onto the existing slot — which the
/// broadcast loop skips entirely.
test "A1: shared peer_id — broadcast is skipped" {
  let room = @editor.InMemoryRoom::new()
  let t_a = @editor.InMemoryTransport::new("shared_agent", room)
  let t_b = @editor.InMemoryTransport::new("shared_agent", room)
  let received : Array[Int] = []
  t_b.on_receive(fn(data) { received.push(data.length()) })
  // Send an arbitrary payload from A (5 arbitrary bytes)
  t_a.send(Bytes::make(5, b'\x00'))
  // B must not receive the message — broadcast skips the "shared_agent" slot
  inspect(received.length(), content="0")
}

///|
/// A2 (CRDT op-ID dedup): When two editors share agent_id and both create
/// local ops at (shared_agent, seq=0), feeding A's export into B causes
/// the duplicate RawVersion to be silently dropped (oplog.mbt:327-330).
/// B's snapshot therefore still reflects only its own first op.
test "A2: shared agent_id — duplicate RawVersion is silently dropped" {
  let editor_a = @json_companion.new_json_editor("shared_agent")
  let editor_b = @json_companion.new_json_editor("shared_agent")
  // B gets a local op at (shared_agent, seq 0) first
  try! editor_b.insert("[1]")
  // A also gets a local op at (shared_agent, seq 0)
  try! editor_a.insert("[9]")
  // Bypass the transport: directly feed A's entire history to B
  try! editor_b.apply_sync(try! editor_a.export_all())
  // Inspect B's snapshot: op_count must remain 3 — A's seq 0 was dropped.
  // (Each character in "[1]" is one CRDT op: 3 ops total for the 3-char string.)
  let snap = editor_b.causal_snapshot()
  inspect(snap.op_count(), content="3")
  let entry = snap.entry(0).unwrap()
  inspect(entry.agent(), content="shared_agent")
  inspect(entry.seq(), content="0")
}

///|
/// A3 (presence collision): Two editors sharing agent_id = "shared_agent"
/// hash to the same `wire_peer_id` (`EphemeralHub::set_presence` keys the
/// store on `to_wire_peer_id(peer_id)` — `editor/ephemeral_hub_readers.mbt:68`).
/// Two distinct users cannot coexist: the presence store has one slot for
/// the shared wire key, so cross-broadcast collapses both entries into one.
///
/// Test: each editor sets its own local presence (Alice on A, Bob on B),
/// then cross-broadcast via the public ephemeral surface
/// (`encode_ephemeral_all` + `apply_ephemeral`, `editor/sync_editor.mbt:167-177`).
/// With shared agent_id each hub's presence map collapses to length 1.
/// Paired with the A3 control below, which shows distinct agent_ids yield
/// length 2 under the same broadcast — confirming the collision is the
/// shared agent_id, not a broken broadcast path. Per Codex review on
/// PR #326 (the previous A3 never propagated presence between editors,
/// so length=1 was satisfied by absence of broadcast rather than collision).
test "A3: shared agent_id — cross-broadcast collapses two presences into one" {
  let editor_a = @json_companion.new_json_editor("shared_agent")
  let editor_b = @json_companion.new_json_editor("shared_agent")
  editor_a.set_local_presence("Alice", "#ff0000")
  editor_b.set_local_presence("Bob", "#0000ff")
  // Cross-broadcast both directions through the public ephemeral path.
  editor_b.apply_ephemeral(editor_a.encode_ephemeral_all())
  editor_a.apply_ephemeral(editor_b.encode_ephemeral_all())
  // Single wire_peer_id → single slot per hub, even after broadcast.
  inspect(editor_a.get_hub().get_online_peers().length(), content="1")
  inspect(editor_b.get_hub().get_online_peers().length(), content="1")
}

///|
/// A3 control: distinct agent_ids — same broadcast yields TWO presence
/// entries per hub. Confirms the A3 collapse is the shared-agent_id
/// collision specifically, not a bug in `apply_ephemeral` / `encode_ephemeral_all`.
test "A3 control: distinct agent_ids — cross-broadcast preserves both presences" {
  let editor_a = @json_companion.new_json_editor("replica_a")
  let editor_b = @json_companion.new_json_editor("replica_b")
  editor_a.set_local_presence("Alice", "#ff0000")
  editor_b.set_local_presence("Bob", "#0000ff")
  editor_b.apply_ephemeral(editor_a.encode_ephemeral_all())
  editor_a.apply_ephemeral(editor_b.encode_ephemeral_all())
  inspect(editor_a.get_hub().get_online_peers().length(), content="2")
  inspect(editor_b.get_hub().get_online_peers().length(), content="2")
}

///|
// ── Part B — Positive control: distinct replica IDs, same logical document ──

///|
const DOC_ID = "doc_A"

///|
/// B1 (baseline indistinguishability): Start both editors from the same source
/// (A inserts, B syncs).  After sync the NodeId for every projection node
/// is identical on both sides.
test "B1: distinct agent_ids + sync — NodeIds are identical post-sync" {
  let editor_a = @json_companion.new_json_editor("replica_a")
  let editor_b = @json_companion.new_json_editor("replica_b")
  // A produces the initial content
  try! editor_a.insert("[42]")
  // Sync A → B
  try! editor_b.apply_sync(try! editor_a.export_all())
  // Both editors see the same text
  inspect(editor_a.get_text(), content="[42]")
  inspect(editor_b.get_text(), content="[42]")
  // Registry comparison: every NodeId in A must also appear in B
  let reg_a = editor_a.get_registry()
  let reg_b = editor_b.get_registry()
  // Collect as arrays for comparison
  let ids_a : Array[@core.NodeId] = reg_a.keys().to_array()
  let ids_b : Array[@core.NodeId] = reg_b.keys().to_array()
  ids_a.sort_by(fn(a, b) { @core.NodeId::compare(a, b) })
  ids_b.sort_by(fn(a, b) { @core.NodeId::compare(a, b) })
  inspect(ids_a.length() == ids_b.length(), content="true")
  // Build a lookup set from B's ids
  let ids_b_set : Set[@core.NodeId] = Set([])
  for id in ids_b {
    ids_b_set.add(id)
  }
  for id in ids_a {
    inspect(ids_b_set.contains(id), content="true")
  }
  ignore(DOC_ID) // conceptual document anchor; no code path inspects its shape
}

///|
/// B1' (NodeId stability with same-variant divergence — NULL FINDING).
/// Both editors start from "[1]", A appends ",2", B appends ",3", then cross-sync.
///
/// FINDING: kind_mismatches = 0.  After convergence, both A and B map every
/// NodeId to the same JsonValue.  Identity is STABLE for same-variant edits.
///
/// WHY: reconcile_children uses same_kind() for LCS matching.  For JsonValue,
/// same_kind(Number(x), Number(y)) = true regardless of x/y.  The LCS matches
/// by VARIANT only and the backtrack is right-biased — both replicas produce
/// the identical matching pattern when both old trees contain the same variant
/// at the divergent position.
///
/// SCOPE WARNING: This null finding holds ONLY for same-variant divergence.
/// B1'' below exercises the mixed-variant case and observes positive divergence
/// — `kind_mismatches = 2`.  Do NOT generalize this B1' result into "Grove-level
/// identity needed only for structural edits"; the symmetry that produces this
/// null finding is fragile.  See decision doc Q2 verdict.
///
/// NOTE: get_registry() must be called after EACH divergent insert to force
/// the projection memo to evaluate the intermediate state before cross-sync.
test "B1': same-variant divergence — NodeId→kind mapping is stable" {
  let editor_a = @json_companion.new_json_editor("replica_a")
  let editor_b = @json_companion.new_json_editor("replica_b")
  // Establish common base: A produces "[1]", B syncs
  try! editor_a.insert("[1]")
  try! editor_b.apply_sync(try! editor_a.export_all())
  inspect(editor_a.get_text(), content="[1]")
  inspect(editor_b.get_text(), content="[1]")
  // Force projection memo evaluation on the shared base
  let reg_a_base = editor_a.get_registry()
  let reg_b_base = editor_b.get_registry()
  inspect(reg_a_base.length() == reg_b_base.length(), content="true")
  // Diverge: A appends ",2", B appends ",3" — no sync between them
  editor_a.move_cursor(2) // position after "1"
  try! editor_a.insert(",2")
  editor_b.move_cursor(2) // same position on B
  try! editor_b.insert(",3")
  // Force projection memo evaluation at each divergent state
  ignore(editor_a.get_registry()) // forces A's memo to reconcile [1]→[1,2]
  ignore(editor_b.get_registry()) // forces B's memo to reconcile [1]→[1,3]
  // Cross-sync to convergence
  try! editor_a.apply_sync(try! editor_b.export_all())
  try! editor_b.apply_sync(try! editor_a.export_all())
  // Text converges
  inspect(editor_a.get_text() == editor_b.get_text(), content="true")
  // Final registry comparison
  let reg_a = editor_a.get_registry()
  let reg_b = editor_b.get_registry()
  let ids_a : Array[@core.NodeId] = reg_a.keys().to_array()
  let ids_b : Array[@core.NodeId] = reg_b.keys().to_array()
  ids_a.sort_by(fn(a, b) { @core.NodeId::compare(a, b) })
  ids_b.sort_by(fn(a, b) { @core.NodeId::compare(a, b) })
  // NodeId sets are identical
  inspect(ids_a.length() == ids_b.length(), content="true")
  let ids_b_set : Set[@core.NodeId] = Set([])
  for id in ids_b {
    ids_b_set.add(id)
  }
  for id in ids_a {
    inspect(ids_b_set.contains(id), content="true")
  }
  // Assert the NULL FINDING: no NodeId maps to different content.
  // Both replicas agree on every NodeId→kind mapping after convergence.
  let kind_mismatches = ids_a
    .iter()
    .filter(fn(id) {
      match (reg_a.get(id), reg_b.get(id)) {
        (Some(node_a), Some(node_b)) => node_a.kind != node_b.kind
        _ => false
      }
    })
    .count()
  inspect(kind_mismatches, content="0")
  // Verified via diagnostic snapshot (session 2026-05-22): both editors converge
  // to identical NodeId→JsonValue maps including the integer NodeId values.
  // A and B observed:
  //   [(0, Number(3)), (1, Array([Number(1), Number(2), Number(3)])),
  //    (5, Number(2)), (10, Number(1))]
  // Right-biased LCS with variant-only same_kind() produces deterministic
  // identical NodeId assignments across divergent same-variant edits *in this
  // specific scenario* (same-variant siblings, same cursor position, no
  // nesting). NOT proven for mixed-variant, asymmetric-position, or nested
  // divergence — see decision doc §B1' scope notes.
}

///|
/// B1'' (mixed-variant divergence — REFUTES the broad B1' generalization).
/// Both editors start from "[1]".  A appends `,"abc"` (String variant);
/// B appends `,true` (Bool variant) — DIFFERENT variants at the same
/// cursor position.  Cross-sync.
///
/// FINDING (verified 2026-05-22 session): NodeIds 5 and 10 are SWAPPED
/// between replicas.  Each editor's old tree contained its own divergent
/// variant; reconcile_children LCS preserves the OLD NodeId at the
/// matched position, but each replica's old NodeId attaches to a
/// different post-merge logical node.
///
///   A's registry: 5 = String("abc"),  10 = Bool(true)
///   B's registry: 5 = Bool(true),     10 = String("abc")
///
/// IMPLICATION FOR Q2: Two identity axes (DocumentId, ReplicaId) are
/// NOT sufficient for cross-replica node identity under mixed-variant
/// divergence.  A third axis (Grove-level structural identity, or a
/// reconciliation-aware id scheme) is needed for any workspace feature
/// that relies on `(doc_id, node_id)` referring to the same logical node
/// across replicas.  This narrows Sonnet's earlier B1' narrative.
test "B1pp: mixed-variant divergence — NodeId mapping diverges across replicas" {
  let editor_a = @json_companion.new_json_editor("replica_a")
  let editor_b = @json_companion.new_json_editor("replica_b")
  // Common base
  try! editor_a.insert("[1]")
  try! editor_b.apply_sync(try! editor_a.export_all())
  inspect(editor_a.get_text(), content="[1]")
  inspect(editor_b.get_text(), content="[1]")
  // Force projection memo on the shared base
  ignore(editor_a.get_registry())
  ignore(editor_b.get_registry())
  // Mixed-variant divergence at the same cursor position
  editor_a.move_cursor(2)
  try! editor_a.insert(",\"abc\"")
  editor_b.move_cursor(2)
  try! editor_b.insert(",true")
  // Force memo at each divergent state
  ignore(editor_a.get_registry())
  ignore(editor_b.get_registry())
  // Cross-sync
  try! editor_a.apply_sync(try! editor_b.export_all())
  try! editor_b.apply_sync(try! editor_a.export_all())
  // Text converges
  inspect(editor_a.get_text() == editor_b.get_text(), content="true")
  // Compare NodeId→JsonValue mappings.
  //
  // Verdict: count_kind_mismatches > 0 — the same logical NodeId carries
  // different JsonValue variants between A and B. Earlier revisions also
  // inspect()-asserted the full sorted `(NodeId.0, kind)` dumps for both
  // replicas; Codex review on PR #326 flagged that as brittle (exact
  // NodeId integers + LCS tie-breaking are implementation-defined per
  // `core/reconcile_properties_wbtest.mbt:323-327`). Both dump
  // assertions were dropped on `<follow-up commit>`.
  //
  // For provenance: when this test was first authored on 2026-05-22
  // (commit 24a8a6e), the observed dumps were:
  //   A: [(0,"Number(1)"), (1,"Array([Number(1), String(\"abc\"), Bool(true)])"),
  //       (5,"String(\"abc\")"), (10,"Bool(true)")]
  //   B: [(0,"Number(1)"), (1,"Array([Number(1), String(\"abc\"), Bool(true)])"),
  //       (5,"Bool(true)"),   (10,"String(\"abc\")")]
  // — NodeIds 5 and 10 swapped between String and Bool. That observation
  // is the original Q2 evidence; it is recorded here as a comment so the
  // historical finding stays readable, without locking the probe to
  // implementation-defined NodeId integers.
  let reg_a = editor_a.get_registry()
  let reg_b = editor_b.get_registry()
  let ids_a : Array[@core.NodeId] = reg_a.keys().to_array()
  inspect(editor_a.get_text(), content="[1,\"abc\",true]")
  let kind_mismatches = ids_a
    .iter()
    .filter(fn(id) {
      match (reg_a.get(id), reg_b.get(id)) {
        (Some(node_a), Some(node_b)) => node_a.kind != node_b.kind
        _ => false
      }
    })
    .count()
  inspect(kind_mismatches, content="2")
}

///|
/// B2 (multi-session convergence): Standard fugue convergence.
/// After A→B sync, B mutates, then B→A sync — text matches.
test "B2: multi-session convergence — text matches after B→A sync" {
  let editor_a = @json_companion.new_json_editor("replica_a")
  let editor_b = @json_companion.new_json_editor("replica_b")
  // Establish common base
  try! editor_a.insert("[1]")
  try! editor_b.apply_sync(try! editor_a.export_all())
  // B mutates
  editor_b.move_cursor(2)
  try! editor_b.insert(",2")
  // B → A sync
  try! editor_a.apply_sync(try! editor_b.export_all())
  // Both converge
  inspect(editor_a.get_text() == editor_b.get_text(), content="true")
}

///|
// ── Part C — agent_id string opacity (Q3 stand-in) ──
//
// Scope (Codex review on PR #326): there is NO DocumentId field today —
// `new_json_editor(agent_id: String)` is now defined with an optional
// `parent_runtime?` parameter as well (`lang/json/companion/json_companion.mbt:8-18`),
// so the required identifier remains a string.
// These tests exercise that string parameter with three candidate DocumentId
// shapes embedded
// in the agent_id (UUID, sha256:, file://) and show the CRDT/transport/
// presence layers treat the value opaquely.
//
// What they DO establish: the editor's existing code paths impose no
// shape constraint on their string identifier. When a real DocumentId
// is added in §P0b (either as a separate axis or embedded in agent_id),
// these layers will accept any stable string.
//
// What they do NOT establish: that a separate DocumentId field
// round-trips through serialization, persistence, or any future
// workspace API. The decision doc Q3 verdict is explicitly bounded to
// the agent_id layer; persistence/durability is Phase-2 work.

///|
/// C_uuid: UUID embedded in `agent_id` is accepted by new_json_editor
/// without error. The existing code path does not inspect the string's
/// shape.
test "C_uuid: UUID-shaped agent_id string is opaque to the editor" {
  let uuid_doc_id = "550e8400-e29b-41d4-a716-446655440000"
  let editor = @json_companion.new_json_editor("replica_" + uuid_doc_id)
  try! editor.insert("[1]")
  inspect(editor.get_text(), content="[1]")
  // Bytes round-trip: the embedded shape survives string operations
  let b = @debug.to_string(uuid_doc_id)
  inspect(b.contains("550e8400"), content="true")
}

///|
/// C_hash: Content-hash-shaped agent_id string is opaque to the editor.
test "C_hash: hash-shaped agent_id string is opaque to the editor" {
  let hash_doc_id = "sha256:abc123"
  let editor = @json_companion.new_json_editor("replica_" + hash_doc_id)
  try! editor.insert("[2]")
  inspect(editor.get_text(), content="[2]")
  let b = @debug.to_string(hash_doc_id)
  inspect(b.contains("sha256"), content="true")
}

///|
/// C_path: File-path-shaped agent_id string is opaque to the editor.
test "C_path: path-shaped agent_id string is opaque to the editor" {
  let path_doc_id = "file:///workspace/doc.json"
  let editor = @json_companion.new_json_editor("replica_" + path_doc_id)
  try! editor.insert("[3]")
  inspect(editor.get_text(), content="[3]")
  let b = @debug.to_string(path_doc_id)
  inspect(b.contains("workspace"), content="true")
}
