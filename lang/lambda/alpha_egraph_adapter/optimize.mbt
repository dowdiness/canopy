///|
// `@egraph.Runner` currently owns a plain `EGraph`; this adapter needs
// `AnalyzedEGraph` so beta and constant-folding hooks run during rebuild.
fn run_saturation(
  analyzed : @egraph.AnalyzedEGraph[AlphaLang, EvalState],
  rules : Array[@egraph.Rewrite],
) -> Unit {
  let node_limit = 5000
  let iter_limit = 30
  for _ in 0..<iter_limit {
    let applied = rules.fold(init=0, fn(count, rule) {
      count + analyzed.egraph.apply_rewrite(rule)
    })
    analyzed.rebuild()
    if applied == 0 || analyzed.size() > node_limit {
      break
    }
  }
}

///|
/// Optimize an alpha-safe Lambda term through the shared `dowdiness/egraph`
/// engine.
///
/// This package is the Canopy-specific adapter layer: it depends on
/// `lang/lambda/alpha` and keeps binders as `BinderId`-backed alpha references
/// during saturation, while the egraph package remains a generic engine. The
/// named `@ast.Term` boundary is handled by `optimize_projected`, which lowers
/// through `ScopeGraph` before calling this function and reifies only after
/// extraction.
pub fn optimize_alpha(term : @alpha.AlphaTerm) -> @alpha.AlphaTerm {
  let analyzed = @egraph.AnalyzedEGraph::AnalyzedEGraph(eval_analysis())
  let root = alpha_term_add(analyzed, term)
  analyzed.rebuild()
  run_saturation(analyzed, safe_rules())
  let (_, rec) = analyzed.extract(root, @egraph.ast_size())
  rec_expr_to_alpha(rec)
}

///|
/// Lower a projected Lambda root through Canopy's `ScopeGraph`, optimize the
/// alpha term with the shared egraph engine, then reify to the named AST
/// boundary. Parser/projection helpers should stay at test or caller boundaries;
/// this production path accepts already-projected source plus its scope graph.
pub fn optimize_projected(
  root : @core.ProjNode[@ast.Term],
  graph : @scope.ScopeGraph,
  policy? : @alpha.ReifyPolicy = Source,
) -> @ast.Term {
  @alpha.reify(optimize_alpha(@alpha.lower_root(root, graph)), policy)
}
