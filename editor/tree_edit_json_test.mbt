// Tests for the JSON -> TreeEditOp parser

///|
test "parse_tree_edit_op: Delete" {
  let json = @json.parse("{\"type\": \"Delete\", \"node_id\": 5}")
  guard parse_tree_edit_op(json) is Ok(op)
  inspect(op, content="Delete(node_id=NodeId(5))")
}

///|
test "parse_tree_edit_op: WrapInLambda with var_name" {
  let json = @json.parse(
    "{\"type\": \"WrapInLambda\", \"node_id\": 3, \"var_name\": \"y\"}",
  )
  guard parse_tree_edit_op(json) is Ok(op)
  inspect(op, content="WrapInLambda(node_id=NodeId(3), var_name=\"y\")")
}

///|
test "parse_tree_edit_op: WrapInLambda defaults var_name to x" {
  let json = @json.parse("{\"type\": \"WrapInLambda\", \"node_id\": 7}")
  guard parse_tree_edit_op(json) is Ok(op)
  inspect(op, content="WrapInLambda(node_id=NodeId(7), var_name=\"x\")")
}

///|
test "parse_tree_edit_op: WrapInApp" {
  let json = @json.parse("{\"type\": \"WrapInApp\", \"node_id\": 2}")
  guard parse_tree_edit_op(json) is Ok(op)
  inspect(op, content="WrapInApp(node_id=NodeId(2))")
}

///|
test "parse_tree_edit_op: Select" {
  let json = @json.parse("{\"type\": \"Select\", \"node_id\": 1}")
  guard parse_tree_edit_op(json) is Ok(op)
  inspect(op, content="Select(node_id=NodeId(1))")
}

///|
test "parse_tree_edit_op: Collapse" {
  let json = @json.parse("{\"type\": \"Collapse\", \"node_id\": 4}")
  guard parse_tree_edit_op(json) is Ok(op)
  inspect(op, content="Collapse(node_id=NodeId(4))")
}

///|
test "parse_tree_edit_op: Expand" {
  let json = @json.parse("{\"type\": \"Expand\", \"node_id\": 6}")
  guard parse_tree_edit_op(json) is Ok(op)
  inspect(op, content="Expand(node_id=NodeId(6))")
}

///|
test "parse_tree_edit_op: unknown type" {
  let json = @json.parse("{\"type\": \"Foo\", \"node_id\": 1}")
  guard parse_tree_edit_op(json) is Err(msg)
  inspect(msg, content="unknown op type: Foo")
}

///|
test "parse_tree_edit_op: missing type" {
  let json = @json.parse("{\"node_id\": 1}")
  guard parse_tree_edit_op(json) is Err(msg)
  inspect(msg, content="missing type field")
}

///|
test "parse_tree_edit_op: not an object" {
  let json = @json.parse("42")
  guard parse_tree_edit_op(json) is Err(msg)
  inspect(msg, content="expected JSON object")
}
