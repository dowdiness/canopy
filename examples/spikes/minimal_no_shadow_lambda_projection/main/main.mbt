///|
const INITIAL_SOURCE : String = "(x, y) => x + y"

///|
const AFTER_RAW_EDIT : String = "(x, y) => x - y"

///|
const AFTER_STRUCTURAL_BATCH : String = "(z, y) => z - y"

///|
const AFTER_EVALUATION_EDIT : String = "((z, y) => z - y) 5 2"

///|
const AFTER_WHITESPACE_EDIT : String = "((z, y) => z - y) 5 2 "

///|
fn require(condition : Bool, message : String) -> Unit {
  guard condition else { abort("P1 FAIL: " + message) }
}

///|
fn projection_root_name(shell : MinimalLambdaProjectionShell) -> String {
  match shell.projection_state.previous_projection {
    Some(root) => "\{root.id()}"
    None => "none"
  }
}

///|
fn commit_metadata(
  shell : MinimalLambdaProjectionShell,
) -> (String, String, String) {
  match shell.lifetime {
    Closed => (
      shell.current_commit_id().to_string(),
      int_option_name(shell.current_predecessor_id()),
      "released",
    )
    Alive => match shell.read_commit() {
      Ok(commit) => (
        commit.commit_id.to_string(),
        int_option_name(commit.predecessor_commit_id),
        commit.trace.length().to_string(),
      )
      Err(error) => abort("P0: commit metadata: " + read_error_name(error))
    }
  }
}

///|
fn[K : Hash + Eq, V] query_metrics(
  name : String,
  query : @next.Query[K, V],
  key : K,
) -> String {
  let debug = query.debug()
  let trace_length = match query.memo_debug(key) {
    Some(memo) => memo.trace_length.to_string()
    None => "none"
  }
  "\{name}_metrics=compute:\{debug.compute_count},cutoff_calls:\{debug.cutoff_calls},cache_hits:\{debug.cache_hits},green_verifications:\{debug.green_verifications},memo_count:\{debug.memo_count},direct_trace_length:\{trace_length}"
}

///|
fn print_state(
  operation : String,
  shell : MinimalLambdaProjectionShell,
  read_result : String,
) -> Unit {
  let registry_debug = shell.registry_query.debug()
  let source_map_debug = shell.source_map_query.debug()
  let term_debug = shell.term_query.debug()
  let eval_debug = shell.eval_query.debug()
  let annotation_debug = shell.annotation_query.debug()
  let (commit_id, predecessor_id, trace_count) = commit_metadata(shell)
  println("\n=== \{operation} ===")
  println("snapshot_id=\{shell.current_snapshot_identity}")
  println("projection_commit_id=\{commit_id}")
  println("predecessor_commit_id=\{predecessor_id}")
  println("trace_event_count=\{trace_count}")
  println("batch_depth=\{shell.batch.depth}")
  println("batch_evidence=\{evidence_name(shell.batch.identity_evidence)}")
  println("semantic_outer_batch_count=\{shell.counters.semantic_outer_batch_count}")
  println("hint_consumption_count=\{shell.counters.hint_consumption_count}")
  println("parser_update_count=\{shell.counters.parser_update_count}")
  println(
    "projection_transition_count=\{shell.counters.projection_transition_count}",
  )
  println("registry_compute_count=\{registry_debug.compute_count}")
  println("source_map_compute_count=\{source_map_debug.compute_count}")
  println("term_compute_count=\{term_debug.compute_count}")
  println("eval_compute_count=\{eval_debug.compute_count}")
  println("annotation_compute_count=\{annotation_debug.compute_count}")
  println(query_metrics("registry", shell.registry_query, ()))
  println(query_metrics("source_map", shell.source_map_query, ()))
  println(query_metrics("term", shell.term_query, ()))
  println(query_metrics("eval", shell.eval_query, ()))
  println(query_metrics("annotation", shell.annotation_query, ()))
  println(
    "previous_projection_root_id=\{node_id_name(shell.counters.last_previous_root_id)}",
  )
  println("current_projection_root_id=\{projection_root_name(shell)}")
  println("next_node_id=\{shell.projection_state.next_node_id.val}")
  println("region_close_count=\{shell.counters.region_close_count}")
  println("lifetime_state=\{lifetime_name(shell.lifetime)}")
  println("read_result=\{read_result}")
}

