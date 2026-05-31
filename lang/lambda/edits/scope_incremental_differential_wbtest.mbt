// Incremental ↔ full differential resolution test (docs/TODO.md §20, plan step 3).
//
// WHAT THIS PINS
// Drives the INCREMENTAL FlatProj path — `to_flat_proj_incremental` (which reuses
// unchanged def subtrees + `reconcile_flat_proj` to preserve binder ids) — across
// an EDIT SEQUENCE, and asserts that a scope graph built from the incrementally
// reconciled `FlatProj` resolves every Var reference IDENTICALLY to one built from
// a fresh FULL `to_flat_proj` of the same final source — after every edit. The
// cross-pipeline PBT (`scope_cross_pipeline_pbt_wbtest.mbt`) compares two FULL
// rebuilds and EXPLICITLY excludes this incremental path; this file fills that gap.
//
// WHY THIS CATCHES REAL BUGS (the staleness class)
// `to_flat_proj_incremental` reuses an old def's `ProjNode` subtree verbatim when
// its start offset AND structural `CstNode` are unchanged (flat_proj.mbt:83-89).
// A reused subtree carries the OLD parse's node positions. We rebuild a fresh
// `SourceMap` (`from_ast` records each node's start/end) and registry from the
// incrementally reconstructed tree, then compare against the full rebuild via the
// SAME range-keyed machinery the cross-pipeline PBT uses (`collect_var_refs` keys
// on "start:end:name"; `binder_span` resolves through SourceMap token spans). If a
// reused subtree's positions ever desync from the new source, the Var-ref key set
// or a binder span diverges and the differential fails — which is the bug, not a
// false positive (scope cutoff itself depends on those ranges, builder.mbt:123).
//
// NON-VACUITY (guards against a full-vs-full tautology)
// Fresh re-parses produce structurally-equal-but-distinct `CstNode`s for unchanged
// defs, so reuse fires through structural `CstNode` Eq exactly as in production
// (flat_proj_wbtest.mbt:322-343 proves this). The dedicated single-edit test below
// asserts `changed.val == [1]`: the non-reuse branch is the ONLY thing that pushes
// an index (flat_proj.mbt:92), so an empty slot for def 0 proves it was REUSED on
// the very step being differentialed. (Asserting `defs[0].3` id-stability would NOT
// prove reuse — `reconcile_flat_proj` preserves matched binder ids by NAME
// regardless of whether the subtree was reused, flat_proj.mbt:189.)
//
// SCOPE / NON-GOALS
// This is a FlatProj-level differential. It threads prev-SyntaxNode + prev-FlatProj
// manually and calls `to_flat_proj_incremental` directly — it does NOT drive the
// `@incr` memo stack (`build_lambda_projection_memos`), whose registry/source-map
// incremental PATCH paths (changed_def_indices side-channel, revision-skew
// fallback, two-phase remove/add) are a separate concern. It also cannot catch a
// bug shared by both pipelines inside `@scope.build`; the frozen hand-derived
// oracle in `scope_equivalence_wbtest.mbt` covers that blind spot.

///|
/// Fresh full parse of a source string into a positioned SyntaxNode. Two
/// independent parses of the same text yield structurally-equal (Eq) `CstNode`s,
/// so feeding successive parses to `to_flat_proj_incremental` exercises its reuse
/// branch faithfully — the same input distribution the production memo sees.
fn parse_syntax(text : String) -> @seam.SyntaxNode raise {
  let (cst, _diags) = @parser.parse_cst(text)
  @seam.SyntaxNode::from_cst(cst)
}

///|
/// Reconstruct a scope graph from a prebuilt `FlatProj` + the source's SyntaxNode,
/// exactly as the production reconstruct flow does (`production_graph_of`):
/// `fp.to_proj_node` → `SourceMap::from_ast` → `populate_token_spans` → registry →
/// `@scope.build`. `base_id` MUST be the high-water mark of the counter that built
/// `fp` (its `.val` after `to_flat_proj`/`to_flat_proj_incremental`); `to_proj_node`
/// allocates the Module node id FROM this counter (flat_proj.mbt:257), so seeding
/// it past every id already present in `fp` is required — a fresh `Ref(0)` would
/// alias the Module id onto an existing init-subtree node id and corrupt the
/// node-id-keyed registry / SourceMap.
fn build_graph_from_fp(
  fp : FlatProj,
  syntax : @seam.SyntaxNode,
  base_id : Int,
) -> (
  @core.ProjNode[@ast.Term],
  Map[NodeId, ProjNode[@ast.Term]],
  @scope.ScopeGraph,
  SourceMap,
) {
  let counter = Ref(base_id)
  let proj = fp.to_proj_node(counter)
  let sm = SourceMap::from_ast(proj)
  populate_token_spans(sm, syntax, proj)
  let registry = scope_test_registry(proj)
  let g = @scope.build(fp, registry, sm)
  (proj, registry, g, sm)
}

