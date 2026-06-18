// Lambda-local analysis projection aggregation.
//
// Phase 2 keeps the aggregation seam deliberately narrow: compose existing
// projected outputs with snapshot-bound external pattern facts, without adding a
// public fact protocol or a broad provider abstraction.

///|
fn analysis_projection_set_pattern_analysis(
  pattern_facts_ref : Ref[Array[@facts.PatternMatchFact]?],
  pattern_snapshot_ref : Ref[@facts.SourceSnapshot?],
  facts : Array[@facts.PatternMatchFact],
  snapshot : @facts.SourceSnapshot,
) -> Unit {
  pattern_facts_ref.val = Some(facts)
  pattern_snapshot_ref.val = Some(snapshot)
}

///|
fn analysis_projection_clear_stale_pattern_analysis(
  pattern_facts_ref : Ref[Array[@facts.PatternMatchFact]?],
  pattern_snapshot_ref : Ref[@facts.SourceSnapshot?],
  current : @facts.SourceSnapshot,
) -> Unit {
  match pattern_snapshot_ref.val {
    Some(snapshot) if snapshot.matches(current) => ()
    _ => {
      pattern_facts_ref.val = None
      pattern_snapshot_ref.val = None
    }
  }
}

///|
fn analysis_projection_decorations(
  pattern_facts_ref : Ref[Array[@facts.PatternMatchFact]?],
  pattern_snapshot_ref : Ref[@facts.SourceSnapshot?],
  semantic_decorations : Array[@protocol.Decoration],
) -> Array[@protocol.Decoration] {
  let pattern_decorations = match
    (pattern_facts_ref.val, pattern_snapshot_ref.val) {
    (Some(facts), Some(snapshot)) =>
      @analysis.facts_to_decorations(facts, snapshot)
    _ => []
  }
  semantic_decorations + pattern_decorations
}

///|
fn analysis_projection_annotations(
  eval_annotations : Map[@core.NodeId, Array[@protocol.ViewAnnotation]],
  semantic_projection : @lambda_semantic.SemanticProjection?,
) -> Map[@core.NodeId, Array[@protocol.ViewAnnotation]] {
  match semantic_projection {
    Some(projection) =>
      append_annotation_map(eval_annotations, projection.annotations)
    None => ()
  }
  eval_annotations
}

///|
fn append_annotation_map(
  target : Map[@core.NodeId, Array[@protocol.ViewAnnotation]],
  extra : Map[@core.NodeId, Array[@protocol.ViewAnnotation]],
) -> Unit {
  for node_id, anns in extra {
    target.update(node_id, fn(existing) {
      let merged = match existing {
        Some(current) => current
        None => []
      }
      merged.append(anns)
      Some(merged)
    })
  }
}
