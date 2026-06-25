///| Internal Markdown heading side table for session-local SDEG Phase 1 snapshots.

// Several side-table records intentionally carry forward-looking fields and
// constructors while SDEG remains package-private. Keep the suppressions local so
// `moon check` still reports accidental unused code elsewhere in this package.

///|
#warnings("-struct_never_constructed-unused_field")
priv struct HeadingObservation {
  id : @core.NodeId
  level : Int
  text : String
  range : @loomcore.Range
  marker : @loomcore.Range?
  text_span : @loomcore.Range?
} derive(Eq)

///|
#warnings("-unused_constructor")
priv enum HeadingSnapshotValidity {
  HeadingSnapshotValid
  HeadingSnapshotInvalid
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
} derive(Eq, Hash)

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
  HeadingSemanticDrift(String, String)
  HeadingOverlappingRange(@loomcore.Range, @loomcore.Range)
  HeadingCandidateCount(Int)
} derive(Eq)

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
} derive(Eq)

///|
priv struct HeadingSideTable {
  rows : Array[HeadingSideTableRow]
  current_index : Map[@core.NodeId, HeadingStableRowId]
  used_stable_ids : Set[HeadingStableRowId]
  retention_threshold : Int
  next_entity_seed : Int
} derive(Eq)

///|
fn ranges_overlap(a : @loomcore.Range, b : @loomcore.Range) -> Bool {
  a.start < b.end && b.start < a.end
}

///|
fn heading_key(obs : HeadingObservation) -> String {
  "h\{obs.level}:\{obs.text}"
}

///|
fn heading_drift_evidence(
  previous : HeadingObservation,
  current : HeadingObservation,
) -> HeadingEntityEvidence? {
  let previous_key = heading_key(previous)
  let current_key = heading_key(current)
  if previous_key != current_key {
    Some(HeadingSemanticDrift(previous_key, current_key))
  } else {
    None
  }
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
  let entries : Array[(@core.NodeId, HeadingStableRowId)] = rows
    .iter()
    .filter_map(row => {
      match (row.status, row.current_id) {
        (HeadingLive, Some(id)) => Some((id, row.stable_id))
        _ => None
      }
    })
    .collect()
  let index = Map::from_iter(entries.iter())
  if index.length() != entries.length() {
    abort("HeadingSideTable invariant violation: duplicate live current_id")
  }
  index
}

///|
fn heading_used_stable_ids(
  rows : Array[HeadingSideTableRow],
) -> Set[HeadingStableRowId] {
  Set::from_iter(rows.iter().map(row => row.stable_id))
}

///|
fn heading_mentioned_current_ids(
  rows : Array[HeadingSideTableRow],
) -> Set[@core.NodeId] {
  Set::from_iter(
    rows
    .iter()
    .flat_map(row => {
      let current_ids : Iter[@core.NodeId] = match row.current_id {
        Some(id) => Iter::singleton(id)
        None => Iter::empty()
      }
      current_ids + row.candidates.iter()
    }),
  )
}

///|
fn next_unused_stable_id(
  used_stable_ids : Set[HeadingStableRowId],
  seed : Int,
) -> (HeadingStableRowId, Int) {
  let candidate = HeadingStableRowId::from_node(@core.NodeId::from_int(seed))
  if used_stable_ids.contains(candidate) {
    next_unused_stable_id(used_stable_ids, seed - 1)
  } else {
    (candidate, seed - 1)
  }
}

///|
// Package-private until production side-table wiring; white-box tests exercise it.
#warnings("-unused_value")
fn HeadingSideTable::from_observations(
  observations : Array[HeadingObservation],
  validity~ : HeadingSnapshotValidity,
  retention_threshold? : Int = 0,
) -> HeadingSideTable {
  let rows = match validity {
    HeadingSnapshotValid => observations.map(heading_side_table_live_row)
    HeadingSnapshotInvalid => []
  }
  {
    rows,
    current_index: heading_current_index(rows),
    used_stable_ids: heading_used_stable_ids(rows),
    retention_threshold,
    next_entity_seed: -1,
  }
}

///|
fn heading_snapshot_validity(
  diagnostics : @loomcore.DiagnosticSet,
  root : @core.ProjNode[@markdown.Block]?,
) -> HeadingSnapshotValidity {
  match root {
    Some(node) if diagnostics.is_empty() && !projection_has_error_block(node) =>
      HeadingSnapshotValid
    _ => HeadingSnapshotInvalid
  }
}

