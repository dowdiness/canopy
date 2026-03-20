///|
/// Wire protocol version byte.
let version : Byte = b'\x01'

///|
/// Message type byte for room control messages.
let msg_room_control : Byte = b'\x05'

///|
/// Flags byte (reserved, currently always 0x00).
let flags_none : Byte = b'\x00'

///|
/// Sub-type byte for PeerJoined.
let sub_join : Byte = b'\x01'

///|
/// Sub-type byte for PeerLeft.
let sub_leave : Byte = b'\x02'

///|
/// Encode an unsigned variable-length integer into the buffer.
fn write_relay_uvarint(buf : @buffer.Buffer, value : Int) -> Unit {
  let mut v = value
  while v >= 0x80 {
    buf.write_byte(((v & 0x7F) | 0x80).to_byte())
    v = v >> 7
  }
  buf.write_byte(v.to_byte())
}

///|
/// Encode a peer control message with the given sub-type and peer ID.
///
/// Wire format: [version][msg_room_control][flags][sub_type][uvarint_len][peer_id_bytes]
/// Note: peer_id_bytes uses MoonBit's internal string encoding (not UTF-8).
fn encode_peer_control(sub_type : Byte, peer_id : String) -> Bytes {
  let buf = @buffer.new()
  buf.write_byte(version)
  buf.write_byte(msg_room_control)
  buf.write_byte(flags_none)
  buf.write_byte(sub_type)
  let tmp = @buffer.new()
  tmp.write_string(peer_id)
  let peer_bytes = tmp.to_bytes()
  write_relay_uvarint(buf, peer_bytes.length())
  buf.write_bytes(peer_bytes)
  buf.to_bytes()
}

///|
/// Encode a PeerJoined message for the given peer ID.
pub fn encode_peer_joined(peer_id : String) -> Bytes {
  encode_peer_control(sub_join, peer_id)
}

///|
/// Encode a PeerLeft message for the given peer ID.
pub fn encode_peer_left(peer_id : String) -> Bytes {
  encode_peer_control(sub_leave, peer_id)
}
