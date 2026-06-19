///| Whitebox side-table tests for the Stable Document Entity Graph Phase 0 idea.

///|
/// These tests keep the side-table model test-local. They reuse the heading
/// observation helpers from `sdeg_heading_spike_wbtest.mbt` and validate the
/// internal lifecycle sketch in `docs/design/sdeg-nodeid-side-table.md`.

///|
enum HeadingSideTableStatus {
  HeadingLive
  HeadingTombstoned
  HeadingAmbiguous
  HeadingRetired
} derive(Eq, Debug)

///|
struct HeadingStableRowId {
  seed : @core.NodeId
} derive(Eq, Debug)

///|
fn HeadingStableRowId::from_node(id : @core.NodeId) -> HeadingStableRowId {
  { seed: id }
}

///|
enum HeadingSideTableConfidence {
  HeadingExact
  HeadingProbable
  HeadingMatchAmbiguous
  HeadingMissing
} derive(Eq, Debug)

///|
enum HeadingEntityEvidence {
  HeadingSameNodeId(@core.NodeId)
  HeadingSameSemanticKey(String)
  HeadingOverlappingRange(@loomcore.Range, @loomcore.Range)
  HeadingCandidateCount(Int)
} derive(Eq, Debug)

///|
struct HeadingMatchCandidate {
  id : @core.NodeId
  evidence : Array[HeadingEntityEvidence]
} derive(Eq, Debug)

///|
struct HeadingSideTableMatch {
  confidence : HeadingSideTableConfidence
  candidates : Array[HeadingMatchCandidate]
  evidence : Array[HeadingEntityEvidence]
} derive(Eq, Debug)

///|
struct HeadingSideTableRow {
  stable_id : HeadingStableRowId
  current_id : @core.NodeId?
  status : HeadingSideTableStatus
  last_live : HeadingObservation
  candidates : Array[@core.NodeId]
  evidence : Array[HeadingEntityEvidence]
} derive(Eq, Debug)

///|
struct HeadingSideTable {
  rows : Array[HeadingSideTableRow]
} derive(Eq, Debug)

///|
fn heading_side_table_live_row(obs : HeadingObservation) -> HeadingSideTableRow {
  {
    stable_id: HeadingStableRowId::from_node(obs.id),
    current_id: Some(obs.id),
    status: HeadingLive,
    last_live: obs,
    candidates: [],
    evidence: [HeadingSameNodeId(obs.id), HeadingCandidateCount(1)],
  }
}

///|
fn HeadingSideTable::from_observations(
  observations : Array[HeadingObservation],
) -> HeadingSideTable {
  { rows: observations.map(heading_side_table_live_row) }
}

///|
fn find_heading_by_id(
  observations : Array[HeadingObservation],
  id : @core.NodeId,
) -> HeadingObservation? {
  observations.iter().find_first(fn(obs) { obs.id == id })
}

///|
fn find_side_table_row(
  table : HeadingSideTable,
  stable_id : @core.NodeId,
) -> HeadingSideTableRow? {
  let row_id = HeadingStableRowId::from_node(stable_id)
  table.rows.iter().find_first(fn(row) { row.stable_id == row_id })
}

///|
fn side_table_has_stable_id(
  rows : Array[HeadingSideTableRow],
  stable_id : HeadingStableRowId,
) -> Bool {
  rows.iter().any(fn(row) { row.stable_id == stable_id })
}

///|
fn node_id_in(ids : Array[@core.NodeId], id : @core.NodeId) -> Bool {
  ids.iter().any(fn(candidate_id) { candidate_id == id })
}

///|
fn side_table_mentions_current_id(
  rows : Array[HeadingSideTableRow],
  current_id : @core.NodeId,
) -> Bool {
  rows
  .iter()
  .any(fn(row) {
    row.current_id == Some(current_id) || node_id_in(row.candidates, current_id)
  })
}

///|
fn heading_evidence(
  previous : HeadingObservation,
  current : HeadingObservation,
) -> Array[HeadingEntityEvidence] {
  let evidence : Array[HeadingEntityEvidence] = []
  if previous.id == current.id {
    evidence.push(HeadingSameNodeId(current.id))
  }
  if previous.level == current.level && previous.text == current.text {
    evidence.push(HeadingSameSemanticKey(heading_key(previous)))
  }
  if ranges_overlap(previous.range, current.range) {
    evidence.push(HeadingOverlappingRange(previous.range, current.range))
  }
  evidence
}

