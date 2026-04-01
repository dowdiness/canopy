///|
fn parse_syntax(text : String) -> @seam.SyntaxNode raise {
  let (cst, _) = @parser.parse_cst(text) catch { _ => fail("parse failed") }
  @seam.SyntaxNode::from_cst(cst)
}

///|
test "to_proj_node: single expression" {
  let syntax = parse_syntax("42")
  let proj = @lambda_proj.to_proj_node(syntax, Ref::new(0))
  inspect(proj.kind, content="Int(42)")
}

///|
test "to_proj_node: single let def + expression" {
  let syntax = parse_syntax("let x = 1\nx")
  let proj = @lambda_proj.to_proj_node(syntax, Ref::new(0))
  inspect(
    proj.kind,
    content=(
      #|Module([("x", Int(1))], Var("x"))
    ),
  )
  inspect(proj.children.length(), content="2")
}

///|
test "to_proj_node: multiple let defs" {
  let syntax = parse_syntax("let x = 1\nlet y = 2\nx + y")
  let proj = @lambda_proj.to_proj_node(syntax, Ref::new(0))
  inspect(
    proj.kind,
    content=(
      #|Module([("x", Int(1)), ("y", Int(2))], Bop(Plus, Var("x"), Var("y")))
    ),
  )
  // Module has 3 children: 2 init ProjNodes + 1 body ProjNode
  inspect(proj.children.length(), content="3")
}

///|
test "to_proj_node: no final expression defaults to Unit" {
  let syntax = parse_syntax("let x = 1\n")
  let proj = @lambda_proj.to_proj_node(syntax, Ref::new(0))
  inspect(
    proj.kind,
    content=(
      #|Module([("x", Int(1))], Unit)
    ),
  )
}

///|
test "to_proj_node: empty document" {
  let syntax = parse_syntax("")
  let proj = @lambda_proj.to_proj_node(syntax, Ref::new(0))
  inspect(proj.kind, content="Unit")
}

///|
test "to_proj_node: single let def with expression" {
  let syntax = parse_syntax("let x = 1\nx")
  let proj = @lambda_proj.to_proj_node(syntax, Ref::new(0))
  inspect(
    proj.kind,
    content=(
      #|Module([("x", Int(1))], Var("x"))
    ),
  )
}
