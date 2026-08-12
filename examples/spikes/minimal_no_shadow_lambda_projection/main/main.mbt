///|
const INITIAL_SOURCE : String = "(x, y) => x + y"

///|
const AFTER_RAW_EDIT : String = "(x, y) => x - y"

///|
const AFTER_STRUCTURAL_BATCH : String = "(z, y) => z - y"

///|
fn require(condition : Bool, message : String) -> Unit {
  guard condition else { abort("P0 FAIL: " + message) }
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
fn print_state(
  operation : String,
  shell : MinimalLambdaProjectionShell,
  read_result : String,
) -> Unit {
  let registry_debug = shell.registry_query.debug()
  let source_map_debug = shell.source_map_query.debug()
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
    Err(error) => abort("P0: current commit read failed: " + read_error_name(error))
  }
}

///|
fn run_prototype() -> Unit raise {
  println("minimal no-shadow Lambda projection P0")
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
  print_state("structural-batch", shell, "2 parser updates -> 1 commit")

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
    shell.source_map_query.debug().compute_count == 0,
    "registry demand does not compute source map",
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

  let close_result = shell.close()
  require(close_result == "Closed", "first close result")
  require(shell.counters.region_close_count == 1, "Region close once")
  print_state("close", shell, close_result)

  let duplicate_result = shell.close()
  require(duplicate_result == "AlreadyClosed", "duplicate close result")
  require(shell.counters.region_close_count == 1, "duplicate close has no effect")
  print_state("duplicate-close", shell, duplicate_result)

  let compute_before = shell.source_map_query.debug().compute_count
  let post_close = match shell.read_source_map() {
    Ok(_) => "Ok(unexpected)"
    Err(error) => "Err(\{read_error_name(error)})"
  }
  require(post_close == "Err(ClosedRegion)", "post-close read result")
  require(
    shell.source_map_query.debug().compute_count == compute_before,
    "post-close read does not execute provider compute",
  )
  print_state("post-close-read", shell, post_close)

  println("\nP0 RESULT: PASS")
}

///|
fn main {
  try! run_prototype()
}
