///|
test "uvarint roundtrip: boundary values" {
  let buf = @buffer.new()
  write_uvarint(buf, 0UL) // zero
  write_uvarint(buf, 127UL) // max single-byte
  write_uvarint(buf, 128UL) // first two-byte
  write_uvarint(buf, 255UL) // 0xFF
  write_uvarint(buf, 16383UL) // max two-byte
  write_uvarint(buf, 16384UL) // first three-byte
  let reader = Reader::new(buf.to_bytes())
  inspect(try! read_uvarint(reader), content="0")
  inspect(try! read_uvarint(reader), content="127")
  inspect(try! read_uvarint(reader), content="128")
  inspect(try! read_uvarint(reader), content="255")
  inspect(try! read_uvarint(reader), content="16383")
  inspect(try! read_uvarint(reader), content="16384")
}

///|
test "ivarint roundtrip: signed boundaries" {
  let buf = @buffer.new()
  write_ivarint(buf, 0L)
  write_ivarint(buf, 1L)
  write_ivarint(buf, -1L)
  write_ivarint(buf, 127L)
  write_ivarint(buf, -128L)
  write_ivarint(buf, 9223372036854775807L) // Int64 max
  write_ivarint(buf, -9223372036854775808L) // Int64 min
  let reader = Reader::new(buf.to_bytes())
  inspect(try! read_ivarint(reader), content="0")
  inspect(try! read_ivarint(reader), content="1")
  inspect(try! read_ivarint(reader), content="-1")
  inspect(try! read_ivarint(reader), content="127")
  inspect(try! read_ivarint(reader), content="-128")
  inspect(try! read_ivarint(reader), content="9223372036854775807")
  inspect(try! read_ivarint(reader), content="-9223372036854775808")
}

///|
test "reader: empty buffer raises" {
  let reader = Reader::new(Bytes::new(0))
  let result : Result[Byte, EphemeralError] = Ok(reader.read_byte()) catch {
    err => Err(err)
  }
  inspect(result is Err(_), content="true")
}

///|
test "peer ID: numeric preserved" {
  inspect(parse_peer_id("123"), content="Some(123)")
  inspect(parse_peer_id("0"), content="Some(0)")
  inspect(parse_peer_id("999999999"), content="Some(999999999)")
}

///|
test "peer ID: leading zero rejected" {
  // "01" has a leading zero with length > 1, so it should be rejected
  inspect(parse_peer_id("01"), content="None")
  inspect(parse_peer_id("007"), content="None")
}

///|
test "peer ID: empty and non-numeric rejected" {
  inspect(parse_peer_id(""), content="None")
  inspect(parse_peer_id("abc"), content="None")
  inspect(parse_peer_id("12a"), content="None")
}

///|
test "peer ID: non-numeric hashed deterministically" {
  let alice1 = to_wire_peer_id("alice")
  let alice2 = to_wire_peer_id("alice")
  let bob = to_wire_peer_id("bob")
  // Deterministic: same input produces same output
  inspect(alice1 == alice2, content="true")
  // Different inputs produce different outputs
  inspect(alice1 != bob, content="true")
  // The result should itself be a numeric string (parseable)
  inspect(parse_peer_id(alice1) is Some(_), content="true")
}

///|
test "ephemeral value roundtrip: all variants" {
  fn roundtrip(value : EphemeralValue) -> EphemeralValue raise {
    let buf = @buffer.new()
    write_ephemeral_value(buf, value)
    let reader = Reader::new(buf.to_bytes())
    read_ephemeral_value(reader)
  }

  inspect(try! roundtrip(EphemeralValue::Null), content="Null")
  inspect(try! roundtrip(EphemeralValue::Bool(true)), content="Bool(true)")
  inspect(try! roundtrip(EphemeralValue::Bool(false)), content="Bool(false)")
  inspect(try! roundtrip(EphemeralValue::I64(42L)), content="I64(42)")
  inspect(try! roundtrip(EphemeralValue::I64(0L)), content="I64(0)")
  inspect(try! roundtrip(EphemeralValue::I64(-1L)), content="I64(-1)")
  inspect(try! roundtrip(EphemeralValue::F64(3.14)), content="F64(3.14)")
  inspect(try! roundtrip(EphemeralValue::F64(0.0)), content="F64(0)")
  inspect(
    try! roundtrip(EphemeralValue::String("hello")),
    content="String(\"hello\")",
  )
  inspect(try! roundtrip(EphemeralValue::String("")), content="String(\"\")")
  // Bytes
  let bytes_buf = @buffer.new()
  bytes_buf.write_byte(b'\x01')
  bytes_buf.write_byte(b'\x02')
  let bytes_val = try! roundtrip(EphemeralValue::Bytes(bytes_buf.to_bytes()))
  match bytes_val {
    EphemeralValue::Bytes(b) => {
      inspect(b.length(), content="2")
      inspect(b[0], content="b'\\x01'")
      inspect(b[1], content="b'\\x02'")
    }
    _ => fail("expected Bytes variant")
  }
  // List
  let list_val = try! roundtrip(
    EphemeralValue::List([EphemeralValue::I64(1L), EphemeralValue::String("a")]),
  )
  inspect(
    list_val,
    content=(
      #|List([I64(1), String("a")])
    ),
  )
  // Map
  let map : Map[String, EphemeralValue] = { "key": EphemeralValue::Bool(true) }
  let map_val = try! roundtrip(EphemeralValue::Map(map))
  inspect(map_val, content="Map({\"key\": Bool(true)})")
}

