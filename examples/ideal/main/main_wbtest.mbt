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
  inspect(parse_node_id("abc") is None, content="true")
  inspect(parse_node_id("") is None, content="true")
}

///|
test "event_detail_node_id extracts nodeId from object detail" {
  inspect(event_detail_node_id("{\"nodeId\":\"42\"}"), content="42")
}

///|
test "event_detail_node_id accepts string detail fallback" {
  inspect(event_detail_node_id("42"), content="42")
}

///|
test "event_detail_node_id rejects unrelated detail" {
  inspect(event_detail_node_id("{\"other\":\"42\"}"), content="")
}

///|
test "event_detail_status extracts status from object detail" {
  inspect(
    event_detail_status("{\"status\":\"connected\"}"),
    content="connected",
  )
}

///|
test "event_detail_status accepts string detail fallback" {
  inspect(event_detail_status("error"), content="error")
}

///|
test "event_detail_status rejects unrelated detail" {
  inspect(event_detail_status("{\"other\":\"connected\"}"), content="")
}

///|
test "event target selector is centralized" {
  inspect(EditorHost.selector(), content="#canopy-editor")
}

///|
test "event names are centralized" {
  inspect(ActionOverlayOpen.event_type(), content="action-overlay-open")
  inspect(ActionKey.event_type(), content="action-key")
  inspect(ExternalCrdtChange.event_type(), content="external-crdt-changed")
  inspect(LongPress.event_type(), content="long-press")
  inspect(SyncStatus.event_type(), content="sync-status")
}

///|
test "dom event subscription error message includes context" {
  inspect(
    dom_event_subscription_error_message(
      EditorHost,
      ActionKey,
      "document is unavailable",
    ),
    content="[canopy] failed to install DOM event subscription target=editor-host event=action-key: document is unavailable",
  )
}
