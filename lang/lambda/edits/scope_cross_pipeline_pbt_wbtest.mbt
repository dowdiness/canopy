// Cross-pipeline resolution-equivalence property test (docs/TODO.md §20).
//
// WHAT THIS PINS
// Two pipelines build a `FlatProj` from the same source, then a scope graph
// resolves each Var reference to a declaration. The pipelines assign a module
// def's binder id (`defs[i].3`) differently:
//   - TEST path (`graph_and_sm_of` / `from_proj_node`): reuses the init node's
//     id (a real node present in the reconstructed tree);
//   - PRODUCTION path (`production_graph_of` / `to_flat_proj`): allocates a
//     SYNTHETIC binder id occupying no registry node.
// Resolution never reads `node_id` (`Builder::resolve` matches name + def_index
// < cutoff), so the hand-verified equivalence proof in
// `scope_equivalence_wbtest.mbt` SHOULD transfer to production — this PBT pins
// that transfer generatively, across many sources.
//
// It also pins the Option-D binder-location contract (docs/TODO.md §20): each
// resolved declaration is LOCATABLE via `@scope.binder_span`, and that location
// is pipeline-INDEPENDENT — both pipelines derive the binder span from the same
// syntax token offsets, so the accessor agrees even though the internal binder
// `node_id` values diverge. This SUPERSEDES the former gap pin (which asserted
// the module binder `node_id` was synthetic / not in the registry); Option D
// locates binders by source span, not `node_id`, so that syntheticness is now
// an internal detail rather than a gap awaiting a fix.
//
// HOW IT STAYS NON-CIRCULAR (see memory: feedback_drift_detector_non_circular)
// The two pipelines differ exactly in their node-id *values*; node ids are
// therefore never compared raw. Each resolution is reduced to a
// pipeline-INDEPENDENT key built from semantic identity (module: def_index;
// lambda: the binding Lam node's SOURCE RANGE — identical across pipelines
// because both inner subtrees come from the same `syntax_to_proj_node`). The
// normalizer carries the binder *name* and, for lambdas, the binder *range*, so
// it cannot collapse a genuine disagreement (resolving to a different module
// def, a different lambda, or to free) into a match.
//
// SCOPE / NON-GOALS
// This is a pure test-path-vs-production-path equivalence over a single parse.
// It does NOT exercise `to_flat_proj_incremental` or the `@incr` memo layer —
// the live editor's incremental rebuild path is a separate concern. It also
// cannot catch a bug shared by both pipelines inside `@scope.build`; the frozen
// hand-derived oracle in `scope_equivalence_wbtest.mbt` covers that blind spot
// and is intentionally retained alongside this generator.

///|
/// Collect every Var reference in a node registry, keyed by a
/// pipeline-independent "start:end:name" string. Var occurrences have unique
/// source spans, so this key is injective within a pipeline; equality of the
/// two pipelines' key sets is itself an invariant (same parse → same Vars).
fn collect_var_refs(
  registry : Map[NodeId, ProjNode[@ast.Term]],
) -> Map[String, NodeId] raise {
  let refs : Map[String, NodeId] = {}
  for id, node in registry {
    if node.kind is @ast.Term::Var(name) {
      let key = "\{node.start}:\{node.end}:\{name}"
      // Injectivity guard: a collision would silently overwrite a reference
      // and hide it from the cross-pipeline comparison.
      guard refs.get(key) is None else {
        fail("Var key \{key} is not injective within a pipeline")
      }
      refs[key] = id
    }
  }
  refs
}

///|
/// Assert the two pipelines see the same set of Var references (by range+name).
/// A divergence here would let range-matching silently skip a reference, so it
/// is pinned rather than assumed.
fn assert_same_var_refs(
  m1 : Map[String, NodeId],
  m2 : Map[String, NodeId],
) -> Unit raise {
  guard m1.length() == m2.length() else {
    fail(
      "Var-ref count differs across pipelines: \{m1.length()} vs \{m2.length()}",
    )
  }
  for k, _ in m1 {
    guard m2.get(k) is Some(_) else {
      fail("Var ref \{k} present in test pipeline but missing in production")
    }
  }
}

