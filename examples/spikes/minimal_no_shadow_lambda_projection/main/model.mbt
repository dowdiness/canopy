///| The prototype has one synchronous lifetime owner.
enum LifetimeState {
  Alive
  Closed
}

///| Evidence is local to one semantic batch.
enum IdentityEvidence {
  NoEvidence
  Valid(Map[@core.NodeId, @core.IdentityTransform])
  Invalidated
}

///| Stateful projection history stays outside the lazy query store.
struct ProjectionState {
  mut previous_projection : @core.ProjNode[@ast.Term]?
  next_node_id : Ref[Int]
}

///| One coherent publication owns the exact parser result used by projection.
struct ProjectionCommit {
  commit_id : Int
  predecessor_commit_id : Int?
  parse_snapshot : @loom.ParseSnapshot[@ast.Term]
  projection : @core.ProjNode[@ast.Term]
  trace : Array[@core.ReconcileTraceEvent]
}

///| Batch-local state; no cross-batch hint queue exists.
struct SemanticBatchState {
  mut depth : Int
  mut start_snapshot_identity : Int
  mut final_snapshot_identity : Int
  mut identity_evidence : IdentityEvidence
}

///| Observable work counters for the throwaway harness.
struct PrototypeCounters {
  mut semantic_outer_batch_count : Int
  mut hint_consumption_count : Int
  mut parser_update_count : Int
  mut projection_transition_count : Int
  mut region_close_count : Int
  mut last_previous_root_id : @core.NodeId?
}

///| The sole application-level mutable owner in P0.
struct MinimalLambdaProjectionShell {
  mut parser : @lambda.ImperativeParser[@ast.Term]?
  batch : SemanticBatchState
  projection_state : ProjectionState
  counters : PrototypeCounters
  store : @next.Store
  region : @next.Region
  commit_source : @next.Source[ProjectionCommit]
  registry_query : @next.Query[
    Unit,
    Map[@core.NodeId, @core.ProjNode[@ast.Term]],
  ]
  source_map_query : @next.Query[Unit, @core.SourceMap]
  term_query : @next.Query[Unit, @ast.Term]
  eval_query : @next.Query[Unit, Array[@lambda_eval.EvalResult]]
  annotation_query : @next.Query[
    Unit,
    Map[@core.NodeId, Array[@protocol.ViewAnnotation]],
  ]
  mut next_snapshot_identity : Int
  mut current_snapshot_identity : Int
  mut next_commit_id : Int
  mut lifetime : LifetimeState
}

///|
fn evidence_name(evidence : IdentityEvidence) -> String {
  match evidence {
    NoEvidence => "NoEvidence"
    Valid(hints) => "Valid(\{hints.length()} hint(s))"
    Invalidated => "Invalidated"
  }
}

///|
fn node_id_name(id : @core.NodeId?) -> String {
  match id {
    Some(value) => "\{value}"
    None => "none"
  }
}

///|
fn int_option_name(value : Int?) -> String {
  match value {
    Some(n) => n.to_string()
    None => "none"
  }
}

///|
fn must_region(result : Result[@next.Region, @next.RegionError]) -> @next.Region {
  match result {
    Ok(value) => value
    Err(_) => abort("P0: create Region")
  }
}

///|
fn[T] must_source(
  result : Result[@next.Source[T], @next.RegionError],
) -> @next.Source[T] {
  match result {
    Ok(value) => value
    Err(_) => abort("P0: create Source")
  }
}

///|
fn[K, V] must_query(
  result : Result[@next.Query[K, V], @next.RegionError],
) -> @next.Query[K, V] {
  match result {
    Ok(value) => value
    Err(_) => abort("P0: create Query")
  }
}

///| Stateful history transition using the production Lambda projection and core reconciler.
fn ProjectionState::transition(
  self : ProjectionState,
  snapshot : @loom.ParseSnapshot[@ast.Term],
  evidence : IdentityEvidence,
  counters : PrototypeCounters,
  commit_id : Int,
  predecessor_commit_id : Int?,
) -> ProjectionCommit {
  let candidate = @lambda_proj.to_proj_node(
    snapshot.syntax,
    self.next_node_id,
  )
  let trace_ref : Ref[Array[@core.ReconcileTraceEvent]] = Ref([])
  let result = match self.previous_projection {
    Some(previous) => {
      counters.last_previous_root_id = Some(previous.id())
      let hints = match evidence {
        Valid(value) => {
          counters.hint_consumption_count = counters.hint_consumption_count + 1
          value
        }
        NoEvidence | Invalidated => Map([])
      }
      @core.reconcile_hinted(
        previous,
        candidate,
        self.next_node_id,
        hints,
        trace_ref=Some(trace_ref),
      )
    }
    None => {
      counters.last_previous_root_id = None
      candidate
    }
  }
  self.previous_projection = Some(result)
  counters.projection_transition_count = counters.projection_transition_count + 1
  {
    commit_id,
    predecessor_commit_id,
    parse_snapshot: snapshot,
    projection: result,
    trace: trace_ref.val.copy(),
  }
}

