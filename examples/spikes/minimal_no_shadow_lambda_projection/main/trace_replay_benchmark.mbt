// P1.5 offline replay of logical edit/demand traces derived from existing
// production Lambda editor integration tests. These are test-derived traces,
// not captured user sessions.

///|
/// A source integration-test operation may publish an edit or be a no-op.
priv enum ReplayOperation {
  NoOp
  Edit(start~ : Int, end~ : Int, replacement~ : String)
}

///|
/// The replay demands either the semantic annotation root or SourceMap only.
priv enum ReplayDemand {
  AnnotationRoot
  SourceMapRoot
}

///|
/// Immutable trace recipe with source-backed provenance documented in P1.5.
priv struct ReplayScenario {
  name : String
  initial_source : String
  final_source : String
  operations : Array[ReplayOperation]
  publications : Int
  demand : ReplayDemand
  semantic_equivalent : Bool
}

///|
/// Counter snapshot from one untimed replay used as a behavioral guard.
priv struct ReplayMetrics {
  parser_updates : Int
  projection_transitions : Int
  initial_nodes : Int
  final_nodes : Int
  term_compute : Int
  term_cutoff_calls : Int
  eval_compute : Int
  eval_green : Int
  source_map_compute : Int
  annotation_compute : Int
}

///|
/// View-update trace from editor_view_decorations_test.mbt.
fn whitespace_view_trace() -> ReplayScenario {
  {
    name: "whitespace-view",
    initial_source: "(x) => x",
    final_source: "(x) => x ",
    operations: [Edit(start=8, end=8, replacement=" ")],
    publications: 1,
    demand: AnnotationRoot,
    semantic_equivalent: true,
  }
}

///|
/// Diagnostic-clear trace from editor_view_decorations_test.mbt.
fn binding_view_trace() -> ReplayScenario {
  {
    name: "binding-view",
    initial_source: "(x) => y",
    final_source: "(x) => x",
    operations: [Edit(start=7, end=8, replacement="x")],
    publications: 1,
    demand: AnnotationRoot,
    semantic_equivalent: false,
  }
}

///|
/// Backspace+insert tail operations from editor_incremental_patch_test.mbt.
fn tail_definition_trace() -> ReplayScenario {
  {
    name: "tail-definition-operations",
    initial_source: "let x = 1\nlet y = 2\nlet z = 0\nz",
    // Cursor length - 3 is before `0`: backspace removes the preceding space,
    // then insertion at the moved cursor produces `90`.
    final_source: "let x = 1\nlet y = 2\nlet z =90\nz",
    operations: [
      Edit(start=27, end=28, replacement=""),
      Edit(start=27, end=27, replacement="9"),
    ],
    publications: 2,
    demand: AnnotationRoot,
    semantic_equivalent: false,
  }
}

///|
/// Four operations with two no-op backspaces and exact SourceMap demand.
fn expression_source_map_trace() -> ReplayScenario {
  {
    name: "expression-source-map-operations",
    initial_source: "42",
    // At cursor zero both backspaces are no-ops; two inserts produce `9942`.
    final_source: "9942",
    operations: [
      NoOp,
      NoOp,
      Edit(start=0, end=0, replacement="9"),
      Edit(start=1, end=1, replacement="9"),
    ],
    publications: 2,
    demand: SourceMapRoot,
    semantic_equivalent: false,
  }
}

///|
/// Count projection nodes through the production preorder traversal.
fn replay_node_count(shell : MinimalLambdaProjectionShell) -> Int {
  let count = Ref(0)
  shell.current_projection_root().walk_preorder(_ => count.val = count.val + 1)
  count.val
}

///|
/// Demand one root and return a small token retained by the benchmark.
fn replay_demand(
  shell : MinimalLambdaProjectionShell,
  demand : ReplayDemand,
) -> Int {
  match demand {
    AnnotationRoot =>
      match shell.read_annotations() {
        Ok(value) => value.length()
        Err(error) => abort("P1.5 annotation read: " + read_error_name(error))
      }
    SourceMapRoot =>
      match shell.read_source_map() {
        Ok(value) => if value.innermost_node_at(0) is Some(_) { 1 } else { 0 }
        Err(error) => abort("P1.5 source-map read: " + read_error_name(error))
      }
  }
}

///|
/// Replay operations in order; only effective edits publish.
fn replay_operations(
  shell : MinimalLambdaProjectionShell,
  scenario : ReplayScenario,
) -> Unit {
  for operation in scenario.operations {
    match operation {
      NoOp => ()
      Edit(start~, end~, replacement~) => {
        shell.begin_semantic_batch(Invalidated)
        try! shell.replace_in_batch(start, end, replacement)
        shell.finish_semantic_batch()
      }
    }
  }
}

///|
/// Timed whole-session replay: construct, initial demand, edits, final demand, close.
fn execute_replay_session(
  scenario : ReplayScenario,
  policy : TermSelectorPolicy,
) -> Int {
  let shell = try! MinimalLambdaProjectionShell(
    scenario.initial_source,
    term_selector_policy=policy,
  )
  let initial = replay_demand(shell, scenario.demand)
  replay_operations(shell, scenario)
  let final_token = replay_demand(shell, scenario.demand)
  guard current_source(shell) == scenario.final_source else {
    abort("P1.5 final source: " + scenario.name)
  }
  ignore(shell.close())
  initial + final_token
}

