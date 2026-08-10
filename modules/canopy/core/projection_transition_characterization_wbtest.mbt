// White-box characterization oracle for the current projection memo shell.
//
// The syntax/reconcile/populate callback types are non-raising; only terminal
// abort defects are possible at those seams. No post-failure state or retry is
// externally observable in the current process. The registry has no fallible
// seam, and parser `Failure` quarantine is a separate upstream path. Therefore
// failure rollback/counter-gap/retry rows are `not applicable to current
// projection callback contract`, not proven behavior.

///|
struct ProjectionOracleLog {
  phases : Array[String]
  entries : Array[String]
}

///|
fn ProjectionOracleLog::ProjectionOracleLog() -> ProjectionOracleLog {
  { phases: [], entries: [] }
}

///|
fn ProjectionOracleLog::record(
  self : ProjectionOracleLog,
  phase : String,
  detail : String,
) -> Unit {
  self.phases.push(phase)
  self.entries.push(phase + ":" + detail)
}

///|
fn ProjectionOracleLog::count_entry(
  self : ProjectionOracleLog,
  entry : String,
) -> Int {
  self.entries.count(entry)
}

///|
fn oracle_syntax(text : String) -> @seam.SyntaxNode {
  let cst = try! @seam.CstNode::new_unclassified(@seam.RawKind(0), [
    @seam.CstElement::Token(@seam.CstToken::CstToken(@seam.RawKind(0), text)),
  ])
  @seam.SyntaxNode::from_cst(cst)
}

///|
fn oracle_trace_event_kind(event : ReconcileTraceEvent) -> String {
  match event {
    Matched(_, _, _, _, _) => "Matched"
    Inserted(_, _, _, _) => "Inserted"
    Deleted(_, _, _, _) => "Deleted"
    Wrapped(_, _, _) => "Wrapped"
    Unwrapped(_, _, _) => "Unwrapped"
    Renamed(_, _) => "Renamed"
    Freshened(_, _, _, _) => "Freshened"
  }
}

///|
fn oracle_trace_signature(events : Array[ReconcileTraceEvent]) -> String {
  events.map(oracle_trace_event_kind).join(",")
}

///|
fn oracle_hint_kind(hint : IdentityTransform) -> String {
  match hint {
    Wrap(inner~) => "Wrap(" + inner.to_string() + ")"
    Unwrap(wrapper~, keep~) =>
      "Unwrap(" + wrapper.to_string() + "," + keep.to_string() + ")"
    Move(subtree~) => "Move(" + subtree.to_string() + ")"
    Replace(old~) => "Replace(" + old.to_string() + ")"
    RenameLeaf(node~) => "RenameLeaf(" + node.to_string() + ")"
    InsertSubtree(parent~, index~) =>
      "InsertSubtree(" + parent.to_string() + "," + index.to_string() + ")"
    DeleteSubtree(node~) => "DeleteSubtree(" + node.to_string() + ")"
    Opaque => "Opaque"
  }
}

///|
fn oracle_hint_signature(hints : Array[IdentityTransform]) -> String {
  hints.map(oracle_hint_kind).join(",")
}

///|
// The reconciler receives a NodeId-keyed map. This fixture only needs the
// structural variants whose key is explicit in the transform; the map is an
// observation adapter, not a production hint policy.
fn oracle_hints_map(
  hints : Array[IdentityTransform],
) -> Map[NodeId, IdentityTransform] {
  let result : Map[NodeId, IdentityTransform] = Map([])
  for hint in hints {
    match hint {
      Wrap(inner~) => result[inner] = Wrap(inner~)
      Unwrap(wrapper~, keep~) => result[wrapper] = Unwrap(wrapper~, keep~)
      Move(subtree~) => result[subtree] = Move(subtree~)
      Replace(old~) => result[old] = Replace(old~)
      RenameLeaf(node~) => result[node] = RenameLeaf(node~)
      DeleteSubtree(node~) => result[node] = DeleteSubtree(node~)
      InsertSubtree(..) | Opaque => ()
    }
  }
  result
}

///|
fn oracle_leaf(
  label : String,
  syntax : @seam.SyntaxNode,
  counter : Ref[Int],
) -> ProjNode[TestExpr] {
  ProjNode::leaf(Leaf(label), syntax, counter)
}

///|
fn oracle_branch(
  label : String,
  children : Array[ProjNode[TestExpr]],
  syntax : @seam.SyntaxNode,
  counter : Ref[Int],
) -> ProjNode[TestExpr] {
  let kinds = children.map(child => child.kind)
  ProjNode::branch(
    Branch(label, kinds),
    syntax.start(),
    syntax.end(),
    children,
    counter,
  )
}

