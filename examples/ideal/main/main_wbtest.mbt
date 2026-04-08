// Whitebox tests for update helpers.

///|
test "split_action_id without colon returns full id and empty choice" {
  let (base, choice) = split_action_id("delete")
  inspect(base, content="delete")
  inspect(choice, content="")
}

///|
test "split_action_id with colon splits on first colon" {
  let (base, choice) = split_action_id("change_op:Plus")
  inspect(base, content="change_op")
  inspect(choice, content="Plus")
}

///|
test "split_action_id with multiple colons splits on first only" {
  let (base, choice) = split_action_id("a:b:c")
  inspect(base, content="a")
  inspect(choice, content="b:c")
}

///|
test "split_action_id with trailing colon gives empty choice" {
  let (base, choice) = split_action_id("foo:")
  inspect(base, content="foo")
  inspect(choice, content="")
}

///|
test "split_action_id with leading colon gives empty base" {
  let (base, choice) = split_action_id(":bar")
  inspect(base, content="")
  inspect(choice, content="bar")
}

///|
test "parse_node_id valid" {
  inspect(parse_node_id("42") is Some(_), content="true")
}

///|
test "parse_node_id invalid returns None" {
  inspect(parse_node_id("abc"), content="None")
  inspect(parse_node_id(""), content="None")
}
