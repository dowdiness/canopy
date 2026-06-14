// Tests for SyncEditor (generic editor behavior over the neutral TestExpr
// grammar). Lambda-specific resolution and projection-shape tests live in
// lang/lambda; these exercise text editing, cursor, undo, CRDT sync, presence,
// and generic parse-on-edit.

///|
fn insert_each(se : SyncEditor[@probe.TestExpr], text : String) -> Unit raise {
  se.insert(text)
}

///|
fn insert_each_and_record(
  se : SyncEditor[@probe.TestExpr],
  text : String,
  timestamp_ms : Int,
) -> Unit raise {
  se.insert_and_record(text, timestamp_ms)
}

///|
test "SyncEditor: create and insert text" {
  let se = @probe.new_test_editor("agent1")
  try! se.insert("x")
  inspect(se.get_text(), content="x")
  inspect(
    @probe.get_test_ast(se),
    content=(
      #|Branch("", [Leaf("x")])
    ),
  )
}

///|
test "SyncEditor: sequential inserts update AST" {
  let se = @probe.new_test_editor("agent1")
  try! se.insert("f")
  inspect(
    @probe.get_test_ast(se),
    content=(
      #|Branch("", [Leaf("f")])
    ),
  )
  try! insert_each(se, "(x)")
  inspect(
    @probe.get_test_ast(se),
    content=(
      #|Branch("", [Branch("f", [Leaf("x")])])
    ),
  )
}

///|
test "SyncEditor: delete updates AST" {
  let se = @probe.new_test_editor("agent1")
  try! insert_each(se, "123")
  inspect(se.get_text(), content="123")
  let deleted = se.backspace()
  inspect(deleted, content="true")
  inspect(se.get_text(), content="12")
}

///|
test "SyncEditor: parse error handling" {
  let se = @probe.new_test_editor("agent1")
  try! insert_each(se, "f(") // unclosed '('
  let _ast = @probe.get_test_ast(se)
  inspect(se.is_parse_valid(), content="false")
}

///|
test "SyncEditor: cursor tracking" {
  let se = @probe.new_test_editor("agent1")
  inspect(se.get_cursor(), content="0")
  try! insert_each(se, "abc")
  inspect(se.get_cursor(), content="3")
  se.move_cursor(1)
  inspect(se.get_cursor(), content="1")
}

///|
test "SyncEditor: concurrent edits converge" {
  let se1 = @probe.new_test_editor("agent1")
  let se2 = @probe.new_test_editor("agent2")
  try! se1.insert("x")
  try! se2.apply_sync(try! se1.export_all())
  inspect(se1.get_text(), content="x")
  inspect(se2.get_text(), content="x")
  try! insert_each(se1, " a")
  try! insert_each(se2, " b")
  try! se1.apply_sync(try! se2.export_all())
  try! se2.apply_sync(try! se1.export_all())
  let text1 = se1.get_text()
  let text2 = se2.get_text()
  inspect(text1 == text2, content="true")
  inspect(@probe.get_test_ast(se1) == @probe.get_test_ast(se2), content="true")
}

///|
test "SyncEditor: collaborative editing converges" {
  let se1 = @probe.new_test_editor("agent1")
  let se2 = @probe.new_test_editor("agent2")
  try! insert_each(se1, "f(")
  try! se2.apply_sync(try! se1.export_all())
  inspect(se1.get_text(), content="f(")
  inspect(se2.get_text(), content="f(")
  try! insert_each(se1, "a)")
  try! insert_each(se2, "b)")
  try! se1.apply_sync(try! se2.export_all())
  try! se2.apply_sync(try! se1.export_all())
  inspect(se1.get_text() == se2.get_text(), content="true")
  inspect(@probe.get_test_ast(se1) == @probe.get_test_ast(se2), content="true")
}

///|
test "SyncEditor: incremental parsing vs full reparse" {
  let se = @probe.new_test_editor("agent1")
  try! insert_each(se, "foo(bar)")
  let _ast1 = @probe.get_test_ast(se)
  se.move_cursor(7) // just after 'r'
  let _deleted = se.backspace() // "foo(ba)"
  try! se.insert("z") // "foo(baz)"
  inspect(
    @probe.get_test_ast(se),
    content=(
      #|Branch("", [Branch("foo", [Leaf("baz")])])
    ),
  )
}

///|
test "SyncEditor: empty document" {
  let se = @probe.new_test_editor("agent1")
  inspect(se.get_text(), content="")
  let _ast = @probe.get_test_ast(se)
}

///|
test "SyncEditor: backspace at start returns false" {
  let se = @probe.new_test_editor("agent1")
  try! insert_each(se, "abc")
  se.move_cursor(0)
  inspect(se.backspace(), content="false")
  inspect(se.get_text(), content="abc")
}

///|
test "SyncEditor: delete at end returns false" {
  let se = @probe.new_test_editor("agent1")
  try! insert_each(se, "abc")
  se.move_cursor(3)
  inspect(se.delete(), content="false")
  inspect(se.get_text(), content="abc")
}