///|
/// Run once outside timing and retain the work counters needed for interpretation.
fn inspect_replay_session(
  scenario : ReplayScenario,
  policy : TermSelectorPolicy,
) -> ReplayMetrics {
  let shell = try! MinimalLambdaProjectionShell(
    scenario.initial_source,
    term_selector_policy=policy,
  )
  let initial_nodes = replay_node_count(shell)
  ignore(replay_demand(shell, scenario.demand))
  replay_operations(shell, scenario)
  ignore(replay_demand(shell, scenario.demand))
  let final_nodes = replay_node_count(shell)
  guard current_source(shell) == scenario.final_source else {
    abort("P1.5 inspected final source: " + scenario.name)
  }
  let term = shell.term_query.debug()
  let evaluate = shell.eval_query.debug()
  let source_map = shell.source_map_query.debug()
  let annotation = shell.annotation_query.debug()
  let metrics = {
    parser_updates: shell.counters.parser_update_count,
    projection_transitions: shell.counters.projection_transition_count,
    initial_nodes,
    final_nodes,
    term_compute: term.compute_count,
    term_cutoff_calls: term.cutoff_calls,
    eval_compute: evaluate.compute_count,
    eval_green: evaluate.green_verifications,
    source_map_compute: source_map.compute_count,
    annotation_compute: annotation.compute_count,
  }
  ignore(shell.close())
  metrics
}

///|
/// Assert demand-sensitive behavior before emitting one parseable counter line.
fn validate_replay_metrics(
  scenario : ReplayScenario,
  policy : TermSelectorPolicy,
  metrics : ReplayMetrics,
) -> Unit {
  guard metrics.parser_updates == scenario.publications + 1 else {
    abort("P1.5 parser update count: " + scenario.name)
  }
  guard metrics.projection_transitions == scenario.publications + 1 else {
    abort("P1.5 projection transition count: " + scenario.name)
  }
  match scenario.demand {
    SourceMapRoot => {
      guard metrics.source_map_compute == 2 else {
        abort("P1.5 SourceMap demand count: " + scenario.name)
      }
      guard metrics.term_compute == 0 && metrics.eval_compute == 0 &&
        metrics.annotation_compute == 0 && metrics.term_cutoff_calls == 0 else {
        abort("P1.5 undemanded semantic work: " + scenario.name)
      }
    }
    AnnotationRoot => {
      guard metrics.term_compute == 2 && metrics.source_map_compute == 2 &&
        metrics.annotation_compute == 2 else {
        abort("P1.5 annotation demand count: " + scenario.name)
      }
      match policy {
        AlwaysChanged => {
          guard metrics.eval_compute == 2 && metrics.eval_green == 0 else {
            abort("P1.5 baseline Evaluation behavior: " + scenario.name)
          }
        }
        EqCutoff =>
          if scenario.semantic_equivalent {
            guard metrics.eval_compute == 1 && metrics.eval_green == 1 else {
              abort("P1.5 equivalent Evaluation behavior: " + scenario.name)
            }
          } else {
            guard metrics.eval_compute == 2 && metrics.eval_green == 0 else {
              abort("P1.5 changing Evaluation behavior: " + scenario.name)
            }
          }
      }
    }
  }
}

///|
/// Benchmark one whole trace session and print its untimed behavior once.
fn run_trace_replay_benchmark(
  b : @bench.T,
  scenario : ReplayScenario,
  policy : TermSelectorPolicy,
) -> Unit {
  let metrics = inspect_replay_session(scenario, policy)
  validate_replay_metrics(scenario, policy, metrics)
  let policy_name = match policy {
    AlwaysChanged => "always_changed"
    EqCutoff => "eq_cutoff"
  }
  println(
    "P1.5_METRICS scenario=\{scenario.name} policy=\{policy_name} operations=\{scenario.operations.length()} publications=\{scenario.publications} initial_nodes=\{metrics.initial_nodes} final_nodes=\{metrics.final_nodes} parser_updates=\{metrics.parser_updates} projection_transitions=\{metrics.projection_transitions} term_compute=\{metrics.term_compute} cutoff_calls=\{metrics.term_cutoff_calls} eval_compute=\{metrics.eval_compute} eval_green=\{metrics.eval_green} source_map_compute=\{metrics.source_map_compute} annotation_compute=\{metrics.annotation_compute}",
  )
  b.bench(() => b.keep(execute_replay_session(scenario, policy)))
}

///|
test "P1.5 whitespace-view/always-changed" (b : @bench.T) {
  run_trace_replay_benchmark(b, whitespace_view_trace(), AlwaysChanged)
}

///|
test "P1.5 whitespace-view/eq-cutoff" (b : @bench.T) {
  run_trace_replay_benchmark(b, whitespace_view_trace(), EqCutoff)
}

///|
test "P1.5 binding-view/always-changed" (b : @bench.T) {
  run_trace_replay_benchmark(b, binding_view_trace(), AlwaysChanged)
}

///|
test "P1.5 binding-view/eq-cutoff" (b : @bench.T) {
  run_trace_replay_benchmark(b, binding_view_trace(), EqCutoff)
}

///|
test "P1.5 tail-definition-operations/always-changed" (b : @bench.T) {
  run_trace_replay_benchmark(b, tail_definition_trace(), AlwaysChanged)
}

///|
test "P1.5 tail-definition-operations/eq-cutoff" (b : @bench.T) {
  run_trace_replay_benchmark(b, tail_definition_trace(), EqCutoff)
}

///|
test "P1.5 expression-source-map-operations/always-changed" (b : @bench.T) {
  run_trace_replay_benchmark(b, expression_source_map_trace(), AlwaysChanged)
}

///|
test "P1.5 expression-source-map-operations/eq-cutoff" (b : @bench.T) {
  run_trace_replay_benchmark(b, expression_source_map_trace(), EqCutoff)
}
