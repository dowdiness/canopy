// P1.4 semantic-changing and mixed release microbenchmarks.
// P1.3's whitespace benchmark is the positive control. This file supplies the
// early mismatch, late mismatch, and 50% semantic-equivalent mixed workloads.

///| The first definition's literal is the first semantic mismatch candidate.
fn cutoff_benchmark_first_literal_position() -> Int {
  "let x0 = ".length()
}

///| The last definition's literal is immediately before newline + body name.
fn cutoff_benchmark_last_literal_position(size : CutoffBenchmarkSize) -> Int {
  let definition_count = cutoff_benchmark_definition_count(size)
  guard definition_count > 1 else { return cutoff_benchmark_first_literal_position() }
  let body = "x\{definition_count - 1}"
  cutoff_benchmark_source(size).length() - body.length() - 2
}

///| Commit one fixture edit and demand the actual AnnotationMap root.
fn cutoff_benchmark_edit_and_read(
  shell : MinimalLambdaProjectionShell,
  start : Int,
  end : Int,
  replacement : String,
) -> Map[@core.NodeId, Array[@protocol.ViewAnnotation]] {
  shell.begin_semantic_batch(Invalidated)
  try! shell.replace_in_batch(start, end, replacement)
  shell.finish_semantic_batch()
  match shell.read_annotations() {
    Ok(value) => value
    Err(error) => abort("P1.4 annotation read: " + read_error_name(error))
  }
}

///| A semantic-changing edit toggles one literal at a fixed early/late position.
fn run_semantic_changing_cutoff_benchmark(
  b : @bench.T,
  size : CutoffBenchmarkSize,
  late : Bool,
  policy : TermSelectorPolicy,
) -> Unit {
  let source = cutoff_benchmark_source(size)
  let shell = try! MinimalLambdaProjectionShell(source, term_selector_policy=policy)
  b.keep(match shell.read_annotations() {
    Ok(value) => value
    Err(error) => abort("P1.4 initial annotation read: " + read_error_name(error))
  })
  let position = if late {
    cutoff_benchmark_last_literal_position(size)
  } else {
    cutoff_benchmark_first_literal_position()
  }
  let original = if late { "1" } else { "0" }
  let changed = if late { "2" } else { "1" }
  guard source[position:position + 1].to_owned() == original else {
    abort("P1.4 semantic edit position")
  }
  let mut changed_state = false
  b.bench(() => {
    let replacement = if changed_state { original } else { changed }
    b.keep(cutoff_benchmark_edit_and_read(shell, position, position + 1, replacement))
    changed_state = !changed_state
  })
  let term = shell.term_query.debug()
  let evaluate = shell.eval_query.debug()
  guard term.compute_count > 1 && evaluate.compute_count > 1 else {
    abort("P1.4 changing edit did not recompute Term and Evaluation")
  }
  guard term.compute_count == evaluate.compute_count else {
    abort("P1.4 changing edit compute counts diverged")
  }
  guard evaluate.green_verifications == 0 else {
    abort("P1.4 changing edit unexpectedly verified Evaluation green")
  }
  match policy {
    AlwaysChanged => ()
    EqCutoff => {
      guard term.cutoff_calls > 0 else {
        abort("P1.4 Eq policy was not invoked")
      }
    }
  }
  ignore(shell.close())
}