///|
test "SyncEditor: export_all produces non-empty message" {
  let se = @probe.new_test_editor("agent1")
  try! se.insert("x")
  let msg = try! se.export_all()
  inspect(msg.op_count() > 0, content="true")
}

///|
test "SyncEditor: lazy AST evaluation" {
  let se = @probe.new_test_editor("agent1")
  try! se.insert("x")
  let _ast1 = @probe.get_test_ast(se)
  inspect(
    @probe.get_test_ast(se),
    content=(
      #|Branch("", [Leaf("x")])
    ),
  )
}

///|
test "SyncEditor: merge invalidates AST cache" {
  let se1 = @probe.new_test_editor("agent1")
  let se2 = @probe.new_test_editor("agent2")
  try! se1.insert("x")
  try! se2.apply_sync(try! se1.export_all())
  let _ast1 = @probe.get_test_ast(se1)
  try! se2.insert("y")
  try! se1.apply_sync(try! se2.export_all())
  let _ast2 = @probe.get_test_ast(se1)
  inspect(
    se1.get_text(),
    content=(
      #|yx
    ),
  )
}

///|
test "SyncEditor: insert_and_record + undo roundtrip" {
  let se = @probe.new_test_editor("agent1")
  try! insert_each_and_record(se, "hello", 1000)
  inspect(se.get_text(), content="hello")
  inspect(se.can_undo(), content="true")
  let undone = se.undo()
  inspect(undone, content="true")
  inspect(se.get_text(), content="")
  inspect(se.get_cursor() <= se.get_text().length(), content="true")
  inspect(se.can_redo(), content="true")
  let redone = se.redo()
  inspect(redone, content="true")
  inspect(se.get_text(), content="hello")
  inspect(se.get_cursor() <= se.get_text().length(), content="true")
  try! se.insert_and_record("!", 3000)
  inspect(se.get_text().length(), content="6")
  inspect(se.get_cursor() <= se.get_text().length(), content="true")
}

///|
test "SyncEditor: backspace_and_record + undo" {
  let se = @probe.new_test_editor("agent1")
  try! insert_each_and_record(se, "abc", 1000)
  let deleted = se.backspace_and_record(2000)
  inspect(deleted, content="true")
  inspect(se.get_text(), content="ab")
  let undone = se.undo()
  inspect(undone, content="true")
  inspect(se.get_text(), content="abc")
  inspect(se.get_cursor() <= se.get_text().length(), content="true")
  try! se.insert_and_record("d", 3000)
  inspect(se.get_cursor() <= se.get_text().length(), content="true")
}

///|
test "SyncEditor: apply_text_edit replaces middle range and updates cursor" {
  let se = @probe.new_test_editor("agent1")
  se.set_text("abc")
  se.move_cursor(0)
  se.apply_text_edit(1, 1, "XYZ", 1000)
  inspect(se.get_text(), content="aXYZc")
  inspect(se.get_cursor(), content="4")
}

///|
test "SyncEditor: apply_text_edit records undo" {
  let se = @probe.new_test_editor("agent1")
  try! insert_each_and_record(se, "abc", 1000)
  se.apply_text_edit(1, 1, "XYZ", 2000)
  inspect(se.get_text(), content="aXYZc")
  let undone = se.undo()
  inspect(undone, content="true")
  inspect(se.get_text(), content="abc")
}

///|
test "SyncEditor: apply_text_edit records multi-character range undo" {
  let se = @probe.new_test_editor("agent1")
  try! insert_each_and_record(se, "abcdef", 1000)
  se.apply_text_edit(1, 3, "XYZ", 2000)
  inspect(se.get_text(), content="aXYZef")
  let undone = se.undo()
  inspect(undone, content="true")
  inspect(se.get_text(), content="abcdef")
}

///|
test "SyncEditor: apply_text_edit reuses parser structure on local edit" {
  let se = @probe.new_test_editor("agent1")
  se.set_text("foo(bar)")
  ignore(@probe.get_test_ast(se))
  se.apply_text_edit(6, 1, "z", 1000) // replace 'r' with 'z'
  inspect(se.get_text(), content="foo(baz)")
  inspect(
    @probe.get_test_ast(se),
    content=(
      #|Branch("", [Branch("foo", [Leaf("baz")])])
    ),
  )
}

///|
test "SyncEditor: clear_undo empties stacks" {
  let se = @probe.new_test_editor("agent1")
  try! se.insert_and_record("x", 1000)
  inspect(se.can_undo(), content="true")
  se.clear_undo()
  inspect(se.can_undo(), content="false")
  inspect(se.get_cursor() <= se.get_text().length(), content="true")
  try! se.insert_and_record("y", 2000)
  inspect(se.get_text(), content="xy")
  inspect(se.get_cursor() <= se.get_text().length(), content="true")
}

