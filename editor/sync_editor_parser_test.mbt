// Tests for SyncEditor parser integration and sync operations.
// Uses the neutral TestExpr grammar — these exercise generic editor
// behavior (parse on set_text, reparse on edit, clear on empty, dirty
// reparse, CRDT sync), not language-specific parse trees. Lambda-grammar
// parse correctness lives in lang/lambda's own tests.

///|
test "parser: initial parse produces AST" {
  let se = try! @probe.new_test_editor("agent1")
  se.set_text("foo")
  inspect(
    @probe.get_test_ast(se),
    content=(
      #|Branch("", [Leaf("foo")])
    ),
  )
}

///|
test "parser: edit updates AST" {
  let se = try! @probe.new_test_editor("agent1")
  se.set_text("foo")
  inspect(
    @probe.get_test_ast(se),
    content=(
      #|Branch("", [Leaf("foo")])
    ),
  )
  se.set_text("f(x)")
  inspect(
    @probe.get_test_ast(se),
    content=(
      #|Branch("", [Branch("f", [Leaf("x")])])
    ),
  )
}

///|
test "parser: empty source clears AST" {
  let se = try! @probe.new_test_editor("agent1")
  se.set_text("foo")
  inspect(
    @probe.get_test_ast(se),
    content=(
      #|Branch("", [Leaf("foo")])
    ),
  )
  se.set_text("")
  inspect(
    @probe.get_test_ast(se),
    content=(
      #|Branch("", [])
    ),
  )
}

///|
test "parser: parse errors reported" {
  let se = try! @probe.new_test_editor("agent1")
  se.set_text("foo(") // unclosed '('
  let errors = se.get_errors()
  inspect(errors.is_empty(), content="false")
}

///|
test "parser: valid source has no errors" {
  let se = try! @probe.new_test_editor("agent1")
  se.set_text("f(x)")
  inspect(se.is_parse_valid(), content="true")
  inspect(se.get_errors().is_empty(), content="true")
}

///|
test "parser: mark_dirty forces reparse" {
  let se = try! @probe.new_test_editor("agent1")
  se.set_text("foo")
  let ast1 = @probe.get_test_ast(se)
  inspect(
    ast1,
    content=(
      #|Branch("", [Leaf("foo")])
    ),
  )
  se.mark_dirty()
  let ast2 = @probe.get_test_ast(se)
  inspect(ast1 == ast2, content="true")
}

///|
test "parser: empty source has no errors" {
  let se = try! @probe.new_test_editor("agent1")
  se.set_text("")
  inspect(se.get_errors().is_empty(), content="true")
}

///|
test "parser: successive edits maintain consistency" {
  let se = try! @probe.new_test_editor("agent1")
  se.set_text("a")
  inspect(
    @probe.get_test_ast(se),
    content=(
      #|Branch("", [Leaf("a")])
    ),
  )
  se.set_text("f(a)")
  inspect(
    @probe.get_test_ast(se),
    content=(
      #|Branch("", [Branch("f", [Leaf("a")])])
    ),
  )
  se.set_text("f(a b)")
  inspect(
    @probe.get_test_ast(se),
    content=(
      #|Branch("", [Branch("f", [Leaf("a"), Leaf("b")])])
    ),
  )
}

///|
test "sync: export and apply roundtrip" {
  let a = try! @probe.new_test_editor("agent-a")
  let b = try! @probe.new_test_editor("agent-b")
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
  let a = try! @probe.new_test_editor("agent-a")
  let b = try! @probe.new_test_editor("agent-b")
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
  let a = try! @probe.new_test_editor("agent-a")
  let b = try! @probe.new_test_editor("agent-b")
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
  let a = try! @probe.new_test_editor("agent-a")
  let b = try! @probe.new_test_editor("agent-b")
  a.set_text("f(x)")
  try! b.apply_sync(try! a.export_all())
  // Both editors should parse to the same AST
  inspect(@probe.get_test_ast(a) == @probe.get_test_ast(b), content="true")
}

///|
test "sync: empty export_all for empty editor" {
  let se = try! @probe.new_test_editor("agent1")
  let msg = try! se.export_all()
  inspect(msg.op_count() == 0, content="true")
}

///|
test "sync: version advances after insert" {
  let se = try! @probe.new_test_editor("agent1")
  let v1 = se.get_version()
  try! se.insert("x")
  let v2 = se.get_version()
  // Version should have changed after insert
  inspect(v1 == v2, content="false")
}
