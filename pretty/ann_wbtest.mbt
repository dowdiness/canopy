///|
test "Ann construction" {
  let ann = { category: Keyword, node_id: None }
  inspect(ann.category, content="Keyword")
}

///|
test "Ann with node_id" {
  let ann = { category: Identifier, node_id: Some(@core.NodeId::from_int(42)) }
  inspect(ann.node_id is None, content="false")
}

///|
test "Span construction" {
  let span : Span = { start: 0, end: 5 }
  inspect(span.start, content="0")
  inspect(span.end, content="5")
}