///|
fn heading_candidate(
  previous : HeadingObservation,
  current : HeadingObservation,
) -> HeadingMatchCandidate {
  { id: current.id, evidence: heading_evidence(previous, current) }
}

///|
fn heading_side_table_match(
  previous : HeadingObservation,
  current : Array[HeadingObservation],
) -> HeadingSideTableMatch {
  let same_node = find_heading_by_id(current, previous.id)
  let semantic_candidates : Array[HeadingMatchCandidate] = current
    .iter()
    .filter(fn(obs) { obs.level == previous.level && obs.text == previous.text })
    .map(fn(obs) { heading_candidate(previous, obs) })
    .collect()
  let semantic_count = semantic_candidates.length()
  match same_node {
    Some(obs) => {
      let candidate = heading_candidate(previous, obs)
      let evidence = if obs.level == previous.level && obs.text == previous.text {
        [
          HeadingSameNodeId(obs.id),
          HeadingSameSemanticKey(heading_key(previous)),
          HeadingCandidateCount(1),
        ]
      } else {
        [HeadingSameNodeId(obs.id), HeadingCandidateCount(1)]
      }
      { confidence: HeadingExact, candidates: [candidate], evidence }
    }
    None if semantic_count == 1 =>
      {
        confidence: HeadingProbable,
        candidates: semantic_candidates,
        evidence: [
          HeadingSameSemanticKey(heading_key(previous)),
          HeadingCandidateCount(1),
        ],
      }
    None if semantic_count > 1 =>
      {
        confidence: HeadingMatchAmbiguous,
        candidates: semantic_candidates,
        evidence: [
          HeadingSameSemanticKey(heading_key(previous)),
          HeadingCandidateCount(semantic_count),
        ],
      }
    None =>
      {
        confidence: HeadingMissing,
        candidates: [],
        evidence: [HeadingCandidateCount(0)],
      }
  }
}

///|
fn candidate_ids(match_result : HeadingSideTableMatch) -> Array[@core.NodeId] {
  match_result.candidates.map(fn(candidate) { candidate.id })
}

///|
fn row_active(row : HeadingSideTableRow) -> Bool {
  row.status != HeadingRetired
}

///|
fn candidate_claim_count(
  matches : Array[(HeadingSideTableRow, HeadingSideTableMatch)],
  id : @core.NodeId,
) -> Int {
  matches
  .iter()
  .filter(fn(pair) { node_id_in(candidate_ids(pair.1), id) })
  .count()
}

///|
fn row_from_match(
  row : HeadingSideTableRow,
  match_result : HeadingSideTableMatch,
  current : Array[HeadingObservation],
  claim_count : (@core.NodeId) -> Int,
) -> HeadingSideTableRow {
  let ids = candidate_ids(match_result)
  if row.status == HeadingRetired {
    { ..row, current_id: None, candidates: [] }
  } else if ids.length() == 0 {
    {
      ..row,
      current_id: None,
      status: HeadingTombstoned,
      candidates: [],
      evidence: match_result.evidence,
    }
  } else if ids.length() == 1 &&
    claim_count(ids[0]) == 1 &&
    (
      match_result.confidence == HeadingExact ||
      match_result.confidence == HeadingProbable
    ) {
    match find_heading_by_id(current, ids[0]) {
      Some(current_obs) =>
        {
          stable_id: row.stable_id,
          current_id: Some(current_obs.id),
          status: HeadingLive,
          last_live: current_obs,
          candidates: [],
          evidence: match_result.evidence,
        }
      None =>
        {
          ..row,
          current_id: None,
          status: HeadingTombstoned,
          candidates: [],
          evidence: match_result.evidence,
        }
    }
  } else {
    {
      ..row,
      current_id: None,
      status: HeadingAmbiguous,
      candidates: ids,
      evidence: match_result.evidence,
    }
  }
}

