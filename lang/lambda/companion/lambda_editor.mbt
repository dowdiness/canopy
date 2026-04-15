// Lambda editor factory and companion.
// Creates a SyncEditor[@ast.Term] with lambda-specific capabilities,
// and a LambdaCompanion holding lambda-specific memos.

///|
/// Holds lambda-specific memos alongside a generic SyncEditor.
/// The FFI layer stores this alongside the editor.
pub struct LambdaCompanion {
  priv rt : @incr.Runtime
  priv proj_memo : @incr.Memo[@lambda_flat.VersionedFlatProj]
  // Escalation memo merges Tier 1 (direct) + Tier 2 (egglog) results.
  // Falls back to Tier 1 results when no definitions are Suppressed.
  priv escalation_memo : @incr.Memo[Array[@lambda_eval.EvalResult]]
}

///|
pub fn LambdaCompanion::get_flat_proj(
  self : LambdaCompanion,
) -> @lambda_proj.FlatProj? {
  self.rt.read(self.proj_memo).proj
}

///|
pub fn LambdaCompanion::get_eval_results(
  self : LambdaCompanion,
) -> Array[@lambda_eval.EvalResult] {
  // Return escalated results (Tier 1 + Tier 2 merge)
  self.rt.read(self.escalation_memo)
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
/// Create a lambda editor with its companion.
pub fn new_lambda_editor(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
) -> (@editor.SyncEditor[@ast.Term], LambdaCompanion) {
  // Ref side-channels to capture memos and runtime from build_memos callback.
  // Safe: new_generic calls build_memos during construction, before returning.
  let rt_ref : Ref[@incr.Runtime?] = Ref::new(None)
  let proj_memo_ref : Ref[@incr.Memo[@lambda_flat.VersionedFlatProj]?] = Ref::new(
    None,
  )
  let eval_memo_ref : Ref[@incr.Memo[Array[@lambda_eval.EvalResult]]?] = Ref::new(
    None,
  )
  let escalation_memo_ref : Ref[@incr.Memo[Array[@lambda_eval.EvalResult]]?] = Ref::new(
    None,
  )
  let cached_proj_node_ref : Ref[@incr.Memo[@core.ProjNode[@ast.Term]?]?] = Ref::new(
    None,
  )
  let editor = @editor.SyncEditor::new_generic(
    agent_id,
    fn(s) { @loom.new_imperative_parser(s, @parser.lambda_grammar) },
    fn(rt, source_text, syntax_tree, parser) {
      rt_ref.val = Some(rt)
      let (proj_memo, cached_proj_node, registry_memo, source_map_memo) = @lambda_flat.build_lambda_projection_memos(
        rt, source_text, syntax_tree, parser,
      )
      proj_memo_ref.val = Some(proj_memo)
      cached_proj_node_ref.val = Some(cached_proj_node)
      let eval_memo = @lambda_eval.build_eval_memo(rt, syntax_tree, parser)
      eval_memo_ref.val = Some(eval_memo)
      // Escalation memo: merges Tier 1 + Tier 2 for incomplete programs
      let escalation_memo = @lambda_eval.build_escalation_memo(
        rt, eval_memo, syntax_tree, parser,
      )
      escalation_memo_ref.val = Some(escalation_memo)
      (cached_proj_node, registry_memo, source_map_memo)
    },
    capture_timeout_ms~,
    capabilities=build_lambda_capabilities(
      rt_ref, cached_proj_node_ref, escalation_memo_ref,
    ),
  )
  let companion : LambdaCompanion = {
    rt: rt_ref.val.unwrap(),
    proj_memo: proj_memo_ref.val.unwrap(),
    escalation_memo: escalation_memo_ref.val.unwrap(),
  }
  (editor, companion)
}

///|
/// Build capabilities using the escalation memo (Tier 1 + Tier 2 merged results).
fn build_lambda_capabilities(
  rt_ref : Ref[@incr.Runtime?],
  cached_proj_node_ref : Ref[@incr.Memo[@core.ProjNode[@ast.Term]?]?],
  escalation_memo_ref : Ref[@incr.Memo[Array[@lambda_eval.EvalResult]]?],
) -> @editor.LanguageCapabilities[@ast.Term] {
  @editor.LanguageCapabilities::new(
    get_annotations=Some(fn() {
      let rt = match rt_ref.val {
        Some(rt) => rt
        None => return {}
      }
      let eval_results = match escalation_memo_ref.val {
        Some(memo) => rt.read(memo)
        None => return {}
      }
      let proj_node = match cached_proj_node_ref.val {
        Some(memo) => rt.read(memo)
        None => None
      }
      build_eval_annotations(eval_results, proj_node)
    }),
    pretty_post_process=Some(fn(layout) {
      let rt = match rt_ref.val {
        Some(rt) => rt
        None => return layout
      }
      let eval_results = match escalation_memo_ref.val {
        Some(memo) => rt.read(memo)
        None => return layout
      }
      @lambda_eval.inject_eval_annotations(layout, eval_results)
    }),
  )
}

///|
/// Apply a lambda tree edit through the text CRDT.
pub fn apply_lambda_tree_edit(
  editor : @editor.SyncEditor[@ast.Term],
  companion : LambdaCompanion,
  op : @lambda_edits.TreeEditOp,
  timestamp_ms : Int,
) -> Result[Unit, @editor.TreeEditError] {
  // Drop uses SyncEditor::move_node which handles placeholders and separators
  // correctly, instead of the naive text splice in compute_drop.
  match op {
    @lambda_edits.TreeEditOp::Drop(source~, target~, position~) =>
      return editor.move_node(source, target, position, timestamp_ms)
    _ => ()
  }
  let source_map = editor.get_source_map()
  let registry = editor.get_registry()
  let flat_proj = match companion.get_flat_proj() {
    Some(fp) => fp
    None => return Err(@editor.TreeEditError::FlatProjUnavailable)
  }
  let ctx : @lambda_edits.EditContext[@ast.Term] = {
    source_text: editor.get_text(),
    source_map,
    registry,
    flat_proj,
  }
  match @lambda_edits.compute_text_edit(op, ctx) {
    Ok(Some((edits, focus_hint))) => {
      if edits.is_empty() {
        return Ok(())
      }
      editor.apply_span_edits(edits, focus_hint, timestamp_ms)
      Ok(())
    }
    Ok(None) =>
      Err(@editor.TreeEditError::UnhandledOperation(detail=op.to_string()))
    Err(msg) => Err(@editor.TreeEditError::ProjectionEdit(detail=msg))
  }
}
