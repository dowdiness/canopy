// P2a Runtime-free whole-module typecheck ownership evidence.
//
// The selected production API is pure at this boundary: convert_from_cst,
// resolve_typed, TypeEnv::bind, and infer. Production diagnostics use a
// current-Incr Accumulator behind private APIs, so this prototype deliberately
// returns no diagnostics and does not claim production ModuleTypeResult parity.

///|
const P2A_INITIAL_SOURCE : String = "let x0 = 0\nlet x1 = x0 + 1\nx1"

///|
const P2A_BODY_SOURCE : String = "let x0 = 0\nlet x1 = x0 + 1\nx1 + 1"

///|
const P2A_STRUCTURAL_SOURCE : String = "let x0 = 0\nlet x1 = x0 + 1\nlet x2 = x1 + 1\nx1 + 1"

///|
/// Reuse production resolution/inference without the current reactive wrapper.
fn p2a_whole_module_typecheck(
  term : @typecheck.TypedTerm,
) -> @typecheck.ModuleTypeResult {
  let resolved = @typecheck.resolve_typed(term)
  // Local mutation only builds the returned prototype-local result.
  let def_types : Array[(String, @typecheck.TypeResult)] = []
  let mut env = @typecheck.TypeEnv::Empty
  for def in resolved.defs {
    let result = try! @typecheck.infer(env, def.1)
    def_types.push((def.0, result))
    env = env.bind(
      def.0,
      if result.had_error {
        @typecheck.Type::TError
      } else {
        result.typ
      },
    )
  }
  let body_type = try! @typecheck.infer(env, resolved.body)
  { body_type, def_types, all_diagnostics: [] }
}

///|
fn p2a_read_typecheck(
  shell : MinimalLambdaProjectionShell,
) -> @typecheck.ModuleTypeResult {
  match shell.read_typecheck() {
    Ok(value) => value
    Err(error) => abort("P2a typecheck read: " + read_error_name(error))
  }
}

///|
fn p2a_require(condition : Bool, message : String) -> Unit {
  guard condition else { abort("P2a FAIL: " + message) }
}

///|
fn p2a_require_clean_int_result(
  result : @typecheck.ModuleTypeResult,
  definition_count : Int,
) -> Unit {
  p2a_require(
    result.body_type == { typ: @typecheck.Type::TInt, had_error: false },
    "body type",
  )
  p2a_require(result.def_types.length() == definition_count, "definition count")
  p2a_require(
    result.def_types.all(pair => {
      pair.1 == { typ: @typecheck.Type::TInt, had_error: false }
    }),
    "definition types",
  )
  p2a_require(result.all_diagnostics.is_empty(), "diagnostics boundary")
}