///|
// The labels select deterministic tree shapes. The shape changes deliberately
// use constructor changes and an insertion so reconciliation emits a useful
// depth-first trace without pinning exact allocator values.
fn oracle_projection_shape(
  source : String,
  syntax : @seam.SyntaxNode,
  counter : Ref[Int],
) -> ProjNode[TestExpr] {
  let a = oracle_leaf("a", syntax, counter)
  let c = oracle_leaf("c", syntax, counter)
  let b = oracle_branch("b", [c], syntax, counter)
  match source {
    "wrapped" => {
      let wrapped_leaf = oracle_leaf("a", syntax, counter)
      let wrapper = oracle_branch("w", [wrapped_leaf], syntax, counter)
      oracle_branch("root", [wrapper, b], syntax, counter)
    }
    "reconciled" => {
      let d = oracle_leaf("d", syntax, counter)
      oracle_branch("root", [a, d, b], syntax, counter)
    }
    "source-map-next" => {
      let d = oracle_leaf("d", syntax, counter)
      oracle_branch("root", [a, b, d], syntax, counter)
    }
    _ => oracle_branch("root", [a, b], syntax, counter)
  }
}

///|
struct ProjectionOracleCallbacks {
  syntax_to_proj : (@seam.SyntaxNode, Ref[Int]) -> ProjNode[TestExpr]
  populate_spans : (SourceMap, @seam.SyntaxNode, ProjNode[TestExpr]) -> Unit
  reconcile_node : (
    ProjNode[TestExpr],
    ProjNode[TestExpr],
    Ref[Int],
    Array[IdentityTransform],
    Ref[Array[ReconcileTraceEvent]]?,
  ) -> ProjNode[TestExpr]
}

///|
fn make_oracle_callbacks(
  log : ProjectionOracleLog,
  trace : Ref[Array[ReconcileTraceEvent]],
  last_counter : Ref[Int],
  last_old : Ref[ProjNode[TestExpr]?],
) -> ProjectionOracleCallbacks {
  let syntax_to_proj = fn(
    syntax : @seam.SyntaxNode,
    counter : Ref[Int],
  ) -> ProjNode[TestExpr] {
    log.record(
      "syntax",
      "before=" +
      counter.val.to_string() +
      ":trace=" +
      oracle_trace_signature(trace.val) +
      ":text=" +
      syntax.text(),
    )
    let result = oracle_projection_shape(syntax.text(), syntax, counter)
    last_counter.val = counter.val
    log.record("syntax", "after=" + counter.val.to_string())
    result
  }
  let populate_spans = fn(
    _source_map : SourceMap,
    syntax : @seam.SyntaxNode,
    root : ProjNode[TestExpr],
  ) -> Unit {
    log.record(
      "populate",
      "nodes=" +
      root
      .fold((_, children) => {
        1 + children.fold(init=0, (total, count) => total + count)
      })
      .to_string() +
      ":text=" +
      syntax.text(),
    )
  }
  let reconcile_node = fn(
    old : ProjNode[TestExpr],
    new_ : ProjNode[TestExpr],
    counter : Ref[Int],
    hints : Array[IdentityTransform],
    trace_ref : Ref[Array[ReconcileTraceEvent]]?,
  ) -> ProjNode[TestExpr] {
    last_old.val = Some(old)
    log.record(
      "reconcile",
      "before=" +
      counter.val.to_string() +
      ":hints=" +
      oracle_hint_signature(hints),
    )
    let result = reconcile_hinted(
      old,
      new_,
      counter,
      oracle_hints_map(hints),
      trace_ref~,
    )
    last_counter.val = counter.val
    log.record(
      "reconcile",
      "after=" +
      counter.val.to_string() +
      ":trace=" +
      oracle_trace_signature(trace.val),
    )
    result
  }
  { syntax_to_proj, populate_spans, reconcile_node }
}

///|
fn oracle_projection_signature(root : ProjNode[TestExpr]?) -> String {
  match root {
    None => "None"
    Some(root) => {
      let nodes : Array[String] = []
      root.walk_preorder(node => {
        nodes.push(
          @loomcore.Renderable::kind_tag(node.kind) +
          "@" +
          node.id().to_string() +
          "[" +
          node.start.to_string() +
          ".." +
          node.end.to_string() +
          "]",
        )
      })
      nodes.join(";")
    }
  }
}