///|
fn current_source(shell : MinimalLambdaProjectionShell) -> String {
  match shell.read_commit() {
    Ok(commit) => commit.parse_snapshot.source
    Err(error) => abort("P1: current commit read failed: " + read_error_name(error))
  }
}

///|
fn has_annotation(
  annotations : Map[@core.NodeId, Array[@protocol.ViewAnnotation]],
  kind : String,
  label : String,
) -> Bool {
  annotations.values().any(entries =>
    entries.any(annotation =>
      annotation.kind == kind && annotation.label == label
    )
  )
}

///| Exercise the production projection-to-protocol annotation consumer.
fn view_has_annotation(
  view : @protocol.ViewNode,
  kind : String,
  label : String,
) -> Bool {
  view.annotations.any(annotation =>
    annotation.kind == kind && annotation.label == label
  ) || view.children.any(child => view_has_annotation(child, kind, label))
}

///| Exercise the production projection-to-protocol annotation consumer.
fn annotation_view(
  shell : MinimalLambdaProjectionShell,
  annotations : Map[@core.NodeId, Array[@protocol.ViewAnnotation]],
) -> @protocol.ViewNode {
  let commit = match shell.read_commit() {
    Ok(value) => value
    Err(error) => abort("P1: annotation consumer commit: " + read_error_name(error))
  }
  let source_map = match shell.read_source_map() {
    Ok(value) => value
    Err(error) => abort("P1: annotation consumer source map: " + read_error_name(error))
  }
  @protocol.proj_to_view_node(
    commit.projection,
    source_map,
    annotations~,
    source_text=Some(commit.parse_snapshot.source),
  )
}

