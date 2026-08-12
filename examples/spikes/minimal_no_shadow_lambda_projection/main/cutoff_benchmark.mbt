// P1.3 release microbenchmarks. The selector policy is the only graph variable.
// Run with:
// NEW_MOON_MOD=0 moon bench --release --target native \
//   -p examples/spikes/minimal_no_shadow_lambda_projection/main \
//   -f cutoff_benchmark.mbt

///| Fixed scenario sizes; the largest remains small enough for repeated setup.
priv enum CutoffBenchmarkSize {
  Small
  Medium
  Large
}

///|
fn cutoff_benchmark_definition_count(size : CutoffBenchmarkSize) -> Int {
  match size {
    Small => 1
    Medium => 32
    Large => 128
  }
}

///| Use a builder because fixture generation is setup outside the timed loop.
fn cutoff_benchmark_source(size : CutoffBenchmarkSize) -> String {
  let definition_count = cutoff_benchmark_definition_count(size)
  let builder = StringBuilder::new()
  builder.write_string("let x0 = 0\n")
  for i = 1; i < definition_count; i = i + 1 {
    builder.write_string("let x")
    builder.write_string(i.to_string())
    builder.write_string(" = x")
    builder.write_string((i - 1).to_string())
    builder.write_string(" + 1\n")
  }
  builder.write_string("x")
  builder.write_string((definition_count - 1).to_string())
  builder.to_string()
}

///| Count real projected nodes through the existing production traversal.
fn cutoff_benchmark_node_count(shell : MinimalLambdaProjectionShell) -> Int {
  let count = Ref(0)
  shell.current_projection_root().walk_preorder(_ => count.val = count.val + 1)
  count.val
}

///| One edit-to-annotation operation; each iteration toggles trailing whitespace.
fn run_cutoff_benchmark(
  b : @bench.T,
  size : CutoffBenchmarkSize,
  policy : TermSelectorPolicy,
) -> Unit {
  let source = cutoff_benchmark_source(size)
  let shell = try! MinimalLambdaProjectionShell(source, term_selector_policy=policy)
  let initial_annotations = match shell.read_annotations() {
    Ok(value) => value
    Err(error) => abort("P1.3 initial annotation read: " + read_error_name(error))
  }
  b.keep(initial_annotations)
  let node_count = cutoff_benchmark_node_count(shell)
  guard node_count == cutoff_benchmark_definition_count(size) * 4 else {
    abort("P1.3 projected node count")
  }
  let mut spaced = false
  b.bench(() => {
    let current_length = current_source(shell).length()
    shell.begin_semantic_batch(Invalidated)
    if spaced {
      try! shell.replace_in_batch(current_length - 1, current_length, "")
    } else {
      try! shell.replace_in_batch(current_length, current_length, " ")
    }
    shell.finish_semantic_batch()
    let annotations = match shell.read_annotations() {
      Ok(value) => value
      Err(error) => abort("P1.3 annotation read: " + read_error_name(error))
    }
    spaced = !spaced
    b.keep(annotations)
  })
  let eval_debug = shell.eval_query.debug()
  let term_debug = shell.term_query.debug()
  guard term_debug.compute_count > 1 else {
    abort("P1.3 selector did not recompute")
  }
  match policy {
    AlwaysChanged => {
      guard eval_debug.compute_count > 1 else {
        abort("P1.3 baseline did not recompute Evaluation")
      }
      guard eval_debug.green_verifications == 0 else {
        abort("P1.3 baseline unexpectedly verified green")
      }
    }
    EqCutoff => {
      guard eval_debug.compute_count == 1 else {
        abort("P1.3 candidate recomputed Evaluation")
      }
      guard eval_debug.green_verifications > 0 else {
        abort("P1.3 candidate did not verify Evaluation green")
      }
    }
  }
  ignore(shell.close())
}

///| Build one independent committed value for component microbenchmarks.
fn cutoff_benchmark_commit(size : CutoffBenchmarkSize) -> ProjectionCommit {
  let shell = try! MinimalLambdaProjectionShell(cutoff_benchmark_source(size))
  let commit = match shell.read_commit() {
    Ok(value) => value
    Err(error) => abort("P1.3 component commit: " + read_error_name(error))
  }
  ignore(shell.close())
  commit
}

///| Build varying operands outside the timed loop to avoid one hot object pair.
fn cutoff_benchmark_commits(size : CutoffBenchmarkSize) -> Array[ProjectionCommit] {
  Array::makei(8, _ => cutoff_benchmark_commit(size))
}

