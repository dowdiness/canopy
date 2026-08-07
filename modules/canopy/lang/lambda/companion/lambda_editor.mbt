// Lambda editor factory and companion.
// Creates a SyncEditor[@ast.Term] with lambda-specific capabilities,
// and a LambdaCompanion holding lambda-specific memos.

///|
/// Holds lambda-specific companion memos alongside a generic SyncEditor.
/// The FFI layer stores this alongside the editor.
pub struct LambdaCompanion {
  // Standard projection memos and parser are retained privately so the
  // capability closures can be built from this extras value without
  // construction-time Ref side-channels.
  priv cached_proj_node : @incr.Derived[@core.ProjNode[@ast.Term]?]
  priv source_map_memo : @incr.Derived[@core.SourceMap]
  priv parser : @loom.Parser[@ast.Term]
  // Escalation memo merges Tier 1 (direct) + Tier 2 (egglog) results.
  // Falls back to Tier 1 results when no definitions are Suppressed.
  priv escalation_memo : @incr.Derived[Array[@lambda_eval.EvalResult]]
  priv analysis : @parser.LambdaAnalysis
  priv analysis_projection : AnalysisProjection
  // Reconciliation trace events populated on every reconcile pass. The caller
  // reads this to display structural changes alongside SpanEdits in the Patch
  // panel or to drive custom trace visualizations.
  priv trace_ref : Ref[Array[@core.ReconcileTraceEvent]]
}

///|
/// Lambda's deep language adapter. Per-editor parser attachments and memos are
/// returned as `LambdaCompanion` (the SPI extras value E); capabilities are
/// then derived from that same value before the editor is exposed.
let lambda_language : @lang_runtime.Language[
  @ast.Term,
  @lambda_edits.TreeEditOp,
  LambdaCompanion,
] = @lang_runtime.Language::Language(
  parse=(source_id, source, runtime) => {
    @loom.new_parser(source_id, source, @parser.lambda_grammar, runtime?)
  },
  project=(parser, hints) => {
    let analysis_projection = AnalysisProjection::new()
    let trace_ref : Ref[Array[@core.ReconcileTraceEvent]] = Ref([])
    let (cached_proj_node, registry_memo, source_map_memo) = @lambda_proj.build_lambda_projection_memos(
      parser,
      identity_hints=hints,
      trace_ref=Some(trace_ref),
    )
    let analysis = @parser.attach_lambda_analysis(parser)
    let eval_memo = @lambda_eval.build_eval_memo(parser)
    let escalation_memo = @lambda_eval.build_escalation_memo(parser, eval_memo)
    let companion : LambdaCompanion = {
      cached_proj_node,
      source_map_memo,
      parser,
      escalation_memo,
      analysis,
      analysis_projection,
      trace_ref,
    }
    (cached_proj_node, registry_memo, source_map_memo, companion)
  },
  edit=(op, ctx) => {
    match op {
      @lambda_edits.TreeEditOp::Drop(source~, target~, position~) => {
        let (source_node, source_range) = ctx.resolve(source)
        let (_, target_range) = ctx.resolve(target)
        let (edits, focus_hint) = @core.compute_move(
          ctx.source_text,
          source,
          source_range,
          target,
          target_range,
          position,
          @loom_core.Renderable::placeholder(source_node.kind),
          " ",
        )
        @lang_runtime.EditResult::Edits(
          edits,
          focus_hint,
          Some(@core.IdentityTransform::Opaque),
        )
      }
      _ =>
        match @lambda_edits.compute_text_edit(op, ctx) {
          Some((edits, focus_hint)) =>
            @lang_runtime.EditResult::Edits(
              edits,
              focus_hint,
              Some(op.to_identity_transform(id => ctx.registry.get(id))),
            )
          None =>
            raise @core.EditError::UnsupportedOperation(
              detail="Unhandled tree edit op: " + op.to_string(),
            )
        }
    }
  },
  capabilities=build_lambda_capabilities,
)

