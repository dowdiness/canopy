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
  RelayedCrdtOps(sender~ : String, payload~ : Bytes)
} derive(Show, Eq)

///|
let protocol_version : Byte = b'\x02'

// Message type constants

///|
let msg_crdt_ops : Byte = b'\x01'

///|
let msg_ephemeral : Byte = b'\x02'

///|
let msg_sync_request : Byte = b'\x03'

///|
let msg_sync_response : Byte = b'\x04'

///|
let msg_room_control : Byte = b'\x05'

///|
let msg_relayed_crdt_ops : Byte = b'\x06'

///|
fn message_type_byte(msg : SyncMessage) -> Byte {
  match msg {
    CrdtOps(_) => msg_crdt_ops
    EphemeralUpdate(_, _) => msg_ephemeral
    SyncRequest(_) => msg_sync_request
    SyncResponse(_) => msg_sync_response
    PeerJoined(_) | PeerLeft(_) => msg_room_control
    RelayedCrdtOps(sender=_, ..) => msg_relayed_crdt_ops
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
    RelayedCrdtOps(sender~, payload~) =>
      return encode_relayed_crdt_ops(sender, payload)
  }
  buf.to_bytes()
}

///|
pub fn encode_relayed_crdt_ops(sender : String, payload : Bytes) -> Bytes {
  let buf = @buffer.new()
  buf.write_byte(protocol_version)
  buf.write_byte(msg_relayed_crdt_ops)
  buf.write_byte(b'\x00')
  write_string(buf, sender)
  buf.write_bytes(payload)
  buf.to_bytes()
}

///|
/// Encode a peer-addressed message with target, request_id, and content.
fn encode_peer_addressed(
  type_byte : Byte,
  target : String,
  request_id : String,
  content : String,
) -> Bytes {
  let buf = @buffer.new()
  buf.write_byte(protocol_version)
  buf.write_byte(type_byte)
  buf.write_byte(b'\x00')
  write_string(buf, target)
  write_string(buf, request_id)
  write_string(buf, content)
  buf.to_bytes()
}

///|
/// Encode a peer-addressed SyncRequest.
/// Wire: [header][target_id][request_id][version_json] — all write_string.
pub fn encode_sync_request(
  target~ : String,
  request_id~ : String,
  version_json~ : String,
) -> Bytes {
  encode_peer_addressed(msg_sync_request, target, request_id, version_json)
}

///|
/// Encode a peer-addressed SyncResponse.
/// Wire: [header][target_id][request_id][sync_message_json] — all write_string.
pub fn encode_sync_response(
  target~ : String,
  request_id~ : String,
  sync_json~ : String,
) -> Bytes {
  encode_peer_addressed(msg_sync_response, target, request_id, sync_json)
}

///|
fn payload_bytes(data : Bytes, payload_start : Int) -> Bytes {
  if payload_start < data.length() {
    data.view(start=payload_start, end=data.length()).to_bytes()
  } else {
    Bytes::new(0)
  }
}

///|
fn read_string_field(
  reader : Reader,
  field : String,
) -> Result[String, ProtocolError] {
  Ok(read_string(reader)) catch {
    _ => Err(ProtocolError::MissingField(field~))
  }
}

///|
pub fn decode_message_result(
  data : Bytes,
) -> Result[SyncMessage, ProtocolError] {
  if data.length() < 3 {
    return Err(ProtocolError::MessageTooShort(length=data.length()))
  }
  if data[0] != protocol_version {
    return Err(ProtocolError::UnsupportedVersion(version=data[0]))
  }
  let msg_type = data[1]
  // data[2] = flags (reserved)
  let payload_start = 3
  // Match uses byte literals (MoonBit match requires literals, not variables).
  // Constants: 0x01=CrdtOps, 0x02=Ephemeral, 0x03=SyncRequest,
  // 0x04=SyncResponse, 0x05=RoomControl, 0x06=RelayedCrdtOps
  match msg_type {
    b'\x01' => Ok(CrdtOps(payload_bytes(data, payload_start)))
    b'\x02' => {
      if payload_start >= data.length() {
        return Err(ProtocolError::MissingNamespace)
      }
      match namespace_from_byte(data[payload_start]) {
        Some(ns) => {
          let ns_payload_start = payload_start + 1
          let ns_payload = payload_bytes(data, ns_payload_start)
          Ok(EphemeralUpdate(ns, ns_payload))
        }
        None => Err(ProtocolError::InvalidNamespace(tag=data[payload_start]))
      }
    }
    b'\x03' => Ok(SyncRequest(payload_bytes(data, payload_start)))
    b'\x04' => Ok(SyncResponse(payload_bytes(data, payload_start)))
    b'\x05' => {
      if payload_start >= data.length() {
        return Err(ProtocolError::MissingRoomControlSubtype)
      }
      let sub_type = data[payload_start]
      match sub_type {
        b'\x01' => {
          let reader = Reader::new(
            data.view(start=payload_start + 1, end=data.length()).to_bytes(),
          )
          let peer_id = match read_string_field(reader, "peer_id") {
            Ok(peer_id) => peer_id
            Err(err) => return Err(err)
          }
          Ok(PeerJoined(peer_id))
        }
        b'\x02' => {
          let reader = Reader::new(
            data.view(start=payload_start + 1, end=data.length()).to_bytes(),
          )
          let peer_id = match read_string_field(reader, "peer_id") {
            Ok(peer_id) => peer_id
            Err(err) => return Err(err)
          }
          Ok(PeerLeft(peer_id))
        }
        _ => Err(ProtocolError::InvalidRoomControlSubtype(sub_type~))
      }
    }
    b'\x06' => {
      let reader = Reader::new(
        data.view(start=payload_start, end=data.length()).to_bytes(),
      )
      let sender = match read_string_field(reader, "sender") {
        Ok(sender) => sender
        Err(err) => return Err(err)
      }
      let remaining_pos = reader.pos
      let remaining_data = data
        .view(start=payload_start + remaining_pos, end=data.length())
        .to_bytes()
      Ok(RelayedCrdtOps(sender~, payload=remaining_data))
    }
    _ => Err(ProtocolError::UnknownMessageType(msg_type~))
  }
}

///|
pub fn decode_message(data : Bytes) -> SyncMessage? {
  match decode_message_result(data) {
    Ok(msg) => Some(msg)
    Err(_) => None
  }
}
