// Prototype-only visibility adapter for the P1 no-shadow annotation evidence.
// This branch must not merge as a production API change.

///|
/// Build the same present-projection annotation map as the production
/// `get_annotations` closure from explicit, coherent values.
pub fn minimal_no_shadow_p1_annotations(
  eval_results : Array[@lambda_eval.EvalResult],
  projection : @core.ProjNode[@ast.Term],
  source_map : @core.SourceMap,
) -> Map[@core.NodeId, Array[@protocol.ViewAnnotation]] {
  AnalysisProjection::new().annotations(
    build_eval_annotations(eval_results, Some(projection)),
    Some(@lambda_semantic.build_semantic_projection(projection, source_map)),
  )
}
