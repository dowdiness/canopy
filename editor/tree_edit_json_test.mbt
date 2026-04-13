// Tests for the JSON -> TreeEditOp parser

///|
test "parse_tree_edit_op: Delete" {
  let json = @json.parse("{\"type\": \"Delete\", \"node_id\": 5}")
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(op, content="Delete(node_id=NodeId(5))")
}

///|
test "parse_tree_edit_op: WrapInLambda with var_name" {
  let json = @json.parse(
    "{\"type\": \"WrapInLambda\", \"node_id\": 3, \"var_name\": \"y\"}",
  )
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(op, content="WrapInLambda(node_id=NodeId(3), var_name=\"y\")")
}

///|
test "parse_tree_edit_op: WrapInLambda defaults var_name to x" {
  let json = @json.parse("{\"type\": \"WrapInLambda\", \"node_id\": 7}")
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(op, content="WrapInLambda(node_id=NodeId(7), var_name=\"x\")")
}

///|
test "parse_tree_edit_op: WrapInApp" {
  let json = @json.parse("{\"type\": \"WrapInApp\", \"node_id\": 2}")
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(op, content="WrapInApp(node_id=NodeId(2))")
}

///|
test "parse_tree_edit_op: Select" {
  let json = @json.parse("{\"type\": \"Select\", \"node_id\": 1}")
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(op, content="Select(node_id=NodeId(1))")
}

///|
test "parse_tree_edit_op: Collapse" {
  let json = @json.parse("{\"type\": \"Collapse\", \"node_id\": 4}")
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(op, content="Collapse(node_id=NodeId(4))")
}

///|
test "parse_tree_edit_op: Expand" {
  let json = @json.parse("{\"type\": \"Expand\", \"node_id\": 6}")
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(op, content="Expand(node_id=NodeId(6))")
}

///|
test "parse_tree_edit_op: unknown type" {
  let json = @json.parse("{\"type\": \"Foo\", \"node_id\": 1}")
  guard (try? @lambda.parse_tree_edit_op(json)) is Err(msg)
  inspect(msg.message(), content="unknown op type: Foo")
}

///|
test "parse_tree_edit_op: missing type" {
  let json = @json.parse("{\"node_id\": 1}")
  guard (try? @lambda.parse_tree_edit_op(json)) is Err(msg)
  inspect(msg.message(), content="missing type field")
}

///|
test "parse_tree_edit_op: type must be string" {
  let json = @json.parse("{\"type\": 1, \"node_id\": 1}")
  guard (try? @lambda.parse_tree_edit_op(json)) is Err(msg)
  inspect(msg.message(), content="type must be a string")
}

///|
test "parse_tree_edit_op: not an object" {
  let json = @json.parse("42")
  guard (try? @lambda.parse_tree_edit_op(json)) is Err(msg)
  inspect(msg.message(), content="expected JSON object")
}

///|
test "parse_tree_edit_op: Unwrap" {
  let json = @json.parse(
    "{\"type\": \"Unwrap\", \"node_id\": 5, \"keep_child_index\": 0}",
  )
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(op, content="Unwrap(node_id=NodeId(5), keep_child_index=0)")
}

///|
test "parse_tree_edit_op: SwapChildren" {
  let json = @json.parse("{\"type\": \"SwapChildren\", \"node_id\": 3}")
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(op, content="SwapChildren(node_id=NodeId(3))")
}

///|
test "parse_tree_edit_op: WrapInIf" {
  let json = @json.parse("{\"type\": \"WrapInIf\", \"node_id\": 2}")
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(op, content="WrapInIf(node_id=NodeId(2))")
}

///|
test "parse_tree_edit_op: WrapInBop" {
  let json = @json.parse(
    "{\"type\": \"WrapInBop\", \"node_id\": 4, \"op\": \"Plus\"}",
  )
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(op, content="WrapInBop(node_id=NodeId(4), op=Plus)")
}

///|
test "parse_tree_edit_op: ChangeOperator" {
  let json = @json.parse(
    "{\"type\": \"ChangeOperator\", \"node_id\": 6, \"new_op\": \"Minus\"}",
  )
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(op, content="ChangeOperator(node_id=NodeId(6), new_op=Minus)")
}

///|
test "parse_tree_edit_op: ExtractToLet" {
  let json = @json.parse(
    "{\"type\": \"ExtractToLet\", \"node_id\": 7, \"var_name\": \"foo\"}",
  )
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(op, content="ExtractToLet(node_id=NodeId(7), var_name=\"foo\")")
}

///|
test "parse_tree_edit_op: InlineDefinition" {
  let json = @json.parse("{\"type\": \"InlineDefinition\", \"node_id\": 8}")
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(op, content="InlineDefinition(node_id=NodeId(8))")
}

///|
test "parse_tree_edit_op: Rename" {
  let json = @json.parse(
    "{\"type\": \"Rename\", \"node_id\": 9, \"new_name\": \"bar\"}",
  )
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(op, content="Rename(node_id=NodeId(9), new_name=\"bar\")")
}

///|
test "parse_tree_edit_op: DeleteBinding" {
  let json = @json.parse(
    "{\"type\": \"DeleteBinding\", \"binding_node_id\": 5}",
  )
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(op, content="DeleteBinding(binding_node_id=NodeId(5))")
}

///|
test "parse_tree_edit_op: InlineAllUsages" {
  let json = @json.parse(
    "{\"type\": \"InlineAllUsages\", \"binding_node_id\": 10}",
  )
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(op, content="InlineAllUsages(binding_node_id=NodeId(10))")
}

///|
test "parse_tree_edit_op: DuplicateBinding" {
  let json = @json.parse(
    "{\"type\": \"DuplicateBinding\", \"binding_node_id\": 11}",
  )
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(op, content="DuplicateBinding(binding_node_id=NodeId(11))")
}

