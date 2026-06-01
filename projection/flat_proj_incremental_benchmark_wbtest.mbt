// Isolated microbenchmark for `@lambda_proj.to_flat_proj_incremental`
// change-detection scan (BAND 2b evidence gate, canopy #443).
//
// Why this exists: the 2026-04-06 pipeline-decomposition doc ESTIMATED this
// function at ~5 ms / ~60% of an 8.5 ms 1000-def keystroke. That figure is
// doubly stale:
//   (a) it was derived by subtraction ("Estimated cost"), never measured in
//       isolation; and
//   (b) it described an O(N) scan checking `physical_equal()` on CstNode
//       pointers — that algorithm no longer exists. flat_proj.mbt:83-84 now
//       compares `new_child.start() == old_child.start()` plus *structural*
//       `cst_node() == cst_node()` equality.
// This file reproduces-or-rejects the cliff by isolating the current scan.
//
// Three scenarios, each at 20/80/320/1000 defs:
//   - unchanged : old and new parsed from identical source. Every comparison
//                 runs to completion and succeeds → pure change-DETECTION cost
//                 (no rebuild, no reconcile; `any_changed` stays false).
//   - tail      : only the last def's value changes (same width, no offset
//                 shift). N-1 reused, 1 rebuilt + reconciled — realistic
//                 single-line keystroke at the bottom of the document.
//   - shifted   : a leading space shifts every def's start offset. The cheap
//                 start() check fails first (short-circuiting the structural
//                 compare), so reuse is fully blocked and every def is rebuilt
//                 + reconciled — the worst case for change propagation.

///|
fn fp_parse_syntax(text : String) -> @seam.SyntaxNode raise {
  let (cst, _) = @parser.parse_cst(text) catch { _ => fail("parse failed") }
  @seam.SyntaxNode::from_cst(cst)
}

// Source generator: reuses `tree_refresh_bench_source(let_count, tail_literal)`
// from tree_refresh_benchmark_wbtest.mbt (same projection wbtest module). It
// emits `let x0 = 0 ... let x{N-1} = {tail}` then the final expr `x{N-1}`, so a
// caller can flip exactly one same-width literal without shifting any offsets.

///|
/// Build (new_root, old_root, old_fp) for a scenario. `old_fp` is the FlatProj
/// of the old tree (the state carried between keystrokes); the bench then runs
/// only the incremental scan against it.
fn fp_incr_setup(
  old_src : String,
  new_src : String,
) -> (@seam.SyntaxNode, @seam.SyntaxNode, @lambda_proj.FlatProj) raise {
  let old_root = fp_parse_syntax(old_src)
  let old_fp = @lambda_proj.to_flat_proj(old_root, Ref(0))
  let new_root = fp_parse_syntax(new_src)
  (new_root, old_root, old_fp)
}

// --- Positive controls: confirm each scenario exercises the intended path ---
// (Calibrate the detector before trusting timing — guards against measuring a
//  vacuous no-op. `changed_indices` records every def that was NOT reused.)

///|
test "control: unchanged scenario reuses all defs (zero changed)" {
  let (new_root, old_root, old_fp) = fp_incr_setup(
    tree_refresh_bench_source(80, "0"),
    tree_refresh_bench_source(80, "0"),
  )
  let changed = Ref(([] : Array[Int]))
  let _ = @lambda_proj.to_flat_proj_incremental(
    new_root,
    old_root,
    old_fp,
    Ref(1000),
    changed_indices=changed,
  )
  inspect(changed.val.length(), content="0")
}

///|
test "control: tail scenario rebuilds exactly one def" {
  let (new_root, old_root, old_fp) = fp_incr_setup(
    tree_refresh_bench_source(80, "0"),
    tree_refresh_bench_source(80, "1"),
  )
  let changed = Ref(([] : Array[Int]))
  let _ = @lambda_proj.to_flat_proj_incremental(
    new_root,
    old_root,
    old_fp,
    Ref(1000),
    changed_indices=changed,
  )
  // Only the last def (index 79) differs; the trailing expr keeps its offset.
  @debug.debug_inspect(changed.val, content="[79]")
}

