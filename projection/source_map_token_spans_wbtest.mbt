// Whitebox tests for SourceMap token-level spans

///|
fn parse_syntax_for_token_test(text : String) -> @seam.SyntaxNode {
  let (cst, _) = @parser.parse_cst(text) catch { _ => abort("parse failed") }
  @seam.SyntaxNode::from_cst(cst)
}

///|
test "token span: lambda param" {
  let text = "\u{03BB}x.x"
  let syntax = parse_syntax_for_token_test(text)
  let counter = Ref::new(0)
  let proj = to_proj_node(syntax, counter)
  let sm = SourceMap::from_ast(proj)
  sm.populate_token_spans(syntax, proj)
  let lambda_id = proj.id()
  let param_span = sm.get_token_span(lambda_id, "param")
  // param "x" after λ: λ is 1 char, so param starts at 1
  guard param_span is Some(span)
  inspect(span.start, content="1")
  inspect(span.end, content="2")
}

///|
test "token span: lambda param multi-char" {
  let text = "\u{03BB}foo.foo"
  let syntax = parse_syntax_for_token_test(text)
  let counter = Ref::new(0)
  let proj = to_proj_node(syntax, counter)
  let sm = SourceMap::from_ast(proj)
  sm.populate_token_spans(syntax, proj)
  let lambda_id = proj.id()
  let param_span = sm.get_token_span(lambda_id, "param")
  guard param_span is Some(span)
  inspect(span.start, content="1")
  inspect(span.end, content="4")
}

///|
test "token span: nested lambda params" {
  // λx.λy.x — outer lambda param "x" at 1..2, inner lambda param "y" at 4..5
  let text = "\u{03BB}x.\u{03BB}y.x"
  let syntax = parse_syntax_for_token_test(text)
  let counter = Ref::new(0)
  let proj = to_proj_node(syntax, counter)
  let sm = SourceMap::from_ast(proj)
  sm.populate_token_spans(syntax, proj)
  // Outer lambda
  let outer_id = proj.id()
  guard sm.get_token_span(outer_id, "param") is Some(outer_span)
  inspect(outer_span.start, content="1")
  inspect(outer_span.end, content="2")
  // Inner lambda is the first child of outer
  let inner_lambda = proj.children[0]
  let inner_id = inner_lambda.id()
  guard sm.get_token_span(inner_id, "param") is Some(inner_span)
  inspect(inner_span.start, content="4")
  inspect(inner_span.end, content="5")
}

///|
test "token span: let def name" {
  // let x = 1\nx — name "x" at position 4..5
  let text = "let x = 1\nx"
  let syntax = parse_syntax_for_token_test(text)
  let counter = Ref::new(0)
  let proj = to_proj_node(syntax, counter)
  let sm = SourceMap::from_ast(proj)
  sm.populate_token_spans(syntax, proj)
  let module_id = proj.id()
  guard sm.get_token_span(module_id, "name:0") is Some(span)
  inspect(span.start, content="4")
  inspect(span.end, content="5")
}

///|
test "token span: multiple let defs" {
  let text = "let x = 1\nlet y = 2\nx + y"
  let syntax = parse_syntax_for_token_test(text)
  let counter = Ref::new(0)
  let proj = to_proj_node(syntax, counter)
  let sm = SourceMap::from_ast(proj)
  sm.populate_token_spans(syntax, proj)
  let module_id = proj.id()
  // First let: "x" at position 4..5
  guard sm.get_token_span(module_id, "name:0") is Some(x_span)
  inspect(x_span.start, content="4")
  inspect(x_span.end, content="5")
  // Second let: "y" at position 14..15
  guard sm.get_token_span(module_id, "name:1") is Some(y_span)
  inspect(y_span.start, content="14")
  inspect(y_span.end, content="15")
}

///|
test "token span: no token spans for simple expression" {
  let text = "42"
  let syntax = parse_syntax_for_token_test(text)
  let counter = Ref::new(0)
  let proj = to_proj_node(syntax, counter)
  let sm = SourceMap::from_ast(proj)
  sm.populate_token_spans(syntax, proj)
  inspect(sm.token_spans.length(), content="0")
}

///|
test "token span: lambda inside let def" {
  // let f = λx.x\nf — both "name:0" and lambda "param" should be recorded
  let text = "let f = \u{03BB}x.x\nf"
  let syntax = parse_syntax_for_token_test(text)
  let counter = Ref::new(0)
  let proj = to_proj_node(syntax, counter)
  let sm = SourceMap::from_ast(proj)
  sm.populate_token_spans(syntax, proj)
  // Module node should have "name:0"
  let module_id = proj.id()
  guard sm.get_token_span(module_id, "name:0") is Some(_)
  // The lambda (child 0 of Module = init of first def) should have "param"
  let lambda_node = proj.children[0]
  guard sm.get_token_span(lambda_node.id(), "param") is Some(param_span)
  // λ is at position 8, x is at position 9..10
  inspect(param_span.start, content="9")
  inspect(param_span.end, content="10")
}

///|
test "token span: get_token_span returns None for missing role" {
  let text = "\u{03BB}x.x"
  let syntax = parse_syntax_for_token_test(text)
  let counter = Ref::new(0)
  let proj = to_proj_node(syntax, counter)
  let sm = SourceMap::from_ast(proj)
  sm.populate_token_spans(syntax, proj)
  let lambda_id = proj.id()
  // "param" exists
  guard sm.get_token_span(lambda_id, "param") is Some(_)
  // "name" does not
  guard sm.get_token_span(lambda_id, "name") is None
  // Non-existent node
  guard sm.get_token_span(NodeId(999), "param") is None
}

///|
test "token span: set_token_span manual" {
  let sm = SourceMap::new()
  let nid = NodeId(42)
  sm.set_token_span(nid, "test_role", Range::new(10, 20))
  guard sm.get_token_span(nid, "test_role") is Some(span)
  inspect(span.start, content="10")
  inspect(span.end, content="20")
}

///|
test "token span: JSON includes token spans" {
  let text = "\u{03BB}x.x"
  let syntax = parse_syntax_for_token_test(text)
  let counter = Ref::new(0)
  let proj = to_proj_node(syntax, counter)
  let sm = SourceMap::from_ast(proj)
  sm.populate_token_spans(syntax, proj)
  let json_str = sm.to_json().stringify()
  inspect(json_str.contains("token_spans"), content="true")
  inspect(json_str.contains("param"), content="true")
}
