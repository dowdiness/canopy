///| Whitebox side-table tests for the Stable Document Entity Graph Phase 0 idea.

///|
/// These tests exercise the package-private side-table model and validate the
/// internal lifecycle sketch in `docs/design/sdeg-nodeid-side-table.md`.

///|
fn find_side_table_row(
  table : HeadingSideTable,
  stable_id : @core.NodeId,
) -> HeadingSideTableRow? {
  let row_id = HeadingStableRowId::from_node(stable_id)
  table.rows.iter().find_first(row => row.stable_id == row_id)
}

///|
fn find_row_by_current_id(
  rows : Array[HeadingSideTableRow],
  current_id : @core.NodeId,
) -> HeadingSideTableRow? {
  rows.iter().find_first(row => row.current_id == Some(current_id))
}

///|
fn synthetic_heading(
  id : Int,
  text : String,
  start : Int,
  level? : Int = 1,
) -> HeadingObservation {
  {
    id: @core.NodeId::from_int(id),
    level,
    text,
    range: @loomcore.Range::new(start, start + text.length() + level + 1),
    marker: None,
    text_span: None,
  }
}

///|
fn evidence_has_same_node(
  evidence : Array[HeadingEntityEvidence],
  id : @core.NodeId,
) -> Bool {
  evidence
  .iter()
  .any(item => {
    match item {
      HeadingSameNodeId(candidate) => candidate == id
      _ => false
    }
  })
}

///|
fn evidence_has_semantic_key(
  evidence : Array[HeadingEntityEvidence],
  key : String,
) -> Bool {
  evidence
  .iter()
  .any(item => {
    match item {
      HeadingSameSemanticKey(candidate) => candidate == key
      _ => false
    }
  })
}

///|
fn evidence_has_candidate_count(
  evidence : Array[HeadingEntityEvidence],
  count : Int,
) -> Bool {
  evidence
  .iter()
  .any(item => {
    match item {
      HeadingCandidateCount(candidate) => candidate == count
      _ => false
    }
  })
}

///|
fn evidence_has_any_candidate_count(
  evidence : Array[HeadingEntityEvidence],
) -> Bool {
  evidence
  .iter()
  .any(item => {
    match item {
      HeadingCandidateCount(_) => true
      _ => false
    }
  })
}

///|
fn stable_row_claim_count(
  rows : Array[HeadingSideTableRow],
  stable_id : HeadingStableRowId,
) -> Int {
  rows
  .iter()
  .filter(row => row.stable_id == stable_id)
  .count()
}

///|
fn live_current_claim_count(
  rows : Array[HeadingSideTableRow],
  current_id : @core.NodeId,
) -> Int {
  rows
  .iter()
  .filter(row => row.status == HeadingLive && row.current_id == Some(current_id))
  .count()
}

///|
fn heading_side_table_row_shape_valid(
  row : HeadingSideTableRow,
  rows : Array[HeadingSideTableRow],
  current : Array[HeadingObservation],
) -> Bool {
  match row.status {
    HeadingLive =>
      match row.current_id {
        Some(current_id) =>
          row.candidates.length() == 0 &&
          find_heading_by_id(current, current_id) is Some(_) &&
          live_current_claim_count(rows, current_id) == 1
        None => false
      }
    HeadingMissing | HeadingTombstoned | HeadingRetired =>
      row.current_id is None && row.candidates.length() == 0
    HeadingAmbiguous =>
      row.current_id is None &&
      row.candidates.length() != 0 &&
      row.candidates.iter().all(id => live_current_claim_count(rows, id) == 0)
  }
}

///|
fn live_row_count(rows : Array[HeadingSideTableRow]) -> Int {
  rows.iter().filter(row => row.status == HeadingLive).count()
}

///|
fn heading_side_table_index_valid(table : HeadingSideTable) -> Bool {
  table.current_index.length() == live_row_count(table.rows) &&
  table.rows
  .iter()
  .all(row => {
    match (row.status, row.current_id) {
      (HeadingLive, Some(current_id)) =>
        table.entity_for_current_node(current_id) == Some(row.stable_id)
      _ => true
    }
  })
}

///|
fn heading_side_table_invariants_hold(
  table : HeadingSideTable,
  current : Array[HeadingObservation],
) -> Bool {
  heading_side_table_index_valid(table) &&
  table.rows
  .iter()
  .all(row => {
    stable_row_claim_count(table.rows, row.stable_id) == 1 &&
    evidence_has_any_candidate_count(row.evidence) &&
    heading_side_table_row_shape_valid(row, table.rows, current)
  })
}