///|
test "control: shifted scenario blocks reuse for every entry" {
  let base = tree_refresh_bench_source(80, "0")
  let (new_root, old_root, old_fp) = fp_incr_setup(base, " " + base)
  let changed = Ref(([] : Array[Int]))
  let _ = @lambda_proj.to_flat_proj_incremental(
    new_root,
    old_root,
    old_fp,
    Ref(1000),
    changed_indices=changed,
  )
  // 80 defs + final expr, all offset-shifted → none reused.
  inspect(changed.val.length(), content="81")
}

// --- Bench runner: setup ONCE (outside the timed loop), measure only the scan ---

///|
/// Parse old/new sources and build the carried-over old FlatProj once, then
/// time only `to_flat_proj_incremental`. Keeping setup out of the `b.bench`
/// closure is the invariant that makes these numbers a scan measurement.
fn bench_fp_incr(
  b : @bench.T,
  old_src : String,
  new_src : String,
) -> Unit raise {
  let (new_root, old_root, old_fp) = fp_incr_setup(old_src, new_src)
  b.bench(() => {
    let r = @lambda_proj.to_flat_proj_incremental(
      new_root,
      old_root,
      old_fp,
      Ref(1000),
    )
    b.keep(r)
  })
}

// --- Scenario: unchanged (pure change-detection cost) ---

///|
test "fp_incr unchanged (20 defs)" (b : @bench.T) {
  bench_fp_incr(
    b,
    tree_refresh_bench_source(20, "0"),
    tree_refresh_bench_source(20, "0"),
  )
}

///|
test "fp_incr unchanged (80 defs)" (b : @bench.T) {
  bench_fp_incr(
    b,
    tree_refresh_bench_source(80, "0"),
    tree_refresh_bench_source(80, "0"),
  )
}

///|
test "fp_incr unchanged (320 defs)" (b : @bench.T) {
  bench_fp_incr(
    b,
    tree_refresh_bench_source(320, "0"),
    tree_refresh_bench_source(320, "0"),
  )
}

///|
test "fp_incr unchanged (1000 defs)" (b : @bench.T) {
  bench_fp_incr(
    b,
    tree_refresh_bench_source(1000, "0"),
    tree_refresh_bench_source(1000, "0"),
  )
}

// --- Scenario: tail-changed (realistic single-line keystroke) ---

///|
test "fp_incr tail (20 defs)" (b : @bench.T) {
  bench_fp_incr(
    b,
    tree_refresh_bench_source(20, "0"),
    tree_refresh_bench_source(20, "1"),
  )
}

///|
test "fp_incr tail (80 defs)" (b : @bench.T) {
  bench_fp_incr(
    b,
    tree_refresh_bench_source(80, "0"),
    tree_refresh_bench_source(80, "1"),
  )
}

///|
test "fp_incr tail (320 defs)" (b : @bench.T) {
  bench_fp_incr(
    b,
    tree_refresh_bench_source(320, "0"),
    tree_refresh_bench_source(320, "1"),
  )
}

///|
test "fp_incr tail (1000 defs)" (b : @bench.T) {
  bench_fp_incr(
    b,
    tree_refresh_bench_source(1000, "0"),
    tree_refresh_bench_source(1000, "1"),
  )
}

// --- Scenario: shifted-offset (reuse fully blocked, worst case) ---

///|
test "fp_incr shifted (20 defs)" (b : @bench.T) {
  let base = tree_refresh_bench_source(20, "0")
  bench_fp_incr(b, base, " " + base)
}

///|
test "fp_incr shifted (80 defs)" (b : @bench.T) {
  let base = tree_refresh_bench_source(80, "0")
  bench_fp_incr(b, base, " " + base)
}

///|
test "fp_incr shifted (320 defs)" (b : @bench.T) {
  let base = tree_refresh_bench_source(320, "0")
  bench_fp_incr(b, base, " " + base)
}

///|
test "fp_incr shifted (1000 defs)" (b : @bench.T) {
  let base = tree_refresh_bench_source(1000, "0")
  bench_fp_incr(b, base, " " + base)
}
