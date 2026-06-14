// Lambda editor factory and companion.
// Creates a SyncEditor[@ast.Term] with lambda-specific capabilities,
// and a LambdaCompanion holding lambda-specific memos.

///|
/// Holds lambda-specific companion memos alongside a generic SyncEditor.
/// The FFI layer stores this alongside the editor.
pub struct LambdaCompanion {
  // Escalation memo merges Tier 1 (direct) + Tier 2 (egglog) results.
  // Falls back to Tier 1 results when no definitions are Suppressed.
  priv escalation_memo : @incr.Derived[Array[@lambda_eval.EvalResult]]
  priv analysis : @parser.LambdaAnalysis
}

///|
/// Reactive view of the escalation-memo cell (Tier 1 + Tier 2 merged results).
pub fn LambdaCompanion::escalation_memo(
  self : LambdaCompanion,
) -> @incr.Derived[Array[@lambda_eval.EvalResult]] {
  self.escalation_memo
}

///|
/// Reactive view of the lambda analysis typecheck result for FFI protected cells.
pub fn LambdaCompanion::typecheck_output(
  self : LambdaCompanion,
) -> @incr.Derived[@typecheck.ModuleTypeResult] {
  self.analysis.typecheck.result
}

///|
/// Dispose only the analysis attachment rooted on the editor parser.
/// FFI lifecycle calls this after protected watches are disposed.
pub fn LambdaCompanion::dispose_analysis_attachment(
  self : LambdaCompanion,
) -> Unit {
  self.analysis.dispose()
}

///|
pub fn LambdaCompanion::get_eval_results(
  self : LambdaCompanion,
) -> Array[@lambda_eval.EvalResult] {
  // Return escalated results (Tier 1 + Tier 2 merge)
  self.escalation_memo.read_or_abort()
}

///|
/// Build a NodeId -> ViewAnnotation map from eval results and a proj node.
pub fn LambdaCompanion::get_eval_annotations(
  self : LambdaCompanion,
  proj_node : @core.ProjNode[@ast.Term]?,
) -> Map[@core.NodeId, Array[@protocol.ViewAnnotation]] {
  build_eval_annotations(self.get_eval_results(), proj_node)
}

///|
/// Shared annotation builder used by both `get_eval_annotations` and
/// the capabilities closure in `build_lambda_capabilities`.
fn build_eval_annotations(
  eval_results : Array[@lambda_eval.EvalResult],
  proj_node : @core.ProjNode[@ast.Term]?,
) -> Map[@core.NodeId, Array[@protocol.ViewAnnotation]] {
  let annotations : Map[@core.NodeId, Array[@protocol.ViewAnnotation]] = {}
  if eval_results.is_empty() {
    return annotations
  }
  let proj = match proj_node {
    Some(p) => p
    None => return annotations
  }
  if proj.kind is @ast.Term::Unit &&
    proj.start == proj.end &&
    proj.children.is_empty() {
    return annotations
  }
  let children = proj.children
  for i, result in eval_results {
    match result {
      @lambda_eval.EvalResult::Suppressed => continue
      @lambda_eval.EvalResult::Value(s) => {
        let target_id = if i < children.length() {
          children[i].id()
        } else {
          proj.id()
        }
        annotations[target_id] = [
          @protocol.ViewAnnotation(kind="eval", label="\u{2192} " + s),
        ]
      }
      @lambda_eval.EvalResult::Stuck(s) => {
        let target_id = if i < children.length() {
          children[i].id()
        } else {
          proj.id()
        }
        annotations[target_id] = [
          @protocol.ViewAnnotation(
            kind="eval",
            label="\u{2192} " + s,
            severity="warning",
          ),
        ]
      }
    }
  }
  annotations
}

///|
fn append_annotation_map(
  target : Map[@core.NodeId, Array[@protocol.ViewAnnotation]],
  extra : Map[@core.NodeId, Array[@protocol.ViewAnnotation]],
) -> Unit {
  for node_id, anns in extra {
    match target.get(node_id) {
      Some(existing) =>
        for ann in anns {
          existing.push(ann)
        }
      None => target[node_id] = anns.copy()
    }
  }
}

