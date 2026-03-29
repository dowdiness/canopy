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
  inspect(msg.message(), content="unknown op type: Foo")
}

///|
test "parse_tree_edit_op: missing type" {
  let json = @json.parse("{\"node_id\": 1}")
  guard parse_tree_edit_op(json) is Err(msg)
  inspect(msg.message(), content="missing type field")
}

///|
test "parse_tree_edit_op: type must be string" {
  let json = @json.parse("{\"type\": 1, \"node_id\": 1}")
  guard parse_tree_edit_op(json) is Err(msg)
  inspect(msg.message(), content="type must be a string")
}

///|
test "parse_tree_edit_op: not an object" {
  let json = @json.parse("42")
  guard parse_tree_edit_op(json) is Err(msg)
  inspect(msg.message(), content="expected JSON object")
}

///|
test "parse_tree_edit_op: Unwrap" {
  let json = @json.parse(
    "{\"type\": \"Unwrap\", \"node_id\": 5, \"keep_child_index\": 0}",
  )
  guard parse_tree_edit_op(json) is Ok(op)
  inspect(op, content="Unwrap(node_id=NodeId(5), keep_child_index=0)")
}

///|
test "parse_tree_edit_op: SwapChildren" {
  let json = @json.parse("{\"type\": \"SwapChildren\", \"node_id\": 3}")
  guard parse_tree_edit_op(json) is Ok(op)
  inspect(op, content="SwapChildren(node_id=NodeId(3))")
}

///|
test "parse_tree_edit_op: WrapInIf" {
  let json = @json.parse("{\"type\": \"WrapInIf\", \"node_id\": 2}")
  guard parse_tree_edit_op(json) is Ok(op)
  inspect(op, content="WrapInIf(node_id=NodeId(2))")
}

///|
test "parse_tree_edit_op: WrapInBop" {
  let json = @json.parse(
    "{\"type\": \"WrapInBop\", \"node_id\": 4, \"op\": \"Plus\"}",
  )
  guard parse_tree_edit_op(json) is Ok(op)
  inspect(op, content="WrapInBop(node_id=NodeId(4), op=Plus)")
}

///|
test "parse_tree_edit_op: ChangeOperator" {
  let json = @json.parse(
    "{\"type\": \"ChangeOperator\", \"node_id\": 6, \"new_op\": \"Minus\"}",
  )
  guard parse_tree_edit_op(json) is Ok(op)
  inspect(op, content="ChangeOperator(node_id=NodeId(6), new_op=Minus)")
}

///|
test "parse_tree_edit_op: ExtractToLet" {
  let json = @json.parse(
    "{\"type\": \"ExtractToLet\", \"node_id\": 7, \"var_name\": \"foo\"}",
  )
  guard parse_tree_edit_op(json) is Ok(op)
  inspect(op, content="ExtractToLet(node_id=NodeId(7), var_name=\"foo\")")
}

///|
test "parse_tree_edit_op: InlineDefinition" {
  let json = @json.parse("{\"type\": \"InlineDefinition\", \"node_id\": 8}")
  guard parse_tree_edit_op(json) is Ok(op)
  inspect(op, content="InlineDefinition(node_id=NodeId(8))")
}

///|
test "parse_tree_edit_op: Rename" {
  let json = @json.parse(
    "{\"type\": \"Rename\", \"node_id\": 9, \"new_name\": \"bar\"}",
  )
  guard parse_tree_edit_op(json) is Ok(op)
  inspect(op, content="Rename(node_id=NodeId(9), new_name=\"bar\")")
}

///|
test "parse_tree_edit_op: DeleteBinding" {
  let json = @json.parse(
    "{\"type\": \"DeleteBinding\", \"binding_node_id\": 5}",
  )
  guard parse_tree_edit_op(json) is Ok(op)
  inspect(op, content="DeleteBinding(binding_node_id=NodeId(5))")
}

///|
test "parse_tree_edit_op: InlineAllUsages" {
  let json = @json.parse(
    "{\"type\": \"InlineAllUsages\", \"binding_node_id\": 10}",
  )
  guard parse_tree_edit_op(json) is Ok(op)
  inspect(op, content="InlineAllUsages(binding_node_id=NodeId(10))")
}

///|
test "parse_tree_edit_op: DuplicateBinding" {
  let json = @json.parse(
    "{\"type\": \"DuplicateBinding\", \"binding_node_id\": 11}",
  )
  guard parse_tree_edit_op(json) is Ok(op)
  inspect(op, content="DuplicateBinding(binding_node_id=NodeId(11))")
}

///|
test "parse_tree_edit_op: MoveBindingUp" {
  let json = @json.parse(
    "{\"type\": \"MoveBindingUp\", \"binding_node_id\": 12}",
  )
  guard parse_tree_edit_op(json) is Ok(op)
  inspect(op, content="MoveBindingUp(binding_node_id=NodeId(12))")
}

///|
test "parse_tree_edit_op: MoveBindingDown" {
  let json = @json.parse(
    "{\"type\": \"MoveBindingDown\", \"binding_node_id\": 13}",
  )
  guard parse_tree_edit_op(json) is Ok(op)
  inspect(op, content="MoveBindingDown(binding_node_id=NodeId(13))")
}

///|
test "parse_tree_edit_op: AddBinding" {
  let json = @json.parse("{\"type\": \"AddBinding\", \"module_node_id\": 14}")
  guard parse_tree_edit_op(json) is Ok(op)
  inspect(op, content="AddBinding(module_node_id=NodeId(14))")
}

///|
test "parse_tree_edit_op: DeleteBinding missing binding_node_id" {
  let json = @json.parse("{\"type\": \"DeleteBinding\", \"node_id\": 5}")
  guard parse_tree_edit_op(json) is Err(msg)
  inspect(msg.message(), content="missing binding_node_id field")
}

///|
test "parse_tree_edit_op: Delete node_id must be number" {
  let json = @json.parse("{\"type\": \"Delete\", \"node_id\": \"five\"}")
  guard parse_tree_edit_op(json) is Err(msg)
  inspect(msg.message(), content="node_id must be a number")
}

///|
test "parse_tree_edit_op: Unwrap keep_child_index must be number" {
  let json = @json.parse(
    "{\"type\": \"Unwrap\", \"node_id\": 5, \"keep_child_index\": \"0\"}",
  )
  guard parse_tree_edit_op(json) is Err(msg)
  inspect(msg.message(), content="keep_child_index must be a number")
}

///|
test "parse_tree_edit_op: WrapInBop op must be string" {
  let json = @json.parse("{\"type\": \"WrapInBop\", \"node_id\": 4, \"op\": 1}")
  guard parse_tree_edit_op(json) is Err(msg)
  inspect(msg.message(), content="op must be a string")
}

///|
test "parse_tree_edit_op: AddBinding missing module_node_id" {
  let json = @json.parse("{\"type\": \"AddBinding\", \"node_id\": 5}")
  guard parse_tree_edit_op(json) is Err(msg)
  inspect(msg.message(), content="missing module_node_id field")
}
