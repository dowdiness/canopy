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
}

///|
priv struct HeadingSideTable {
  rows : Array[HeadingSideTableRow]
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
  }
}

///|
#warnings("-unused_value")
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
fn heading_side_table_match(
  previous : HeadingObservation,
  current : Array[HeadingObservation],
) -> HeadingSideTableMatch {
  let same_node = find_heading_by_id(current, previous.id)
  let semantic_candidates : Array[HeadingMatchCandidate] = current
    .iter()
    .filter(obs => obs.level == previous.level && obs.text == previous.text)
    .map(obs => heading_candidate(previous, obs))
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
  match_result.candidates.map(candidate => candidate.id)
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
fn row_from_match(
  row : HeadingSideTableRow,
  match_result : HeadingSideTableMatch,
  current : Array[HeadingObservation],
  claim_count : (@core.NodeId) -> Int,
) -> HeadingSideTableRow {
  let ids = candidate_ids(match_result)
  match row.status {
    HeadingRetired => { ..row, current_id: None, candidates: [] }
    _ =>
      match ids {
        [] =>
          {
            ..row,
            current_id: None,
            status: HeadingTombstoned,
            candidates: [],
            evidence: match_result.evidence,
          }
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
        _ =>
          {
            ..row,
            current_id: None,
            status: HeadingAmbiguous,
            candidates: ids,
            evidence: match_result.evidence,
          }
      }
  }
}

///|
#warnings("-unused_value")
fn HeadingSideTable::advance(
  self : HeadingSideTable,
  current : Array[HeadingObservation],
) -> HeadingSideTable {
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
        let match_result = heading_side_table_match_with_same_node_priority(
          row, current, semantic_current,
        )
        row_from_match(row, match_result, current, id => {
          candidate_claim_count(matches, id)
        })
      }
    }
  })
  let fresh_rows : Array[HeadingSideTableRow] = current
    .iter()
    .filter(obs => {
      !side_table_mentions_current_id(next_rows, obs.id) &&
      !side_table_has_stable_id(
        next_rows,
        HeadingStableRowId::from_node(obs.id),
      )
    })
    .map(heading_side_table_live_row)
    .collect()
  { rows: next_rows + fresh_rows }
}
