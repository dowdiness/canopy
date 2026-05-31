// Behavioral tests for the binder-location accessor and go-to-definition
// (plan §7.1). Unlike `build_fixture` in graph_wbtest.mbt, these populate token
// spans (via the SyntaxNode → ProjNode pipeline), since `binder_span` reads
// them. Expected offsets are hand-derived and match the conventions pinned in
// projection/source_map_token_spans_wbtest.mbt (e.g. `let x` name → 4..5,
// `λx` param → 1..2).

///|
/// Build a scope graph and a token-span-populated SourceMap from source.
fn build_fixture_with_spans(
  text : String,
) -> (ScopeGraph, @core.SourceMap) raise {
  let (cst, _) = @parser.parse_cst(text) catch { _ => fail("parse failed") }
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let proj = @lambda_proj.to_proj_node(syntax, Ref(0))
  let flat_proj = @lambda_proj.FlatProj::from_proj_node(proj)
  let source_map = @core.SourceMap::from_ast(proj)
  @lambda_proj.populate_token_spans(source_map, syntax, proj)
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = {}
  @core.collect_registry(proj, registry)
  let g = build(flat_proj, registry, source_map)
  (g, source_map)
}

///|
test "go_to_definition: module def — body var jumps to the name token" {
  // "let x = 1\nx" — name "x" at 4..5; body var "x" at 10.
  let (g, sm) = build_fixture_with_spans("let x = 1\nx")
  guard go_to_definition(g, sm, 10) is Some(r)
  inspect(r.start, content="4")
  inspect(r.end, content="5")
}

///|
test "go_to_definition: shadowed module def — later def wins (production id path)" {
  // "let x = 1\nlet x = 2\nx" — name:0 "x" at 4..5, name:1 "x" at 14..15.
  // The body var (pos 20) resolves to def_index=1, so the binder span must be
  // 14..15, NOT 4..5. This exercises the module-def binder whose production
  // FlatProj id was synthetic — the case Option D fixes.
  let (g, sm) = build_fixture_with_spans("let x = 1\nlet x = 2\nx")
  guard go_to_definition(g, sm, 20) is Some(r)
  inspect(r.start, content="14")
  inspect(r.end, content="15")
}

///|
test "go_to_definition: lambda param — body var jumps to the param token" {
  // "λx. x" — param "x" at 1..2; body var "x" at 4.
  let (g, sm) = build_fixture_with_spans("\u{03BB}x. x")
  guard go_to_definition(g, sm, 4) is Some(r)
  inspect(r.start, content="1")
  inspect(r.end, content="2")
}

///|
test "go_to_definition: nested lambda shadowing — innermost param wins" {
  // "λx. λx. x" — outer param at 1..2, inner param at 5..6; innermost use at 8
  // resolves to the inner λ.
  let (g, sm) = build_fixture_with_spans("\u{03BB}x. \u{03BB}x. x")
  guard go_to_definition(g, sm, 8) is Some(r)
  inspect(r.start, content="5")
  inspect(r.end, content="6")
}

///|
test "go_to_definition: caret on a wrapping paren resolves to the inner var's binder" {
  // "let x = 1\n(x)" — `(` at 10, `x` at 11, `)` at 12. ParenExpr deliberately
  // widens the wrapped Var's node span to cover the parens (proj_node.mbt), so a
  // caret on `(` (pos 10) resolves to `x` and jumps to its binder "x" at 4..5.
  // Intended position→node behavior, not identifier-token-strict (Codex P2 on
  // PR #405 — verified intentional, pinned here).
  let (g, sm) = build_fixture_with_spans("let x = 1\n(x)")
  guard go_to_definition(g, sm, 10) is Some(r)
  inspect(r.start, content="4")
  inspect(r.end, content="5")
}

///|
test "go_to_definition: free variable — no jump" {
  // "x" — unbound; go-to-definition yields None.
  let (g, sm) = build_fixture_with_spans("x")
  inspect(go_to_definition(g, sm, 0) is None, content="true")
}

///|
test "binder_span: None when token spans were not populated" {
  // A SourceMap built via from_ast without populate_token_spans has no token
  // spans — binder_span must degrade to None, never a wrong location.
  let (proj, _errs) = @lambda_proj.parse_to_proj_node("let x = 1\nx")
  let flat_proj = @lambda_proj.FlatProj::from_proj_node(proj)
  let source_map = @core.SourceMap::from_ast(proj)
  let registry : Map[@core.NodeId, @core.ProjNode[@ast.Term]] = {}
  @core.collect_registry(proj, registry)
  let g = build(flat_proj, registry, source_map)
  inspect(g.decls[0].kind is ModuleDef(_), content="true")
  inspect(binder_span(g, g.decls[0], source_map) is None, content="true")
}
