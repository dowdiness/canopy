///|
test "ProjNode JSON export for simple expression" {
  let (proj, _) = @lambda_proj.parse_to_proj_node("42")
  inspect(
    proj.to_json().stringify(),
    content=(
      #|{"node_id":0,"kind":["Int",42],"children":[],"start":0,"end":2}
    ),
  )
}

///|
test "ProjNode JSON export for lambda" {
  let (proj, _) = @lambda_proj.parse_to_proj_node("\u{03BB}x.x")
  inspect(
    proj.to_json().stringify(),
    content=(
      #|{"node_id":1,"kind":["Lam","x",["Var","x"]],"children":[{"node_id":0,"kind":["Var","x"],"children":[],"start":3,"end":4}],"start":0,"end":4}
    ),
  )
}

///|
test "ProjNode JSON export for application" {
  let (proj, _) = @lambda_proj.parse_to_proj_node("f x")
  inspect(
    proj.to_json().stringify(),
    content=(
      #|{"node_id":2,"kind":["App",["Var","f"],["Var","x"]],"children":[{"node_id":0,"kind":["Var","f"],"children":[],"start":0,"end":1},{"node_id":1,"kind":["Var","x"],"children":[],"start":1,"end":3}],"start":0,"end":3}
    ),
  )
}

///|
test "ProjNode JSON export for binary op" {
  let (proj, _) = @lambda_proj.parse_to_proj_node("1 + 2")
  inspect(
    proj.to_json().stringify(),
    content=(
      #|{"node_id":2,"kind":["Bop","Plus",["Int",1],["Int",2]],"children":[{"node_id":0,"kind":["Int",1],"children":[],"start":0,"end":1},{"node_id":1,"kind":["Int",2],"children":[],"start":3,"end":5}],"start":0,"end":5}
    ),
  )
}

///|
test "ProjNode JSON export for module" {
  let (proj, _) = @lambda_proj.parse_to_proj_node("let x = 1\nx")
  inspect(
    proj.to_json().stringify(),
    content=(
      #|{"node_id":2,"kind":["Module",[["x",["Int",1]]],["Var","x"]],"children":[{"node_id":0,"kind":["Int",1],"children":[],"start":7,"end":9},{"node_id":1,"kind":["Var","x"],"children":[],"start":10,"end":11}],"start":0,"end":11}
    ),
  )
}

///|
test "SourceMap JSON export" {
  let (proj, _) = @lambda_proj.parse_to_proj_node("1 + 2")
  let sm = @core.SourceMap::from_ast(proj)
  inspect(
    sm.to_json().stringify(),
    content=(
      #|[{"node_id":2,"start":0,"end":5},{"node_id":0,"start":0,"end":1},{"node_id":1,"start":3,"end":5}]
    ),
  )
}