///|
/// Assert no two distinct Lam nodes in a registry share a source range, so the
/// range is a faithful identity for a lambda binder (Codex design-review
/// guardrail: otherwise the LamParam normalizer could collapse two lambdas).
fn assert_lam_ranges_unique(
  registry : Map[NodeId, ProjNode[@ast.Term]],
) -> Unit raise {
  let seen : Map[String, NodeId] = {}
  for _, node in registry {
    if node.kind is @ast.Term::Lam(_, _) {
      let key = "\{node.start}:\{node.end}"
      guard seen.get(key) is None else {
        fail("two distinct Lam nodes share range \{key} (range not injective)")
      }
      seen[key] = node.id()
    }
  }
}

///|
/// Source ranges of a Module's def inits, indexed by def_index. Both pipelines
/// reconstruct the Module with the def inits as its first N children (in def
/// order), built from the same `syntax_to_proj_node`, so this array is
/// pipeline-independent. Empty for a non-Module root (no module defs exist).
fn def_init_ranges(root : ProjNode[@ast.Term]) -> Array[String] {
  match root.kind {
    Module(term_defs, _) =>
      [
        for i in 0..<term_defs.length() => {
          "\{root.children[i].start}:\{root.children[i].end}"
        }
      ]
    _ => []
  }
}

///|
/// Reduce a resolved declaration to a pipeline-independent key. Module decls
/// use (def_index, name, init source range); lambda decls use the binder Lam
/// node's source range (looked up in THAT pipeline's own registry) plus the
/// name. Both kinds key on a SOURCE RANGE, not a node id or a bare index, so a
/// future pipeline divergence that re-indexed defs (same def_index → different
/// source def with a coincidentally equal name) cannot collapse a real
/// disagreement. A binder absent from its registry/range array is a hard
/// failure, never a fallback.
fn normalize_decl(
  decl : @scope.Decl?,
  registry : Map[NodeId, ProjNode[@ast.Term]],
  init_ranges : Array[String],
) -> String raise {
  match decl {
    None => "free"
    Some(d) =>
      match d.kind {
        ModuleDef(def_index~) => {
          guard def_index >= 0 && def_index < init_ranges.length() else {
            fail("ModuleDef def_index \{def_index} out of range")
          }
          "module:\{def_index}:\{d.name}:\{init_ranges[def_index]}"
        }
        LamParam(lam_id~) => {
          guard registry.get(lam_id) is Some(n) else {
            fail("LamParam binder absent from registry (range lookup failed)")
          }
          "lam:\{n.start}:\{n.end}:\{d.name}"
        }
      }
  }
}

///|
/// One side of a resolution-agreement comparison. Bundling the graph, registry,
/// source map, and normalized-declaration ranges prevents accidental argument
/// reordering at the three call sites while keeping the helper whitebox-local.
struct ResolutionSide {
  graph : @scope.ScopeGraph
  registry : Map[NodeId, ProjNode[@ast.Term]]
  source_map : SourceMap
  ranges : Array[String]
  value_label : String
  binder_label : String
}

///|
fn ResolutionSide::ResolutionSide(
  graph~ : @scope.ScopeGraph,
  registry~ : Map[NodeId, ProjNode[@ast.Term]],
  source_map~ : SourceMap,
  ranges~ : Array[String],
  value_label~ : String,
  binder_label~ : String,
) -> ResolutionSide {
  { graph, registry, source_map, ranges, value_label, binder_label }
}

