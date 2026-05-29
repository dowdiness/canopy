// Frozen wire-format fixtures for the relay protocol.
//
// These pin the EXACT on-the-wire bytes relay produces, asserted against
// hand-derived byte literals — NOT re-derived by calling the code under test.
// They are the safety net for migrating relay's hand-rolled varint/string
// codec onto `lib/byte-codec`: the migration is only byte-safe if every literal
// below still matches after the rewrite. relay's frames are transmitted between
// peers, so a silent format change is a correctness break.
//
// Layout reference (see wire.mbt):
//   peer control: [version=0x02][msg=0x05][flags=0x00][sub_type][write_string(peer_id)]
//   wrapped:      [version=0x02][new_type][flags=0x00][write_string(sender)][payload]
//   write_string(s) = [uvarint(utf16le_bytes_len)][utf16le bytes]
// UTF-16LE of ASCII "x" is the byte pair [0xXX, 0x00].

///|
test "FROZEN encode_peer_joined(alice) full wire bytes" {
  let actual = encode_peer_joined("alice")
  // 02 05 00 01 | uvarint(10)=0a | "alice" utf16le (61 00 6c 00 69 00 63 00 65 00)
  inspect(actual.length(), content="15")
  inspect(
    actual == b"\x02\x05\x00\x01\x0a\x61\x00\x6c\x00\x69\x00\x63\x00\x65\x00",
    content="true",
  )
}

///|
test "FROZEN encode_peer_left(bob) full wire bytes" {
  let actual = encode_peer_left("bob")
  // 02 05 00 02 | uvarint(6)=06 | "bob" utf16le (62 00 6f 00 62 00)
  inspect(actual.length(), content="11")
  inspect(
    actual == b"\x02\x05\x00\x02\x06\x62\x00\x6f\x00\x62\x00",
    content="true",
  )
}

///|
test "FROZEN encode_peer_joined(empty) header-only" {
  let actual = encode_peer_joined("")
  // 02 05 00 01 | uvarint(0)=00 | no peer bytes
  inspect(actual.length(), content="5")
  inspect(actual == b"\x02\x05\x00\x01\x00", content="true")
}

///|
test "FROZEN wrap_with_sender appends payload after sender id" {
  // data payload begins at offset 3 (aa bb); header bytes 01 00 07 are dropped.
  let data = b"\x01\x00\x07\xaa\xbb"
  let actual = wrap_with_sender("alice", b'\x06', data, 3)
  // 02 06 00 | uvarint(10)=0a | "alice" utf16le | payload (aa bb)
  inspect(actual.length(), content="16")
  inspect(
    actual ==
    b"\x02\x06\x00\x0a\x61\x00\x6c\x00\x69\x00\x63\x00\x65\x00\xaa\xbb",
    content="true",
  )
}

///|
test "FROZEN wrap_with_sender with no payload (offset == length)" {
  // payload_offset == data.length(): nothing is appended after the sender id.
  let data = b"\x01\x02\x03"
  let actual = wrap_with_sender("bob", b'\x06', data, 3)
  // 02 06 00 | uvarint(6)=06 | "bob" utf16le
  inspect(actual.length(), content="10")
  inspect(actual == b"\x02\x06\x00\x06\x62\x00\x6f\x00\x62\x00", content="true")
}

///|
test "FROZEN read_relay_string decodes frozen frame to (target, offset)" {
  // 02 03 00 (SyncRequest header) | uvarint(4)=04 | "xy" utf16le (78 00 79 00)
  let data = b"\x02\x03\x00\x04\x78\x00\x79\x00"
  match read_relay_string(data, 3) {
    Some((target, after)) => {
      inspect(target, content="xy")
      inspect(after, content="8")
    }
    None => fail("expected Some((\"xy\", 8))")
  }
}

///|
test "FROZEN read_relay_string returns None on truncated string body" {
  // Claims length 4 but only two string bytes (78 00) follow.
  let data = b"\x02\x03\x00\x04\x78\x00"
  inspect(read_relay_string(data, 3) is None, content="true")
}

///|
test "FROZEN read_relay_string returns None on truncated length varint" {
  // Offset 3 is past the end of the buffer entirely.
  let data = b"\x02\x03\x00"
  inspect(read_relay_string(data, 3) is None, content="true")
}