///|
test "sdeg phase0: NodeId side table preserves same-node matches before semantic ones" {
  let counter : Ref[Int] = Ref(0)
  let source = "# A\n# B\n"
  let next_source = "# C\n# A\n"
  let (initial_cst, _) = @markdown.parse_cst(source)
  let initial = syntax_to_proj_node(
    @seam.SyntaxNode::from_cst(initial_cst),
    counter,
  )
  let initial_map = source_map_for(source, initial)
  let before = collect_heading_observations(initial, initial_map)
  let table = HeadingSideTable::from_observations(before)
  let a_before = find_heading(before, "A").unwrap()
  let b_before = find_heading(before, "B").unwrap()

  let (edited, edited_map) = project_after_reconcile(
    initial, next_source, counter,
  )
  let after = collect_heading_observations(edited, edited_map)
  let c_after = find_heading(after, "C").unwrap()
  let a_after = find_heading(after, "A").unwrap()
  let advanced = table.advance(after)
  let a_row = find_side_table_row(advanced, a_before.id).unwrap()
  let b_row = find_side_table_row(advanced, b_before.id).unwrap()

  inspect(a_row.status == HeadingLive, content="true")
  inspect(b_row.status == HeadingLive, content="true")
  inspect(a_row.current_id == Some(c_after.id), content="true")
  inspect(b_row.current_id == Some(a_after.id), content="true")
  inspect(evidence_has_same_node(a_row.evidence, c_after.id), content="true")
  inspect(evidence_has_same_node(b_row.evidence, a_after.id), content="true")
  inspect(advanced.rows.length(), content="2")
  inspect(heading_side_table_invariants_hold(advanced, after), content="true")
}

///|
test "sdeg phase0: NodeId side table tombstone recovers delete-restore" {
  let counter : Ref[Int] = Ref(0)
  let initial_source = "# A\n# B\n"
  let deleted_source = "# B\n"
  let restored_source = "# A\n# B\n"
  let (initial_cst, _) = @markdown.parse_cst(initial_source)
  let initial = syntax_to_proj_node(
    @seam.SyntaxNode::from_cst(initial_cst),
    counter,
  )
  let initial_map = source_map_for(initial_source, initial)
  let before = collect_heading_observations(initial, initial_map)
  let table = HeadingSideTable::from_observations(before)
  let a_before = find_heading(before, "A").unwrap()

  let (deleted, deleted_map) = project_after_reconcile(
    initial, deleted_source, counter,
  )
  let deleted_observations = collect_heading_observations(deleted, deleted_map)
  let missing_table = table.advance(deleted_observations)
  let a_missing_row = find_side_table_row(missing_table, a_before.id).unwrap()
  let tombstoned_table = missing_table.advance(deleted_observations)
  let a_tombstoned_row = find_side_table_row(tombstoned_table, a_before.id).unwrap()

  let (restored, restored_map) = project_after_reconcile(
    deleted, restored_source, counter,
  )
  let restored_observations = collect_heading_observations(
    restored, restored_map,
  )
  let a_restored = find_heading(restored_observations, "A").unwrap()
  let restored_table = tombstoned_table.advance(restored_observations)
  let a_restored_row = find_side_table_row(restored_table, a_before.id).unwrap()

  inspect(a_missing_row.status == HeadingMissing, content="true")
  inspect(a_missing_row.current_id is None, content="true")
  inspect(
    evidence_has_candidate_count(a_missing_row.evidence, 0),
    content="true",
  )
  inspect(a_tombstoned_row.status == HeadingTombstoned, content="true")
  inspect(a_tombstoned_row.current_id is None, content="true")
  inspect(a_restored_row.consecutive_absences, content="0")
  inspect(a_restored_row.status == HeadingLive, content="true")
  inspect(
    a_restored_row.stable_id == HeadingStableRowId::from_node(a_before.id),
    content="true",
  )
  inspect(a_restored_row.current_id == Some(a_restored.id), content="true")
  inspect(
    evidence_has_semantic_key(a_restored_row.evidence, heading_key(a_before)),
    content="true",
  )
  inspect(
    evidence_has_candidate_count(a_restored_row.evidence, 1),
    content="true",
  )
}

