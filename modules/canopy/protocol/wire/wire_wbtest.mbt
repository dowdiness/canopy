///|
fn str_to_bytes(s : String) -> Bytes {
  let buf = Buffer()
  buf.write_string_utf16le(s.view())
  buf.to_bytes()
}

///|
test "encode/decode preserves message variants and exact payloads" {
  let messages : Array[SyncMessage] = [
    CrdtOps(str_to_bytes("hello")),
    CrdtOps(b"\x42\x43"),
    EphemeralUpdate(Cursor, str_to_bytes("data")),
    EphemeralUpdate(Cursor, b"\x01\x02"),
    SyncRequest(str_to_bytes("req")),
    SyncRequest(b"\x10"),
    SyncResponse(b"\x20"),
    PeerJoined("alice"),
    PeerLeft("bob"),
  ]
  for msg in messages {
    assert_eq(decode_message(encode_message(msg)), Some(msg))
  }
}

///|
test "decode_message returns None for malformed frames" {
  let cases : Array[(String, Bytes)] = [
    ("empty", b""),
    ("one-byte header", b"\x02"),
    ("two-byte header", b"\x02\x01"),
    ("wrong version", b"\xFF\x01\x00"),
    ("wrong version with payload", b"\xFF\x01\x00\x00"),
    ("v2 frame", b"\x02\x01\x00"),
    ("unknown message type", b"\x03\xFF\x00"),
    ("missing namespace", b"\x03\x02\x00"),
    ("invalid namespace", b"\x03\x02\x00\xFF"),
    ("missing room subtype", b"\x03\x05\x00"),
    ("truncated peer id", b"\x03\x05\x00\x01"),
    ("unknown room subtype", b"\x03\x05\x00\xFF"),
  ]
  for (name, bytes) in cases {
    assert_true(decode_message(bytes) is None, msg=name)
  }
}

///|
test "decode_message accepts CrdtOps with empty payload" {
  assert_eq(decode_message(b"\x03\x01\x00"), Some(CrdtOps(b"")))
}

///|
test "decode_message_result reports wrong version" {
  let result = decode_message_result(b"\xFF\x01\x00")
  guard! result is Err(err)
  inspect(err.message(), content="unsupported protocol version: 255")
}

///|
test "v2 frame is rejected after v3 cutover" {
  let result = decode_message_result(b"\x02\x01\x00")
  guard! result is Err(err)
  match err {
    UnsupportedVersion(version~) => inspect(version, content="b'\\x02'")
    _ => fail("expected UnsupportedVersion")
  }
  inspect(err.message(), content="unsupported protocol version: 2")
}

///|
test "decode_message_result reports unknown message type" {
  let result = decode_message_result(b"\x03\xFF\x00")
  guard! result is Err(err)
  inspect(err.message(), content="unknown protocol message type: 255")
}

///|
test "wire format: version byte is 0x03" {
  let encoded = encode_message(CrdtOps(b""))
  inspect(encoded[0], content="b'\\x03'")
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
test "v3: encode/decode RelayedCrdtOps roundtrip" {
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
test "v3: RelayedCrdtOps with empty payload" {
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
test "v3: encode/decode SyncRequest with target and request_id" {
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
test "v3: encode/decode SyncResponse with target and request_id" {
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
test "v3: SyncRequest with empty version_json" {
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

///|
test "decode_message_result reports missing room control subtype" {
  let result = decode_message_result(b"\x03\x05\x00")
  guard! result is Err(err)
  inspect(err.message(), content="missing room control subtype")
}

///|
test "decode_message_result reports invalid room control subtype before peer id" {
  let result = decode_message_result(b"\x03\x05\x00\xFF")
  guard! result is Err(err)
  inspect(err.message(), content="invalid room control subtype: 255")
}
