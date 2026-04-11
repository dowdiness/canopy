// Benchmark for TreeEditorState::refresh — measures the tree refresh hot path.

///|
fn tree_refresh_bench_source(let_count : Int, tail_literal : String) -> String {
  let segments : Array[String] = []
  for i = 0; i < let_count - 1; i = i + 1 {
    segments.push("let x\{i} = \{i}")
  }
  segments.push("let x\{let_count - 1} = \{tail_literal}")
  segments.push("x\{let_count - 1}")
  segments.join("\n")
}

///|
fn tree_refresh_bench_setup(
  let_count : Int,
) -> (
  TreeEditorState[@ast.Term],
  ProjNode[@ast.Term],
  SourceMap,
  ProjNode[@ast.Term],
  SourceMap,
) raise {
  let source_a = tree_refresh_bench_source(let_count, "0")
  let source_b = tree_refresh_bench_source(let_count, "1")
  let (root_a, _) = @lambda_proj.parse_to_proj_node(source_a)
  let sm_a = SourceMap::from_ast(root_a)
  let state = TreeEditorState::from_projection(Some(root_a), sm_a)
  let (root_b, _) = @lambda_proj.parse_to_proj_node(source_b)
  let reconciled = @core.reconcile(root_a, root_b, Ref::new(1000))
  let sm_b = SourceMap::from_ast(reconciled)
  (state, root_a, sm_a, reconciled, sm_b)
}

// --- Scenario 1: unchanged projection (refresh is a no-op) ---

///|
test "tree refresh unchanged (20 defs)" (b : @bench.T) {
  let (initial_state, root_a, sm_a, _, _) = tree_refresh_bench_setup(20)
  let mut state = initial_state
  b.bench(() => {
    state = state.refresh(Some(root_a), sm_a)
    b.keep(state.tree)
  })
}

///|
test "tree refresh unchanged (80 defs)" (b : @bench.T) {
  let (initial_state, root_a, sm_a, _, _) = tree_refresh_bench_setup(80)
  let mut state = initial_state
  b.bench(() => {
    state = state.refresh(Some(root_a), sm_a)
    b.keep(state.tree)
  })
}

///|
test "tree refresh unchanged (320 defs)" (b : @bench.T) {
  let (initial_state, root_a, sm_a, _, _) = tree_refresh_bench_setup(320)
  let mut state = initial_state
  b.bench(() => {
    state = state.refresh(Some(root_a), sm_a)
    b.keep(state.tree)
  })
}

///|
test "tree refresh unchanged (1000 defs)" (b : @bench.T) {
  let (initial_state, root_a, sm_a, _, _) = tree_refresh_bench_setup(1000)
  let mut state = initial_state
  b.bench(() => {
    state = state.refresh(Some(root_a), sm_a)
    b.keep(state.tree)
  })
}

// --- Scenario 2: 1 def changed out of N ---

///|
test "tree refresh 1 changed (20 defs)" (b : @bench.T) {
  let (initial_state, root_a, sm_a, reconciled_b, sm_b) = tree_refresh_bench_setup(
    20,
  )
  let mut state = initial_state
  let mut use_b = true
  b.bench(() => {
    let (proj, sm) = if use_b { (reconciled_b, sm_b) } else { (root_a, sm_a) }
    state = state.refresh(Some(proj), sm)
    b.keep(state.tree)
    use_b = !use_b
  })
}

///|
test "tree refresh 1 changed (320 defs)" (b : @bench.T) {
  let (initial_state, root_a, sm_a, reconciled_b, sm_b) = tree_refresh_bench_setup(
    320,
  )
  let mut state = initial_state
  let mut use_b = true
  b.bench(() => {
    let (proj, sm) = if use_b { (reconciled_b, sm_b) } else { (root_a, sm_a) }
    state = state.refresh(Some(proj), sm)
    b.keep(state.tree)
    use_b = !use_b
  })
}

///|
test "tree refresh 1 changed (1000 defs)" (b : @bench.T) {
  let (initial_state, root_a, sm_a, reconciled_b, sm_b) = tree_refresh_bench_setup(
    1000,
  )
  let mut state = initial_state
  let mut use_b = true
  b.bench(() => {
    let (proj, sm) = if use_b { (reconciled_b, sm_b) } else { (root_a, sm_a) }
    state = state.refresh(Some(proj), sm)
    b.keep(state.tree)
    use_b = !use_b
  })
}

///|
test "tree refresh 1 changed (80 defs)" (b : @bench.T) {
  let (initial_state, root_a, sm_a, reconciled_b, sm_b) = tree_refresh_bench_setup(
    80,
  )
  let mut state = initial_state
  let mut use_b = true
  b.bench(() => {
    let (proj, sm) = if use_b { (reconciled_b, sm_b) } else { (root_a, sm_a) }
    state = state.refresh(Some(proj), sm)
    b.keep(state.tree)
    use_b = !use_b
  })
}
