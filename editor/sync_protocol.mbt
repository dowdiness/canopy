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
pub fn encode_message(msg : SyncMessage) -> Bytes {
  let buf = @buffer.new()
  buf.write_byte(protocol_version)
  buf.write_byte(message_type_byte(msg))
  buf.write_byte(b'\x00') // flags: no BFT
  match msg {
    CrdtOps(payload) | SyncRequest(payload) | SyncResponse(payload) =>
      buf.write_bytes(payload)
    EphemeralUpdate(ns, payload) => {
      // Wire: [namespace: u8][payload bytes] — namespace byte immediately after header
      buf.write_byte(namespace_to_byte(ns))
      buf.write_bytes(payload)
    }
    PeerJoined(peer_id) => {
      buf.write_byte(b'\x01') // sub_type: Join
      write_string(buf, peer_id)
    }
    PeerLeft(peer_id) => {
      buf.write_byte(b'\x02') // sub_type: Leave
      write_string(buf, peer_id)
    }
  }
  buf.to_bytes()
}

///|
pub fn decode_message(data : Bytes) -> SyncMessage? {
  if data.length() < 3 {
    return None
  }
  if data[0] != protocol_version {
    return None
  }
  let msg_type = data[1]
  // data[2] = flags (ignored in v1)
  let payload_start = 3
  match msg_type {
    b'\x01' =>
      Some(
        CrdtOps(
          if payload_start < data.length() {
            data.view(start=payload_start, end=data.length()).to_bytes()
          } else {
            Bytes::new(0)
          },
        ),
      )
    b'\x02' => {
      if payload_start >= data.length() {
        return None
      }
      match namespace_from_byte(data[payload_start]) {
        Some(ns) => {
          let ns_payload_start = payload_start + 1
          let ns_payload = if ns_payload_start < data.length() {
            data.view(start=ns_payload_start, end=data.length()).to_bytes()
          } else {
            Bytes::new(0)
          }
          Some(EphemeralUpdate(ns, ns_payload))
        }
        None => None
      }
    }
    b'\x03' =>
      Some(
        SyncRequest(
          if payload_start < data.length() {
            data.view(start=payload_start, end=data.length()).to_bytes()
          } else {
            Bytes::new(0)
          },
        ),
      )
    b'\x04' =>
      Some(
        SyncResponse(
          if payload_start < data.length() {
            data.view(start=payload_start, end=data.length()).to_bytes()
          } else {
            Bytes::new(0)
          },
        ),
      )
    b'\x05' => {
      if payload_start >= data.length() {
        return None
      }
      let sub_type = data[payload_start]
      let reader = Reader::new(
        data.view(start=payload_start + 1, end=data.length()).to_bytes(),
      )
      let peer_id = read_string(reader) catch { _ => return None }
      match sub_type {
        b'\x01' => Some(PeerJoined(peer_id))
        b'\x02' => Some(PeerLeft(peer_id))
        _ => None
      }
    }
    _ => None
  }
}