///|
/// Exercise demand/edit/close behavior and print one observable stage per gate.
fn run_p2a_typecheck_evidence() -> Unit {
  let shell = try! MinimalLambdaProjectionShell(P2A_INITIAL_SOURCE)
  p2a_require(
    shell.typed_term_query.debug().compute_count == 0,
    "initial TypedTerm lazy",
  )
  p2a_require(
    shell.typecheck_query.debug().compute_count == 0,
    "initial typecheck lazy",
  )
  println("P2a initial typed=0 typecheck=0 current_runtime=0")

  let first = p2a_read_typecheck(shell)
  p2a_require_clean_int_result(first, 2)
  p2a_require(
    first.def_types.map(pair => pair.0) == ["x0", "x1"],
    "definition order",
  )
  p2a_require(
    shell.typed_term_query.debug().compute_count == 1,
    "first TypedTerm",
  )
  p2a_require(
    shell.typecheck_query.debug().compute_count == 1,
    "first typecheck",
  )
  p2a_require(
    shell.typed_term_query.memo_debug(()).unwrap().trace_length == 1,
    "TypedTerm direct trace",
  )
  p2a_require(
    shell.typecheck_query.memo_debug(()).unwrap().trace_length == 1,
    "typecheck direct trace",
  )
  println("P2a first-demand typed=1 typecheck=1 defs=2 direct-trace=1/1")

  let repeated = p2a_read_typecheck(shell)
  p2a_require(repeated == first, "repeated value")
  p2a_require(
    shell.typed_term_query.debug().compute_count == 1,
    "repeat TypedTerm memo",
  )
  p2a_require(
    shell.typecheck_query.debug().compute_count == 1,
    "repeat typecheck memo",
  )
  println("P2a repeated-read typed=1 typecheck=1")

  // Body-only edit publishes one new commit but performs no typecheck work yet.
  let body_start = P2A_INITIAL_SOURCE.length() - 2
  shell.begin_semantic_batch(Invalidated)
  try! shell.replace_in_batch(body_start, P2A_INITIAL_SOURCE.length(), "x1 + 1")
  shell.finish_semantic_batch()
  p2a_require(current_source(shell) == P2A_BODY_SOURCE, "body source")
  p2a_require(
    shell.typed_term_query.debug().compute_count == 1,
    "body edit TypedTerm lazy",
  )
  p2a_require(
    shell.typecheck_query.debug().compute_count == 1,
    "body edit typecheck lazy",
  )
  println("P2a body-edit-before-demand typed=1 typecheck=1")

  let body_result = p2a_read_typecheck(shell)
  p2a_require_clean_int_result(body_result, 2)
  p2a_require(
    shell.typed_term_query.debug().compute_count == 2,
    "body TypedTerm",
  )
  p2a_require(
    shell.typecheck_query.debug().compute_count == 2,
    "body typecheck",
  )
  println("P2a body-edit-demand typed=2 typecheck=2 defs=2")

  // Structural definition insertion is also lazy until the next demand.
  shell.begin_semantic_batch(Invalidated)
  try! shell.replace_in_batch(body_start, body_start, "let x2 = x1 + 1\n")
  shell.finish_semantic_batch()
  p2a_require(
    current_source(shell) == P2A_STRUCTURAL_SOURCE,
    "structural source",
  )
  p2a_require(
    shell.typed_term_query.debug().compute_count == 2,
    "structural TypedTerm lazy",
  )
  p2a_require(
    shell.typecheck_query.debug().compute_count == 2,
    "structural typecheck lazy",
  )
  println("P2a structural-edit-before-demand typed=2 typecheck=2")

  let structural_result = p2a_read_typecheck(shell)
  p2a_require_clean_int_result(structural_result, 3)
  p2a_require(
    shell.typed_term_query.debug().compute_count == 3,
    "structural TypedTerm",
  )
  p2a_require(
    shell.typecheck_query.debug().compute_count == 3,
    "structural typecheck",
  )
  println("P2a structural-edit-demand typed=3 typecheck=3 defs=3")

  let before_close_typed = shell.typed_term_query.debug().compute_count
  let before_close_typecheck = shell.typecheck_query.debug().compute_count
  p2a_require(shell.close() == "Closed", "first close")
  p2a_require(
    shell.typed_term_query.debug().memo_count == 0,
    "close TypedTerm memo",
  )
  p2a_require(
    shell.typecheck_query.debug().memo_count == 0,
    "close typecheck memo",
  )
  p2a_require(
    shell.typed_term_query.memo_debug(()) is None,
    "close TypedTerm trace",
  )
  p2a_require(
    shell.typecheck_query.memo_debug(()) is None,
    "close typecheck trace",
  )
  p2a_require(shell.close() == "AlreadyClosed", "duplicate close")
  match shell.read_typecheck() {
    Err(error) =>
      p2a_require(read_error_name(error) == "ClosedRegion", "post-close result")
    Ok(_) => abort("P2a post-close typecheck read succeeded")
  }
  p2a_require(
    shell.typed_term_query.debug().compute_count == before_close_typed,
    "post-close TypedTerm compute",
  )
  p2a_require(
    shell.typecheck_query.debug().compute_count == before_close_typecheck,
    "post-close typecheck compute",
  )
  println(
    "P2a close=Closed duplicate=AlreadyClosed post-close=ClosedRegion compute-delta=0",
  )
  println("P2a RESULT: PASS WITH CONSTRAINTS")
}
