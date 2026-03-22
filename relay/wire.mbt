///|
/// Wire protocol version byte.
let version : Byte = b'\x02'

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
/// Read a uvarint from a byte slice starting at offset. Returns (value, new_offset).
fn read_relay_uvarint(data : Bytes, offset : Int) -> (Int, Int)? {
  let mut result = 0
  let mut shift = 0
  let mut pos = offset
  for i = 0; i < 10; i = i + 1 {
    if pos >= data.length() {
      return None
    }
    let b = data[pos].to_int()
    pos += 1
    result = result | ((b & 0x7F) << shift)
    if (b & 0x80) == 0 {
      return Some((result, pos))
    }
    shift += 7
  }
  None
}

///|
/// Read a length-prefixed string from data at offset. Returns (string, new_offset).
fn read_relay_string(data : Bytes, offset : Int) -> (String, Int)? {
  match read_relay_uvarint(data, offset) {
    None => None
    Some((len, pos)) => {
      if pos + len > data.length() {
        return None
      }
      let bytes = data.view(start=pos, end=pos + len).to_bytes()
      Some((bytes.to_unchecked_string(), pos + len))
    }
  }
}

///|
/// Wrap a message with sender ID and a new type byte.
/// Output: [version][new_type][flags][sender_id (uvarint len + bytes)][payload from offset]
fn wrap_with_sender(
  sender : String,
  new_type : Byte,
  data : Bytes,
  payload_offset : Int,
) -> Bytes {
  let buf = @buffer.new()
  buf.write_byte(version)
  buf.write_byte(new_type)
  buf.write_byte(flags_none)
  let tmp = @buffer.new()
  tmp.write_string(sender)
  let sender_bytes = tmp.to_bytes()
  write_relay_uvarint(buf, sender_bytes.length())
  buf.write_bytes(sender_bytes)
  if payload_offset < data.length() {
    buf.write_bytes(
      data.view(start=payload_offset, end=data.length()).to_bytes(),
    )
  }
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