///|
/// Assert the scope graph from an incremental `FlatProj` resolves identically to
/// one from a fresh full `to_flat_proj` of the same `syntax`. Reuses the
/// cross-pipeline PBT's pipeline-INDEPENDENT comparison leaves (`collect_var_refs`,
/// `assert_same_var_refs`, `assert_lam_ranges_unique`, `def_init_ranges`,
/// `normalize_decl`), so node-id values are never compared raw.
fn assert_incr_matches_full(
  incr_fp : FlatProj,
  incr_base_id : Int,
  syntax : @seam.SyntaxNode,
  context : String,
) -> Unit raise {
  let (proj_i, reg_i, g_i, sm_i) = build_graph_from_fp(
    incr_fp, syntax, incr_base_id,
  )
  let full_counter = Ref(0)
  let full_fp = @lambda_proj.to_flat_proj(syntax, full_counter)
  let (proj_f, reg_f, g_f, sm_f) = build_graph_from_fp(
    full_fp,
    syntax,
    full_counter.val,
  )
  let ranges_i = def_init_ranges(proj_i)
  let ranges_f = def_init_ranges(proj_f)
  assert_resolution_agrees(
    ResolutionSide(
      graph=g_i,
      registry=reg_i,
      source_map=sm_i,
      ranges=ranges_i,
      value_label="incr",
      binder_label="incr",
    ),
    ResolutionSide(
      graph=g_f,
      registry=reg_f,
      source_map=sm_f,
      ranges=ranges_f,
      value_label="full",
      binder_label="full",
    ),
    context_prefix="[\{context}] ",
    binder_span_disagreement="binder span disagrees across incr/full",
  )
}

///|
/// Drive an edit sequence: parse `sources[0]` fully, then for each subsequent
/// source re-parse fresh, reconcile via `to_flat_proj_incremental` against the
/// previous tree+proj, and assert the differential AFTER EVERY edit. The counter
/// is threaded persistently across the whole sequence (as the production memo's
/// `next_id_ref` is), so binder ids accumulate rather than reset.
fn run_diff_sequence(sources : Array[String]) -> Unit raise {
  guard sources.length() >= 1 else {
    fail("run_diff_sequence needs >=1 source")
  }
  let counter = Ref(0)
  let mut prev_syntax = parse_syntax(sources[0])
  let mut prev_fp = @lambda_proj.to_flat_proj(prev_syntax, counter)
  assert_incr_matches_full(
    prev_fp,
    counter.val,
    prev_syntax,
    "init:\{sources[0]}",
  )
  for i in 1..<sources.length() {
    let new_syntax = parse_syntax(sources[i])
    let changed = Ref(([] : Array[Int]))
    let incr_fp = @lambda_proj.to_flat_proj_incremental(
      new_syntax,
      prev_syntax,
      prev_fp,
      counter,
      changed_indices=changed,
    )
    assert_incr_matches_full(
      incr_fp,
      counter.val,
      new_syntax,
      "edit\{i}:\{sources[i]}",
    )
    prev_syntax = new_syntax
    prev_fp = incr_fp
  }
}

// ---------------------------------------------------------------------------
// Non-vacuity guard: prove reuse actually fires on the step being asserted.
// ---------------------------------------------------------------------------

///|
test "incr-diff: editing one def reuses the others (non-vacuity) and agrees" {
  let counter = Ref(0)
  let s0 = parse_syntax("let x = 1\nlet y = 2\nx")
  let fp0 = @lambda_proj.to_flat_proj(s0, counter)
  let s1 = parse_syntax("let x = 1\nlet y = 3\nx")
  let changed = Ref(([] : Array[Int]))
  let fp1 = @lambda_proj.to_flat_proj_incremental(
    s1,
    s0,
    fp0,
    counter,
    changed_indices=changed,
  )
  // Non-vacuity: def 0 (`x = 1`, unchanged at the same start) must be REUSED, so its
  // index is NOT pushed; only def 1 (`y = 3` vs `y = 2`) is rebuilt. Asserting "def 0
  // absent from changed" (rather than the exact `== [1]`) keeps the guard robust to a
  // body/offset shift if the fixture text is later edited to differ in length — the
  // load-bearing claim is that the unchanged def was reused, not the precise rebuilt
  // set. This is the sharp proof that the differential is NOT a full-vs-full tautology.
  inspect(changed.val.contains(0), content="false")
  inspect(changed.val.contains(1), content="true")
  assert_incr_matches_full(fp1, counter.val, s1, "single-def-edit")
}

