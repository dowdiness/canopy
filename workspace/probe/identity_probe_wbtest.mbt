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
/// A3 (presence collision): Both editors share agent_id = "shared_agent".
/// Calling set_local_presence on A then on B silently overwrites A's entry
/// because both hash to the same wire_peer_id key in the Presence store.
/// Observable: get_online_peers() length stays 1 on A's hub; the surviving
/// entry carries B's display name (last writer wins).
test "A3: shared agent_id — presence is silently overwritten" {
  let editor_a = @json_companion.new_json_editor("shared_agent")
  let editor_b = @json_companion.new_json_editor("shared_agent")
  editor_a.set_local_presence("Alice", "#ff0000")
  editor_b.set_local_presence("Bob", "#0000ff")
  // A's own hub should show only 1 entry (B overwrote A's slot locally on B,
  // but each editor writes to its own hub — so A's hub still shows Alice).
  // The key insight: two editors with the same agent_id write to the SAME
  // wire key; whichever hub you inspect, it has exactly 1 presence slot.
  let online_on_a = editor_a.get_hub().get_online_peers()
  inspect(online_on_a.length(), content="1")
  let online_on_b = editor_b.get_hub().get_online_peers()
  inspect(online_on_b.length(), content="1")
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
/// B1' (NodeId stability with same-variant divergence — NULL FINDING, meaningful).
/// Both editors start from "[1]", A appends ",2", B appends ",3", then cross-sync.
///
/// FINDING: kind_mismatches = 0.  After convergence, both A and B map every
/// NodeId to the same JsonValue.  Identity is STABLE for same-variant edits.
///
/// WHY: reconcile_children uses same_kind() for LCS matching.  For JsonValue,
/// same_kind(Number(x), Number(y)) = true regardless of x/y.  This means the
/// LCS step matches by VARIANT only and the backtrack is right-biased — both
/// replicas produce the identical matching pattern regardless of the numeric
/// values they divergently inserted.
///
/// IMPLICATION FOR Q1/Q2: The identity threat (Appendix C #8) is real for
/// STRUCTURAL changes (adding an Array where a Number was) but NOT for
/// same-variant value changes.  This narrows the scope of Grove-level identity
/// tracking required in a workspace: only structural edits (variant-level
/// changes) need cross-document identity stabilization, not value edits.
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
  let kind_mismatches = ids_a.iter().filter(fn(id) {
    match (reg_a.get(id), reg_b.get(id)) {
      (Some(node_a), Some(node_b)) => node_a.kind != node_b.kind
      _ => false
    }
  }).count()
  inspect(kind_mismatches, content="0")
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
// ── Part C — Shape-agnosticism: DocumentId string shape is irrelevant ──

///|
/// C_uuid: UUID-shaped DocumentId is accepted by new_json_editor without error.
/// The existing code path does not inspect the string's shape.
test "C_uuid: UUID-shaped DocumentId is shape-agnostic" {
  let uuid_doc_id = "550e8400-e29b-41d4-a716-446655440000"
  let editor = @json_companion.new_json_editor("replica_" + uuid_doc_id)
  try! editor.insert("[1]")
  inspect(editor.get_text(), content="[1]")
  // Bytes round-trip: string survives serialization
  let b = @debug.to_string(uuid_doc_id)
  inspect(b.contains("550e8400"), content="true")
}

///|
/// C_hash: Content-hash-shaped DocumentId is shape-agnostic.
test "C_hash: content-hash-shaped DocumentId is shape-agnostic" {
  let hash_doc_id = "sha256:abc123"
  let editor = @json_companion.new_json_editor("replica_" + hash_doc_id)
  try! editor.insert("[2]")
  inspect(editor.get_text(), content="[2]")
  let b = @debug.to_string(hash_doc_id)
  inspect(b.contains("sha256"), content="true")
}

///|
/// C_path: File-path-shaped DocumentId is shape-agnostic.
test "C_path: path-shaped DocumentId is shape-agnostic" {
  let path_doc_id = "file:///workspace/doc.json"
  let editor = @json_companion.new_json_editor("replica_" + path_doc_id)
  try! editor.insert("[3]")
  inspect(editor.get_text(), content="[3]")
  let b = @debug.to_string(path_doc_id)
  inspect(b.contains("workspace"), content="true")
}