///|
/// Assert two independently-built scope graphs resolve every Var reference to
/// the same pipeline-independent declaration key, and that resolved binders are
/// locatable at the same source span. The binder-span half keeps Option D's two
/// distinct affirmations together: locatability (`is Some`) and equality of the
/// located spans. Caller-supplied labels preserve each differential's existing
/// failure text while centralizing the shared assertion conditions.
fn assert_resolution_agrees(
  left : ResolutionSide,
  right : ResolutionSide,
  context_prefix~ : String,
  binder_span_disagreement~ : String,
) -> Unit raise {
  assert_lam_ranges_unique(left.registry)
  assert_lam_ranges_unique(right.registry)
  let refs_left = collect_var_refs(left.registry)
  let refs_right = collect_var_refs(right.registry)
  assert_same_var_refs(refs_left, refs_right)
  for key, id_left in refs_left {
    let id_right = refs_right.get(key).unwrap()
    let d_left = @scope.declaration(left.graph, id_left)
    let d_right = @scope.declaration(right.graph, id_right)
    let n_left = normalize_decl(d_left, left.registry, left.ranges)
    let n_right = normalize_decl(d_right, right.registry, right.ranges)
    guard n_left == n_right else {
      fail(
        "\{context_prefix}resolution disagrees for Var \{key}: \{left.value_label}=\{n_left} \{right.value_label}=\{n_right}",
      )
    }
    if (d_left, d_right) is (Some(dd_left), Some(dd_right)) {
      let bs_left = @scope.binder_span(left.graph, dd_left, left.source_map)
      let bs_right = @scope.binder_span(right.graph, dd_right, right.source_map)
      guard bs_right is Some(_) else {
        fail(
          "\{context_prefix}\{right.binder_label}: binder not locatable via binder_span for \{key}",
        )
      }
      guard bs_left is Some(_) else {
        fail(
          "\{context_prefix}\{left.binder_label}: binder not locatable via binder_span for \{key}",
        )
      }
      guard bs_left == bs_right else {
        fail("\{context_prefix}\{binder_span_disagreement} for Var \{key}")
      }
    }
  }
}

///|
/// Drive both pipelines on one source string and assert resolution agreement.
/// `expect_clean` asserts zero parser diagnostics (the generated/well-formed
/// property); error-recovery fixtures pass `expect_clean=false` since both
/// pipelines recover from the SAME syntax tree.
fn check_agreement(text : String, expect_clean? : Bool = true) -> Unit raise {
  let (_cst, diags) = @parser.parse_cst(text)
  if expect_clean {
    guard diags.length() == 0 else {
      fail("expected clean parse but got \{diags.length()} diagnostic(s)")
    }
  }
  // Pipeline 1: test path (from_proj_node), with token spans for binder_span.
  let (proj1, _fp1, g1, sm1) = graph_and_sm_of(text)
  let reg1 = scope_test_registry(proj1)
  let ranges1 = def_init_ranges(proj1)
  // Pipeline 2: production path (to_flat_proj), with token spans.
  let (proj2, reg2, g2, sm2) = production_graph_of(text)
  let ranges2 = def_init_ranges(proj2)
  assert_resolution_agrees(
    ResolutionSide(
      graph=g1,
      registry=reg1,
      source_map=sm1,
      ranges=ranges1,
      value_label="test",
      binder_label="test pipeline",
    ),
    ResolutionSide(
      graph=g2,
      registry=reg2,
      source_map=sm2,
      ranges=ranges2,
      value_label="production",
      binder_label="production",
    ),
    context_prefix="",
    binder_span_disagreement="binder location disagrees across pipelines",
  )
}

// ---------------------------------------------------------------------------
// Generator: a random lambda AST printed to a parseable source string.
// Restricted to parseable variants (no Unbound/Error/Hole; Module root-only;
// no nested Module/Unit which `print_term` would emit non-atomically). The
// printed string is fed identically to BOTH pipelines — the test never assumes
// the parse round-trips the generated Term, only that the string parses.
// ---------------------------------------------------------------------------

///|
let gen_names : Array[String] = ["a", "b", "c", "x", "y", "z"]

///|
fn gen_pick(rs : @splitmix.RandomState, n : Int) -> Int {
  rs.next_positive_int() % n
}

///|
fn gen_name(rs : @splitmix.RandomState) -> String {
  gen_names[gen_pick(rs, gen_names.length())]
}

///|
/// Generate an expression Term (no Module, no Unit) of bounded depth.
fn gen_expr(rs : @splitmix.RandomState, depth : Int) -> @ast.Term {
  if depth <= 0 {
    // Leaf: Var or Int.
    if gen_pick(rs, 2) == 0 {
      @ast.Term::Var(gen_name(rs))
    } else {
      @ast.Term::Int(gen_pick(rs, 10))
    }
  } else {
    // No `If`: `print_term` emits `if c then t else e` UNPARENTHESIZED, which
    // is unparseable in application/operand position. Every other variant
    // prints parenthesized (Lam/App/Bop) or atomic (Var/Int), so any
    // composition stays parseable. If adds no resolution case App lacks.
    match gen_pick(rs, 5) {
      0 => @ast.Term::Var(gen_name(rs))
      1 => @ast.Term::Int(gen_pick(rs, 10))
      2 => @ast.Term::Lam(gen_name(rs), gen_expr(rs, depth - 1))
      3 => @ast.Term::App(gen_expr(rs, depth - 1), gen_expr(rs, depth - 1))
      _ => {
        let op = if gen_pick(rs, 2) == 0 {
          @ast.Bop::Plus
        } else {
          @ast.Bop::Minus
        }
        @ast.Term::Bop(op, gen_expr(rs, depth - 1), gen_expr(rs, depth - 1))
      }
    }
  }
}