///|
test "sdeg phase0: NodeId side table keeps duplicate restore ambiguous" {
  let counter : Ref[Int] = Ref(0)
  let initial_source = "# A\n# B\n"
  let deleted_source = "# B\n"
  let restored_source = "# A\n# A\n# B\n"
  let (initial_cst, _) = @markdown.parse_cst(initial_source)
  let initial = syntax_to_proj_node(
    @seam.SyntaxNode::from_cst(initial_cst),
    counter,
  )
  let initial_map = source_map_for(initial_source, initial)
  let before = collect_heading_observations(initial, initial_map)
  let table = HeadingSideTable::from_observations(before)
  let a_before = find_heading(before, "A").unwrap()

  let (deleted, deleted_map) = project_after_reconcile(
    initial, deleted_source, counter,
  )
  let deleted_table = table.advance(
    collect_heading_observations(deleted, deleted_map),
  )
  let (restored, restored_map) = project_after_reconcile(
    deleted, restored_source, counter,
  )
  let restored_observations = collect_heading_observations(
    restored, restored_map,
  )
  let restored_table = deleted_table.advance(restored_observations)
  let a_restored_row = find_side_table_row(restored_table, a_before.id).unwrap()

  inspect(a_restored_row.status == HeadingAmbiguous, content="true")
  inspect(a_restored_row.current_id is None, content="true")
  inspect(a_restored_row.candidates.length(), content="2")
  inspect(
    evidence_has_semantic_key(a_restored_row.evidence, heading_key(a_before)),
    content="true",
  )
  inspect(
    evidence_has_candidate_count(a_restored_row.evidence, 2),
    content="true",
  )
  inspect(
    heading_side_table_invariants_hold(restored_table, restored_observations),
    content="true",
  )
}

///|
test "sdeg phase0: NodeId side table conflicts do not double-claim current nodes" {
  let old_a0 = synthetic_heading(1, "A", 0)
  let old_a1 = synthetic_heading(2, "A", 4)
  let current_a = synthetic_heading(100, "A", 0)
  let table = HeadingSideTable::from_observations([old_a0, old_a1])
  let advanced = table.advance([current_a])
  let row0 = find_side_table_row(advanced, old_a0.id).unwrap()
  let row1 = find_side_table_row(advanced, old_a1.id).unwrap()

  inspect(advanced.rows.length(), content="2")
  inspect(row0.status == HeadingAmbiguous, content="true")
  inspect(row1.status == HeadingAmbiguous, content="true")
  inspect(evidence_has_candidate_count(row0.evidence, 1), content="true")
  inspect(evidence_has_candidate_count(row1.evidence, 1), content="true")
  inspect(row0.current_id is None, content="true")
  inspect(row1.current_id is None, content="true")
  inspect(node_id_in(row0.candidates, current_a.id), content="true")
  inspect(node_id_in(row1.candidates, current_a.id), content="true")
  inspect(
    heading_side_table_invariants_hold(advanced, [current_a]),
    content="true",
  )
}

///|
test "sdeg phase1: same-node match wins over duplicate semantic claimant" {
  let old_a0 = synthetic_heading(1, "A", 0)
  let old_a1 = synthetic_heading(2, "A", 4)
  let current_a0 = synthetic_heading(1, "A", 0)
  let table = HeadingSideTable::from_observations([old_a0, old_a1])
  let advanced = table.advance([current_a0])
  let row0 = find_side_table_row(advanced, old_a0.id).unwrap()
  let row1 = find_side_table_row(advanced, old_a1.id).unwrap()

  inspect(row0.status == HeadingLive, content="true")
  inspect(row0.current_id == Some(current_a0.id), content="true")
  inspect(evidence_has_same_node(row0.evidence, current_a0.id), content="true")
  inspect(row1.status == HeadingMissing, content="true")
  inspect(row1.current_id is None, content="true")
  inspect(evidence_has_candidate_count(row1.evidence, 0), content="true")
  inspect(advanced.rows.length(), content="2")
  inspect(
    heading_side_table_invariants_hold(advanced, [current_a0]),
    content="true",
  )
}

///|
test "sdeg phase1: heading level change without same-node evidence stays fresh" {
  let old_a = synthetic_heading(1, "A", 0, level=1)
  let current_a = synthetic_heading(100, "A", 0, level=2)
  let table = HeadingSideTable::from_observations([old_a])
  let advanced = table.advance([current_a])
  let old_row = find_side_table_row(advanced, old_a.id).unwrap()
  let fresh_row = find_side_table_row(advanced, current_a.id).unwrap()

  inspect(old_row.status == HeadingMissing, content="true")
  inspect(old_row.current_id is None, content="true")
  inspect(evidence_has_candidate_count(old_row.evidence, 0), content="true")
  inspect(fresh_row.status == HeadingLive, content="true")
  inspect(fresh_row.current_id == Some(current_a.id), content="true")
  inspect(advanced.rows.length(), content="2")
  inspect(
    heading_side_table_invariants_hold(advanced, [current_a]),
    content="true",
  )
}

