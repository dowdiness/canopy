///|
test "hub: set and get edit mode" {
  let hub = EphemeralHub::new("alice")
  hub.set_edit_mode("node-1")
  inspect(hub.get_edit_mode("alice"), content="Some({node_id: \"node-1\"})")
}

///|
test "hub: clear edit mode" {
  let hub = EphemeralHub::new("alice")
  hub.set_edit_mode("node-1")
  hub.clear_edit_mode()
  inspect(hub.get_edit_mode("alice"), content="None")
}

///|
test "hub: set and get cursor" {
  let hub = EphemeralHub::new("alice")
  hub.set_cursor(42, selection=Some((10, 20)))
  match hub.get_cursor("alice") {
    Some((pos, sel)) => {
      inspect(pos, content="42")
      inspect(sel, content="Some((10, 20))")
    }
    None => fail("expected cursor")
  }
}

///|
test "hub: set presence and get online peers" {
  let hub = EphemeralHub::new("alice")
  hub.set_presence("Alice", "#ff0000", Active)
  let peers = hub.get_online_peers()
  inspect(peers.length(), content="1")
  inspect(peers[0].display_name, content="Alice")
}

///|
test "hub: on_peer_leave clears all namespaces" {
  let hub = EphemeralHub::new("alice")
  hub.set_cursor(42)
  hub.set_edit_mode("node-1")
  hub.set_presence("Alice", "#ff0000", Active)
  hub.on_peer_leave("alice")
  inspect(hub.get_edit_mode("alice"), content="None")
  inspect(hub.get_online_peers().length(), content="0")
  inspect(hub.get_cursor("alice"), content="None")
}

///|
test "hub: encode_all and apply_all roundtrip" {
  let hub_a = EphemeralHub::new("alice")
  hub_a.set_edit_mode("node-5")
  hub_a.set_presence("Alice", "#ff0000", Active)
  let bytes = hub_a.encode_all()
  let hub_b = EphemeralHub::new("bob")
  hub_b.apply_all(bytes)
  inspect(hub_b.get_edit_mode("alice"), content="Some({node_id: \"node-5\"})")
}

///|
test "hub: per-namespace encode/apply" {
  let hub_a = EphemeralHub::new("alice")
  hub_a.set_edit_mode("node-3")
  let bytes = hub_a.encode(EditMode)
  let hub_b = EphemeralHub::new("bob")
  hub_b.apply(EditMode, bytes)
  inspect(hub_b.get_edit_mode("alice"), content="Some({node_id: \"node-3\"})")
}

///|
test "hub: get_all_editing" {
  let hub = EphemeralHub::new("alice")
  hub.set_edit_mode("node-7")
  let editing = hub.get_all_editing()
  inspect(editing.length(), content="1")
}

///|
test "hub: apply_all with empty bytes" {
  let hub = EphemeralHub::new("alice")
  hub.apply_all(Bytes::new(0))
  inspect(hub.get_online_peers().length(), content="0")
}
