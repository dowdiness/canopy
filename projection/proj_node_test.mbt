///|
fn parse_syntax(text : String) -> @seam.SyntaxNode {
  let (cst, _) = @parser.parse_cst(text) catch { _ => abort("parse failed") }
  @seam.SyntaxNode::from_cst(cst)
}

///|
test "to_proj_node: single expression" {
  let syntax = parse_syntax("42")
  let proj = @projection.to_proj_node(syntax, Ref::new(0))
  inspect(proj.kind, content="Int(42)")
}

///|
test "to_proj_node: single let def + expression" {
  let syntax = parse_syntax("let x = 1\nx")
  let proj = @projection.to_proj_node(syntax, Ref::new(0))
  inspect(proj.kind, content="Let(\"x\", Int(1), Var(\"x\"))")
  inspect(proj.children.length(), content="2")
}

///|
test "to_proj_node: multiple let defs" {
  let syntax = parse_syntax("let x = 1\nlet y = 2\nx + y")
  let proj = @projection.to_proj_node(syntax, Ref::new(0))
  inspect(
    proj.kind,
    content="Let(\"x\", Int(1), Let(\"y\", Int(2), Bop(Plus, Var(\"x\"), Var(\"y\"))))",
  )
}

///|
test "to_proj_node: no final expression defaults to Unit" {
  let syntax = parse_syntax("let x = 1\n")
  let proj = @projection.to_proj_node(syntax, Ref::new(0))
  inspect(proj.kind, content="Let(\"x\", Int(1), Unit)")
}

///|
test "to_proj_node: empty document" {
  let syntax = parse_syntax("")
  let proj = @projection.to_proj_node(syntax, Ref::new(0))
  inspect(proj.kind, content="Unit")
}

///|
test "to_proj_node: single let def with expression" {
  let syntax = parse_syntax("let x = 1\nx")
  let proj = @projection.to_proj_node(syntax, Ref::new(0))
  inspect(proj.kind, content="Let(\"x\", Int(1), Var(\"x\"))")
}
