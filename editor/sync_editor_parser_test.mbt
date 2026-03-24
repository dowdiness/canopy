// Tests for SyncEditor parser integration and sync operations.

///|
test "parser: initial parse produces AST" {
  let se = SyncEditor::new_lambda("agent1")
  se.set_text("42")
  let ast = se.get_ast()
  inspect(@ast.print_term(ast), content="42")
}

///|
test "parser: edit updates AST" {
  let se = SyncEditor::new_lambda("agent1")
  se.set_text("42")
  inspect(@ast.print_term(se.get_ast()), content="42")
  se.set_text("λx.x")
  let ast = se.get_ast()
  inspect(@ast.print_term(ast), content="(λx. x)")
}

///|
test "parser: empty source clears AST" {
  let se = SyncEditor::new_lambda("agent1")
  se.set_text("42")
  inspect(@ast.print_term(se.get_ast()), content="42")
  se.set_text("")
  // Empty source should yield Unit (the fallback)
  let ast = se.get_ast()
  inspect(@ast.print_term(ast), content="()")
}

///|
test "parser: parse errors reported" {
  let se = SyncEditor::new_lambda("agent1")
  se.set_text("λ.x")
  let errors = se.get_errors()
  inspect(errors.is_empty(), content="false")
}

///|
test "parser: valid source has no errors" {
  let se = SyncEditor::new_lambda("agent1")
  se.set_text("λx.x")
  inspect(se.is_parse_valid(), content="true")
  inspect(se.get_errors().is_empty(), content="true")
}

///|
test "parser: mark_dirty forces reparse" {
  let se = SyncEditor::new_lambda("agent1")
  se.set_text("42")
  let ast1 = se.get_ast()
  inspect(@ast.print_term(ast1), content="42")
  se.mark_dirty()
  let ast2 = se.get_ast()
  inspect(@ast.print_term(ast2), content="42")
}

///|
test "parser: get_ast_pretty contains expression" {
  let se = SyncEditor::new_lambda("agent1")
  se.set_text("42")
  let pretty = se.get_ast_pretty()
  inspect(pretty.contains("42"), content="true")
  inspect(pretty.contains("Expression:"), content="true")
}

///|
test "parser: complex expression parses correctly" {
  let se = SyncEditor::new_lambda("agent1")
  se.set_text("λf.λx.f x")
  inspect(@ast.print_term(se.get_ast()), content="(λf. (λx. (f x)))")
}

///|
test "parser: let binding with body" {
  let se = SyncEditor::new_lambda("agent1")
  se.set_text("let x = 1\nx + 2")
  let ast = se.get_ast()
  inspect(
    @ast.print_term(ast),
    content=(
      #|let x = 1
      #|(x + 2)
    ),
  )
}

///|
test "parser: if-then-else expression" {
  let se = SyncEditor::new_lambda("agent1")
  se.set_text("if x then 1 else 2")
  inspect(@ast.print_term(se.get_ast()), content="if x then 1 else 2")
}

///|
test "parser: arithmetic addition" {
  let se = SyncEditor::new_lambda("agent1")
  se.set_text("1 + 2 + 3")
  let ast = se.get_ast()
  inspect(@ast.print_term(ast), content="((1 + 2) + 3)")
}

///|
test "parser: empty source has no errors" {
  let se = SyncEditor::new_lambda("agent1")
  se.set_text("")
  inspect(se.get_errors().is_empty(), content="true")
}

///|
test "parser: resolution tracks bound and free variables" {
  let se = SyncEditor::new_lambda("agent1")
  se.set_text("λx.x + y")
  let res = se.get_resolution()
  // Verify resolution is populated (bound x, free y)
  inspect(res.vars.length() > 0, content="true")
}

///|
test "parser: successive edits maintain consistency" {
  let se = SyncEditor::new_lambda("agent1")
  se.set_text("1")
  inspect(@ast.print_term(se.get_ast()), content="1")
  se.set_text("1 + 2")
  inspect(@ast.print_term(se.get_ast()), content="(1 + 2)")
  se.set_text("1 + 2 + 3")
  inspect(@ast.print_term(se.get_ast()), content="((1 + 2) + 3)")
}

///|
test "sync: export and apply roundtrip" {
  let a = SyncEditor::new_lambda("agent-a")
  let b = SyncEditor::new_lambda("agent-b")
  try! a.insert("h")
  try! a.insert("e")
  try! a.insert("l")
  try! a.insert("l")
  try! a.insert("o")
  let msg = try! a.export_all()
  try! b.apply_sync(msg)
  inspect(b.get_text(), content="hello")
}

///|
test "sync: export_since for incremental sync" {
  let a = SyncEditor::new_lambda("agent-a")
  let b = SyncEditor::new_lambda("agent-b")
  // Initial content
  try! a.insert("x")
  try! b.apply_sync(try! a.export_all())
  inspect(b.get_text(), content="x")
  // Capture B's version before A adds more
  let b_version = b.get_version()
  // A inserts more text
  try! a.insert("y")
  try! a.insert("z")
  // Incremental sync: only send what B is missing
  let delta = try! a.export_since(b_version)
  try! b.apply_sync(delta)
  inspect(a.get_text(), content="xyz")
  inspect(b.get_text(), content="xyz")
}

///|
test "sync: bidirectional sync converges" {
  let a = SyncEditor::new_lambda("agent-a")
  let b = SyncEditor::new_lambda("agent-b")
  try! a.insert("a")
  try! b.insert("b")
  // Sync both ways
  try! b.apply_sync(try! a.export_all())
  try! a.apply_sync(try! b.export_all())
  // Both should have the same text
  inspect(a.get_text() == b.get_text(), content="true")
}

///|
test "sync: AST consistent after sync" {
  let a = SyncEditor::new_lambda("agent-a")
  let b = SyncEditor::new_lambda("agent-b")
  a.set_text("λx.x")
  try! b.apply_sync(try! a.export_all())
  // Both editors should parse to the same AST
  inspect(
    @ast.print_term(a.get_ast()) == @ast.print_term(b.get_ast()),
    content="true",
  )
}

///|
test "sync: empty export_all for empty editor" {
  let se = SyncEditor::new_lambda("agent1")
  let msg = try! se.export_all()
  inspect(msg.op_count() == 0, content="true")
}

///|
test "sync: version advances after insert" {
  let se = SyncEditor::new_lambda("agent1")
  let v1 = se.get_version()
  try! se.insert("x")
  let v2 = se.get_version()
  // Version should have changed after insert
  inspect(v1 == v2, content="false")
}
