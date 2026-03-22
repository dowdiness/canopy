///|
fn str_to_bytes(s : String) -> Bytes {
  let buf = @buffer.new()
  buf.write_string(s)
  buf.to_bytes()
}

///|
test "encode/decode CrdtOps roundtrip" {
  let payload = str_to_bytes("hello")
  let msg = CrdtOps(payload)
  match decode_message(encode_message(msg)) {
    Some(CrdtOps(decoded_payload)) =>
      inspect(
        decoded_payload.length(),
        content=(
          #|10
        ),
      )
    _ => fail("expected CrdtOps")
  }
}

///|
test "encode/decode EphemeralUpdate roundtrip" {
  let payload = str_to_bytes("data")
  let msg = EphemeralUpdate(Cursor, payload)
  match decode_message(encode_message(msg)) {
    Some(EphemeralUpdate(ns, _)) => inspect(ns, content="Cursor")
    _ => fail("expected EphemeralUpdate")
  }
}

///|
test "encode/decode SyncRequest roundtrip" {
  let msg = SyncRequest(str_to_bytes("req"))
  match decode_message(encode_message(msg)) {
    Some(SyncRequest(_)) => ()
    _ => fail("expected SyncRequest")
  }
}

///|
test "encode/decode PeerJoined roundtrip" {
  let msg = PeerJoined("alice")
  inspect(
    decode_message(encode_message(msg)),
    content="Some(PeerJoined(\"alice\"))",
  )
}

///|
test "encode/decode PeerLeft roundtrip" {
  let msg = PeerLeft("bob")
  inspect(
    decode_message(encode_message(msg)),
    content="Some(PeerLeft(\"bob\"))",
  )
}

///|
test "decode rejects wrong version" {
  let buf = @buffer.new()
  buf.write_byte(b'\xFF') // bad version
  buf.write_byte(b'\x01')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  inspect(decode_message(buf.to_bytes()), content="None")
}

///|
test "decode rejects too short" {
  let buf = @buffer.new()
  buf.write_byte(b'\x02')
  buf.write_byte(b'\x01')
  inspect(decode_message(buf.to_bytes()), content="None")
}

///|
test "wire format: version byte is 0x02" {
  let encoded = encode_message(CrdtOps(b""))
  inspect(encoded[0], content="b'\\x02'")
}

///|
test "wire format: flags byte is 0x00" {
  let encoded = encode_message(CrdtOps(b""))
  inspect(encoded[2], content="b'\\x00'")
}

///|
test "EphemeralUpdate all namespaces" {
  let namespaces : Array[EphemeralNamespace] = [
    Cursor,
    EditMode,
    Drag,
    Presence,
  ]
  for ns in namespaces {
    let msg = EphemeralUpdate(ns, str_to_bytes("x"))
    match decode_message(encode_message(msg)) {
      Some(EphemeralUpdate(decoded_ns, _)) =>
        if decoded_ns != ns {
          fail("namespace mismatch")
        }
      _ => fail("expected EphemeralUpdate")
    }
  }
}

///|
test "v2: encode/decode RelayedCrdtOps roundtrip" {
  let payload = str_to_bytes("test payload")
  let encoded = encode_relayed_crdt_ops("alice", payload)
  let decoded = decode_message(encoded)
  match decoded {
    Some(RelayedCrdtOps(sender~, payload~)) => {
      inspect(sender, content="alice")
      inspect(payload.to_unchecked_string(), content="test payload")
    }
    _ => fail("expected RelayedCrdtOps")
  }
}

///|
test "v2: RelayedCrdtOps with empty payload" {
  let encoded = encode_relayed_crdt_ops("bob", Bytes::new(0))
  let decoded = decode_message(encoded)
  match decoded {
    Some(RelayedCrdtOps(sender~, payload~)) => {
      inspect(sender, content="bob")
      inspect(payload.length(), content="0")
    }
    _ => fail("expected RelayedCrdtOps")
  }
}

///|
test "v2: encode/decode SyncRequest with target and request_id" {
  let encoded = encode_sync_request(
    target="bob",
    request_id="42",
    version_json="{}",
  )
  let decoded = decode_message(encoded)
  match decoded {
    Some(SyncRequest(payload)) => {
      let reader = Reader::new(payload)
      let target = read_string(reader) catch {
        _ => {
          fail("read target")
          return
        }
      }
      let req_id = read_string(reader) catch {
        _ => {
          fail("read req_id")
          return
        }
      }
      let ver = read_string(reader) catch {
        _ => {
          fail("read ver")
          return
        }
      }
      inspect(target, content="bob")
      inspect(req_id, content="42")
      inspect(ver, content="{}")
    }
    _ => fail("expected SyncRequest")
  }
}

///|
test "v2: encode/decode SyncResponse with target and request_id" {
  let encoded = encode_sync_response(
    target="alice",
    request_id="7",
    sync_json="{\"runs\":[]}",
  )
  let decoded = decode_message(encoded)
  match decoded {
    Some(SyncResponse(payload)) => {
      let reader = Reader::new(payload)
      let target = read_string(reader) catch {
        _ => {
          fail("read target")
          return
        }
      }
      let req_id = read_string(reader) catch {
        _ => {
          fail("read req_id")
          return
        }
      }
      let json = read_string(reader) catch {
        _ => {
          fail("read json")
          return
        }
      }
      inspect(target, content="alice")
      inspect(req_id, content="7")
      inspect(json, content="{\"runs\":[]}")
    }
    _ => fail("expected SyncResponse")
  }
}

///|
test "v2: SyncRequest with empty version_json" {
  let encoded = encode_sync_request(target="x", request_id="1", version_json="")
  let decoded = decode_message(encoded)
  match decoded {
    Some(SyncRequest(payload)) => {
      let reader = Reader::new(payload)
      let target = read_string(reader) catch {
        _ => {
          fail("read")
          return
        }
      }
      let req_id = read_string(reader) catch {
        _ => {
          fail("read")
          return
        }
      }
      let ver = read_string(reader) catch {
        _ => {
          fail("read")
          return
        }
      }
      inspect(target, content="x")
      inspect(req_id, content="1")
      inspect(ver, content="")
    }
    _ => fail("expected SyncRequest")
  }
}