///| Construct one parser, one history owner, and one Store/Region read model.
fn MinimalLambdaProjectionShell::MinimalLambdaProjectionShell(
  initial_source : String,
) -> MinimalLambdaProjectionShell raise Failure {
  let parser = @lambda.new_imperative_parser(
    @diagnostic.SourceId::SourceId("minimal-no-shadow-lambda-projection"),
    initial_source,
  )
  let snapshot = parser.parse()
  let projection_state : ProjectionState = {
    previous_projection: None,
    next_node_id: Ref(0),
  }
  let counters : PrototypeCounters = {
    semantic_outer_batch_count: 0,
    hint_consumption_count: 0,
    parser_update_count: 1,
    projection_transition_count: 0,
    region_close_count: 0,
    last_previous_root_id: None,
  }
  let initial_commit = projection_state.transition(
    snapshot,
    NoEvidence,
    counters,
    1,
    None,
  )
  let store = @next.Store()
  let region = must_region(store.region())
  let commit_source = must_source(region.source(initial_commit))
  let commit_view = commit_source.view()
  let registry_query = must_query(region.query((ctx, _ : Unit) => {
    match ctx.read(commit_view) {
      Err(error) => Err(error)
      Ok(commit) => {
        let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = Map([])
        @core.collect_registry(commit.projection, registry)
        Ok(registry)
      }
    }
  }))
  let source_map_query = must_query(region.query((ctx, _ : Unit) => {
    match ctx.read(commit_view) {
      Err(error) => Err(error)
      Ok(commit) => {
        let source_map = @core.SourceMap::from_ast(commit.projection)
        @lambda_proj.populate_token_spans(
          source_map,
          commit.parse_snapshot.syntax,
          commit.projection,
        )
        Ok(source_map)
      }
    }
  }))
  let term_query = must_query(region.query_eq((ctx, _ : Unit) => {
    match ctx.read(commit_view) {
      Err(error) => Err(error)
      Ok(commit) => Ok(commit.projection.kind)
    }
  }))
  let term_view = term_query.at(())
  let eval_query = must_query(region.query((ctx, _ : Unit) => {
    match ctx.read(term_view) {
      Err(error) => Err(error)
      Ok(term) => Ok(@lambda_eval.eval_term(term))
    }
  }))
  let eval_view = eval_query.at(())
  let source_map_view = source_map_query.at(())
  let annotation_query = must_query(region.query((ctx, _ : Unit) => {
    match ctx.read(commit_view) {
      Err(error) => Err(error)
      Ok(commit) => match ctx.read(eval_view) {
        Err(error) => Err(error)
        Ok(eval_results) => match ctx.read(source_map_view) {
          Err(error) => Err(error)
          Ok(source_map) =>
            Ok(
              @lambda_companion.minimal_no_shadow_p1_annotations(
                eval_results,
                commit.projection,
                source_map,
              ),
            )
        }
      }
    }
  }))
  {
    parser: Some(parser),
    batch: {
      depth: 0,
      start_snapshot_identity: 1,
      final_snapshot_identity: 1,
      identity_evidence: NoEvidence,
    },
    projection_state,
    counters,
    store,
    region,
    commit_source,
    registry_query,
    source_map_query,
    term_query,
    eval_query,
    annotation_query,
    next_snapshot_identity: 2,
    current_snapshot_identity: 1,
    next_commit_id: 2,
    lifetime: Alive,
  }
}

///|
fn MinimalLambdaProjectionShell::begin_semantic_batch(
  self : MinimalLambdaProjectionShell,
  evidence : IdentityEvidence,
) -> Unit {
  guard self.lifetime is Alive else { abort("P0: begin after close") }
  guard self.batch.depth == 0 else { abort("P0: nested batch is out of scope") }
  self.batch.depth = 1
  self.batch.start_snapshot_identity = self.current_snapshot_identity
  self.batch.final_snapshot_identity = self.current_snapshot_identity
  self.batch.identity_evidence = evidence
  self.counters.semantic_outer_batch_count = self.counters.semantic_outer_batch_count + 1
}

///| Apply one ASCII fixture replacement to the parser without publishing projection.
fn MinimalLambdaProjectionShell::replace_in_batch(
  self : MinimalLambdaProjectionShell,
  start : Int,
  end : Int,
  replacement : String,
) -> Unit raise Failure {
  guard self.lifetime is Alive else { abort("P0: edit after close") }
  guard self.batch.depth == 1 else { abort("P0: edit outside batch") }
  let parser = match self.parser {
    Some(value) => value
    None => abort("P0: parser payload released")
  }
  let source = parser.get_source()
  let new_source = source[:start].to_owned() +
    replacement +
    source[end:].to_owned()
  ignore(parser.edit(
    @loom_core.Edit::replace(start, end, start + replacement.length()),
    new_source,
  ))
  self.counters.parser_update_count = self.counters.parser_update_count + 1
  self.batch.final_snapshot_identity = self.next_snapshot_identity
  self.next_snapshot_identity = self.next_snapshot_identity + 1
}

