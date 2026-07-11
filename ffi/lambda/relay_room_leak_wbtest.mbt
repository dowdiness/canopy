// Regression tests for CF Worker memory leak: rejected connects to
// otherwise-new rooms must not leave empty entries in `relay_rooms`.
// A malicious or buggy client could otherwise send `?room=<unique>`
// with an invalid peer_id repeatedly to grow the map unbounded.

///|
fn noop_send(_ : Bytes) -> Unit {
  ()
}

///|
fn clear_relay_rooms() -> Unit {
  let keys = relay_rooms.keys().to_array()
  for k in keys {
    relay_rooms.remove(k)
  }
}

///|
test "relay_on_connect: rejected empty peer_id does not leak empty room" {
  clear_relay_rooms()
  let accepted = relay_on_connect("leak-test-empty", "", noop_send)
  inspect(accepted, content="false")
  // The room must not remain in the map — would otherwise grow
  // unbounded across unique room IDs.
  inspect(relay_rooms.contains("leak-test-empty"), content="false")
}

///|
test "relay_on_connect: duplicate rejection keeps the room alive" {
  clear_relay_rooms()
  inspect(relay_on_connect("leak-test-dup", "alice", noop_send), content="true")
  // Duplicate rejection does NOT drop the room — the original peer
  // is still a legitimate member.
  inspect(
    relay_on_connect("leak-test-dup", "alice", noop_send),
    content="false",
  )
  inspect(relay_rooms.contains("leak-test-dup"), content="true")
  // Cleanup
  relay_on_disconnect("leak-test-dup", "alice")
  inspect(relay_rooms.contains("leak-test-dup"), content="false")
}

///|
test "relay_on_connect: rejection in a room with other peers preserves the room" {
  clear_relay_rooms()
  inspect(
    relay_on_connect("leak-test-mixed", "alice", noop_send),
    content="true",
  )
  // Trying to rejoin as alice is rejected, room has 1 peer so stays.
  inspect(
    relay_on_connect("leak-test-mixed", "alice", noop_send),
    content="false",
  )
  inspect(relay_rooms.contains("leak-test-mixed"), content="true")
  relay_on_disconnect("leak-test-mixed", "alice")
  inspect(relay_rooms.contains("leak-test-mixed"), content="false")
}
