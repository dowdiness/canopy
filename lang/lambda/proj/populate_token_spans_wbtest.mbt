///|
fn parse_proj_with_token_spans(
  text : String,
) -> (ProjNode[@ast.Term], SourceMap) raise {
  let (cst, _) = @parser.parse_cst(text) catch { _ => fail("parse failed") }
  let syntax = @seam.SyntaxNode::from_cst(cst)
  let proj = to_proj_node(syntax, Ref(0))
  let source_map = SourceMap::from_ast(proj)
  populate_token_spans(source_map, syntax, proj)
  (proj, source_map)
}

///|
fn expect_param_span(
  source_map : SourceMap,
  node : ProjNode[@ast.Term],
  start : Int,
  end : Int,
) -> Unit raise {
  guard source_map.get_token_span(node.id(), PARAM_ROLE) is Some(span) else {
    fail("missing param span")
  }
  if span.start != start || span.end != end {
    fail("expected param span \{start}..\{end}, got \{span.start}..\{span.end}")
  }
}

///|
test "populate_token_spans: application left spine reaches every lambda arg" {
  let text = "(\u{03BB}x. x) (\u{03BB}y. y) (\u{03BB}z. z)"
  let (proj, source_map) = parse_proj_with_token_spans(text)
  let inner_app = proj.children[0]
  expect_param_span(source_map, inner_app.children[0], 2, 3)
  expect_param_span(source_map, inner_app.children[1], 10, 11)
  expect_param_span(source_map, proj.children[1], 18, 19)
}

///|
test "populate_token_spans: binary left spine reaches every lambda operand" {
  let text = "(\u{03BB}a. a) + (\u{03BB}b. b) + (\u{03BB}c. c)"
  let (proj, source_map) = parse_proj_with_token_spans(text)
  let inner_bop = proj.children[0]
  expect_param_span(source_map, inner_bop.children[0], 2, 3)
  expect_param_span(source_map, inner_bop.children[1], 12, 13)
  expect_param_span(source_map, proj.children[1], 22, 23)
}
