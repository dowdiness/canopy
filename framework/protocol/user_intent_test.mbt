// Tests for UserIntent JSON serialization and deserialization (round-trip).

///|
test "UserIntent::TextEdit to_json" {
  let intent = @protocol.UserIntent::TextEdit(from=1, to=5, insert="a")
  let s = intent.to_json().stringify()
  inspect(
    s,
    content="{\"type\":\"TextEdit\",\"from\":1,\"to\":5,\"insert\":\"a\"}",
  )
}

///|
test "UserIntent::TextEdit round-trip" {
  let intent = @protocol.UserIntent::TextEdit(from=1, to=5, insert="a")
  let json = intent.to_json()
  let decoded : @protocol.UserIntent = @json.from_json(json)
  assert_eq(intent, decoded)
}

///|
test "UserIntent::StructuralEdit to_json" {
  let params : Map[String, String] = {}
  params["var_name"] = "x"
  let intent = @protocol.UserIntent::StructuralEdit(
    node_id=@core.NodeId::from_int(42),
    op="WrapInLambda",
    params~,
  )
  let s = intent.to_json().stringify()
  assert_true(s.contains("\"type\":\"StructuralEdit\""))
  assert_true(s.contains("\"node_id\":42"))
  assert_true(s.contains("\"op\":\"WrapInLambda\""))
  assert_true(s.contains("\"var_name\":\"x\""))
}

///|
test "UserIntent::StructuralEdit round-trip" {
  let params : Map[String, String] = {}
  params["var_name"] = "y"
  let intent = @protocol.UserIntent::StructuralEdit(
    node_id=@core.NodeId::from_int(7),
    op="Delete",
    params~,
  )
  let json = intent.to_json()
  let decoded : @protocol.UserIntent = @json.from_json(json)
  assert_eq(intent, decoded)
}

///|
test "UserIntent::StructuralEdit round-trip with empty params" {
  let intent = @protocol.UserIntent::StructuralEdit(
    node_id=@core.NodeId::from_int(7),
    op="Delete",
    params={},
  )
  let json = intent.to_json()
  let decoded : @protocol.UserIntent = @json.from_json(json)
  assert_eq(intent, decoded)
}

///|
test "UserIntent::SelectNode round-trip" {
  let intent = @protocol.UserIntent::SelectNode(
    node_id=@core.NodeId::from_int(99),
  )
  let json = intent.to_json()
  let decoded : @protocol.UserIntent = @json.from_json(json)
  assert_eq(intent, decoded)
}

///|
test "UserIntent::SetCursor round-trip" {
  let intent = @protocol.UserIntent::SetCursor(position=42)
  let json = intent.to_json()
  let decoded : @protocol.UserIntent = @json.from_json(json)
  assert_eq(intent, decoded)
}

///|
test "UserIntent::Undo to_json" {
  let intent = @protocol.UserIntent::Undo
  let s = intent.to_json().stringify()
  inspect(s, content="{\"type\":\"Undo\"}")
}

///|
test "UserIntent::Undo round-trip" {
  let intent = @protocol.UserIntent::Undo
  let json = intent.to_json()
  let decoded : @protocol.UserIntent = @json.from_json(json)
  assert_eq(intent, decoded)
}

///|
test "UserIntent::Redo round-trip" {
  let intent = @protocol.UserIntent::Redo
  let json = intent.to_json()
  let decoded : @protocol.UserIntent = @json.from_json(json)
  assert_eq(intent, decoded)
}

///|
test "UserIntent::CommitEdit round-trip" {
  let intent = @protocol.UserIntent::CommitEdit(
    node_id=@core.NodeId::from_int(5),
    value="new_name",
  )
  let json = intent.to_json()
  let decoded : @protocol.UserIntent = @json.from_json(json)
  assert_eq(intent, decoded)
}

///|
test "UserIntent from_json rejects unknown type" {
  let json = @json.parse("{\"type\": \"Unknown\"}")
  let result : Result[@protocol.UserIntent, _] = Ok(@json.from_json(json)) catch {
    e => Err(e)
  }
  assert_true(result is Err(_))
}

///|
test "UserIntent from_json rejects non-object" {
  let json = Json::array([])
  let result : Result[@protocol.UserIntent, _] = Ok(@json.from_json(json)) catch {
    e => Err(e)
  }
  assert_true(result is Err(_))
}

///|
test "UserIntent from_json string parse" {
  let json = @json.parse("{\"type\":\"SetCursor\",\"position\":10}")
  let decoded : @protocol.UserIntent = @json.from_json(json)
  assert_eq(decoded, @protocol.UserIntent::SetCursor(position=10))
}