///|
fn oracle_registry_signature(
  registry : Map[NodeId, ProjNode[TestExpr]],
) -> String {
  let pairs = registry.to_array()
  pairs.sort_by((left, right) => left.0.compare(right.0))
  pairs.map(pair => pair.0.to_string()).join(",")
}

///|
// This ID-only signature is a white-box consistency check for the registry
// memo; it does not make the scheduler's evaluation order a public contract.
fn oracle_projection_id_signature(root : ProjNode[TestExpr]) -> String {
  let ids : Array[NodeId] = []
  root.walk_preorder(node => ids.push(node.id()))
  ids.sort_by((left, right) => left.compare(right))
  ids.map(id => id.to_string()).join(",")
}

///|
fn oracle_source_map_signature(
  root : ProjNode[TestExpr]?,
  source_map : SourceMap,
) -> String {
  match root {
    None => "None"
    Some(root) => {
      let ranges : Array[String] = []
      root.walk_preorder(node => {
        let range = match source_map.get_range(node.id()) {
          Some(range) => range.start.to_string() + ".." + range.end.to_string()
          None => "missing"
        }
        ranges.push(node.id().to_string() + "=" + range)
      })
      ranges.join(";")
    }
  }
}

///|
struct ProjectionObservation {
  parse_revision : String
  projection : String
  registry : String
  source_map : String
  counter : Int
  trace : String
  pending : String
  projection_compute_count : Int
  registry_compute_count : Int
  source_map_compute_count : Int
}

///|
fn ProjectionObservation::signature(self : ProjectionObservation) -> String {
  "parse=" +
  self.parse_revision +
  "|projection=" +
  self.projection +
  "|registry=" +
  self.registry +
  "|source_map=" +
  self.source_map +
  "|counter=" +
  self.counter.to_string() +
  "|trace=" +
  self.trace +
  "|pending=" +
  self.pending +
  "|computes=" +
  self.projection_compute_count.to_string() +
  "," +
  self.registry_compute_count.to_string() +
  "," +
  self.source_map_compute_count.to_string()
}

///|
struct RealBuilderFixture {
  syntax_input : @incr.Input[@seam.SyntaxNode]
  syntax_tree : @incr.Derived[@seam.SyntaxNode]
  proj_memo : @incr.Derived[ProjNode[TestExpr]?]
  registry_memo : @incr.Derived[Map[NodeId, ProjNode[TestExpr]]]
  source_map_memo : @incr.Derived[SourceMap]
  pending : Ref[Array[IdentityTransform]]
  trace : Ref[Array[ReconcileTraceEvent]]
  last_counter : Ref[Int]
  last_old : Ref[ProjNode[TestExpr]?]
  log : ProjectionOracleLog
  take_count : Ref[Int]
}

///|
fn make_real_builder_fixture() -> RealBuilderFixture {
  let runtime = @incr.Runtime()
  let syntax_input = @incr.Input::Input(runtime, oracle_syntax("initial"))
  let syntax_tree = @incr.Derived::Derived(
    runtime,
    fn() { syntax_input.get() },
    label="oracle_syntax",
  )
  let pending : Ref[Array[IdentityTransform]] = Ref([])
  let trace : Ref[Array[ReconcileTraceEvent]] = Ref([])
  let last_counter = Ref(0)
  let last_old : Ref[ProjNode[TestExpr]?] = Ref(None)
  let log = ProjectionOracleLog()
  let take_count = Ref(0)
  let consumer = IdentityHintConsumer::IdentityHintConsumer(fn() {
    take_count.val = take_count.val + 1
    let batch = pending.val.copy()
    pending.val.clear()
    log.record(
      "take",
      "trace=" +
      oracle_trace_signature(trace.val) +
      ":hints=" +
      oracle_hint_signature(batch),
    )
    batch
  })
  let callbacks = make_oracle_callbacks(log, trace, last_counter, last_old)
  let (proj_memo, registry_memo, source_map_memo) = build_projection_memos_with_identity_hints(
    runtime,
    syntax_tree,
    callbacks.syntax_to_proj,
    callbacks.populate_spans,
    callbacks.reconcile_node,
    identity_hints=consumer,
    trace_ref=Some(trace),
    label="oracle",
  )
  try! runtime.on_derived_event(event => {
    match event {
      @incr.DerivedEvent::Completed(completed) =>
        match runtime.cell_info(completed.cell_id) {
          Some(info) =>
            match info.label {
              Some(label) => log.record("compute", label)
              None => ()
            }
          None => ()
        }
      _ => ()
    }
  })
  {
    syntax_input,
    syntax_tree,
    proj_memo,
    registry_memo,
    source_map_memo,
    pending,
    trace,
    last_counter,
    last_old,
    log,
    take_count,
  }
}