///|
/// Generate a source Term: either a bare expression or a root Module with
/// 1..=3 defs (names drawn from the tiny alphabet to force shadowing) and a
/// body expression.
fn gen_source(rs : @splitmix.RandomState, depth : Int) -> @ast.Term {
  if gen_pick(rs, 2) == 0 {
    gen_expr(rs, depth)
  } else {
    let def_count = 1 + gen_pick(rs, 3)
    let defs : Array[(@ast.VarName, @ast.Term)] = []
    for _ in 0..<def_count {
      defs.push((gen_name(rs), gen_expr(rs, depth - 1)))
    }
    @ast.Term::Module(defs, gen_expr(rs, depth - 1))
  }
}

///|
/// Newtype wrapper so quickcheck can generate source strings via an AST. `Show`
/// renders the source text, so a counterexample prints the offending program.
struct GenSource(@ast.Term)

///|
impl Show for GenSource with fn output(self, logger) {
  logger.write_string(@ast.print_term(self.0))
}

///|
impl @quickcheck.Arbitrary for GenSource with fn arbitrary(size, rs) {
  let depth = if size < 1 { 1 } else if size > 4 { 4 } else { size }
  GenSource(gen_source(rs, depth))
}

///|
impl @qc.Shrink for GenSource

// ---------------------------------------------------------------------------
// Edge set (docs/TODO.md §20 exit criterion): empty/Unit body, error nodes,
// nested blocks, shadowing chains. Each drives the same `check_agreement`.
// ---------------------------------------------------------------------------

///|
test "cross-pipeline edge: empty / Unit body" {
  // Def with no trailing body → synthetic Unit body (built differently per
  // pipeline, but carries no Var so resolution is vacuously equal).
  check_agreement("let x = 0")
  check_agreement("let x = 0\nlet y = 1")
}

///|
test "cross-pipeline edge: error / recovery nodes" {
  // Missing let-binding value → `error_node_for_syntax` in BOTH pipelines.
  // Recovery is identical (same syntax tree), so resolution still agrees;
  // diagnostics are expected, so do not assert a clean parse.
  check_agreement("let x =\nx", expect_clean=false)
}

///|
test "cross-pipeline edge: nested blocks" {
  check_agreement("λx. λy. (x y)")
  check_agreement("((λx. x) (λy. y))")
  check_agreement("let f = λx. λy. (x y)\n(f f)")
}

///|
test "cross-pipeline edge: shadowing chains" {
  // Later module def wins; lambda param shadows module def; nested lambdas.
  check_agreement("let x = 1\nlet x = 2\nlet x = 3\nx")
  check_agreement("λx. λx. λx. x")
  check_agreement("let x = 0\nλx. λy. x")
  // Self-referential and forward/backward init visibility.
  check_agreement("let x = x\nx")
  check_agreement("let a = b\nlet b = 1\na")
  check_agreement("let x = 1\nlet x = x\nx")
}

///|
test "cross-pipeline: fixed sanity case agrees" {
  check_agreement("let x = 0\nλx. x")
}

///|
/// Generated well-formed sources must resolve identically across both
/// `FlatProj` construction pipelines (docs/TODO.md §20). The cross-pipeline
/// property is near-tautological (resolution ignores `node_id`; both pipelines
/// build defs from the same syntax in the same order), so a few hundred cases
/// give the same confidence as thousands — `max_success` is sized for CI cost,
/// not coverage. The edge-set fixtures above carry the structurally tricky
/// cases that random generation is unlikely to hit.
test "property: resolution agrees across both FlatProj pipelines" {
  @qc.quick_check_fn_error(
    fn(gs : GenSource) -> Unit raise { check_agreement(@ast.print_term(gs.0)) },
    max_success=300,
  )
}
