///|
test "integration: two hubs sync via InMemoryTransport" {
  let room = InMemoryRoom::new()
  let hub_a = EphemeralHub::new("alice")
  let hub_b = EphemeralHub::new("bob")
  let t_a = InMemoryTransport::new("alice", room)
  let t_b = InMemoryTransport::new("bob", room)
  // Wire: when alice sends ephemeral, bob applies
  t_b.on_receive(fn(data) {
    match decode_message(data) {
      Some(EphemeralUpdate(ns, payload)) => hub_b.apply(ns, payload)
      _ => ()
    }
  })
  // Alice sets presence and sends
  hub_a.set_presence("Alice", "#ff0000", Active)
  let presence_bytes = hub_a.encode(Presence)
  t_a.send(encode_message(EphemeralUpdate(Presence, presence_bytes)))
  // Bob should see alice's presence
  let peers = hub_b.get_online_peers()
  inspect(peers.length(), content="1")
  inspect(peers[0].display_name, content="Alice")
}

///|
test "integration: peer leave clears state across hubs" {
  let hub_a = EphemeralHub::new("alice")
  let hub_b = EphemeralHub::new("bob")
  // Simulate: alice's presence applied to bob's hub
  hub_a.set_presence("Alice", "#ff0000", Active)
  hub_b.apply(Presence, hub_a.encode(Presence))
  inspect(hub_b.get_online_peers().length(), content="1")
  // Alice leaves
  hub_b.on_peer_leave("alice")
  inspect(hub_b.get_online_peers().length(), content="0")
}

///|
test "integration: encode_all catches up new peer" {
  let hub_a = EphemeralHub::new("alice")
  hub_a.set_edit_mode("node-42")
  hub_a.set_presence("Alice", "#ff0000", Active)
  let full_state = hub_a.encode_all()
  // New peer joins and receives full state
  let hub_c = EphemeralHub::new("carol")
  hub_c.apply_all(full_state)
  inspect(hub_c.get_edit_mode("alice"), content="Some({node_id: \"node-42\"})")
  inspect(hub_c.get_online_peers().length(), content="1")
}

///|
test "integration: drag state lifecycle" {
  let hub_a = EphemeralHub::new("alice")
  let hub_b = EphemeralHub::new("bob")
  // Alice starts drag
  hub_a.set_drag("src-node", target=Some(("tgt-node", After)))
  hub_b.apply(Drag, hub_a.encode(Drag))
  // Bob sees drag
  let drag_states = hub_b.get_store(Drag).get_all_states()
  inspect(drag_states.length(), content="1")
  // Alice cancels drag
  hub_a.clear_drag()
  hub_b.apply(Drag, hub_a.encode(Drag))
  let after_clear = hub_b.get_store(Drag).get_all_states()
  inspect(after_clear.length(), content="0")
}