///|
fn inline_text_to(
  inlines : Array[@markdown.Inline],
  buf : StringBuilder,
) -> Unit {
  inlines
  .iter()
  .each(inline => {
    match inline {
      Text(s) => buf.write_string(s)
      Bold(children) | Italic(children) => inline_text_to(children, buf)
      InlineCode(s) => buf.write_string(s)
      Link(children, _url) => inline_text_to(children, buf)
      Error(s) => buf.write_string(s)
    }
  })
}

///|
fn inline_text(inlines : Array[@markdown.Inline]) -> String {
  let buf = StringBuilder::new()
  inline_text_to(inlines, buf)
  buf.to_string()
}

///|
fn heading_observation(
  node : @core.ProjNode[@markdown.Block],
  source_map : @core.SourceMap,
) -> HeadingObservation? {
  match node.kind {
    Heading(level, inlines) =>
      match source_map.get_range(node.id()) {
        Some(range) =>
          Some({
            id: node.id(),
            level,
            text: inline_text(inlines),
            range,
            marker: source_map.get_token_span(node.id(), "marker"),
            text_span: source_map.get_token_span(node.id(), "text"),
          })
        None => None
      }
    _ => None
  }
}

///|
fn collect_heading_observations_into(
  node : @core.ProjNode[@markdown.Block],
  source_map : @core.SourceMap,
  out : Array[HeadingObservation],
) -> Unit {
  // Accumulate into one output array so recursive traversal preserves preorder
  // without repeatedly concatenating child arrays.
  match heading_observation(node, source_map) {
    Some(obs) => out.push(obs)
    None => ()
  }
  node.children
  .iter()
  .each(child => collect_heading_observations_into(child, source_map, out))
}

///|
fn collect_heading_observations(
  root : @core.ProjNode[@markdown.Block],
  source_map : @core.SourceMap,
) -> Array[HeadingObservation] {
  // Current SDEG phase collects headings with a full projection-tree walk.
  // Benchmark before broadening this to more entity kinds or finer invalidation.
  let out : Array[HeadingObservation] = []
  collect_heading_observations_into(root, source_map, out)
  out
}

///|
fn projection_has_error_block(node : @core.ProjNode[@markdown.Block]) -> Bool {
  block_has_projection_error(node.kind) ||
  node.children.iter().any(projection_has_error_block)
}

///|
fn block_has_projection_error(block : @markdown.Block) -> Bool {
  match block {
    Document(_) => false
    Heading(_, inlines) | Paragraph(inlines) =>
      inlines.iter().any(inline_has_projection_error)
    UnorderedList(_) | OrderedList(_, _) => false
    UnorderedListItem(inlines) | OrderedListItem(inlines, _) =>
      inlines.iter().any(inline_has_projection_error)
    CodeBlock(_, _) | HtmlBlock(_) => false
    Error(_) => true
  }
}

///|
fn inline_has_projection_error(inline : @markdown.Inline) -> Bool {
  match inline {
    Bold(children) | Italic(children) =>
      children.iter().any(inline_has_projection_error)
    Link(children, _) => children.iter().any(inline_has_projection_error)
    Error(_) => true
    Text(_) | InlineCode(_) => false
  }
}

///|
fn heading_side_table_snapshot_observations(
  root : @core.ProjNode[@markdown.Block]?,
  source_map : @core.SourceMap,
  validity : HeadingSnapshotValidity,
) -> Array[HeadingObservation] {
  match (root, validity) {
    (Some(node), HeadingSnapshotValid) =>
      collect_heading_observations(node, source_map)
    _ => []
  }
}

///|
fn build_markdown_heading_side_table_memo(
  parser : @loom.Parser[@markdown.Block],
  proj_memo : @incr.Derived[@core.ProjNode[@markdown.Block]?],
  source_map_memo : @incr.Derived[@core.SourceMap],
) -> @incr.Derived[HeadingSideTable] {
  let previous_table : Ref[HeadingSideTable?] = Ref(None)
  @incr.Derived::Derived(
    parser.runtime(),
    fn() -> HeadingSideTable {
      let root = proj_memo.get_or_abort()
      let source_map = source_map_memo.get_or_abort()
      let diagnostics = parser.diagnostics().get_or_abort()
      let validity = heading_snapshot_validity(diagnostics, root)
      let observations = heading_side_table_snapshot_observations(
        root, source_map, validity,
      )
      let table = match previous_table.val {
        Some(previous) => previous.advance(observations, validity~)
        None => HeadingSideTable::from_observations(observations, validity~)
      }
      previous_table.val = Some(table)
      table
    },
    label="markdown_heading_side_table",
  )
}

