///|
test "command_for_key maps the four arrows" {
  inspect(command_for_key("ArrowUp") is Some(NavUp), content="true")
  inspect(command_for_key("ArrowDown") is Some(NavDown), content="true")
  inspect(command_for_key("ArrowLeft") is Some(NavLeft), content="true")
  inspect(command_for_key("ArrowRight") is Some(NavRight), content="true")
}

///|
test "command_for_key maps Enter to Activate" {
  inspect(command_for_key("Enter") is Some(Activate), content="true")
}

///|
test "command_for_key leaves app-owned keys unclaimed" {
  // Delete / Backspace (structural edit), "." (action overlay), Escape
  // (close/deselect), and typeahead are the consumer's, not the behavior's.
  inspect(command_for_key("Delete") is None, content="true")
  inspect(command_for_key("Backspace") is None, content="true")
  inspect(command_for_key("Escape") is None, content="true")
  inspect(command_for_key(".") is None, content="true")
  inspect(command_for_key(" ") is None, content="true")
  inspect(command_for_key("Home") is None, content="true")
  inspect(command_for_key("End") is None, content="true")
  inspect(command_for_key("a") is None, content="true")
}

///|
test "expanded_value omits the attr for leaves" {
  inspect(expanded_value(Leaf) is None, content="true")
  inspect(expanded_value(Collapsed) is Some("false"), content="true")
  inspect(expanded_value(Expanded) is Some("true"), content="true")
}

///|
test "treeitem_id uses the node key as suffix" {
  let model = Model::new(id="canopy-outline")
  assert_eq(model.treeitem_id("42"), "canopy-outline-treeitem-42")
  assert_eq(model.treeitem_id("7"), "canopy-outline-treeitem-7")
}
