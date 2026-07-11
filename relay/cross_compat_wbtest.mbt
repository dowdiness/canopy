///|
test "relay PeerJoined wire format matches editor protocol" {
  let msg = encode_peer_joined("alice")
  // Verify header: [version=0x02][type=0x05][flags=0x00][sub=0x01]
  inspect(msg[0], content="b'\\x02'")
  inspect(msg[1], content="b'\\x05'")
  inspect(msg[2], content="b'\\x00'")
  inspect(msg[3], content="b'\\x01'")
  inspect(msg.length() > 5, content="true")
}

///|
test "relay PeerLeft wire format" {
  let msg = encode_peer_left("bob")
  inspect(msg[3], content="b'\\x02'")
}