///|
// Package-private current-node index query; used by side-table invariant tests.
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
fn heading_evidence(
  previous : HeadingObservation,
  current : HeadingObservation,
) -> Array[HeadingEntityEvidence] {
  let evidence = []
  if previous.id == current.id {
    evidence.push(HeadingSameNodeId(current.id))
    if heading_drift_evidence(previous, current) is Some(drift) {
      evidence.push(drift)
    }
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
  matches.iter().filter(pair => candidate_ids(pair.1).contains(id)).count()
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
  let excluded : Set[@core.NodeId] = Set::from_iter(excluded_ids.iter())
  current.iter().filter(obs => !excluded.contains(obs.id)).collect()
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
      // A Missing row with counter=0 comes from the invalid-snapshot hold path.
      // Its first later valid absence should stay Missing with counter=1; the
      // second consecutive valid absence enters Tombstoned so consumers can
      // observe the missing state before retention/GC policy applies.
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
        [id] if claim_count(id) == 1 &&
          (
            match_result.confidence is HeadingExact ||
            match_result.confidence is HeadingProbable
          ) =>
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
// Package-private until production side-table wiring; white-box tests exercise it.
#warnings("-unused_value")
fn HeadingSideTable::advance(
  self : HeadingSideTable,
  current : Array[HeadingObservation],
  validity~ : HeadingSnapshotValidity,
) -> HeadingSideTable {
  match validity {
    HeadingSnapshotInvalid => {
      let rows = self.rows.map(row => {
        let status = match row.status {
          HeadingLive | HeadingAmbiguous =>
            HeadingSideTableStatus::HeadingMissing
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
        used_stable_ids: self.used_stable_ids,
        retention_threshold: self.retention_threshold,
        next_entity_seed: self.next_entity_seed,
      }
    }
    HeadingSnapshotValid => {
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
            guard matches
              .iter()
              .find_first(pair => pair.0.stable_id == row.stable_id)
              is Some(pair) else {
              abort(
                "HeadingSideTable invariant violation: active row has no match",
              )
            }
            let match_result = pair.1
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
      let used_stable_ids = self.used_stable_ids.copy()
      let occupied_current_ids = heading_mentioned_current_ids(next_rows)
      let (fresh_rows, next_entity_seed) : (Array[HeadingSideTableRow], Int) = {
        let result : Array[HeadingSideTableRow] = []
        let mut seed = self.next_entity_seed
        for obs in current {
          if !occupied_current_ids.contains(obs.id) {
            let base_stable = HeadingStableRowId::from_node(obs.id)
            let (stable_id, next_seed) = if used_stable_ids.contains(
                base_stable,
              ) {
              next_unused_stable_id(used_stable_ids, seed)
            } else {
              (base_stable, seed)
            }
            seed = next_seed
            used_stable_ids.add(stable_id)
            occupied_current_ids.add(obs.id)
            result.push({ ..heading_side_table_live_row(obs), stable_id, })
          }
        }
        (result, seed)
      }
      let rows = next_rows + fresh_rows
      {
        rows,
        current_index: heading_current_index(rows),
        used_stable_ids,
        retention_threshold: self.retention_threshold,
        next_entity_seed,
      }
    }
  }
}

///|
/// Drop all rows where `gc_eligible` returns `true`. Returns a new table
/// with only rows that are still active or retainable.
/// No-op when no retired rows exist.
// Package-private until production side-table wiring; white-box tests exercise it.
#warnings("-unused_value")
fn HeadingSideTable::collect_garbage(
  self : HeadingSideTable,
) -> HeadingSideTable {
  let rows = self.rows.iter().filter(row => !gc_eligible(row)).collect()
  {
    rows,
    current_index: heading_current_index(rows),
    used_stable_ids: self.used_stable_ids.copy(),
    retention_threshold: self.retention_threshold,
    next_entity_seed: self.next_entity_seed,
  }
}