///| One timed block has two equivalent whitespace edits and two changing edits.
fn run_mixed_cutoff_benchmark(
  b : @bench.T,
  size : CutoffBenchmarkSize,
  policy : TermSelectorPolicy,
) -> Unit {
  let source = cutoff_benchmark_source(size)
  let shell = try! MinimalLambdaProjectionShell(source, term_selector_policy=policy)
  b.keep(match shell.read_annotations() {
    Ok(value) => value
    Err(error) => abort("P1.4 initial mixed annotation read: " + read_error_name(error))
  })
  let semantic_position = cutoff_benchmark_first_literal_position()
  guard source[semantic_position:semantic_position + 1].to_owned() == "0" else {
    abort("P1.4 mixed semantic edit position")
  }
  b.bench(() => {
    // Equivalent: append whitespace.
    b.keep(cutoff_benchmark_edit_and_read(shell, source.length(), source.length(), " "))
    // Changing: first definition 0 -> 1 while whitespace remains.
    b.keep(cutoff_benchmark_edit_and_read(
      shell,
      semantic_position,
      semantic_position + 1,
      "1",
    ))
    // Equivalent: remove whitespace while semantic value remains changed.
    b.keep(cutoff_benchmark_edit_and_read(
      shell,
      source.length(),
      source.length() + 1,
      "",
    ))
    // Changing: restore first definition 1 -> 0 and the initial source state.
    b.keep(cutoff_benchmark_edit_and_read(
      shell,
      semantic_position,
      semantic_position + 1,
      "0",
    ))
  })
  guard current_source(shell) == source else { abort("P1.4 mixed state restoration") }
  let term = shell.term_query.debug()
  let evaluate = shell.eval_query.debug()
  let term_operations = term.compute_count - 1
  let eval_operations = evaluate.compute_count - 1
  match policy {
    AlwaysChanged => {
      guard term_operations == eval_operations else {
        abort("P1.4 baseline mixed Evaluation count")
      }
      guard evaluate.green_verifications == 0 else {
        abort("P1.4 baseline mixed green verification")
      }
    }
    EqCutoff => {
      guard term_operations == eval_operations * 2 else {
        abort("P1.4 candidate mixed Evaluation count")
      }
      guard evaluate.green_verifications == eval_operations else {
        abort("P1.4 candidate mixed green count")
      }
    }
  }
  ignore(shell.close())
}

///|
test "P1.4 medium/early-changing/always-changed" (b : @bench.T) {
  run_semantic_changing_cutoff_benchmark(b, Medium, false, AlwaysChanged)
}

///|
test "P1.4 medium/early-changing/eq-cutoff" (b : @bench.T) {
  run_semantic_changing_cutoff_benchmark(b, Medium, false, EqCutoff)
}

///|
test "P1.4 medium/late-changing/always-changed" (b : @bench.T) {
  run_semantic_changing_cutoff_benchmark(b, Medium, true, AlwaysChanged)
}

///|
test "P1.4 medium/late-changing/eq-cutoff" (b : @bench.T) {
  run_semantic_changing_cutoff_benchmark(b, Medium, true, EqCutoff)
}

///|
test "P1.4 large/early-changing/always-changed" (b : @bench.T) {
  run_semantic_changing_cutoff_benchmark(b, Large, false, AlwaysChanged)
}

///|
test "P1.4 large/early-changing/eq-cutoff" (b : @bench.T) {
  run_semantic_changing_cutoff_benchmark(b, Large, false, EqCutoff)
}

///|
test "P1.4 large/late-changing/always-changed" (b : @bench.T) {
  run_semantic_changing_cutoff_benchmark(b, Large, true, AlwaysChanged)
}

///|
test "P1.4 large/late-changing/eq-cutoff" (b : @bench.T) {
  run_semantic_changing_cutoff_benchmark(b, Large, true, EqCutoff)
}

///|
test "P1.4 medium/mixed-50/always-changed" (b : @bench.T) {
  run_mixed_cutoff_benchmark(b, Medium, AlwaysChanged)
}

///|
test "P1.4 medium/mixed-50/eq-cutoff" (b : @bench.T) {
  run_mixed_cutoff_benchmark(b, Medium, EqCutoff)
}

///|
test "P1.4 large/mixed-50/always-changed" (b : @bench.T) {
  run_mixed_cutoff_benchmark(b, Large, AlwaysChanged)
}

///|
test "P1.4 large/mixed-50/eq-cutoff" (b : @bench.T) {
  run_mixed_cutoff_benchmark(b, Large, EqCutoff)
}
