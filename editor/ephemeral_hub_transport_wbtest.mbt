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