///|
/// Read the current reconciliation trace, filter to user-facing
/// StructuredChange events (discards Matched events), and return them.
pub fn LambdaCompanion::get_structured_changes(
  self : LambdaCompanion,
) -> Array[@core.StructuredChange] {
  @core.to_structured_changes(self.trace_ref.val)
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
/// Replace host-provided pattern analysis facts used by editor decorations.
pub fn LambdaCompanion::set_pattern_analysis(
  self : LambdaCompanion,
  facts : Array[@facts.PatternMatchFact],
  snapshot : @facts.SourceSnapshot,
) -> Unit {
  self.analysis_projection.set_pattern_analysis(facts, snapshot)
}

///|
/// Drop host-provided pattern analysis if it no longer matches the current source.
pub fn LambdaCompanion::clear_stale_pattern_analysis(
  self : LambdaCompanion,
  current : @facts.SourceSnapshot,
) -> Unit {
  self.analysis_projection.clear_stale_pattern_analysis(current)
}

///|
/// Project host-provided pattern facts that still match the current source.
pub fn LambdaCompanion::get_pattern_matches(
  self : LambdaCompanion,
  current : @facts.SourceSnapshot,
) -> Array[@analysis.MatchListEntry] {
  self.analysis_projection.match_list(current)
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
  let annotations : Map[@core.NodeId, Array[@protocol.ViewAnnotation]] = Map([])
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
/// Create a lambda editor with its companion.
/// Raises `TextError::EmptyReplicaId` when `agent_id` is empty.
pub fn new_lambda_editor(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
  parent_runtime? : @incr.Runtime,
) -> (@editor.SyncEditor[@ast.Term], LambdaCompanion) raise {
  lambda_language.build(agent_id, capture_timeout_ms~, parent_runtime?)
}

///|
/// Build capabilities using the escalation memo (Tier 1 + Tier 2 merged results).
fn build_lambda_capabilities(
  companion : LambdaCompanion,
) -> @editor.LanguageCapabilities[@ast.Term] {
  @editor.LanguageCapabilities::new(
    get_annotations=Some(fn() {
      let eval_results = companion.escalation_memo.read_or_abort()
      let proj_node = companion.cached_proj_node.read_or_abort()
      let eval_annotations = build_eval_annotations(eval_results, proj_node)
      let semantic_projection = match proj_node {
        Some(root) =>
          Some(
            @lambda_semantic.build_semantic_projection(
              root,
              companion.source_map_memo.read_or_abort(),
            ),
          )
        None => None
      }
      companion.analysis_projection.annotations(
        eval_annotations, semantic_projection,
      )
    }),
    get_decorations=Some(fn() {
      let semantic_decorations = match
        companion.cached_proj_node.read_or_abort() {
        Some(root) =>
          @lambda_semantic.build_semantic_projection(
            root,
            companion.source_map_memo.read_or_abort(),
          ).decorations
        None => []
      }
      companion.analysis_projection.decorations(semantic_decorations)
    }),
    get_diagnostics=Some(fn() {
      let snapshot = companion.parser.snapshot().read_or_abort()
      guard companion.cached_proj_node.read_or_abort() is Some(root) else {
        return None
      }
      Some(
        (
          snapshot.source,
          @lambda_semantic.build_semantic_diagnostics(
            companion.parser.source_id(),
            snapshot.source,
            root,
            companion.source_map_memo.read_or_abort(),
          ),
        ),
      ) catch {
        _ => None
      }
    }),
    pretty_post_process=Some(fn(layout) {
      @lambda_eval.inject_eval_annotations(
        layout,
        companion.escalation_memo.read_or_abort(),
      )
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
) -> Result[Array[@core.SpanEdit], @core.EditError] raise {
  let _ = companion
  lambda_language.apply_edit(editor, op, timestamp_ms)
}

///|
/// Apply one Lambda edit and return an opt-in, detached scope-failure review
/// for the agent host. Ordinary editor and protocol paths remain on
/// `apply_lambda_tree_edit` and do not pay the two scope snapshots.
pub fn apply_lambda_tree_edit_with_reachable_failure_review(
  editor : @editor.SyncEditor[@ast.Term],
  companion : LambdaCompanion,
  op : @lambda_edits.TreeEditOp,
  timestamp_ms : Int,
  attribution : ReachableFailureAttribution,
) -> Result[ReachableFailureReview, @core.EditError] raise {
  let before = snapshot_reachable_failures(editor)
  match apply_lambda_tree_edit(editor, companion, op, timestamp_ms) {
    Err(error) => Err(error)
    Ok(edits) => {
      editor.refresh()
      let after = snapshot_reachable_failures(editor)
      Ok(build_reachable_failure_review(attribution, edits, before, after))
    }
  }
}

///|
/// The imperative shell reads the current projection capabilities; scope
/// construction and failure collection themselves remain deterministic.
fn snapshot_reachable_failures(
  editor : @editor.SyncEditor[@ast.Term],
) -> Array[@lambda_scope.ReachableFailure] raise Failure {
  let source_map = editor.get_source_map()
  @lambda_scope.failures(
    @lambda_scope.build(editor.get_registry(), source_map),
    source_map,
  )
}