///| Compare structurally equal Terms from independent parser/projection owners.
fn run_term_eq_benchmark(b : @bench.T, size : CutoffBenchmarkSize) -> Unit {
  let left = cutoff_benchmark_commits(size).map(commit => commit.projection.kind)
  let right = cutoff_benchmark_commits(size).map(commit => commit.projection.kind)
  let mut index = 0
  b.bench(() => {
    let i = index % left.length()
    guard left[i] == right[i] else { abort("P1.3 equal Term fixtures") }
    b.keep(true)
    index = index + 1
  })
}

///| Isolate the Tier-1 work skipped by the candidate graph.
fn run_eval_benchmark(b : @bench.T, size : CutoffBenchmarkSize) -> Unit {
  let terms = cutoff_benchmark_commits(size).map(commit => commit.projection.kind)
  let mut index = 0
  b.bench(() => {
    b.keep(@lambda_eval.eval_term(terms[index % terms.length()]))
    index = index + 1
  })
}

///| Measure the source-related work shared by both selector policies.
fn run_source_map_benchmark(b : @bench.T, size : CutoffBenchmarkSize) -> Unit {
  let commits = cutoff_benchmark_commits(size)
  let mut index = 0
  b.bench(() => {
    let commit = commits[index % commits.length()]
    let source_map = @core.SourceMap::from_ast(commit.projection)
    @lambda_proj.populate_token_spans(
      source_map,
      commit.parse_snapshot.syntax,
      commit.projection,
    )
    b.keep(source_map)
    index = index + 1
  })
}

///| Measure pure annotation aggregation after Evaluation and SourceMap exist.
fn run_annotation_map_benchmark(b : @bench.T, size : CutoffBenchmarkSize) -> Unit {
  let fixtures = cutoff_benchmark_commits(size).map(commit => {
    let eval_results = @lambda_eval.eval_term(commit.projection.kind)
    let source_map = @core.SourceMap::from_ast(commit.projection)
    @lambda_proj.populate_token_spans(
      source_map,
      commit.parse_snapshot.syntax,
      commit.projection,
    )
    (commit, eval_results, source_map)
  })
  let mut index = 0
  b.bench(() => {
    let (commit, eval_results, source_map) = fixtures[index % fixtures.length()]
    b.keep(
      @lambda_companion.minimal_no_shadow_p1_annotations(
        eval_results,
        commit.projection,
        source_map,
      ),
    )
    index = index + 1
  })
}

///|
test "P1.3 small/always-changed whitespace edit + annotation read" (b : @bench.T) {
  run_cutoff_benchmark(b, Small, AlwaysChanged)
}

///|
test "P1.3 small/eq-cutoff whitespace edit + annotation read" (b : @bench.T) {
  run_cutoff_benchmark(b, Small, EqCutoff)
}

///|
test "P1.3 medium/eq-cutoff whitespace edit + annotation read" (b : @bench.T) {
  run_cutoff_benchmark(b, Medium, EqCutoff)
}

///|
test "P1.3 medium/always-changed whitespace edit + annotation read" (b : @bench.T) {
  run_cutoff_benchmark(b, Medium, AlwaysChanged)
}

///|
test "P1.3 large/always-changed whitespace edit + annotation read" (b : @bench.T) {
  run_cutoff_benchmark(b, Large, AlwaysChanged)
}

///|
test "P1.3 large/eq-cutoff whitespace edit + annotation read" (b : @bench.T) {
  run_cutoff_benchmark(b, Large, EqCutoff)
}

///|
test "P1.3 small/Term structural Eq" (b : @bench.T) {
  run_term_eq_benchmark(b, Small)
}

///|
test "P1.3 medium/Term structural Eq" (b : @bench.T) {
  run_term_eq_benchmark(b, Medium)
}

///|
test "P1.3 large/Term structural Eq" (b : @bench.T) {
  run_term_eq_benchmark(b, Large)
}

///|
test "P1.3 small/eval_term" (b : @bench.T) {
  run_eval_benchmark(b, Small)
}

///|
test "P1.3 medium/eval_term" (b : @bench.T) {
  run_eval_benchmark(b, Medium)
}

///|
test "P1.3 large/eval_term" (b : @bench.T) {
  run_eval_benchmark(b, Large)
}

///|
test "P1.3 small/SourceMap build" (b : @bench.T) {
  run_source_map_benchmark(b, Small)
}

///|
test "P1.3 medium/SourceMap build" (b : @bench.T) {
  run_source_map_benchmark(b, Medium)
}

///|
test "P1.3 large/SourceMap build" (b : @bench.T) {
  run_source_map_benchmark(b, Large)
}

///|
test "P1.3 small/AnnotationMap aggregate" (b : @bench.T) {
  run_annotation_map_benchmark(b, Small)
}

///|
test "P1.3 medium/AnnotationMap aggregate" (b : @bench.T) {
  run_annotation_map_benchmark(b, Medium)
}

///|
test "P1.3 large/AnnotationMap aggregate" (b : @bench.T) {
  run_annotation_map_benchmark(b, Large)
}
