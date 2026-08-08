// Isolated microbenchmarks for `@core.reconcile` on WIDE sibling lists
// (BAND 2b evidence gate, canopy #443, cliff #2).
//
// Three workloads (Phase 2 of
// docs/plans/2026-08-08-core-reconcile-engine-deepening.md):
//
// 1. Positional fast path — equal-width inputs with the same kind at every
//    position take the exact full-match positional path and skip the O(m×n)
//    LCS table. These inputs model append/leaf-content edits where the
//    sibling structure is unchanged.
// 2. Forced LCS fallback — the same wide lists with one different-kind child
//    spliced mid-list, which rejects the positional shortcut and reaches the
//    quadratic DP table. Models structural edits on wide sibling lists.
// 3. Exact-key — `reconcile_with_exact_key` over the same wide lists:
//    fingerprint maps for both trees plus the weighted suffix DP.
//
// IMPORTANT scope note: Lambda's root Module reconcile hook routes the def
// list through duplicate-safe name matching (hash-based, O(N)) and only calls
// `@core.reconcile` per individual def/body subtree (narrow). The wide-sibling
// path is reached when `@core.reconcile` runs on a parent that itself has many
// direct children — e.g. a Module node reconciled as a whole (the
// JSON/flat-list projection path), which is what these benches construct by
// reconciling two N-def Modules directly.

// Source generator: reuses `tree_refresh_bench_source` from
// tree_refresh_benchmark_wbtest.mbt (same projection wbtest module). An N-def
// program projects to a Module ProjNode with N+1 direct children (one init per
// def + the trailing body), giving a wide sibling list for the LCS DP.

///|
let reconcile_lcs_benchmark_source : @loomcore.SourceId = @loomcore.SourceId(
  "canopy-test:projection-reconcile-lcs-benchmark",
)

///|
fn lcs_setup(n : Int) -> (ProjNode[@ast.Term], ProjNode[@ast.Term]) raise {
  let (root_a, _) = @lambda_proj.parse_to_proj_node(
    reconcile_lcs_benchmark_source,
    tree_refresh_bench_source(n, "0"),
  )
  let (root_b, _) = @lambda_proj.parse_to_proj_node(
    reconcile_lcs_benchmark_source,
    tree_refresh_bench_source(n, "1"),
  )
  (root_a, root_b)
}

///|
/// Same wide lists as `lcs_setup`, but with one different-kind child spliced
/// at the middle of the second tree. The positional fast path requires
/// same-kind at every index, so this setup reaches the LCS DP table.
fn lcs_setup_fallback(
  n : Int,
) -> (ProjNode[@ast.Term], ProjNode[@ast.Term]) raise {
  let (root_a, root_b) = lcs_setup(n)
  let mid = root_b.children.length() / 2
  let new_children : Array[ProjNode[@ast.Term]] = []
  for i, c in root_b.children {
    if i == mid {
      new_children.push(@core.ProjNode(@ast.Term::Int(0), 0, 0, -1, []))
    } else {
      new_children.push(c)
    }
  }
  (
    root_a,
    @core.ProjNode(
      root_b.kind,
      root_b.start,
      root_b.end,
      root_b.node_id,
      new_children,
    ),
  )
}

///|
/// Cheap exact key for the benchmark: variant name only (`kind_tag`).
/// Duplicate defs share a key, so the fingerprint machinery sees realistic
/// same-key siblings while the weighted suffix DP still runs.
fn bench_exact_key(node : @ast.Term) -> String {
  @loomcore.Renderable::kind_tag(node)
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
test "control: fallback workload reaches the LCS DP table" {
  // The spliced Int child cannot match positionally: an Inserted trace event
  // proves the fallback ran (the positional fast path would emit Matched for
  // every child). Also pins that the spliced node gets a fresh id.
  let (root_a, root_b) = lcs_setup_fallback(20)
  let trace = Ref([])
  let result = @core.reconcile(root_a, root_b, Ref(1000), trace_ref=Some(trace))
  let inserted = trace.val
    .filter(ev => ev is @core.ReconcileTraceEvent::Inserted(_, _, _, _))
    .length()
  inspect(inserted >= 1, content="true")
  let mid = result.children.length() / 2
  inspect(result.children[mid].node_id >= 1000, content="true")
}

///|
/// Build the two N-def Module trees once, then time only `@core.reconcile`
/// over the N+1 direct children. The two sources differ only in the final
/// literal, so their sibling kind sequence is positionally identical — the
/// positional fast path.
fn bench_reconcile_fast_path(b : @bench.T, n : Int) -> Unit raise {
  let (root_a, root_b) = lcs_setup(n)
  b.bench(() => {
    let r = @core.reconcile(root_a, root_b, Ref(1000))
    b.keep(r)
  })
}

///|
/// Same wide shape with one different-kind child mid-list — forces the LCS
/// DP table.
fn bench_reconcile_fallback(b : @bench.T, n : Int) -> Unit raise {
  let (root_a, root_b) = lcs_setup_fallback(n)
  b.bench(() => {
    let r = @core.reconcile(root_a, root_b, Ref(1000))
    b.keep(r)
  })
}

///|
/// `reconcile_with_exact_key` on the wide lists: fingerprint maps for both
/// trees plus the weighted suffix DP.
fn bench_reconcile_exact_key(b : @bench.T, n : Int) -> Unit raise {
  let (root_a, root_b) = lcs_setup(n)
  b.bench(() => {
    let r = @core.reconcile_with_exact_key(
      root_a,
      root_b,
      Ref(1000),
      bench_exact_key,
    )
    b.keep(r)
  })
}

///|
test "reconcile positional fast path (20 defs)" (b : @bench.T) {
  bench_reconcile_fast_path(b, 20)
}

///|
test "reconcile positional fast path (80 defs)" (b : @bench.T) {
  bench_reconcile_fast_path(b, 80)
}

///|
test "reconcile positional fast path (320 defs)" (b : @bench.T) {
  bench_reconcile_fast_path(b, 320)
}

///|
test "reconcile positional fast path (1000 defs)" (b : @bench.T) {
  bench_reconcile_fast_path(b, 1000)
}

///|
test "reconcile forced LCS fallback (20 defs)" (b : @bench.T) {
  bench_reconcile_fallback(b, 20)
}

///|
test "reconcile forced LCS fallback (80 defs)" (b : @bench.T) {
  bench_reconcile_fallback(b, 80)
}

///|
test "reconcile forced LCS fallback (320 defs)" (b : @bench.T) {
  bench_reconcile_fallback(b, 320)
}

///|
test "reconcile forced LCS fallback (1000 defs)" (b : @bench.T) {
  bench_reconcile_fallback(b, 1000)
}

///|
test "reconcile exact-key wide siblings (20 defs)" (b : @bench.T) {
  bench_reconcile_exact_key(b, 20)
}

///|
test "reconcile exact-key wide siblings (80 defs)" (b : @bench.T) {
  bench_reconcile_exact_key(b, 80)
}

///|
test "reconcile exact-key wide siblings (320 defs)" (b : @bench.T) {
  bench_reconcile_exact_key(b, 320)
}

///|
test "reconcile exact-key wide siblings (1000 defs)" (b : @bench.T) {
  bench_reconcile_exact_key(b, 1000)
}
