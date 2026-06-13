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
test "populate_token_spans: LetDef name span lives on LetDef node" {
  let text = "let x = 1\nx"
  let (proj, source_map) = parse_proj_with_token_spans(text)
  let let_def = proj.children[0]
  guard source_map.get_token_span(let_def.id(), LET_DEF_NAME_ROLE) is Some(span) else {
    fail("missing LetDef name span")
  }
  inspect(span.start, content="4")
  inspect(span.end, content="5")
  guard source_map.get_token_span(proj.id(), module_name_role(0)) is Some(_) else {
    fail("missing module-level compatibility name span")
  }
}

///|
test "populate_token_spans: nested block LetDef name span lives on LetDef node" {
  let text = "let x = { let y = 1\n  y }\nx"
  let (proj, source_map) = parse_proj_with_token_spans(text)
  let block_module = proj.children[0].children[0]
  let nested_let_def = block_module.children[0]
  guard source_map.get_token_span(nested_let_def.id(), LET_DEF_NAME_ROLE)
    is Some(span) else {
    fail("missing nested LetDef name span")
  }
  inspect(span.start, content="14")
  inspect(span.end, content="15")
  guard source_map.get_token_span(block_module.id(), module_name_role(0))
    is Some(_) else {
    fail("missing nested module-level compatibility name span")
  }
}

///|
test "populate_token_spans: root block LetDef name span lives on LetDef node" {
  let text = "{ let y = 1\n  y }"
  let (proj, source_map) = parse_proj_with_token_spans(text)
  let nested_let_def = proj.children[0]
  guard source_map.get_token_span(nested_let_def.id(), LET_DEF_NAME_ROLE)
    is Some(span) else {
    fail("missing root block LetDef name span")
  }
  inspect(span.start, content="6")
  inspect(span.end, content="7")
}

///|
test "populate_token_spans: multi-param lambda spans each desugared Lam" {
  let text = "(x, y) => x"
  let (proj, source_map) = parse_proj_with_token_spans(text)
  expect_param_span(source_map, proj, 1, 2)
  expect_param_span(source_map, proj.children[0], 4, 5)
}

///|
test "populate_token_spans: typed multi-param lambda ignores type identifiers" {
  let text = "(f : Int -> Int, x : Int) => f x"
  let (proj, source_map) = parse_proj_with_token_spans(text)
  expect_param_span(source_map, proj, 1, 2)
  expect_param_span(source_map, proj.children[0], 17, 18)
}

///|
test "populate_token_spans: typed fn params ignore type identifiers" {
  let text = "fn twice(f : Int -> Int, x : Int) { f x }\ntwice"
  let (proj, source_map) = parse_proj_with_token_spans(text)
  let fn_lam = proj.children[0].children[0]
  expect_param_span(source_map, fn_lam, 9, 10)
  expect_param_span(source_map, fn_lam.children[0], 25, 26)
}

///|
test "populate_token_spans: application left spine reaches every lambda arg" {
  let text = "((x) => x) ((y) => y) ((z) => z)"
  let (proj, source_map) = parse_proj_with_token_spans(text)
  let inner_app = proj.children[0]
  expect_param_span(source_map, inner_app.children[0], 2, 3)
  expect_param_span(source_map, inner_app.children[1], 13, 14)
  expect_param_span(source_map, proj.children[1], 24, 25)
}

///|
test "populate_token_spans: binary left spine reaches every lambda operand" {
  let text = "((a) => a) + ((b) => b) + ((c) => c)"
  let (proj, source_map) = parse_proj_with_token_spans(text)
  let inner_bop = proj.children[0]
  expect_param_span(source_map, inner_bop.children[0], 2, 3)
  expect_param_span(source_map, inner_bop.children[1], 15, 16)
  expect_param_span(source_map, proj.children[1], 28, 29)
}