///|
fn observe_real_builder(
  fixture : RealBuilderFixture,
  root : ProjNode[TestExpr]?,
  registry : Map[NodeId, ProjNode[TestExpr]],
  source_map : SourceMap,
) -> ProjectionObservation {
  {
    parse_revision: @debug.to_string(fixture.syntax_tree.verified_at()),
    projection: oracle_projection_signature(root),
    registry: oracle_registry_signature(registry),
    source_map: oracle_source_map_signature(root, source_map),
    counter: fixture.last_counter.val,
    trace: oracle_trace_signature(fixture.trace.val),
    pending: oracle_hint_signature(fixture.pending.val),
    projection_compute_count: fixture.log.phases.count("syntax"),
    registry_compute_count: fixture.log.count_entry("compute:oracle_registry"),
    source_map_compute_count: fixture.log.count_entry(
      "compute:oracle_source_map",
    ),
  }
}

///|
fn assert_contains_entry(
  log : ProjectionOracleLog,
  entry : String,
) -> Unit raise {
  guard log.entries.contains(entry) else {
    fail("missing observation entry: " + entry)
  }
}

///|
test "projection transition oracle: real builder success, callback order, and consume-once reads" {
  let fixture = make_real_builder_fixture()
  let initial = fixture.proj_memo.read_or_abort().unwrap()
  let initial_projection = oracle_projection_signature(Some(initial))
  guard initial_projection.length() > 0 else {
    fail("initial projection signature must be populated")
  }
  let initial_registry = fixture.registry_memo.read_or_abort()
  @debug.assert_eq(
    oracle_projection_id_signature(initial),
    oracle_registry_signature(initial_registry),
  )
  let initial_source_map = fixture.source_map_memo.read_or_abort()
  let initial_source_map_signature = oracle_source_map_signature(
    Some(initial),
    initial_source_map,
  )
  guard initial_source_map_signature.contains("missing") == false else {
    fail("initial source-map signature must cover the projection")
  }
  @debug.assert_eq(initial_registry.length(), 4)
  @debug.assert_eq(initial_source_map.node_count(), 4)
  assert_contains_entry(fixture.log, "syntax:before=0:trace=:text=initial")
  @debug.assert_eq(fixture.take_count.val, 0)
  let initial_observation = observe_real_builder(
    fixture,
    Some(initial),
    initial_registry,
    initial_source_map,
  )
  fixture.log.record("observation", initial_observation.signature())

  // This exercises callback state, not a scheduler-order compatibility
  // contract. The old trace is visible during syntax conversion and allocator
  // work; the production shell clears it before the consumer drains hints.
  let wrapped_inner = initial.children[0].id()
  let counter_before_transition = fixture.last_counter.val
  fixture.trace.val = [Freshened(initial.id(), 0, initial.id(), "sentinel")]
  fixture.pending.val.push(Wrap(inner=wrapped_inner))
  fixture.syntax_input.force_set(oracle_syntax("wrapped"))
  let pending_before_demand = fixture.pending.val.copy()
  @debug.assert_eq(pending_before_demand.length(), 1)

  let reconciled = fixture.proj_memo.read_or_abort().unwrap()
  let syntax_before_entry = "syntax:before=" +
    counter_before_transition.to_string() +
    ":trace=Freshened:text=wrapped"
  assert_contains_entry(fixture.log, syntax_before_entry)
  guard fixture.log.entries.any(entry => {
    entry == "take:trace=:hints=Wrap(" + wrapped_inner.to_string() + ")"
  }) else {
    fail("take_pending must observe a cleared trace and the owned hint batch")
  }
  match
    (
      fixture.log.entries.search_by(entry => entry == syntax_before_entry),
      fixture.log.entries.search_by(entry => {
        entry == "take:trace=:hints=Wrap(" + wrapped_inner.to_string() + ")"
      }),
    ) {
    (Some(syntax_index), Some(take_index)) =>
      if syntax_index < take_index {
        ()
      } else {
        fail("syntax conversion must precede hint consumption")
      }
    _ => fail("missing callback order observations")
  }
  guard fixture.last_counter.val > counter_before_transition else {
    fail("syntax conversion must advance the projection allocator")
  }
  match fixture.last_old.val {
    Some(old) => @debug.assert_eq(old.id(), initial.id())
    None => fail("reconcile must receive the previous projection")
  }
  guard fixture.log.entries.any(entry => {
    entry.contains(":hints=Wrap(" + wrapped_inner.to_string() + ")")
  }) else {
    fail("reconcile must receive the owned hint batch")
  }
  @debug.assert_eq(fixture.take_count.val, 1)
  @debug.assert_eq(fixture.pending.val.is_empty(), true)
  guard fixture.trace.val.length() > 0 else {
    fail("reconcile trace should contain the successful hint realization")
  }
  guard fixture.trace.val[0] is Wrapped(_, _, _) else {
    fail("first trace event should be Wrapped")
  }
  let reconciled_projection = oracle_projection_signature(Some(reconciled))
  guard initial_projection != reconciled_projection else {
    fail("structural update must publish a changed projection signature")
  }

  // A same-revision read is a memo cache hit: no callback, allocator movement,
  // or second consumer drain. Completed-event labels are only white-box cell
  // evidence here, not a scheduler-order claim.
  let callback_log_length = fixture.log.phases.length()
  let projection_compute_count = fixture.log.count_entry("compute:oracle_proj")
  let counter_after_first = fixture.last_counter.val
  let second = fixture.proj_memo.read_or_abort().unwrap()
  @debug.assert_eq(
    oracle_projection_signature(Some(second)),
    reconciled_projection,
  )
  @debug.assert_eq(fixture.take_count.val, 1)
  @debug.assert_eq(fixture.last_counter.val, counter_after_first)
  @debug.assert_eq(fixture.log.phases.length(), callback_log_length)
  @debug.assert_eq(
    fixture.log.count_entry("compute:oracle_proj"),
    projection_compute_count,
  )

  let final_registry = fixture.registry_memo.read_or_abort()
  @debug.assert_eq(
    oracle_projection_id_signature(second),
    oracle_registry_signature(final_registry),
  )
  let final_source_map = fixture.source_map_memo.read_or_abort()
  let final_source_map_signature = oracle_source_map_signature(
    Some(second),
    final_source_map,
  )
  guard final_source_map_signature.contains("missing") == false else {
    fail("final source-map signature must cover the projection")
  }
  @debug.assert_eq(final_registry.length(), final_source_map.node_count())
  let final_observation = observe_real_builder(
    fixture,
    Some(second),
    final_registry,
    final_source_map,
  )
  fixture.log.record("observation", final_observation.signature())
  guard final_observation.registry.length() > 0 else {
    fail("registry signature must be populated")
  }
  guard final_observation.source_map.length() > 0 else {
    fail("source-map signature must be populated")
  }
}

