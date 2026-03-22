///|
test "encode_peer_joined starts with version byte 0x02" {
  let bytes = encode_peer_joined("alice")
  inspect(bytes[0], content="b'\\x02'")
}

///|
test "encode_peer_joined has room_control message type 0x05" {
  let bytes = encode_peer_joined("alice")
  inspect(bytes[1], content="b'\\x05'")
}

///|
test "encode_peer_joined has flags byte 0x00" {
  let bytes = encode_peer_joined("alice")
  inspect(bytes[2], content="b'\\x00'")
}

///|
test "encode_peer_joined has sub_type 0x01 for join" {
  let bytes = encode_peer_joined("alice")
  inspect(bytes[3], content="b'\\x01'")
}

///|
test "encode_peer_left has sub_type 0x02 for leave" {
  let bytes = encode_peer_left("bob")
  inspect(bytes[3], content="b'\\x02'")
}

///|
test "encode_peer_left starts with version byte 0x02" {
  let bytes = encode_peer_left("bob")
  inspect(bytes[0], content="b'\\x02'")
}

///|
test "encode_peer_left has room_control message type 0x05" {
  let bytes = encode_peer_left("bob")
  inspect(bytes[1], content="b'\\x05'")
}

///|
test "encode_peer_joined encodes peer_id length as uvarint" {
  let bytes = encode_peer_joined("alice")
  // "alice" is 10 bytes via Buffer (MoonBit internal encoding), uvarint = 0x0A
  inspect(bytes[4], content="b'\\x0A'")
}

///|
test "encode_peer_joined encodes peer_id bytes" {
  let bytes = encode_peer_joined("alice")
  // Header: version(1) + msg_type(1) + flags(1) + sub_type(1) + uvarint_len(1) = 5 bytes
  // Then 10 bytes of "alice" (MoonBit Buffer encoding: 2 bytes per ASCII char)
  inspect(bytes.length(), content="15")
  // Check 'a' first byte = 0x61
  inspect(bytes[5], content="b'\\x61'")
}

///|
test "write_relay_uvarint encodes small values in one byte" {
  let buf = @buffer.new()
  write_relay_uvarint(buf, 5)
  let bytes = buf.to_bytes()
  inspect(bytes.length(), content="1")
  inspect(bytes[0], content="b'\\x05'")
}

///|
test "write_relay_uvarint encodes 128 in two bytes" {
  let buf = @buffer.new()
  write_relay_uvarint(buf, 128)
  let bytes = buf.to_bytes()
  inspect(bytes.length(), content="2")
  // 128 = 0x80 => first byte: (0x00 | 0x80) = 0x80, second byte: 0x01
  inspect(bytes[0], content="b'\\x80'")
  inspect(bytes[1], content="b'\\x01'")
}

///|
test "encode_peer_joined with empty peer_id" {
  let bytes = encode_peer_joined("")
  // Header: version(1) + msg_type(1) + flags(1) + sub_type(1) + uvarint_len(1) = 5 bytes
  // uvarint_len = 0, no peer_id bytes
  inspect(bytes.length(), content="5")
  inspect(bytes[4], content="b'\\x00'")
}