///|
fn HeadingSideTable::advance(
  self : HeadingSideTable,
  current : Array[HeadingObservation],
) -> HeadingSideTable {
  let matches : Array[(HeadingSideTableRow, HeadingSideTableMatch)] = []
  for row in self.rows {
    if row_active(row) {
      matches.push((row, heading_side_table_match(row.last_live, current)))
    }
  }
  let next_rows : Array[HeadingSideTableRow] = []
  for row in self.rows {
    if row.status == HeadingRetired {
      next_rows.push({ ..row, current_id: None, candidates: [] })
    } else {
      let match_result = heading_side_table_match(row.last_live, current)
      next_rows.push(
        row_from_match(row, match_result, current, fn(id) {
          candidate_claim_count(matches, id)
        }),
      )
    }
  }
  for obs in current {
    if !side_table_mentions_current_id(next_rows, obs.id) &&
      !side_table_has_stable_id(
        next_rows,
        HeadingStableRowId::from_node(obs.id),
      ) {
      next_rows.push(heading_side_table_live_row(obs))
    }
  }
  { rows: next_rows }
}

///|
fn synthetic_heading(
  id : Int,
  text : String,
  start : Int,
) -> HeadingObservation {
  {
    id: @core.NodeId::from_int(id),
    level: 1,
    text,
    range: @loomcore.Range::new(start, start + text.length() + 2),
    marker: None,
    text_span: None,
  }
}

///|
fn heading_side_table_invariants_hold(
  table : HeadingSideTable,
  current : Array[HeadingObservation],
) -> Bool {
  let stable_ids : Array[HeadingStableRowId] = []
  let live_ids : Array[@core.NodeId] = []
  let ambiguous_ids : Array[@core.NodeId] = []
  let mut ok = true
  for row in table.rows {
    if stable_ids.iter().any(fn(id) { id == row.stable_id }) {
      ok = false
    } else {
      stable_ids.push(row.stable_id)
    }
    match row.status {
      HeadingLive =>
        match row.current_id {
          Some(current_id) => {
            if node_id_in(live_ids, current_id) {
              ok = false
            } else {
              live_ids.push(current_id)
            }
            if find_heading_by_id(current, current_id) is None {
              ok = false
            }
            if row.candidates.length() != 0 {
              ok = false
            }
          }
          None => ok = false
        }
      HeadingTombstoned =>
        if row.current_id is Some(_) || row.candidates.length() != 0 {
          ok = false
        }
      HeadingAmbiguous => {
        if row.current_id is Some(_) || row.candidates.length() == 0 {
          ok = false
        }
        for id in row.candidates {
          ambiguous_ids.push(id)
        }
      }
      HeadingRetired =>
        if row.current_id is Some(_) || row.candidates.length() != 0 {
          ok = false
        }
    }
  }
  for id in ambiguous_ids {
    if node_id_in(live_ids, id) {
      ok = false
    }
  }
  ok
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
  let deleted_table = table.advance(
    collect_heading_observations(deleted, deleted_map),
  )
  let a_deleted_row = find_side_table_row(deleted_table, a_before.id).unwrap()

  let (restored, restored_map) = project_after_reconcile(
    deleted, restored_source, counter,
  )
  let restored_observations = collect_heading_observations(
    restored, restored_map,
  )
  let a_restored = find_heading(restored_observations, "A").unwrap()
  let restored_table = deleted_table.advance(restored_observations)
  let a_restored_row = find_side_table_row(restored_table, a_before.id).unwrap()

  inspect(a_deleted_row.status == HeadingTombstoned, content="true")
  inspect(a_deleted_row.current_id is None, content="true")
  inspect(a_restored_row.status == HeadingLive, content="true")
  inspect(
    a_restored_row.stable_id == HeadingStableRowId::from_node(a_before.id),
    content="true",
  )
  inspect(a_restored_row.current_id == Some(a_restored.id), content="true")
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
test "sdeg phase0: NodeId side table retired rows do not revive" {
  let old_a = synthetic_heading(1, "A", 0)
  let current_a = synthetic_heading(100, "A", 0)
  let retired_row = {
    ..heading_side_table_live_row(old_a),
    current_id: None,
    status: HeadingRetired,
    candidates: [],
  }
  let table = { rows: [retired_row] }
  let advanced = table.advance([current_a])
  let old_row = find_side_table_row(advanced, old_a.id).unwrap()
  let fresh_row = find_side_table_row(advanced, current_a.id).unwrap()

  inspect(old_row.status == HeadingRetired, content="true")
  inspect(old_row.current_id is None, content="true")
  inspect(fresh_row.status == HeadingLive, content="true")
  inspect(fresh_row.current_id == Some(current_a.id), content="true")
  inspect(advanced.rows.length(), content="2")
  inspect(
    heading_side_table_invariants_hold(advanced, [current_a]),
    content="true",
  )
}