///|
test "ephemeral value roundtrip: nested structures" {
  let inner_map : Map[String, EphemeralValue] = {
    "nested": EphemeralValue::I64(99L),
  }
  let inner_list : Array[EphemeralValue] = [
    EphemeralValue::Map(inner_map),
    EphemeralValue::Bool(false),
  ]
  let outer_map : Map[String, EphemeralValue] = {
    "items": EphemeralValue::List(inner_list),
    "count": EphemeralValue::I64(2L),
  }
  let value = EphemeralValue::Map(outer_map)
  let buf = @buffer.new()
  write_ephemeral_value(buf, value)
  let reader = Reader::new(buf.to_bytes())
  let decoded = try! read_ephemeral_value(reader)
  // Verify structure by navigating the decoded value
  match decoded {
    EphemeralValue::Map(m) => {
      inspect(m.length(), content="2")
      match m["items"] {
        EphemeralValue::List(items) => {
          inspect(items.length(), content="2")
          match items[0] {
            EphemeralValue::Map(inner) =>
              inspect(inner["nested"], content="I64(99)")
            _ => fail("expected inner Map")
          }
          inspect(items[1], content="Bool(false)")
        }
        _ => fail("expected List")
      }
      inspect(m["count"], content="I64(2)")
    }
    _ => fail("expected outer Map")
  }
}

///|
test "ephemeral value roundtrip: empty containers" {
  let buf = @buffer.new()
  write_ephemeral_value(buf, EphemeralValue::List([]))
  let empty_map : Map[String, EphemeralValue] = {}
  write_ephemeral_value(buf, EphemeralValue::Map(empty_map))
  let reader = Reader::new(buf.to_bytes())
  inspect(try! read_ephemeral_value(reader), content="List([])")
  inspect(try! read_ephemeral_value(reader), content="Map({})")
}

///|
test "encode_entries/decode_entries roundtrip" {
  let entries : Array[(String, EphemeralRecord)] = [
    ("1", { value: Some(EphemeralValue::I64(42L)), clock: 3L, updated_at: 0UL }),
    (
      "2",
      {
        value: Some(EphemeralValue::String("hello")),
        clock: 5L,
        updated_at: 0UL,
      },
    ),
  ]
  let bytes = encode_entries(entries)
  let decoded = try! decode_entries(bytes)
  inspect(decoded.length(), content="2")
  // Keys are preserved as numeric strings
  inspect(decoded[0].0, content="1")
  inspect(decoded[1].0, content="2")
  // Values are preserved
  inspect(decoded[0].1.value, content="Some(I64(42))")
  inspect(decoded[1].1.value, content="Some(String(\"hello\"))")
  // Clocks are preserved
  inspect(decoded[0].1.clock, content="3")
  inspect(decoded[1].1.clock, content="5")
}

///|
test "encode_entries/decode_entries: empty array" {
  let bytes = encode_entries([])
  inspect(bytes.length(), content="0")
  let decoded = try! decode_entries(bytes)
  inspect(decoded.length(), content="0")
}

///|
test "encode_entries/decode_entries: None value becomes Null" {
  let entries : Array[(String, EphemeralRecord)] = [
    ("1", { value: None, clock: 1L, updated_at: 0UL }),
  ]
  let bytes = encode_entries(entries)
  let decoded = try! decode_entries(bytes)
  inspect(decoded.length(), content="1")
  // Null round-trips back to None via decode_entries
  inspect(decoded[0].1.value, content="None")
}

///|
test "f64 roundtrip: special values" {
  fn roundtrip_f64(v : Double) -> Double raise {
    let buf = @buffer.new()
    write_f64_le(buf, v)
    let reader = Reader::new(buf.to_bytes())
    read_f64_le(reader)
  }

  inspect(try! roundtrip_f64(0.0), content="0")
  inspect(try! roundtrip_f64(-0.0), content="0")
  inspect(try! roundtrip_f64(1.0), content="1")
  inspect(try! roundtrip_f64(-1.0), content="-1")
  inspect(
    try! roundtrip_f64(1.7976931348623157e308),
    content="1.7976931348623157e+308",
  ) // Double max
  let min_pos = 5.0e-324
  inspect(try! roundtrip_f64(min_pos), content="5e-324") // Double min positive
  let inf : Double = 1.0 / 0.0
  let neg_inf : Double = -1.0 / 0.0
  let nan : Double = 0.0 / 0.0
  inspect(try! roundtrip_f64(inf), content="Infinity")
  inspect(try! roundtrip_f64(neg_inf), content="-Infinity")
  inspect((try! roundtrip_f64(nan)).is_nan(), content="true")
}

///|
test "string roundtrip: edge cases" {
  let buf = @buffer.new()
  write_string(buf, "") // empty
  write_string(buf, " ") // single space
  write_string(buf, "\n\t\r") // whitespace chars
  let reader = Reader::new(buf.to_bytes())
  inspect(try! (read_string(reader) == ""), content="true")
  inspect(try! (read_string(reader) == " "), content="true")
  inspect(try! (read_string(reader) == "\n\t\r"), content="true")
}

///|
test "len_bytes roundtrip" {
  let buf = @buffer.new()
  write_len_bytes(buf, Bytes::new(0)) // empty bytes
  let three = Bytes::new(3)
  write_len_bytes(buf, three)
  let reader = Reader::new(buf.to_bytes())
  let empty = try! read_len_bytes(reader)
  inspect(empty.length(), content="0")
  let three_out = try! read_len_bytes(reader)
  inspect(three_out.length(), content="3")
}
