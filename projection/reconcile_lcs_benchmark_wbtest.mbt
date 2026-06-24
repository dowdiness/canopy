// Isolated microbenchmark for `@core.reconcile_children`'s LCS DP on WIDE
// sibling lists (BAND 2b evidence gate, canopy #443, cliff #2).
//
// core/reconcile.mbt fills an (m+1)×(n+1) DP table unconditionally (the double
// loop never short-circuits), so LCS child matching is O(m×n) by inspection.
// But "O(n²) is bad" is not a profile — at small N with a trivial loop body it
// may still be microseconds. This isolates the actual cost.
//
// IMPORTANT scope note: Lambda's root Module reconcile hook routes the def
// list through duplicate-safe name matching (hash-based, O(N)) and only calls
// `@core.reconcile` per individual def/body subtree (narrow). The wide-sibling
// LCS is reached when `@core.reconcile` runs on a parent that itself has many
// direct children — e.g. a Module node reconciled as a whole (the
// JSON/flat-list projection path), which is what this bench constructs by
// reconciling two N-def Modules directly.

// Source generator: reuses `tree_refresh_bench_source` from
// tree_refresh_benchmark_wbtest.mbt (same projection wbtest module). An N-def
// program projects to a Module ProjNode with N+1 direct children (one init per
// def + the trailing body), giving a wide sibling list for the LCS DP.

///|
fn lcs_setup(n : Int) -> (ProjNode[@ast.Term], ProjNode[@ast.Term]) raise {
  let (root_a, _) = @lambda_proj.parse_to_proj_node(
    tree_refresh_bench_source(n, "0"),
  )
  let (root_b, _) = @lambda_proj.parse_to_proj_node(
    tree_refresh_bench_source(n, "1"),
  )
  (root_a, root_b)
}

///|
test "control: reconcile operates on a wide sibling list" {
  // Pin the wide-sibling width at every benched size: an N-def program must
  // project to a Module with N+1 direct children (N inits + trailing body) so
  // the LCS DP runs on an N+1-wide list. Guards against a future regression in
  // Module construction silently degrading any bench to a degenerate tree.
  let (root_20, _) = lcs_setup(20)
  inspect(root_20.children.length(), content="21")
  let (root_80, _) = lcs_setup(80)
  inspect(root_80.children.length(), content="81")
  let (root_320, _) = lcs_setup(320)
  inspect(root_320.children.length(), content="321")
  let (root_1000, _) = lcs_setup(1000)
  inspect(root_1000.children.length(), content="1001")
}

///|
/// Build the two N-def Module trees once, then time only `@core.reconcile`
/// (which runs the wide-sibling LCS DP over the N+1 direct children).
fn bench_reconcile(b : @bench.T, n : Int) -> Unit raise {
  let (root_a, root_b) = lcs_setup(n)
  b.bench(() => {
    let r = @core.reconcile(root_a, root_b, Ref(1000))
    b.keep(r)
  })
}

///|
test "reconcile wide-siblings (20 defs)" (b : @bench.T) {
  bench_reconcile(b, 20)
}

///|
test "reconcile wide-siblings (80 defs)" (b : @bench.T) {
  bench_reconcile(b, 80)
}

///|
test "reconcile wide-siblings (320 defs)" (b : @bench.T) {
  bench_reconcile(b, 320)
}

///|
test "reconcile wide-siblings (1000 defs)" (b : @bench.T) {
  bench_reconcile(b, 1000)
}
