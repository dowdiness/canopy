// Workspace identity probe — P0a gate #4.
//
// Q2 follow-through. Refines the failure surface that B1'' opened up by
// probing four additional divergence cases that the gate #3 decision doc
// (docs/research/2026-05-23-workspace-identity-decision.md §Q2) named as
// open follow-ups:
//
//   C1 — asymmetric position (same variant, different positions)
//   C2 — nested-array divergence (both replicas mutate different sub-arrays)
//   C3 — delete + insert (one replica deletes, the other modifies near)
//   C4 — object-member mixed-variant divergence (Codex addition: same_kind
//        for Object ignores keys entirely, see loom/examples/json/src/proj_traits.mbt:14-25)
//
// Verdict shape (per Codex pre-implementation review 2026-05-23):
//   - keep assertions at the level of "kind_mismatches > 0" or "= 0"; do NOT
//     predict which exact element keeps its NodeId — LCS tie-breaking is
//     implementation-defined per the project's own property tests at
//     core/reconcile_properties_wbtest.mbt:323-327.
//   - dump observable (NodeId.0, @debug.to_string(kind)) snapshots for
//     diagnosis only. Snapshots are *evidence*, not the verdict.
//
// Probe template (mirrors B1' / B1'' at identity_probe_wbtest.mbt:138-291):
//   1. common base via insert + apply_sync(export_all)
//   2. force projection memo via get_registry() on both replicas
//   3. each replica makes a LOCAL divergent edit (no cross-sync between)
//   4. force memo again
//   5. cross-sync both ways
//   6. assert text convergence
//   7. count kind_mismatches + key-set asymmetries — load-bearing verdict
//      metrics. (Earlier revisions also inspect()-asserted full
//      (NodeId, kind) registry dumps; Codex review on PR #326 flagged that
//      as brittle since NodeId integers + LCS tie-breaking are
//      implementation-defined per the header. The dump assertions have
//      been removed; B1'' in identity_probe_wbtest.mbt:255-276 keeps the
//      foundational dump as documented evidence of the original swap.)

///|
fn count_kind_mismatches(
  editor_a : @editor.SyncEditor[@_json_lang.JsonValue],
  editor_b : @editor.SyncEditor[@_json_lang.JsonValue],
) -> Int {
  let reg_a = editor_a.get_registry()
  let reg_b = editor_b.get_registry()
  let ids_a : Array[@core.NodeId] = reg_a.keys().to_array()
  ids_a
  .iter()
  .filter(fn(id) {
    match (reg_a.get(id), reg_b.get(id)) {
      (Some(node_a), Some(node_b)) => node_a.kind != node_b.kind
      _ => false
    }
  })
  .count()
}

///|
fn count_keys_only_in_a(
  editor_a : @editor.SyncEditor[@_json_lang.JsonValue],
  editor_b : @editor.SyncEditor[@_json_lang.JsonValue],
) -> Int {
  let reg_a = editor_a.get_registry()
  let reg_b = editor_b.get_registry()
  reg_a.keys().iter().filter(fn(id) { reg_b.get(id) is None }).count()
}

///|
// ============================================================
// C1 — asymmetric position (same variant)
//
// Base "[1,2,3]". A appends ",4" (cursor=6); B prepends "0,"
// (cursor=1). Cross-sync. Both edits insert Number variants —
// B1' was the null finding for SAME-position same-variant edits;
// this case asks whether ASYMMETRIC position still preserves identity.
// ============================================================