///|
test "sdeg phase0: NodeId side table invariants hold across lifecycle states" {
  let counter : Ref[Int] = Ref(0)
  let source = "# A\n# B\n"
  let deleted_source = "# B\n"
  let restored_source = "# A\n# B\n"
  let (initial_cst, _) = @markdown.parse_cst(source)
  let initial = syntax_to_proj_node(
    @seam.SyntaxNode::from_cst(initial_cst),
    counter,
  )
  let initial_map = source_map_for(source, initial)
  let initial_observations = collect_heading_observations(initial, initial_map)
  let table = HeadingSideTable::from_observations(initial_observations)

  let (deleted, deleted_map) = project_after_reconcile(
    initial, deleted_source, counter,
  )
  let deleted_observations = collect_heading_observations(deleted, deleted_map)
  let deleted_table = table.advance(deleted_observations)

  let (restored, restored_map) = project_after_reconcile(
    deleted, restored_source, counter,
  )
  let restored_observations = collect_heading_observations(
    restored, restored_map,
  )
  let restored_table = deleted_table.advance(restored_observations)

  inspect(
    heading_side_table_invariants_hold(table, initial_observations),
    content="true",
  )
  inspect(
    heading_side_table_invariants_hold(deleted_table, deleted_observations),
    content="true",
  )
  inspect(
    heading_side_table_invariants_hold(restored_table, restored_observations),
    content="true",
  )
}

///|
test "sdeg phase1: tombstoned rows retire after retention threshold" {
  let old_a = synthetic_heading(1, "A", 0)
  let table = HeadingSideTable::from_observations(
    [old_a],
    retention_threshold=3,
  )
  let missing_table = table.advance([])
  let missing_row = find_side_table_row(missing_table, old_a.id).unwrap()
  let tombstoned_table = missing_table.advance([])
  let tombstoned_row = find_side_table_row(tombstoned_table, old_a.id).unwrap()
  let retired_table = tombstoned_table.advance([])
  let retired_row = find_side_table_row(retired_table, old_a.id).unwrap()

  inspect(missing_row.status == HeadingMissing, content="true")
  inspect(missing_row.consecutive_absences, content="1")
  inspect(tombstoned_row.status == HeadingTombstoned, content="true")
  inspect(tombstoned_row.consecutive_absences, content="2")
  inspect(retired_row.status == HeadingRetired, content="true")
  inspect(retired_row.current_id is None, content="true")
  inspect(retired_row.consecutive_absences, content="3")
  inspect(heading_side_table_invariants_hold(missing_table, []), content="true")
  inspect(
    heading_side_table_invariants_hold(tombstoned_table, []),
    content="true",
  )
  inspect(heading_side_table_invariants_hold(retired_table, []), content="true")
}

///|
test "sdeg phase1: tombstoned rows stay retained below threshold" {
  let old_a = synthetic_heading(1, "A", 0)
  let table = HeadingSideTable::from_observations(
    [old_a],
    retention_threshold=3,
  )
  let missing_table = table.advance([])
  let tombstoned_table = missing_table.advance([])
  let tombstoned_row = find_side_table_row(tombstoned_table, old_a.id).unwrap()

  inspect(tombstoned_row.status == HeadingTombstoned, content="true")
  inspect(tombstoned_row.consecutive_absences, content="2")
  inspect(
    heading_side_table_invariants_hold(tombstoned_table, []),
    content="true",
  )
}

///|
test "sdeg phase1: gc_eligible is true for retired, false for other statuses" {
  let old_a = synthetic_heading(1, "A", 0)
  let table = HeadingSideTable::from_observations(
    [old_a],
    retention_threshold=3,
  )
  let fresh_row = find_side_table_row(table, old_a.id).unwrap()
  inspect(gc_eligible(fresh_row), content="false")

  let missing_table = table.advance([])
  let missing_row = find_side_table_row(missing_table, old_a.id).unwrap()
  inspect(missing_row.status == HeadingMissing, content="true")
  inspect(gc_eligible(missing_row), content="false")

  let tombstoned_table = missing_table.advance([])
  let tombstoned_row = find_side_table_row(tombstoned_table, old_a.id).unwrap()
  inspect(tombstoned_row.status == HeadingTombstoned, content="true")
  inspect(gc_eligible(tombstoned_row), content="false")

  let retired_table = tombstoned_table.advance([])
  let retired_row = find_side_table_row(retired_table, old_a.id).unwrap()
  inspect(retired_row.status == HeadingRetired, content="true")
  inspect(gc_eligible(retired_row), content="true")
}