///|
fn run_prototype() -> Unit raise {
  println("minimal no-shadow Lambda annotations P1")
  let shell = MinimalLambdaProjectionShell(INITIAL_SOURCE)

  require(shell.counters.parser_update_count == 1, "initial parse count")
  require(
    shell.counters.projection_transition_count == 1,
    "initial projection transition count",
  )
  require(shell.registry_query.debug().compute_count == 0, "initial registry lazy")
  require(
    shell.source_map_query.debug().compute_count == 0,
    "initial source map lazy",
  )
  require(shell.term_query.debug().compute_count == 0, "initial term lazy")
  require(shell.eval_query.debug().compute_count == 0, "initial eval lazy")
  require(
    shell.annotation_query.debug().compute_count == 0,
    "initial annotations lazy",
  )
  print_state("initial", shell, "not demanded")

  shell.begin_semantic_batch(Invalidated)
  shell.replace_in_batch(12, 13, "-")
  shell.finish_semantic_batch()
  require(current_source(shell) == AFTER_RAW_EDIT, "raw edit source")
  require(shell.counters.parser_update_count == 2, "raw parser update +1")
  require(
    shell.counters.projection_transition_count == 2,
    "raw projection transition +1",
  )
  require(shell.registry_query.debug().compute_count == 0, "raw registry lazy")
  require(
    shell.source_map_query.debug().compute_count == 0,
    "raw source map lazy",
  )
  print_state("raw-edit", shell, "not demanded")

  let rename_target = shell.current_projection_root().id()
  let hints : Map[@core.NodeId, @core.IdentityTransform] = Map([])
  hints[rename_target] = @core.IdentityTransform::RenameLeaf(
    node=rename_target,
  )
  shell.begin_semantic_batch(Valid(hints))
  shell.replace_in_batch(10, 11, "z")
  require(
    shell.counters.projection_transition_count == 2,
    "no projection after intermediate parser snapshot",
  )
  shell.replace_in_batch(1, 2, "z")
  require(
    shell.counters.projection_transition_count == 2,
    "no projection before outer finalizer",
  )
  shell.finish_semantic_batch()
  require(
    current_source(shell) == AFTER_STRUCTURAL_BATCH,
    "structural batch source",
  )
  require(shell.counters.parser_update_count == 4, "structural parser updates +2")
  require(
    shell.counters.projection_transition_count == 3,
    "structural projection transition +1",
  )
  require(shell.counters.hint_consumption_count == 1, "hint consumed once")
  require(
    shell.registry_query.debug().compute_count == 0,
    "structural registry still lazy",
  )
  require(
    shell.source_map_query.debug().compute_count == 0,
    "structural source map still lazy",
  )
  require(
    shell.term_query.debug().compute_count == 0,
    "structural term still lazy",
  )
  require(
    shell.eval_query.debug().compute_count == 0,
    "structural eval still lazy",
  )
  require(
    shell.annotation_query.debug().compute_count == 0,
    "structural annotations still lazy",
  )
  print_state("structural-batch", shell, "2 parser updates -> 1 commit")

  let annotations_first = match shell.read_annotations() {
    Ok(value) => value
    Err(error) => abort("P1: annotation read: " + read_error_name(error))
  }
  let annotations_second = match shell.read_annotations() {
    Ok(value) => value
    Err(error) => abort("P1: repeated annotation read: " + read_error_name(error))
  }
  require(
    has_annotation(annotations_first, "eval", "→ ‹closure›"),
    "Tier-1 closure annotation",
  )
  require(
    has_annotation(annotations_first, "semantic-ref", "bound z"),
    "semantic annotation merged",
  )
  require(annotations_second == annotations_first, "annotation memo value reuse")
  require(shell.eval_query.debug().compute_count == 1, "eval memo reuse")
  require(
    shell.annotation_query.debug().compute_count == 1,
    "annotation memo reuse",
  )
  require(
    shell.source_map_query.debug().compute_count == 1,
    "annotation demand computes source map once",
  )
  require(
    shell.registry_query.debug().compute_count == 0,
    "annotation demand leaves registry lazy",
  )
  require(
    shell.term_query.memo_debug(()).map(memo => memo.trace_length) == Some(1),
    "Term selector direct trace owns only ProjectionCommit dependency",
  )
  require(
    shell.eval_query.memo_debug(()).map(memo => memo.trace_length) == Some(1),
    "Evaluation direct trace owns only Term selector dependency",
  )
  require(
    shell.source_map_query.memo_debug(()).map(memo => memo.trace_length) == Some(1),
    "source-map trace owns only ProjectionCommit dependency",
  )
  require(
    shell.annotation_query.memo_debug(()).map(memo => memo.trace_length) == Some(3),
    "annotation trace owns commit, evaluation, and source-map dependencies",
  )
  let closure_view = annotation_view(shell, annotations_first)
  require(
    view_has_annotation(closure_view, "eval", "→ ‹closure›"),
    "production ViewNode consumer receives closure annotation",
  )
  print_state(
    "demand-annotations",
    shell,
    "entries=\{annotations_first.length()}, repeated=\{annotations_second.length()}",
  )

  let registry_first = match shell.read_registry() {
    Ok(value) => value
    Err(error) => abort("P0: registry read: " + read_error_name(error))
  }
  let registry_second = match shell.read_registry() {
    Ok(value) => value
    Err(error) => abort("P0: repeated registry read: " + read_error_name(error))
  }
  require(shell.registry_query.debug().compute_count == 1, "registry memo reuse")
  require(
    shell.registry_query.debug().cache_hits == 1,
    "registry repeated read is a same-epoch cache hit",
  )
  require(
    shell.registry_query.memo_debug(()).map(memo => memo.trace_length) == Some(1),
    "registry trace owns only ProjectionCommit dependency",
  )
  require(
    shell.source_map_query.debug().compute_count == 1,
    "registry demand does not recompute source map",
  )
  print_state(
    "demand-registry",
    shell,
    "nodes=\{registry_first.length()}, repeated=\{registry_second.length()}",
  )

  let target_id = match find_variable_node_id(
    shell.current_projection_root(),
    "z",
  ) {
    Some(value) => value
    None => abort("P0: expected projected Var(z)")
  }
  let source_map_first = match shell.read_source_map() {
    Ok(value) => value
    Err(error) => abort("P0: source map read: " + read_error_name(error))
  }
  let source_map_second = match shell.read_source_map() {
    Ok(value) => value
    Err(error) => abort("P0: repeated source map read: " + read_error_name(error))
  }
  let commit = match shell.read_commit() {
    Ok(value) => value
    Err(error) => abort("P0: coherent commit read: " + read_error_name(error))
  }
  let range = match source_map_first.get_range(target_id) {
    Some(value) => value
    None => abort("P0: source range missing")
  }
  let repeated_range = source_map_second.get_range(target_id)
  let token_range = match source_map_first.get_token_span(
    target_id,
    @lambda_proj.REFERENCE_NAME_ROLE,
  ) {
    Some(value) => value
    None => abort("P0: reference token range missing")
  }
  let repeated_token_range = source_map_second.get_token_span(
    target_id,
    @lambda_proj.REFERENCE_NAME_ROLE,
  )
  let node_snippet = commit.parse_snapshot.source[range.start:range.end].to_owned()
  let token_snippet = commit.parse_snapshot.source[
    token_range.start:token_range.end
  ].to_owned()
  println(
    "source-range probe: node_id=\{target_id}, node_range=\{range.start}..\{range.end}, node_slice=«\{node_snippet}», token_range=\{token_range.start}..\{token_range.end}, token_slice=«\{token_snippet}»",
  )
  require(token_snippet == "z", "source-range consumer substring")
  require(repeated_range == Some(range), "repeated source-map node range")
  require(
    repeated_token_range == Some(token_range),
    "repeated source-map token range",
  )
  require(
    shell.source_map_query.debug().compute_count == 1,
    "source-map memo reuse",
  )
  require(
    shell.registry_query.debug().compute_count == 1,
    "source-map demand does not recompute registry",
  )
  print_state(
    "demand-source-map",
    shell,
    "node_id=\{target_id}, range=\{token_range.start}..\{token_range.end}, slice=\{token_snippet}",
  )

  shell.begin_semantic_batch(Invalidated)
  shell.replace_in_batch(0, AFTER_STRUCTURAL_BATCH.length(), AFTER_EVALUATION_EDIT)
  shell.finish_semantic_batch()
  require(current_source(shell) == AFTER_EVALUATION_EDIT, "evaluation edit source")
  let application_annotations = match shell.read_annotations() {
    Ok(value) => value
    Err(error) => abort("P1: updated annotation read: " + read_error_name(error))
  }
  require(
    has_annotation(application_annotations, "eval", "→ 3"),
    "updated Tier-1 value annotation",
  )
  require(
    !has_annotation(application_annotations, "eval", "→ ‹closure›"),
    "stale closure annotation absent",
  )
  let application_view = annotation_view(shell, application_annotations)
  require(
    view_has_annotation(application_view, "eval", "→ 3"),
    "production ViewNode consumer receives updated annotation",
  )
  require(shell.counters.parser_update_count == 5, "evaluation parser update +1")
  require(
    shell.counters.projection_transition_count == 4,
    "evaluation projection transition +1",
  )
  require(shell.term_query.debug().compute_count == 2, "term recompute once")
  require(shell.term_query.debug().cutoff_calls == 1, "term cutoff once")
  require(shell.eval_query.debug().compute_count == 2, "eval recompute once")
  require(
    shell.annotation_query.debug().compute_count == 2,
    "annotation recompute once",
  )
  require(
    shell.source_map_query.debug().compute_count == 2,
    "source map recompute once",
  )
  require(
    shell.registry_query.debug().compute_count == 1,
    "evaluation does not recompute undemanded registry",
  )
  require(
    shell.eval_query.debug().green_verifications == 0,
    "P1 has no edit-time green evaluation verification",
  )
  require(
    shell.source_map_query.debug().green_verifications == 0,
    "P1 has no edit-time green source-map verification",
  )
  require(
    shell.annotation_query.debug().green_verifications == 0,
    "P1 has no edit-time green annotation verification",
  )
  print_state("evaluation-edit", shell, "eval=→ 3, ViewNode consumer=pass")

  let term_before_whitespace = match shell.term_query.memo_debug(()) {
    Some(value) => value
    None => abort("P1.2: Term selector memo missing before whitespace edit")
  }
  shell.begin_semantic_batch(Invalidated)
  shell.replace_in_batch(
    AFTER_EVALUATION_EDIT.length(),
    AFTER_EVALUATION_EDIT.length(),
    " ",
  )
  shell.finish_semantic_batch()
  require(current_source(shell) == AFTER_WHITESPACE_EDIT, "whitespace edit source")
  let whitespace_annotations = match shell.read_annotations() {
    Ok(value) => value
    Err(error) => abort("P1.2: whitespace annotation read: " + read_error_name(error))
  }
  require(
    has_annotation(whitespace_annotations, "eval", "→ 3"),
    "whitespace preserves evaluation annotation",
  )
  let term_after_whitespace = match shell.term_query.memo_debug(()) {
    Some(value) => value
    None => abort("P1.2: Term selector memo missing after whitespace edit")
  }
  require(shell.term_query.debug().compute_count == 3, "Term selector recomputes")
  require(shell.term_query.debug().cutoff_calls == 2, "Term Eq cutoff runs")
  require(
    term_after_whitespace.changed_at == term_before_whitespace.changed_at,
    "Term Eq cutoff preserves changed_at",
  )
  require(
    term_after_whitespace.verified_at != term_before_whitespace.verified_at,
    "Term selector verified_at advances",
  )
  require(
    shell.eval_query.debug().compute_count == 2,
    "Evaluation compute is skipped after whitespace edit",
  )
  require(
    shell.eval_query.debug().green_verifications == 1,
    "Evaluation verifies green after Term backdating",
  )
  require(
    shell.source_map_query.debug().compute_count == 3,
    "SourceMap still recomputes for changed snapshot",
  )
  require(
    shell.annotation_query.debug().compute_count == 3,
    "AnnotationMap still recomputes for direct commit dependency",
  )
  require(
    shell.registry_query.debug().compute_count == 1,
    "undemanded Registry still does no edit-time work",
  )
  print_state(
    "whitespace-green-path",
    shell,
    "Term backdated, Evaluation green, eval_compute_delta=0",
  )

  let close_result = shell.close()
  require(close_result == "Closed", "first close result")
  require(shell.counters.region_close_count == 1, "Region close once")
  require(shell.registry_query.debug().memo_count == 0, "close clears Registry memo")
  require(
    shell.source_map_query.debug().memo_count == 0,
    "close clears SourceMap memo",
  )
  require(shell.term_query.debug().memo_count == 0, "close clears Term memo")
  require(shell.eval_query.debug().memo_count == 0, "close clears Evaluation memo")
  require(
    shell.annotation_query.debug().memo_count == 0,
    "close clears AnnotationMap memo",
  )
  require(shell.registry_query.memo_debug(()) is None, "Registry trace released")
  require(
    shell.source_map_query.memo_debug(()) is None,
    "SourceMap trace released",
  )
  require(shell.term_query.memo_debug(()) is None, "Term trace released")
  require(shell.eval_query.memo_debug(()) is None, "Evaluation trace released")
  require(
    shell.annotation_query.memo_debug(()) is None,
    "AnnotationMap trace released",
  )
  print_state("close", shell, close_result)

  let duplicate_result = shell.close()
  require(duplicate_result == "AlreadyClosed", "duplicate close result")
  require(shell.counters.region_close_count == 1, "duplicate close has no effect")
  print_state("duplicate-close", shell, duplicate_result)

  let annotation_compute_before = shell.annotation_query.debug().compute_count
  let term_compute_before = shell.term_query.debug().compute_count
  let eval_compute_before = shell.eval_query.debug().compute_count
  let source_map_compute_before = shell.source_map_query.debug().compute_count
  let post_close = match shell.read_annotations() {
    Ok(_) => "Ok(unexpected)"
    Err(error) => "Err(\{read_error_name(error)})"
  }
  require(post_close == "Err(ClosedRegion)", "post-close read result")
  require(
    shell.annotation_query.debug().compute_count == annotation_compute_before,
    "post-close annotation read does not compute",
  )
  require(
    shell.term_query.debug().compute_count == term_compute_before,
    "post-close annotation read does not select Term",
  )
  require(
    shell.eval_query.debug().compute_count == eval_compute_before,
    "post-close annotation read does not evaluate",
  )
  require(
    shell.source_map_query.debug().compute_count == source_map_compute_before,
    "post-close annotation read does not compute source map",
  )
  print_state("post-close-read", shell, post_close)

  println("\nP1.2 RESULT: PASS WITH CONSTRAINTS")
}

///|
fn main {
  try! run_prototype()
  println("")
  run_p2a_typecheck_evidence()
}