///|
test "C1: asymmetric position (same variant) — NodeId mapping" {
  let editor_a = @json_companion.new_json_editor("replica_a")
  let editor_b = @json_companion.new_json_editor("replica_b")
  // Common base.
  try! editor_a.insert("[1,2,3]")
  try! editor_b.apply_sync(try! editor_a.export_all())
  inspect(editor_a.get_text(), content="[1,2,3]")
  inspect(editor_b.get_text(), content="[1,2,3]")
  ignore(editor_a.get_registry())
  ignore(editor_b.get_registry())
  // A appends at end; B prepends at start. Same variant (Number), different position.
  editor_a.move_cursor(6) // before final "]"
  try! editor_a.insert(",4")
  editor_b.move_cursor(1) // after opening "["
  try! editor_b.insert("0,")
  ignore(editor_a.get_registry())
  ignore(editor_b.get_registry())
  // Cross-sync.
  try! editor_a.apply_sync(try! editor_b.export_all())
  try! editor_b.apply_sync(try! editor_a.export_all())
  inspect(editor_a.get_text() == editor_b.get_text(), content="true")
  // Verdict (per the file header: load-bear only on count metrics, not on
  // exact NodeId integers — LCS tie-breaking is implementation-defined).
  inspect(count_kind_mismatches(editor_a, editor_b), content="0")
  inspect(count_keys_only_in_a(editor_a, editor_b), content="0")
  inspect(count_keys_only_in_a(editor_b, editor_a), content="0")
}

///|
// ============================================================
// C2 — nested-array divergence
//
// Base "[[1],[2]]". A inserts ",9" inside inner[0] → "[[1,9],[2]]".
// B inserts ",9" inside inner[1] → "[[1],[2,9]]". Cross-sync.
// Both edits are same-variant (Number) added to different sub-arrays.
//
// Question: does drift propagate to the OUTER NodeIds, or stay localized
// to inner arrays? Outer children are both Array variant on both replicas
// throughout, so same_kind should match the outer LCS deterministically.
// ============================================================

///|
test "C2: nested-array divergence — NodeId mapping" {
  let editor_a = @json_companion.new_json_editor("replica_a")
  let editor_b = @json_companion.new_json_editor("replica_b")
  // Common base "[[1],[2]]" — positions 0..=8.
  try! editor_a.insert("[[1],[2]]")
  try! editor_b.apply_sync(try! editor_a.export_all())
  inspect(editor_a.get_text(), content="[[1],[2]]")
  inspect(editor_b.get_text(), content="[[1],[2]]")
  ignore(editor_a.get_registry())
  ignore(editor_b.get_registry())
  // A: cursor=3 is just before first "]" — insert ",9" → "[[1,9],[2]]".
  editor_a.move_cursor(3)
  try! editor_a.insert(",9")
  // B: cursor=7 is just before second "]" — insert ",9" → "[[1],[2,9]]".
  editor_b.move_cursor(7)
  try! editor_b.insert(",9")
  ignore(editor_a.get_registry())
  ignore(editor_b.get_registry())
  // Cross-sync.
  try! editor_a.apply_sync(try! editor_b.export_all())
  try! editor_b.apply_sync(try! editor_a.export_all())
  inspect(editor_a.get_text() == editor_b.get_text(), content="true")
  // Verdict.
  inspect(count_kind_mismatches(editor_a, editor_b), content="2")
  inspect(count_keys_only_in_a(editor_a, editor_b), content="0")
  inspect(count_keys_only_in_a(editor_b, editor_a), content="0")
}

///|
// ============================================================
// C3 — delete + insert
//
// Base "[1,2,3]". A deletes ",2" (delete_at(2, 2) → "[1,3]");
// B inserts ",9" after "2" (cursor=4, insert ",9" → "[1,2,9,3]").
// Cross-sync.
//
// Codex note: FugueMax is a sequence CRDT with tombstones. A's delete
// marks the LV for "2" as deleted; B's insert is anchored to neighbors
// at insert time and remains visible after sync. Don't expect "CRDT op
// missing" as common failure mode. *Do* expect potential registry-key
// asymmetry — projection NodeIds are local per editor, reconcile is
// history-dependent (core/projection_memo.mbt:16-30).
// ============================================================