// ---------------------------------------------------------------------------
// Hand-crafted edit sequences. Each drives `run_diff_sequence`, which asserts the
// incr↔full differential after every step. Cover the structural edit kinds the
// reconcile path must handle: init change, insert, delete, rename/shadow shift,
// body edit, and an earlier-def growth that SHIFTS later defs (forcing rebuild).
// ---------------------------------------------------------------------------

///|
test "incr-diff: change a def init across a sequence" {
  run_diff_sequence([
    "let x = 0\nx", "let x = 1\nx", "let x = (x + 1)\nx", "let x = 2\nx",
  ])
}

///|
test "incr-diff: insert and delete defs" {
  run_diff_sequence([
    "let x = 0\nx", "let x = 0\nlet y = 1\nx", "let x = 0\nlet y = 1\nlet z = 2\n(x y)",
    "let x = 0\nlet z = 2\n(x z)", "let z = 2\nz",
  ])
}

///|
test "incr-diff: rename a binder shifts shadowing resolution" {
  // Renaming the second `x` to `w` changes which def the body `x` resolves to
  // (later-x → only-x), and renaming back restores it. The differential must
  // track the resolution flip on both incr and full.
  run_diff_sequence([
    "let x = 1\nlet x = 2\nx", "let x = 1\nlet w = 2\nx", "let x = 1\nlet x = 2\nx",
  ])
}

///|
test "incr-diff: lambda shadowing edits" {
  run_diff_sequence([
    "let x = 0\nλx. x", "let x = 0\nλy. x", "λx. λx. x", "λx. λy. (x y)",
  ])
}

///|
test "incr-diff: body-only edits preserve def reuse" {
  run_diff_sequence([
    "let a = 1\nlet b = 2\na", "let a = 1\nlet b = 2\nb", "let a = 1\nlet b = 2\n(a + b)",
    "let a = 1\nlet b = 2\n(b + a)",
  ])
}

///|
test "incr-diff: growing an earlier def shifts later defs" {
  // `a`'s init grows, shifting `b` and the body to later offsets. The shifted
  // defs are NOT reused (start changed, flat_proj.mbt:83) and are rebuilt with
  // fresh positions; the differential confirms full agreement after the shift.
  run_diff_sequence([
    "let a = 0\nlet b = 1\n(a + b)", "let a = (0 + 0)\nlet b = 1\n(a + b)", "let a = ((0 + 0) + 0)\nlet b = 1\n(a + b)",
  ])
}

///|
test "incr-diff: self-reference and forward/backward visibility under edits" {
  run_diff_sequence([
    "let x = x\nx", "let x = 1\nlet x = x\nx", "let a = b\nlet b = 1\na", "let a = 1\nlet b = a\nb",
  ])
}

// ---------------------------------------------------------------------------
// Deterministic generative fuzz (analog of
// loom/examples/lambda/src/imperative_differential_fuzz_test.mbt). A linear
// congruential generator produces a start source and a sequence of string edits;
// each step reconciles incrementally and — on a clean parse — asserts the incr↔full
// differential. `checked_cases > 0` guards against a vacuous pass if the generator
// ever drifts toward exclusively malformed inputs.
// ---------------------------------------------------------------------------

///|
fn idiff_next_seed(seed : Int) -> Int {
  (seed * 1103515245 + 12345) % 2147483647
}

///|
/// Token fragments that the lambda lexer always accepts (no lex-error chars), so
/// the source-file grammar can recover structurally via diagnostics rather than a
/// raised `LexError`. Includes `let`, `λ`, separators, and a small name/number
/// alphabet sized to force shadowing.
fn idiff_pool() -> Array[String] {
  [
    "x", "y", "z", "a", "b", "0", "1", "2", "let", " = ", " ", "\n", "(", ")", "+",
    "-", "λ", ".",
  ]
}

