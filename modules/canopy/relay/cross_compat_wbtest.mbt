///|
test "relay PeerJoined wire format matches editor protocol" {
  let msg = encode_peer_joined("alice")
  // Verify header: [version=0x03][type=0x05][flags=0x00][sub=0x01]
  inspect(
    msg[0],
    content=(
      #|3
    ),
  )
  inspect(
    msg[1],
    content=(
      #|5
    ),
  )
  inspect(
    msg[2],
    content=(
      #|0
    ),
  )
  inspect(
    msg[3],
    content=(
      #|1
    ),
  )
  inspect(msg.length() > 5, content="true")
}

///|
test "relay PeerLeft wire format" {
  let msg = encode_peer_left("bob")
  inspect(
    msg[3],
    content=(
      #|2
    ),
  )
}