///| The outermost finalizer publishes exactly one ProjectionCommit.
fn MinimalLambdaProjectionShell::finish_semantic_batch(
  self : MinimalLambdaProjectionShell,
) -> Unit {
  guard self.lifetime is Alive else { abort("P0: finish after close") }
  guard self.batch.depth == 1 else { abort("P0: no batch to finish") }
  self.batch.depth = 0
  guard self.batch.final_snapshot_identity !=
    self.batch.start_snapshot_identity else { return }
  let parser = match self.parser {
    Some(value) => value
    None => abort("P0: parser payload released")
  }
  let snapshot = match parser.current() {
    Some(value) => value
    None => abort("P0: final parser snapshot missing")
  }
  let predecessor = self.next_commit_id - 1
  let commit = self.projection_state.transition(
    snapshot,
    self.batch.identity_evidence,
    self.counters,
    self.next_commit_id,
    Some(predecessor),
  )
  match self.store.transaction(tx => tx.set(self.commit_source, commit)) {
    Ok(_) => ()
    Err(_) => abort("P0: publish ProjectionCommit")
  }
  self.current_snapshot_identity = self.batch.final_snapshot_identity
  self.next_commit_id = self.next_commit_id + 1
}

///|
fn MinimalLambdaProjectionShell::current_projection_root(
  self : MinimalLambdaProjectionShell,
) -> @core.ProjNode[@ast.Term] {
  match self.projection_state.previous_projection {
    Some(value) => value
    None => abort("P0: projection payload released")
  }
}

///| Use production preorder traversal rather than a new recursive tree walk.
fn find_variable_node_id(
  root : @core.ProjNode[@ast.Term],
  name : String,
) -> @core.NodeId? {
  let found : Ref[@core.NodeId?] = Ref(None)
  root.walk_preorder(node => {
    if found.val is None {
      match node.kind {
        @ast.Term::Var(value) if value == name => found.val = Some(node.id())
        _ => ()
      }
    }
  })
  found.val
}

///|
fn MinimalLambdaProjectionShell::read_registry(
  self : MinimalLambdaProjectionShell,
) -> Result[Map[@core.NodeId, @core.ProjNode[@ast.Term]], @next.ReadError] {
  self.store.read(self.registry_query.at(()))
}

///|
fn MinimalLambdaProjectionShell::read_source_map(
  self : MinimalLambdaProjectionShell,
) -> Result[@core.SourceMap, @next.ReadError] {
  self.store.read(self.source_map_query.at(()))
}

///|
fn MinimalLambdaProjectionShell::read_commit(
  self : MinimalLambdaProjectionShell,
) -> Result[ProjectionCommit, @next.ReadError] {
  self.store.read(self.commit_source.view())
}

///|
fn MinimalLambdaProjectionShell::read_annotations(
  self : MinimalLambdaProjectionShell,
) -> Result[
  Map[@core.NodeId, Array[@protocol.ViewAnnotation]],
  @next.ReadError,
] {
  self.store.read(self.annotation_query.at(()))
}

///| Close only P0-owned provider resources and release parser/history payload.
fn MinimalLambdaProjectionShell::close(
  self : MinimalLambdaProjectionShell,
) -> String {
  match self.lifetime {
    Closed => "AlreadyClosed"
    Alive => match self.region.close() {
      Err(_) => abort("P0: first Region close")
      Ok(_) => {
        self.lifetime = Closed
        self.parser = None
        self.projection_state.previous_projection = None
        self.batch.depth = 0
        self.batch.identity_evidence = NoEvidence
        self.counters.region_close_count = self.counters.region_close_count + 1
        "Closed"
      }
    }
  }
}

///|
fn MinimalLambdaProjectionShell::current_commit_id(
  self : MinimalLambdaProjectionShell,
) -> Int {
  self.next_commit_id - 1
}

///|
fn MinimalLambdaProjectionShell::current_predecessor_id(
  self : MinimalLambdaProjectionShell,
) -> Int? {
  let current = self.current_commit_id()
  if current == 1 { None } else { Some(current - 1) }
}

///|
fn lifetime_name(state : LifetimeState) -> String {
  match state {
    Alive => "Alive"
    Closed => "Closed"
  }
}

///|
fn read_error_name(error : @next.ReadError) -> String {
  match error {
    @next.ReadError::CrossStore(_) => "CrossStore"
    @next.ReadError::ClosedRegion(_) => "ClosedRegion"
    @next.ReadError::ExpiredEvalContext(_) => "ExpiredEvalContext"
    @next.ReadError::ReentrantRootRead(_) => "ReentrantRootRead"
    @next.ReadError::ReadDuringTransaction(_) => "ReadDuringTransaction"
    @next.ReadError::Cycle(_) => "Cycle"
  }
}
