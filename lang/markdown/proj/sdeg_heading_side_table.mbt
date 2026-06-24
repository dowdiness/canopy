///| Internal Markdown heading side table for session-local SDEG Phase 1 snapshots.

///|
#warnings("-struct_never_constructed-unused_field")
priv struct HeadingObservation {
  id : @core.NodeId
  level : Int
  text : String
  range : @loomcore.Range
  marker : @loomcore.Range?
  text_span : @loomcore.Range?
}

///|
priv enum HeadingSideTableStatus {
  HeadingLive
  HeadingMissing
  HeadingTombstoned
  HeadingAmbiguous
  HeadingRetired
} derive(Eq)

///|
priv struct HeadingStableRowId {
  seed : @core.NodeId
} derive(Eq)

///|
fn HeadingStableRowId::from_node(id : @core.NodeId) -> HeadingStableRowId {
  { seed: id }
}

///|
#warnings("-unused_constructor")
priv enum HeadingSideTableConfidence {
  HeadingExact
  HeadingProbable
  HeadingMatchAmbiguous
  HeadingMissing
}

///|
#warnings("-unused_constructor")
priv enum HeadingEntityEvidence {
  HeadingSameNodeId(@core.NodeId)
  HeadingSameSemanticKey(String)
  HeadingOverlappingRange(@loomcore.Range, @loomcore.Range)
  HeadingCandidateCount(Int)
}

///|
#warnings("-unused_field")
priv struct HeadingMatchCandidate {
  id : @core.NodeId
  evidence : Array[HeadingEntityEvidence]
}

///|
priv struct HeadingSideTableMatch {
  confidence : HeadingSideTableConfidence
  candidates : Array[HeadingMatchCandidate]
  evidence : Array[HeadingEntityEvidence]
}

///|
#warnings("-unused_field")
priv struct HeadingSideTableRow {
  stable_id : HeadingStableRowId
  current_id : @core.NodeId?
  status : HeadingSideTableStatus
  last_live : HeadingObservation
  candidates : Array[@core.NodeId]
  evidence : Array[HeadingEntityEvidence]
  // Counts consecutive valid-snapshot absences. `Missing` with zero absences
  // means no valid absence evidence has been observed yet, usually because an
  // invalid snapshot used the hold path.
  consecutive_absences : Int
}

///|
priv struct HeadingSideTable {
  rows : Array[HeadingSideTableRow]
  current_index : Map[@core.NodeId, HeadingStableRowId]
  retention_threshold : Int
  next_entity_seed : Int
}

///|
fn ranges_overlap(a : @loomcore.Range, b : @loomcore.Range) -> Bool {
  a.start < b.end && b.start < a.end
}

///|
fn heading_key(obs : HeadingObservation) -> String {
  "h\{obs.level}:\{obs.text}"
}

///|
fn heading_side_table_live_row(obs : HeadingObservation) -> HeadingSideTableRow {
  {
    stable_id: HeadingStableRowId::from_node(obs.id),
    current_id: Some(obs.id),
    status: HeadingLive,
    last_live: obs,
    candidates: [],
    evidence: [HeadingSameNodeId(obs.id), HeadingCandidateCount(1)],
    consecutive_absences: 0,
  }
}

///|
fn heading_current_index(
  rows : Array[HeadingSideTableRow],
) -> Map[@core.NodeId, HeadingStableRowId] {
  Map::from_iter(
    rows
    .iter()
    .filter_map(row => {
      match (row.status, row.current_id) {
        (HeadingLive, Some(id)) => Some((id, row.stable_id))
        _ => None
      }
    }),
  )
}

///|
#warnings("-unused_value")
fn HeadingSideTable::from_observations(
  observations : Array[HeadingObservation],
  retention_threshold? : Int = 0,
  is_valid_parse? : Bool = true,
) -> HeadingSideTable {
  let rows = if is_valid_parse {
    observations.map(heading_side_table_live_row)
  } else {
    []
  }
  {
    rows,
    current_index: heading_current_index(rows),
    retention_threshold,
    next_entity_seed: -1,
  }
}

///|
#warnings("-unused_value")
fn HeadingSideTable::entity_for_current_node(
  self : HeadingSideTable,
  current_id : @core.NodeId,
) -> HeadingStableRowId? {
  self.current_index.get(current_id)
}

///|
fn find_heading_by_id(
  observations : Array[HeadingObservation],
  id : @core.NodeId,
) -> HeadingObservation? {
  observations.iter().find_first(obs => obs.id == id)
}

///|
fn side_table_has_stable_id(
  rows : Array[HeadingSideTableRow],
  stable_id : HeadingStableRowId,
) -> Bool {
  rows.iter().any(row => row.stable_id == stable_id)
}