///|
/// Create a lambda editor with its companion.
pub fn new_lambda_editor(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
  parent_runtime? : @incr.Runtime,
) -> (@editor.SyncEditor[@ast.Term], LambdaCompanion) {
  // Ref side-channels let the build_memos callback publish companion memos
  // back out to the enclosing scope for companion construction + capabilities
  // wiring.
  let escalation_memo_ref : Ref[@incr.Derived[Array[@lambda_eval.EvalResult]]?] = Ref(
    None,
  )
  let analysis_ref : Ref[@parser.LambdaAnalysis?] = Ref(None)
  let cached_proj_node_ref : Ref[@incr.Derived[@core.ProjNode[@ast.Term]?]?] = Ref(
    None,
  )
  let source_map_memo_ref : Ref[@incr.Derived[@core.SourceMap]?] = Ref(None)
  let editor = @editor.SyncEditor::new_generic(
    agent_id,
    fn(s, rt) { @loom.new_parser(s, @parser.lambda_grammar, runtime?=rt) },
    fn(parser) {
      let (cached_proj_node, registry_memo, source_map_memo) = @lambda_proj.build_lambda_projection_memos(
        parser,
      )
      cached_proj_node_ref.val = Some(cached_proj_node)
      source_map_memo_ref.val = Some(source_map_memo)
      analysis_ref.val = Some(@parser.attach_lambda_analysis(parser))
      let eval_memo = @lambda_eval.build_eval_memo(parser)
      // Escalation memo: merges Tier 1 + Tier 2 for incomplete programs
      let escalation_memo = @lambda_eval.build_escalation_memo(
        parser, eval_memo,
      )
      escalation_memo_ref.val = Some(escalation_memo)
      (cached_proj_node, registry_memo, source_map_memo)
    },
    capture_timeout_ms~,
    parent_runtime?,
    capabilities=build_lambda_capabilities(
      cached_proj_node_ref, source_map_memo_ref, escalation_memo_ref,
    ),
  )
  let companion : LambdaCompanion = {
    escalation_memo: escalation_memo_ref.val.unwrap(),
    analysis: analysis_ref.val.unwrap(),
  }
  (editor, companion)
}

///|
/// Build capabilities using the escalation memo (Tier 1 + Tier 2 merged results).
fn build_lambda_capabilities(
  cached_proj_node_ref : Ref[@incr.Derived[@core.ProjNode[@ast.Term]?]?],
  source_map_memo_ref : Ref[@incr.Derived[@core.SourceMap]?],
  escalation_memo_ref : Ref[@incr.Derived[Array[@lambda_eval.EvalResult]]?],
) -> @editor.LanguageCapabilities[@ast.Term] {
  @editor.LanguageCapabilities::new(
    get_annotations=Some(fn() {
      let eval_results = match escalation_memo_ref.val {
        Some(memo) => memo.read_or_abort()
        None => []
      }
      let proj_node = match cached_proj_node_ref.val {
        Some(memo) => memo.read_or_abort()
        None => None
      }
      let annotations = build_eval_annotations(eval_results, proj_node)
      match (proj_node, source_map_memo_ref.val) {
        (Some(root), Some(source_map_memo)) =>
          append_annotation_map(
            annotations,
            @lambda_semantic.build_semantic_projection(
              root,
              source_map_memo.read_or_abort(),
            ).annotations,
          )
        _ => ()
      }
      annotations
    }),
    get_decorations=Some(fn() {
      match (cached_proj_node_ref.val, source_map_memo_ref.val) {
        (Some(cached_proj_memo), Some(source_map_memo)) =>
          match cached_proj_memo.read_or_abort() {
            Some(root) =>
              @lambda_semantic.build_semantic_projection(
                root,
                source_map_memo.read_or_abort(),
              ).decorations
            None => []
          }
        _ => []
      }
    }),
    pretty_post_process=Some(fn(layout) {
      let eval_results = match escalation_memo_ref.val {
        Some(memo) => memo.read_or_abort()
        None => return layout
      }
      @lambda_eval.inject_eval_annotations(layout, eval_results)
    }),
  )
}

///|
/// Apply a lambda tree edit through the text CRDT.
///
/// Returns the array of `SpanEdit`s that were applied to the underlying
/// text CRDT, so callers can record a patch-level trace alongside the
/// originating `TreeEditOp` (see the Inspector Patch panel).
pub fn apply_lambda_tree_edit(
  editor : @editor.SyncEditor[@ast.Term],
  companion : LambdaCompanion,
  op : @lambda_edits.TreeEditOp,
  timestamp_ms : Int,
) -> Result[Array[@core.SpanEdit], @editor.TreeEditError] {
  // Drop uses SyncEditor::move_node which handles placeholders and separators
  // correctly, instead of the naive text splice in compute_drop.
  match op {
    @lambda_edits.TreeEditOp::Drop(source~, target~, position~) =>
      return editor.move_node(source, target, position, timestamp_ms)
    _ => ()
  }
  let _ = companion
  let source_map = editor.get_source_map()
  let registry = editor.get_registry()
  let definition_index = match editor.get_proj_node() {
    Some(root) => @lambda_proj.DefinitionIndex::from_proj_node(root)
    None => return Err(@editor.TreeEditError::ModuleProjectionUnavailable)
  }
  let ctx : @lambda_edits.EditContext[@ast.Term] = {
    source_text: editor.get_text(),
    source_map,
    registry,
    definition_index,
  }
  match @lambda_edits.compute_text_edit(op, ctx) {
    Ok(Some((edits, focus_hint))) => {
      if edits.is_empty() {
        return Ok(edits)
      }
      editor.apply_span_edits(edits, focus_hint, timestamp_ms)
      Ok(edits)
    }
    Ok(None) =>
      Err(@editor.TreeEditError::UnhandledOperation(detail=op.to_string()))
    Err(msg) => Err(@editor.TreeEditError::ProjectionEdit(detail=msg))
  }
}