///|
test "SyncEditor: non-numeric agent IDs encode and delete presence" {
  let alice = @probe.new_test_editor("web-user")
  let bob = @probe.new_test_editor("local-user")
  alice.set_text("abcd")
  alice.move_cursor(2)
  alice.set_local_presence("Alice", "#ff0000")
  let initial = alice.encode_ephemeral_all()
  inspect(initial.length() > 0, content="true")
  bob.apply_ephemeral(initial)
  inspect(bob.get_peer_cursors().length(), content="1")
  let alice_cursor = bob.get_peer_cursors().get("web-user").unwrap()
  inspect(alice_cursor.adjusted_cursor, content="2")
  inspect(alice_cursor.display_name, content="Alice")
  alice.delete_local_presence()
  bob.apply_ephemeral(alice.encode_ephemeral_all())
  inspect(bob.get_peer_cursors().length(), content="0")
}

///|
test "SyncEditor: local edits and undo keep peer cursors in sync" {
  let local_editor = @probe.new_test_editor("local-user")
  let remote = @probe.new_test_editor("remote-user")
  local_editor.set_text("abcd")
  try! remote.apply_sync(try! local_editor.export_all())
  remote.move_cursor(3)
  remote.set_local_presence("Bob", "#00ff00")
  local_editor.apply_ephemeral(remote.encode_ephemeral_all())
  inspect(
    local_editor.get_peer_cursors().get("remote-user").unwrap().adjusted_cursor,
    content="3",
  )
  local_editor.move_cursor(0)
  try! local_editor.insert_and_record("X", 1000)
  // Insert at position 0 correctly places X before "abcd" per Fugue
  // Algorithm 1 (left child of rightOrigin). Peer cursor shifts to 4.
  inspect(
    local_editor.get_text(),
    content=(
      #|Xabcd
    ),
  )
  inspect(
    local_editor.get_peer_cursors().get("remote-user").unwrap().adjusted_cursor,
    content=(
      #|4
    ),
  )
  inspect(local_editor.undo(), content="true")
  inspect(local_editor.get_text(), content="abcd")
  inspect(
    local_editor.get_peer_cursors().get("remote-user").unwrap().adjusted_cursor,
    content="3",
  )
}

///|
test "SyncEditor: remote sync tracks actual merged text positions" {
  let viewer = @probe.new_test_editor("viewer")
  let remote = @probe.new_test_editor("peer-b")
  viewer.set_text("abcd")
  try! remote.apply_sync(try! viewer.export_all())
  remote.move_cursor(1)
  remote.set_local_presence("Bob", "#00ff00")
  viewer.apply_ephemeral(remote.encode_ephemeral_all())
  remote.move_cursor(0)
  try! remote.insert("X")
  remote.move_cursor(remote.get_text().length())
  try! remote.insert("Y")
  try! viewer.apply_sync(try! remote.export_all())
  // X at position 0 (before "abcd"), Y appended at end → "XabcdY"
  inspect(
    viewer.get_text(),
    content=(
      #|XabcdY
    ),
  )
  inspect(
    viewer.get_peer_cursors().get("peer-b").unwrap().adjusted_cursor,
    content=(
      #|2
    ),
  )
}

///|
test "SyncEditor: apply_sync does not pollute undo stack" {
  let se1 = @probe.new_test_editor("alice", capture_timeout_ms=500)
  let se2 = @probe.new_test_editor("bob", capture_timeout_ms=500)

  // Alice types
  try! se1.insert_and_record("hello", 1000)

  // Sync to Bob
  try! se2.apply_sync(try! se1.export_all())

  // Bob's undo stack should be empty — remote ops must not be tracked
  inspect(se2.can_undo(), content="false")
}

///|
test "SyncEditor: undo returns sync message for peer broadcast" {
  let se = @probe.new_test_editor("alice", capture_timeout_ms=500)

  // Type some text
  try! se.insert_and_record("hello", 1000)

  // Undo
  let msg = se.undo_and_export()
  inspect(se.get_text(), content="")

  // The returned message should contain ops
  match msg {
    Some(m) => inspect(m.is_empty(), content="false")
    None => inspect(false, content="true") // should have returned Some
  }
}

///|
test "SyncEditor: undo sync ops can be applied to peer" {
  let se1 = @probe.new_test_editor("alice", capture_timeout_ms=500)
  let se2 = @probe.new_test_editor("bob", capture_timeout_ms=500)

  // Alice types
  try! se1.insert_and_record("hello", 1000)

  // Sync initial state to Bob
  try! se2.apply_sync(try! se1.export_all())
  inspect(se2.get_text(), content="hello")

  // Alice undoes and gets sync ops
  let msg = se1.undo_and_export()
  inspect(se1.get_text(), content="")

  // Apply undo ops to Bob
  match msg {
    Some(m) => try! se2.apply_sync(m)
    None => ()
  }

  // Bob should converge with Alice
  inspect(se2.get_text(), content="")
}