///|
test "projection transition oracle (white-box cells): direct source-map demand computes projection and source-map only" {
  let fixture = make_real_builder_fixture()
  let source_map = fixture.source_map_memo.read_or_abort()

  // Completed-event labels identify the existing Derived cells that computed;
  // they are white-box demand evidence, not a scheduler-order contract.
  guard fixture.log.count_entry("compute:oracle_proj") > 0 else {
    fail("direct source-map demand must compute projection")
  }
  guard fixture.log.count_entry("compute:oracle_source_map") > 0 else {
    fail("direct source-map demand must compute source-map")
  }
  @debug.assert_eq(fixture.log.count_entry("compute:oracle_registry"), 0)

  let root = fixture.proj_memo.read_or_abort().unwrap()
  guard oracle_projection_signature(Some(root)).length() > 0 else {
    fail("direct source-map demand must publish a projection signature")
  }
  guard oracle_source_map_signature(Some(root), source_map).contains("missing") ==
    false else {
    fail("direct source-map demand must populate every projected range")
  }
}

///|
test "projection transition oracle (white-box cells): direct registry demand computes projection and registry only" {
  let fixture = make_real_builder_fixture()
  let registry = fixture.registry_memo.read_or_abort()

  // These labels are explicit implementation evidence for the two demanded
  // Derived cells. The test intentionally makes no scheduler-order claim.
  guard fixture.log.count_entry("compute:oracle_proj") > 0 else {
    fail("direct registry demand must compute projection")
  }
  guard fixture.log.count_entry("compute:oracle_registry") > 0 else {
    fail("direct registry demand must compute registry")
  }
  @debug.assert_eq(fixture.log.count_entry("compute:oracle_source_map"), 0)

  let root = fixture.proj_memo.read_or_abort().unwrap()
  guard oracle_projection_signature(Some(root)).length() > 0 else {
    fail("direct registry demand must publish a projection signature")
  }
  @debug.assert_eq(
    oracle_projection_id_signature(root),
    oracle_registry_signature(registry),
  )
}