///|
fn node_id_in(ids : Array[@core.NodeId], id : @core.NodeId) -> Bool {
  ids.iter().any(candidate_id => candidate_id == id)
}

///|
fn side_table_mentions_current_id(
  rows : Array[HeadingSideTableRow],
  current_id : @core.NodeId,
) -> Bool {
  rows
  .iter()
  .any(row => {
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
fn heading_side_table_match_evidence(
  candidates : Array[HeadingMatchCandidate],
  count : Int,
) -> Array[HeadingEntityEvidence] {
  candidates.iter().flat_map(candidate => candidate.evidence.iter()).collect() +
  [HeadingCandidateCount(count)]
}

///|
fn heading_side_table_match(
  previous : HeadingObservation,
  current : Array[HeadingObservation],
) -> HeadingSideTableMatch {
  match find_heading_by_id(current, previous.id) {
    Some(obs) => {
      let candidate = heading_candidate(previous, obs)
      {
        confidence: HeadingExact,
        candidates: [candidate],
        evidence: heading_side_table_match_evidence([candidate], 1),
      }
    }
    None => {
      let semantic_candidates : Array[HeadingMatchCandidate] = current
        .iter()
        .filter(obs => obs.level == previous.level && obs.text == previous.text)
        .map(obs => heading_candidate(previous, obs))
        .collect()
      let semantic_count = semantic_candidates.length()
      match semantic_count {
        1 =>
          {
            confidence: HeadingProbable,
            candidates: semantic_candidates,
            evidence: heading_side_table_match_evidence(semantic_candidates, 1),
          }
        count if count > 1 =>
          {
            confidence: HeadingMatchAmbiguous,
            candidates: semantic_candidates,
            evidence: heading_side_table_match_evidence(
              semantic_candidates, count,
            ),
          }
        _ =>
          {
            confidence: HeadingMissing,
            candidates: [],
            evidence: [HeadingCandidateCount(0)],
          }
      }
    }
  }
}

///|
fn candidate_ids(match_result : HeadingSideTableMatch) -> Array[@core.NodeId] {
  match_result.candidates.map(candidate => candidate.id)
}

///|
fn row_active(row : HeadingSideTableRow) -> Bool {
  row.status != HeadingRetired
}

///|
// L4/L5 GC predicate reserved for the future production GC caller.
#warnings("-unused_value")
fn gc_eligible(row : HeadingSideTableRow) -> Bool {
  row.status == HeadingRetired
}

///|
fn candidate_claim_count(
  matches : Array[(HeadingSideTableRow, HeadingSideTableMatch)],
  id : @core.NodeId,
) -> Int {
  matches.iter().filter(pair => node_id_in(candidate_ids(pair.1), id)).count()
}

///|
fn same_node_claim_ids(
  rows : Array[HeadingSideTableRow],
  current : Array[HeadingObservation],
) -> Array[@core.NodeId] {
  rows
  .iter()
  .filter(row_active)
  .filter(row => find_heading_by_id(current, row.last_live.id) is Some(_))
  .map(row => row.last_live.id)
  .collect()
}

///|
fn current_without_ids(
  current : Array[HeadingObservation],
  excluded_ids : Array[@core.NodeId],
) -> Array[HeadingObservation] {
  current.iter().filter(obs => !node_id_in(excluded_ids, obs.id)).collect()
}

///|
fn heading_side_table_match_with_same_node_priority(
  row : HeadingSideTableRow,
  current : Array[HeadingObservation],
  semantic_current : Array[HeadingObservation],
) -> HeadingSideTableMatch {
  match find_heading_by_id(current, row.last_live.id) {
    Some(_) => heading_side_table_match(row.last_live, current)
    None => heading_side_table_match(row.last_live, semantic_current)
  }
}

///|
fn heading_side_table_absent_row(
  row : HeadingSideTableRow,
  evidence : Array[HeadingEntityEvidence],
  retention_threshold : Int,
) -> HeadingSideTableRow {
  let new_absences = row.consecutive_absences + 1
  let next_status = match row.status {
    HeadingTombstoned =>
      if retention_threshold > 0 && new_absences >= retention_threshold {
        HeadingRetired
      } else {
        HeadingTombstoned
      }
    HeadingMissing =>
      if row.consecutive_absences == 0 {
        HeadingSideTableStatus::HeadingMissing
      } else {
        HeadingTombstoned
      }
    _ => HeadingSideTableStatus::HeadingMissing
  }
  {
    ..row,
    current_id: None,
    status: next_status,
    candidates: [],
    evidence,
    consecutive_absences: new_absences,
  }
}

///|
fn row_from_match(
  row : HeadingSideTableRow,
  match_result : HeadingSideTableMatch,
  current : Array[HeadingObservation],
  claim_count : (@core.NodeId) -> Int,
  retention_threshold? : Int = 0,
) -> HeadingSideTableRow {
  let ids = candidate_ids(match_result)
  match row.status {
    HeadingRetired => { ..row, current_id: None, candidates: [] }
    _ =>
      match ids {
        [] =>
          heading_side_table_absent_row(
            row,
            match_result.evidence,
            retention_threshold,
          )
        [id] if match_result.confidence is HeadingExact ||
          (claim_count(id) == 1 && match_result.confidence is HeadingProbable) =>
          match find_heading_by_id(current, id) {
            Some(current_obs) =>
              {
                stable_id: row.stable_id,
                current_id: Some(current_obs.id),
                status: HeadingLive,
                last_live: current_obs,
                candidates: [],
                evidence: match_result.evidence,
                consecutive_absences: 0,
              }
            None =>
              heading_side_table_absent_row(
                row,
                match_result.evidence,
                retention_threshold,
              )
          }
        _ =>
          {
            ..row,
            current_id: None,
            status: HeadingAmbiguous,
            candidates: ids,
            evidence: match_result.evidence,
            consecutive_absences: 0,
          }
      }
  }
}

///|
#warnings("-unused_value")
fn HeadingSideTable::advance(
  self : HeadingSideTable,
  current : Array[HeadingObservation],
  is_valid_parse? : Bool = true,
) -> HeadingSideTable {
  if !is_valid_parse {
    let rows = self.rows.map(row => {
      let status = match row.status {
        HeadingLive | HeadingAmbiguous => HeadingSideTableStatus::HeadingMissing
        _ => row.status
      }
      // Invalid snapshots supply no durable match evidence; keep `evidence` and
      // `last_live` as last trusted data while clearing current
      // anchors/candidates and preserving the valid-absence counter.
      { ..row, current_id: None, status, candidates: [] }
    })
    {
      rows,
      current_index: heading_current_index(rows),
      retention_threshold: self.retention_threshold,
      next_entity_seed: self.next_entity_seed,
    }
  } else {
    let same_node_ids = same_node_claim_ids(self.rows, current)
    let semantic_current = current_without_ids(current, same_node_ids)
    let matches : Array[(HeadingSideTableRow, HeadingSideTableMatch)] = self.rows
      .iter()
      .filter(row_active)
      .map(row => {
        (
          row,
          heading_side_table_match_with_same_node_priority(
            row, current, semantic_current,
          ),
        )
      })
      .collect()
    let next_rows = self.rows.map(row => {
      match row.status {
        HeadingRetired => { ..row, current_id: None, candidates: [] }
        _ => {
          let match_result = matches
            .iter()
            .find_first(pair => pair.0.stable_id == row.stable_id)
            .unwrap().1
          row_from_match(
            row,
            match_result,
            current,
            id => candidate_claim_count(matches, id),
            retention_threshold=self.retention_threshold,
          )
        }
      }
    })
    let (fresh_rows, next_entity_seed) : (Array[HeadingSideTableRow], Int) = {
      let result : Array[HeadingSideTableRow] = []
      let mut seed = self.next_entity_seed
      for obs in current {
        if !side_table_mentions_current_id(next_rows, obs.id) &&
          !side_table_mentions_current_id(result, obs.id) {
          let base_stable = HeadingStableRowId::from_node(obs.id)
          if side_table_has_stable_id(next_rows, base_stable) ||
            side_table_has_stable_id(result, base_stable) {
            let fallback = @core.NodeId::from_int(seed)
            seed = seed - 1
            result.push({
              ..heading_side_table_live_row(obs),
              stable_id: HeadingStableRowId::from_node(fallback),
            })
          } else {
            result.push(heading_side_table_live_row(obs))
          }
        }
      }
      (result, seed)
    }
    let rows = next_rows + fresh_rows
    {
      rows,
      current_index: heading_current_index(rows),
      retention_threshold: self.retention_threshold,
      next_entity_seed,
    }
  }
}

///|
/// Drop all rows where `gc_eligible` returns `true`. Returns a new table
/// with only rows that are still active or retainable.
/// No-op when no retired rows exist.
#warnings("-unused_value")
fn HeadingSideTable::collect_garbage(
  self : HeadingSideTable,
) -> HeadingSideTable {
  let rows = self.rows.iter().filter(row => !gc_eligible(row)).collect()
  {
    rows,
    current_index: heading_current_index(rows),
    retention_threshold: self.retention_threshold,
    next_entity_seed: self.next_entity_seed,
  }
}
