// Lambda-local analysis projection aggregation.
//
// Phase 2 keeps the aggregation seam deliberately narrow: compose existing
// projected outputs with snapshot-bound external pattern facts, without adding a
// public fact protocol or a broad provider abstraction.

///|
priv struct SnapshotPatternAnalysis {
  facts : Array[@facts.PatternMatchFact]
  snapshot : @facts.SourceSnapshot
}

///|
priv struct AnalysisProjection {
  pattern_analysis_ref : Ref[SnapshotPatternAnalysis?]
}

///|
fn AnalysisProjection::new() -> AnalysisProjection {
  { pattern_analysis_ref: Ref(None) }
}

///|
fn AnalysisProjection::set_pattern_analysis(
  self : AnalysisProjection,
  facts : Array[@facts.PatternMatchFact],
  snapshot : @facts.SourceSnapshot,
) -> Unit {
  self.pattern_analysis_ref.val = Some({ facts, snapshot })
}

///|
fn AnalysisProjection::clear_stale_pattern_analysis(
  self : AnalysisProjection,
  current : @facts.SourceSnapshot,
) -> Unit {
  match self.pattern_analysis_ref.val {
    Some(analysis) if analysis.snapshot.matches(current) => ()
    _ => self.pattern_analysis_ref.val = None
  }
}

///|
fn AnalysisProjection::decorations(
  self : AnalysisProjection,
  semantic_decorations : Array[@protocol.Decoration],
) -> Array[@protocol.Decoration] {
  let pattern_decorations = match self.pattern_analysis_ref.val {
    Some(analysis) =>
      @analysis.facts_to_decorations(analysis.facts, analysis.snapshot)
    None => []
  }
  semantic_decorations + pattern_decorations
}

///|
fn AnalysisProjection::annotations(
  _self : AnalysisProjection,
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
