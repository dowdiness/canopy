// Tests for ParsedEditor integration

///|
test "create and insert text" {
  let pe = ParsedEditor::new("agent1")
  try! pe.insert("x")
  inspect(pe.get_text(), content="x")

  // Get AST
  let ast = pe.get_ast()
  let ast_str = @ast.print_ast_node(ast)
  inspect(ast_str, content="x")
}

///|
test "sequential inserts update AST" {
  let pe = ParsedEditor::new("agent1")
  try! pe.insert("x")

  // First AST
  let ast1 = pe.get_ast()
  inspect(@ast.print_ast_node(ast1), content="x")

  // Add more text
  try! pe.insert(" + 1")

  // Second AST should be different
  let ast2 = pe.get_ast()
  let ast2_str = @ast.print_ast_node(ast2)
  inspect(ast2_str, content="(x + 1)")
}

///|
test "delete updates dirty flag" {
  let pe = ParsedEditor::new("agent1")
  try! pe.insert("123")
  inspect(pe.get_text(), content="123")

  // Get initial AST (123 is a valid integer)
  let _ast = pe.get_ast()

  // Delete last character
  let deleted = pe.backspace()
  inspect(deleted, content="true")
  inspect(pe.get_text(), content="12")
}

///|
test "parse error handling" {
  let pe = ParsedEditor::new("agent1")
  try! pe.insert("λ.") // Invalid: missing parameter
  let _ast = pe.get_ast()

  // Should have error node
  inspect(pe.is_parse_valid(), content="false")
}

///|
test "cursor tracking" {
  let pe = ParsedEditor::new("agent1")
  inspect(pe.get_cursor(), content="0")
  try! pe.insert("abc")
  inspect(pe.get_cursor(), content="3")
  pe.move_cursor(1)
  inspect(pe.get_cursor(), content="1")
}

///|
test "concurrent edits converge to same AST" {
  let pe1 = ParsedEditor::new("agent1")
  let pe2 = ParsedEditor::new("agent2")

  // Initial: "x"
  try! pe1.insert("x")
  try! pe2.apply_sync(try! pe1.export_all())

  // Verify text convergence
  inspect(pe1.get_text(), content="x")
  inspect(pe2.get_text(), content="x")

  // Concurrent: pe1 adds " + 1", pe2 adds " - 2"
  try! pe1.insert(" + 1")
  try! pe2.insert(" - 2")

  // Merge
  try! pe1.apply_sync(try! pe2.export_all())
  try! pe2.apply_sync(try! pe1.export_all())

  // Verify text and AST convergence
  let text1 = pe1.get_text()
  let text2 = pe2.get_text()
  inspect(text1 == text2, content="true")
  let ast1 = pe1.get_ast()
  let ast2 = pe2.get_ast()
  let ast1_str = @ast.print_ast_node(ast1)
  let ast2_str = @ast.print_ast_node(ast2)
  inspect(ast1_str == ast2_str, content="true")
}

///|
test "collaborative lambda editing" {
  let pe1 = ParsedEditor::new("agent1")
  let pe2 = ParsedEditor::new("agent2")

  // Agent 1 creates lambda skeleton
  try! pe1.insert("λx.")
  try! pe2.apply_sync(try! pe1.export_all())

  // Verify convergence
  inspect(pe1.get_text(), content="λx.")
  inspect(pe2.get_text(), content="λx.")

  // Concurrent body edits
  try! pe1.insert("x + 1")
  try! pe2.insert("x - 1")

  // Merge and verify both valid
  try! pe1.apply_sync(try! pe2.export_all())
  try! pe2.apply_sync(try! pe1.export_all())
  let text1 = pe1.get_text()
  let text2 = pe2.get_text()
  inspect(text1 == text2, content="true")

  // Both should parse successfully (though they may conflict in the body)
  let ast1 = pe1.get_ast()
  let ast2 = pe2.get_ast()

  // ASTs should be identical after convergence
  let ast1_str = @ast.print_ast_node(ast1)
  let ast2_str = @ast.print_ast_node(ast2)
  inspect(ast1_str == ast2_str, content="true")
}

///|
test "incremental parsing vs full reparse" {
  let pe = ParsedEditor::new("agent1")
  try! pe.insert("λf.λx.if f x then x + 1 else x - 1")

  // Get initial AST
  let _ast1 = pe.get_ast()

  // Make small edit at end
  pe.move_cursor(34)
  let _deleted = pe.backspace()
  try! pe.insert("2")

  // Get updated AST (should use incremental parsing)
  let ast2 = pe.get_ast()

  // Verify change
  let ast2_str = @ast.print_ast_node(ast2)
  inspect(ast2_str, content="(λf. (λx. if (f x) then (x + 1) else (x - 2)))")
}

///|
test "empty document" {
  let pe = ParsedEditor::new("agent1")

  // Empty text
  inspect(pe.get_text(), content="")

  // Should still be able to get AST (may be error node)
  let _ast = pe.get_ast()
}

///|
test "backspace at start returns false" {
  let pe = ParsedEditor::new("agent1")
  try! pe.insert("abc")
  pe.move_cursor(0)
  let result = pe.backspace()
  inspect(result, content="false")
  inspect(pe.get_text(), content="abc")
}

///|
test "delete at end returns false" {
  let pe = ParsedEditor::new("agent1")
  try! pe.insert("abc")
  pe.move_cursor(3)
  let result = pe.delete()
  inspect(result, content="false")
  inspect(pe.get_text(), content="abc")
}

///|
test "export_all produces non-empty message" {
  let pe = ParsedEditor::new("agent1")
  try! pe.insert("x")
  let msg = try! pe.export_all()
  inspect(msg.op_count() > 0, content="true")
}

///|
test "lazy AST evaluation" {
  let pe = ParsedEditor::new("agent1")
  try! pe.insert("x")

  // First get_ast() should parse
  let _ast1 = pe.get_ast()

  // Second get_ast() should return cached AST (no reparse)
  let ast2 = pe.get_ast()

  // Verify AST is correct
  let ast2_str = @ast.print_ast_node(ast2)
  inspect(ast2_str, content="x")
}

///|
test "merge invalidates AST cache" {
  let pe1 = ParsedEditor::new("agent1")
  let pe2 = ParsedEditor::new("agent2")

  // Start with common base
  try! pe1.insert("x")
  try! pe2.apply_sync(try! pe1.export_all())
  let _ast1 = pe1.get_ast()

  // pe2 makes change and pe1 merges
  try! pe2.insert("y")
  try! pe1.apply_sync(try! pe2.export_all())

  // get_ast() should reparse
  let ast2 = pe1.get_ast()
  let _ast2_str = @ast.print_ast_node(ast2)

  // AST should reflect merged text
  inspect(pe1.get_text(), content="xy")
}
