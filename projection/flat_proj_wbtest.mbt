///|
test "to_flat_proj: single expression" {
  let ip = @loom.new_imperative_parser("42", @parser.lambda_grammar)
  let syntax = ip.parse()
  let fp = to_flat_proj(syntax, Ref::new(0))
  inspect(fp.defs.length(), content="0")
  inspect(
    fp.final_expr.map(fn(n) { n.kind.to_string() }),
    content="Some(\"Int(42)\")",
  )
}

///|
test "to_flat_proj: single let def + expression" {
  let ip = @loom.new_imperative_parser("let x = 1\nx", @parser.lambda_grammar)
  let syntax = ip.parse()
  let fp = to_flat_proj(syntax, Ref::new(0))
  inspect(fp.defs.length(), content="1")
  inspect(fp.defs[0].0, content="x")
  inspect(fp.defs[0].1.kind, content="Int(1)")
  inspect(
    fp.final_expr.map(fn(n) { n.kind.to_string() }),
    content="Some(\"Var(\\\"x\\\")\")",
  )
}

///|
test "to_flat_proj: multiple let defs" {
  let ip = @loom.new_imperative_parser(
    "let x = 1\nlet y = 2\nx + y", @parser.lambda_grammar,
  )
  let syntax = ip.parse()
  let fp = to_flat_proj(syntax, Ref::new(0))
  inspect(fp.defs.length(), content="2")
  inspect(fp.defs[0].0, content="x")
  inspect(fp.defs[1].0, content="y")
}

///|
test "to_flat_proj: no final expression defaults to None" {
  let ip = @loom.new_imperative_parser("let x = 1\n", @parser.lambda_grammar)
  let syntax = ip.parse()
  let fp = to_flat_proj(syntax, Ref::new(0))
  inspect(fp.defs.length(), content="1")
  inspect(fp.final_expr, content="None")
}

///|
test "to_flat_proj: empty document" {
  let ip = @loom.new_imperative_parser("", @parser.lambda_grammar)
  let syntax = ip.parse()
  let fp = to_flat_proj(syntax, Ref::new(0))
  inspect(fp.defs.length(), content="0")
  inspect(fp.final_expr, content="None")
}

///|
test "reconcile_flat_proj: unchanged defs preserve IDs" {
  let ip = @loom.new_imperative_parser(
    "let x = 1\nlet y = 2\nx", @parser.lambda_grammar,
  )
  let syntax = ip.parse()
  let counter = Ref::new(0)
  let old = to_flat_proj(syntax, counter)
  let old_ids = old.defs.map(fn(d) { d.3 })

  // Simulate reparse (same text, fresh IDs)
  let ip2 = @loom.new_imperative_parser(
    "let x = 1\nlet y = 2\nx", @parser.lambda_grammar,
  )
  let syntax2 = ip2.parse()
  let new_fp = to_flat_proj(syntax2, counter)

  let reconciled = reconcile_flat_proj(old, new_fp, counter)
  let new_ids = reconciled.defs.map(fn(d) { d.3 })
  inspect(new_ids == old_ids, content="true")
}

///|
test "reconcile_flat_proj: changed init gets reconciled children" {
  let counter = Ref::new(0)
  let ip1 = @loom.new_imperative_parser("let x = 1\nx", @parser.lambda_grammar)
  let old = to_flat_proj(ip1.parse(), counter)
  let old_id = old.defs[0].3

  let ip2 = @loom.new_imperative_parser("let x = 2\nx", @parser.lambda_grammar)
  let new_fp = to_flat_proj(ip2.parse(), counter)

  let reconciled = reconcile_flat_proj(old, new_fp, counter)
  // Def NodeId preserved (same name, same position)
  inspect(reconciled.defs[0].3 == old_id, content="true")
  // Init value changed
  inspect(reconciled.defs[0].1.kind, content="Int(2)")
}

///|
test "reconcile_flat_proj: insertion gets fresh ID" {
  let counter = Ref::new(0)
  let ip1 = @loom.new_imperative_parser("let x = 1\nx", @parser.lambda_grammar)
  let old = to_flat_proj(ip1.parse(), counter)
  let old_x_id = old.defs[0].3

  let ip2 = @loom.new_imperative_parser(
    "let x = 1\nlet y = 2\nx", @parser.lambda_grammar,
  )
  let new_fp = to_flat_proj(ip2.parse(), counter)
  let reconciled = reconcile_flat_proj(old, new_fp, counter)

  inspect(reconciled.defs.length(), content="2")
  // x preserved
  inspect(reconciled.defs[0].3 == old_x_id, content="true")
  // y is new — different ID from old x
  inspect(reconciled.defs[1].3 != old_x_id, content="true")
}

///|
test "reconcile_flat_proj: final_expr reconciled" {
  let counter = Ref::new(0)
  let ip1 = @loom.new_imperative_parser("42", @parser.lambda_grammar)
  let old = to_flat_proj(ip1.parse(), counter)
  let old_final_id = old.final_expr.unwrap().node_id

  let ip2 = @loom.new_imperative_parser("99", @parser.lambda_grammar)
  let new_fp = to_flat_proj(ip2.parse(), counter)

  let reconciled = reconcile_flat_proj(old, new_fp, counter)
  // Same kind (Int) → old ID preserved
  inspect(
    reconciled.final_expr.unwrap().node_id == old_final_id,
    content="true",
  )
  // Value changed
  inspect(reconciled.final_expr.unwrap().kind, content="Int(99)")
}