///|
test "C3: delete + insert — NodeId mapping" {
  let editor_a = @json_companion.new_json_editor("replica_a")
  let editor_b = @json_companion.new_json_editor("replica_b")
  // Common base "[1,2,3]".
  try! editor_a.insert("[1,2,3]")
  try! editor_b.apply_sync(try! editor_a.export_all())
  inspect(editor_a.get_text(), content="[1,2,3]")
  inspect(editor_b.get_text(), content="[1,2,3]")
  ignore(editor_a.get_registry())
  ignore(editor_b.get_registry())
  // A deletes ",2" to produce "[1,3]". `delete_at(pos, timestamp_ms)`
  // removes ONE character at pos; do two consecutive calls.
  let _ = editor_a.delete_at(2, 0) // remove ","  → "[12,3]"
  let _ = editor_a.delete_at(2, 0) // remove "2"  → "[1,3]"
  inspect(editor_a.get_text(), content="[1,3]")
  // B inserts ",9" after "2" → "[1,2,9,3]".
  editor_b.move_cursor(4)
  try! editor_b.insert(",9")
  inspect(editor_b.get_text(), content="[1,2,9,3]")
  ignore(editor_a.get_registry())
  ignore(editor_b.get_registry())
  // Cross-sync.
  try! editor_a.apply_sync(try! editor_b.export_all())
  try! editor_b.apply_sync(try! editor_a.export_all())
  inspect(editor_a.get_text() == editor_b.get_text(), content="true")
  // Capture the converged text so the verdict reflects the FugueMax order.
  inspect(editor_a.get_text(), content="[1,9,3]")
  // Verdict.
  inspect(count_kind_mismatches(editor_a, editor_b), content="0")
  inspect(count_keys_only_in_a(editor_a, editor_b), content="1")
  inspect(count_keys_only_in_a(editor_b, editor_a), content="1")
}

///|
// ============================================================
// C4 — object-member mixed variant (Codex-recommended addition)
//
// Base `{"a":1,"b":2}`. A inserts `"x":"foo",` at start; B inserts
// `"y":true,` at start. Different keys, DIFFERENT variants
// (String vs Bool). Cross-sync.
//
// Load-bearing because `same_kind` for Object ignores keys entirely
// (loom/examples/json/src/proj_traits.mbt:14-25). Object children are
// matched by their VALUE'S variant. The LCS for object members has the
// same B1''-style swap potential as arrays, but is even more sensitive
// because key information doesn't constrain matching at all.
//
// Spec-aware workspaces will likely identify cross-document references
// via object members (e.g., `{"id": "node-42", "kind": "definition"}`),
// so object-member identity is directly load-bearing for the §3.2 design.
// ============================================================

///|
test "C4: object-member mixed variant — NodeId mapping" {
  let editor_a = @json_companion.new_json_editor("replica_a")
  let editor_b = @json_companion.new_json_editor("replica_b")
  // Common base `{"a":1,"b":2}` (length 13).
  try! editor_a.insert("{\"a\":1,\"b\":2}")
  try! editor_b.apply_sync(try! editor_a.export_all())
  inspect(editor_a.get_text(), content="{\"a\":1,\"b\":2}")
  inspect(editor_b.get_text(), content="{\"a\":1,\"b\":2}")
  ignore(editor_a.get_registry())
  ignore(editor_b.get_registry())
  // A inserts `"x":"foo",` at position 1 (after `{`):
  editor_a.move_cursor(1)
  try! editor_a.insert("\"x\":\"foo\",")
  inspect(editor_a.get_text(), content="{\"x\":\"foo\",\"a\":1,\"b\":2}")
  // B inserts `"y":true,` at position 1:
  editor_b.move_cursor(1)
  try! editor_b.insert("\"y\":true,")
  inspect(editor_b.get_text(), content="{\"y\":true,\"a\":1,\"b\":2}")
  ignore(editor_a.get_registry())
  ignore(editor_b.get_registry())
  // Cross-sync.
  try! editor_a.apply_sync(try! editor_b.export_all())
  try! editor_b.apply_sync(try! editor_a.export_all())
  inspect(editor_a.get_text() == editor_b.get_text(), content="true")
  // Capture the converged text so the verdict reflects the FugueMax order.
  inspect(
    editor_a.get_text(),
    content="{\"x\":\"foo\",\"y\":true,\"a\":1,\"b\":2}",
  )
  // Verdict.
  inspect(count_kind_mismatches(editor_a, editor_b), content="2")
  inspect(
    count_keys_only_in_a(editor_a, editor_b),
    content=(
      #|0
    ),
  )
  inspect(
    count_keys_only_in_a(editor_b, editor_a),
    content=(
      #|0
    ),
  )
}
