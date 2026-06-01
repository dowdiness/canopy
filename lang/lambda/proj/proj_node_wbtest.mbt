///|
test "syntax_to_proj_node: block expression with def and body" {
  let (proj, errors) = parse_to_proj_node("{ let x = 1; x }")
  inspect(errors.is_empty(), content="true")
  inspect(
    proj.kind,
    content=(
      #|Module([("x", Int(1))], Var("x"))
    ),
  )
  inspect(proj.children.length(), content="2")
  inspect(proj.children[0].kind, content="LetDef(\"x\", Int(1))")
  inspect(proj.children[0].children.length(), content="1")
  inspect(proj.children[0].children[0].kind, content="Int(1)")
}

///|
test "syntax_to_proj_node: hole literal" {
  let (proj, errors) = parse_to_proj_node("_")
  inspect(errors.is_empty(), content="true")
  inspect(proj.kind, content="Hole(0)")
}