///|
fn idiff_make_source(seed : Int) -> String {
  let pool = idiff_pool()
  let mut s = seed
  let mut out = ""
  let count = seed.abs() % 10 + 3
  let pool_len = pool.length()
  for _ in 0..<count {
    s = idiff_next_seed(s)
    out = out + pool[s.abs() % pool_len]
  }
  out
}

///|
fn idiff_clamp(pos : Int, len : Int) -> Int {
  if pos < 0 {
    0
  } else if pos > len {
    len
  } else {
    pos
  }
}

///|
/// Apply a random insert / delete / replace, returning (new_source, next_seed).
fn idiff_apply_edit(source : String, seed : Int) -> (String, Int) {
  let pool = idiff_pool()
  let pool_len = pool.length()
  let len = source.length()
  let mut s = idiff_next_seed(seed)
  let op = s.abs() % 3
  s = idiff_next_seed(s)
  let frag_count = s.abs() % 3 + 1
  let mut frag = ""
  for _ in 0..<frag_count {
    s = idiff_next_seed(s)
    frag = frag + pool[s.abs() % pool_len]
  }
  s = idiff_next_seed(s)
  if op == 0 || len == 0 {
    let start = idiff_clamp(s.abs() % (len + 1), len)
    (source[0:start].to_owned() + frag + source[start:len].to_owned(), s)
  } else {
    let raw_a = s.abs() % (len + 1)
    s = idiff_next_seed(s)
    let raw_b = s.abs() % (len + 1)
    let from = idiff_clamp(if raw_a <= raw_b { raw_a } else { raw_b }, len)
    let to = idiff_clamp(if raw_a <= raw_b { raw_b } else { raw_a }, len)
    let left = source[0:from].to_owned()
    let right = source[to:len].to_owned()
    if op == 1 {
      (left + right, s)
    } else {
      (left + frag + right, s)
    }
  }
}

///|
test "incr-diff: deterministic fuzz — incr resolution == full after each edit" {
  let mut checked_cases = 0
  let mut reused_clean_steps = 0
  for case_i in 0..<25 {
    let mut seed = 53 + case_i * 113
    let mut source = idiff_make_source(seed)
    // The pool is lex-safe so parse_cst recovers via diagnostics rather than a
    // raised LexError, but catch defensively (as the loom fuzzer does) so a future
    // pool/seed change surfaces as a skipped case, not a crashed suite.
    let (cst0, _d0) = @parser.parse_cst(source) catch { _ => continue }
    let mut prev_syntax = @seam.SyntaxNode::from_cst(cst0)
    let counter = Ref(0)
    let mut prev_fp = @lambda_proj.to_flat_proj(prev_syntax, counter)
    for edit_i in 0..<8 {
      let (new_source, next_seed) = idiff_apply_edit(source, seed)
      let (cst, diags) = @parser.parse_cst(new_source) catch {
        _ => {
          source = new_source
          seed = next_seed
          continue
        }
      }
      let new_syntax = @seam.SyntaxNode::from_cst(cst)
      let changed = Ref(([] : Array[Int]))
      let incr_fp = @lambda_proj.to_flat_proj_incremental(
        new_syntax,
        prev_syntax,
        prev_fp,
        counter,
        changed_indices=changed,
      )
      // Differential is strongest on well-formed inputs; both pipelines build
      // from the SAME recovered tree, but the resolution oracle is cleanest when
      // there are no recovery nodes to reason about.
      if diags.length() == 0 {
        assert_incr_matches_full(
          incr_fp,
          counter.val,
          new_syntax,
          "fuzz case=\{case_i} edit=\{edit_i} src=\{new_source}",
        )
        checked_cases = checked_cases + 1
        // Broaden the non-vacuity guarantee beyond the single-def test: a clean
        // step "reused" iff ≥1 child carried over (changed records only REBUILT
        // children — def indices plus -1 for the final expr). A CstNode-Eq reuse
        // regression that turned every step into a full rebuild would drop this
        // to 0 and fail the suite, not pass vacuously as full-vs-full.
        let total_children = incr_fp.defs.length() +
          (if incr_fp.final_expr is Some(_) { 1 } else { 0 })
        if changed.val.length() < total_children {
          reused_clean_steps = reused_clean_steps + 1
        }
      }
      prev_syntax = new_syntax
      prev_fp = incr_fp
      source = new_source
      seed = next_seed
    }
  }
  // Guard against a vacuous pass if the generator drifts toward malformed strings.
  inspect(checked_cases > 0, content="true")
  // Guard against a vacuous pass if reuse silently stops firing on clean steps.
  inspect(reused_clean_steps > 0, content="true")
}