///|
test "parse_tree_edit_op: MoveBindingUp" {
  let json = @json.parse(
    "{\"type\": \"MoveBindingUp\", \"binding_node_id\": 12}",
  )
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(op, content="MoveBindingUp(binding_node_id=NodeId(12))")
}

///|
test "parse_tree_edit_op: MoveBindingDown" {
  let json = @json.parse(
    "{\"type\": \"MoveBindingDown\", \"binding_node_id\": 13}",
  )
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(op, content="MoveBindingDown(binding_node_id=NodeId(13))")
}

///|
test "parse_tree_edit_op: AddBinding" {
  let json = @json.parse("{\"type\": \"AddBinding\", \"module_node_id\": 14}")
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(op, content="AddBinding(module_node_id=NodeId(14))")
}

///|
test "parse_tree_edit_op: DeleteBinding missing binding_node_id" {
  let json = @json.parse("{\"type\": \"DeleteBinding\", \"node_id\": 5}")
  guard (try? @lambda.parse_tree_edit_op(json)) is Err(msg)
  inspect(msg.message(), content="missing binding_node_id field")
}

///|
test "parse_tree_edit_op: Delete node_id must be number" {
  let json = @json.parse("{\"type\": \"Delete\", \"node_id\": \"five\"}")
  guard (try? @lambda.parse_tree_edit_op(json)) is Err(msg)
  inspect(msg.message(), content="node_id must be a number")
}

///|
test "parse_tree_edit_op: Unwrap keep_child_index must be number" {
  let json = @json.parse(
    "{\"type\": \"Unwrap\", \"node_id\": 5, \"keep_child_index\": \"0\"}",
  )
  guard (try? @lambda.parse_tree_edit_op(json)) is Err(msg)
  inspect(msg.message(), content="keep_child_index must be a number")
}

///|
test "parse_tree_edit_op: WrapInBop op must be string" {
  let json = @json.parse("{\"type\": \"WrapInBop\", \"node_id\": 4, \"op\": 1}")
  guard (try? @lambda.parse_tree_edit_op(json)) is Err(msg)
  inspect(msg.message(), content="op must be a string")
}

///|
test "parse_tree_edit_op: AddBinding missing module_node_id" {
  let json = @json.parse("{\"type\": \"AddBinding\", \"node_id\": 5}")
  guard (try? @lambda.parse_tree_edit_op(json)) is Err(msg)
  inspect(msg.message(), content="missing module_node_id field")
}

///|
test "parse_tree_edit_op: StartDrag" {
  let json = @json.parse("{\"type\": \"StartDrag\", \"node_id\": 10}")
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(op, content="StartDrag(node_id=NodeId(10))")
}

///|
test "parse_tree_edit_op: StartDrag missing node_id" {
  let json = @json.parse("{\"type\": \"StartDrag\"}")
  guard (try? @lambda.parse_tree_edit_op(json)) is Err(msg)
  inspect(msg.message(), content="missing node_id field")
}

///|
test "parse_tree_edit_op: DragOver" {
  let json = @json.parse(
    "{\"type\": \"DragOver\", \"target\": 3, \"position\": \"Before\"}",
  )
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(op, content="DragOver(target=NodeId(3), position=Before)")
}

///|
test "parse_tree_edit_op: DragOver missing position" {
  let json = @json.parse("{\"type\": \"DragOver\", \"target\": 3}")
  guard (try? @lambda.parse_tree_edit_op(json)) is Err(msg)
  inspect(msg.message(), content="missing position field")
}

///|
test "parse_tree_edit_op: Drop" {
  let json = @json.parse(
    "{\"type\": \"Drop\", \"source\": 1, \"target\": 5, \"position\": \"After\"}",
  )
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(
    op,
    content="Drop(source=NodeId(1), target=NodeId(5), position=After)",
  )
}

///|
test "parse_tree_edit_op: Drop with Inside position" {
  let json = @json.parse(
    "{\"type\": \"Drop\", \"source\": 2, \"target\": 7, \"position\": \"Inside\"}",
  )
  guard (try? @lambda.parse_tree_edit_op(json)) is Ok(op)
  inspect(
    op,
    content="Drop(source=NodeId(2), target=NodeId(7), position=Inside)",
  )
}

///|
test "parse_tree_edit_op: Drop missing source" {
  let json = @json.parse(
    "{\"type\": \"Drop\", \"target\": 5, \"position\": \"After\"}",
  )
  guard (try? @lambda.parse_tree_edit_op(json)) is Err(msg)
  inspect(msg.message(), content="missing source field")
}

///|
test "parse_tree_edit_op: Drop missing target" {
  let json = @json.parse(
    "{\"type\": \"Drop\", \"source\": 1, \"position\": \"After\"}",
  )
  guard (try? @lambda.parse_tree_edit_op(json)) is Err(msg)
  inspect(msg.message(), content="missing target field")
}

///|
test "parse_tree_edit_op: Drop bad position string" {
  let json = @json.parse(
    "{\"type\": \"Drop\", \"source\": 1, \"target\": 5, \"position\": \"Left\"}",
  )
  guard (try? @lambda.parse_tree_edit_op(json)) is Err(msg)
  inspect(msg.message(), content="position must be a string")
}

///|
test "parse_tree_edit_op: Drop position not a string" {
  let json = @json.parse(
    "{\"type\": \"Drop\", \"source\": 1, \"target\": 5, \"position\": 42}",
  )
  guard (try? @lambda.parse_tree_edit_op(json)) is Err(msg)
  inspect(msg.message(), content="position must be a string")
}
