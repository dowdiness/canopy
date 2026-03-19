///|
pub(open) trait SyncTransport {
  send(Self, Bytes) -> Unit
  on_receive(Self, (Bytes) -> Unit) -> Unit
  close(Self) -> Unit
}

///|
pub(all) enum SyncMessage {
  CrdtOps(Bytes)
  EphemeralUpdate(EphemeralNamespace, Bytes)
  SyncRequest(Bytes)
  SyncResponse(Bytes)
  PeerJoined(String)
  PeerLeft(String)
} derive(Show, Eq)

///|
let protocol_version : Byte = b'\x01'

///|
fn message_type_byte(msg : SyncMessage) -> Byte {
  match msg {
    CrdtOps(_) => b'\x01'
    EphemeralUpdate(_, _) => b'\x02'
    SyncRequest(_) => b'\x03'
    SyncResponse(_) => b'\x04'
    PeerJoined(_) | PeerLeft(_) => b'\x05'
  }
}

///|
fn write_msg_uvarint(buf : @buffer.Buffer, value : Int) -> Unit {
  let mut v = value
  while v >= 0x80 {
    buf.write_byte(((v & 0x7F) | 0x80).to_byte())
    v = v >> 7
  }
  buf.write_byte(v.to_byte())
}

///|
fn write_msg_string(buf : @buffer.Buffer, s : String) -> Unit {
  let tmp = @buffer.new()
  tmp.write_string(s)
  let bytes = tmp.to_bytes()
  write_msg_uvarint(buf, bytes.length())
  buf.write_bytes(bytes)
}

///|
pub fn encode_message(msg : SyncMessage) -> Bytes {
  let buf = @buffer.new()
  buf.write_byte(protocol_version)
  buf.write_byte(message_type_byte(msg))
  buf.write_byte(b'\x00') // flags: no BFT
  match msg {
    CrdtOps(payload) | SyncRequest(payload) | SyncResponse(payload) =>
      buf.write_bytes(payload)
    EphemeralUpdate(ns, payload) => {
      buf.write_byte(namespace_to_byte(ns))
      buf.write_bytes(payload)
    }
    PeerJoined(peer_id) => {
      buf.write_byte(b'\x01') // sub_type: Join
      write_msg_string(buf, peer_id)
    }
    PeerLeft(peer_id) => {
      buf.write_byte(b'\x02') // sub_type: Leave
      write_msg_string(buf, peer_id)
    }
  }
  buf.to_bytes()
}

///|
fn read_msg_uvarint(data : Bytes, offset : Ref[Int]) -> Int {
  let mut result = 0
  let mut shift = 0
  while offset.val < data.length() {
    let b = data[offset.val].to_int()
    offset.val = offset.val + 1
    result = result | ((b & 0x7F) << shift)
    if (b & 0x80) == 0 {
      break
    }
    shift = shift + 7
  }
  result
}

///|
fn read_msg_string(data : Bytes, offset : Ref[Int]) -> String {
  let len = read_msg_uvarint(data, offset)
  if offset.val + len > data.length() {
    return ""
  }
  let str_bytes = data.view(start=offset.val, end=offset.val + len).to_bytes()
  offset.val = offset.val + len
  str_bytes.to_unchecked_string()
}

///|
fn slice_from(data : Bytes, start : Int) -> Bytes {
  if start >= data.length() {
    return Bytes::new(0)
  }
  data.view(start~, end=data.length()).to_bytes()
}

///|
pub fn decode_message(data : Bytes) -> SyncMessage? {
  if data.length() < 3 {
    return None
  }
  let version = data[0]
  if version != protocol_version {
    return None
  }
  let msg_type = data[1]
  // data[2] = flags (ignored in v1)
  let payload = slice_from(data, 3)
  match msg_type {
    b'\x01' => Some(CrdtOps(payload))
    b'\x02' => {
      if payload.length() < 1 {
        return None
      }
      match namespace_from_byte(payload[0]) {
        Some(ns) => Some(EphemeralUpdate(ns, slice_from(payload, 1)))
        None => None
      }
    }
    b'\x03' => Some(SyncRequest(payload))
    b'\x04' => Some(SyncResponse(payload))
    b'\x05' => {
      if payload.length() < 1 {
        return None
      }
      let sub_type = payload[0]
      let offset = Ref::new(1)
      let peer_id = read_msg_string(payload, offset)
      match sub_type {
        b'\x01' => Some(PeerJoined(peer_id))
        b'\x02' => Some(PeerLeft(peer_id))
        _ => None
      }
    }
    _ => None
  }
}