///|
test "sdeg phase1: retired rows with same NodeId get fallback stable_id" {
  let old_a = synthetic_heading(1, "A", 0)
  // Same NodeId reappears (e.g. after retirement, undo restores to same NodeId)
  let current_a = synthetic_heading(1, "A", 0)
  let retired_row = {
    ..heading_side_table_live_row(old_a),
    current_id: None,
    status: HeadingRetired,
    candidates: [],
  }
  let rows = [retired_row]
  let table = { rows, current_index: heading_current_index(rows), retention_threshold: 0, next_entity_seed: -1 }
  let advanced = table.advance([current_a])
  let old_row = find_side_table_row(advanced, old_a.id).unwrap()
  let fresh_row = find_row_by_current_id(advanced.rows, current_a.id).unwrap()

  inspect(old_row.status == HeadingRetired, content="true")
  inspect(old_row.current_id is None, content="true")

  // Fresh row gets created with a fallback stable_id (not suppressed)
  inspect(fresh_row.status == HeadingLive, content="true")
  inspect(fresh_row.current_id == Some(current_a.id), content="true")
  inspect(
    fresh_row.stable_id != HeadingStableRowId::from_node(current_a.id),
    content="true",
  )
  inspect(advanced.rows.length(), content="2")
  inspect(
    heading_side_table_invariants_hold(advanced, [current_a]),
    content="true",
  )
}

///|
test "sdeg phase1: retired rows with fallback stable_id satisfy invariants" {
  // Multiple retired rows getting same-NodeId observations at once.
  // Each must get a unique fallback stable_id.
  let old_a = synthetic_heading(1, "A", 0)
  let old_b = synthetic_heading(2, "B", 0)
  let retired_a = {
    ..heading_side_table_live_row(old_a),
    current_id: None,
    status: HeadingRetired,
    candidates: [],
  }
  let retired_b = {
    ..heading_side_table_live_row(old_b),
    current_id: None,
    status: HeadingRetired,
    candidates: [],
  }
  let rows = [retired_a, retired_b]
  let table = { rows, current_index: heading_current_index(rows), retention_threshold: 0, next_entity_seed: -1 }
  let current_a = synthetic_heading(1, "A", 0)
  let current_b = synthetic_heading(2, "B", 0)
  let advanced = table.advance([current_a, current_b])
  let fresh_a = find_row_by_current_id(advanced.rows, current_a.id).unwrap()
  let fresh_b = find_row_by_current_id(advanced.rows, current_b.id).unwrap()

  inspect(fresh_a.status == HeadingLive, content="true")
  inspect(fresh_b.status == HeadingLive, content="true")
  inspect(
    fresh_a.stable_id != fresh_b.stable_id,
    content="true",
  )
  inspect(advanced.rows.length(), content="4")
  inspect(
    heading_side_table_invariants_hold(advanced, [current_a, current_b]),
    content="true",
  )
}

///|
test "sdeg phase1: collect_garbage removes retired rows only" {
  // Create a table with a retired row (manually constructed) and a live row
  let old_a = synthetic_heading(1, "A", 0)
  let old_b = synthetic_heading(2, "B", 0)
  let retired = {
    ..heading_side_table_live_row(old_a),
    current_id: None,
    status: HeadingRetired,
    candidates: [],
  }
  let live = heading_side_table_live_row(old_b)
  let rows = [retired, live]
  let table = { rows, current_index: heading_current_index(rows), retention_threshold: 0, next_entity_seed: -1 }
  let gc_table = table.collect_garbage()

  // Retired row removed, live row kept
  inspect(gc_table.rows.length(), content="1")
  let remaining = gc_table.rows.iter().find_first(row => row.status == HeadingLive).unwrap()
  inspect(remaining.stable_id == HeadingStableRowId::from_node(old_b.id), content="true")
  inspect(
    heading_side_table_invariants_hold(gc_table, [old_b]),
    content="true",
  )
}

///|
test "sdeg phase1: collect_garbage is no-op on table with no retired rows" {
  let old_a = synthetic_heading(1, "A", 0)
  let table = HeadingSideTable::from_observations([old_a])
  let gc_table = table.collect_garbage()

  inspect(gc_table.rows.length(), content="1")
  inspect(
    heading_side_table_invariants_hold(gc_table, [old_a]),
    content="true",
  )
}
