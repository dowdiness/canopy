///|
/// LEB128 varints + length-prefixed UTF-16LE strings come from the shared
/// `lib/byte-codec` package. relay keeps only its own framing here; the
/// generic codec lives in one place (see docs/plans/2026-05-29-byte-codec-package-design.md).
using @byte_codec {type Reader, read_string, write_string}

///|
/// Wire envelope constants come from the canonical protocol package
/// (`dowdiness/canopy/protocol/wire`) since redesign S1; relay keeps only
/// its own framing helpers below.
using @wire {
  protocol_version,
  msg_room_control,
  flags_none,
  sub_join,
  sub_leave,
}

///|
/// Encode a peer control message with the given sub-type and peer ID.
///
/// Wire format: [version][msg_room_control][flags][sub_type][uvarint_len][peer_id_bytes]
/// Note: peer_id_bytes uses MoonBit's internal string encoding (not UTF-8).
fn encode_peer_control(sub_type : Byte, peer_id : String) -> Bytes {
  let buf = Buffer()
  buf.write_byte(protocol_version)
  buf.write_byte(msg_room_control)
  buf.write_byte(flags_none)
  buf.write_byte(sub_type)
  write_string(buf, peer_id)
  buf.to_bytes()
}

///|
/// Read a length-prefixed string from `data` starting at `offset`. Returns
/// `(string, new_offset)`, or `None` if the frame is truncated or malformed.
///
/// Adapts `byte-codec`'s raising `Reader` to relay's `Option`-returning
/// boundary: the byte stream is sliced from `offset` so the cursor starts at
/// the length prefix, and any `CodecError` (EOF, oversized length) maps to a
/// dropped frame.
fn read_relay_string(data : Bytes, offset : Int) -> (String, Int)? {
  let reader = Reader::new(
    data.view(start=offset, end=data.length()).to_owned(),
  )
  let s = read_string(reader) catch { _ => return None }
  Some((s, offset + reader.pos))
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
  let buf = Buffer()
  buf.write_byte(protocol_version)
  buf.write_byte(new_type)
  buf.write_byte(flags_none)
  write_string(buf, sender)
  if payload_offset < data.length() {
    buf.write_bytes(
      data.view(start=payload_offset, end=data.length()).to_owned(),
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
