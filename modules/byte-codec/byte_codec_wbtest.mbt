///|
test "uvarint roundtrip: boundary values" {
  let buf = Buffer()
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
  let buf = Buffer()
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
  let result : Result[Byte, CodecError] = Ok(reader.read_byte()) catch {
    err => Err(err)
  }
  inspect(result is Err(_), content="true")
}

///|
test "f64 roundtrip: special values" {
  fn roundtrip_f64(v : Double) -> Double raise {
    let buf = Buffer()
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
  let buf = Buffer()
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
  let buf = Buffer()
  write_len_bytes(buf, Bytes::new(0)) // empty bytes
  let three = Bytes::new(3)
  write_len_bytes(buf, three)
  let reader = Reader::new(buf.to_bytes())
  let empty = try! read_len_bytes(reader)
  inspect(empty.length(), content="0")
  let three_out = try! read_len_bytes(reader)
  inspect(three_out.length(), content="3")
}

// --- frozen wire-format fixtures ---
//
// Pin the EXACT byte output of each primitive so the on-the-wire format cannot
// change silently. The `content=` snapshots are frozen literals, never
// re-derived by calling the code under test.

///|
test "wire fixture: uvarint byte layout" {
  let buf = Buffer()
  write_uvarint(buf, 0UL)
  write_uvarint(buf, 127UL)
  write_uvarint(buf, 128UL)
  write_uvarint(buf, 300UL)
  write_uvarint(buf, 16384UL)
  inspect(
    buf.to_bytes(),
    content="b\"\\x00\\x7f\\x80\\x01\\xac\\x02\\x80\\x80\\x01\"",
  )
}

///|
test "wire fixture: ivarint byte layout" {
  let buf = Buffer()
  write_ivarint(buf, 0L)
  write_ivarint(buf, 1L)
  write_ivarint(buf, -1L)
  write_ivarint(buf, 64L)
  write_ivarint(buf, -64L)
  inspect(buf.to_bytes(), content="b\"\\x00\\x02\\x01\\x80\\x01\\x7f\"")
}

///|
test "wire fixture: string byte layout" {
  let buf = Buffer()
  write_string(buf, "")
  write_string(buf, "hi")
  write_string(buf, "é")
  inspect(
    buf.to_bytes(),
    content=(
      #|b"\x00\x04h\x00i\x00\x02\xe9\x00"
    ),
  )
}

///|
test "wire fixture: f64 byte layout" {
  let buf = Buffer()
  write_f64_le(buf, 1.5)
  write_f64_le(buf, -0.0)
  inspect(
    buf.to_bytes(),
    content=(
      #|b"\x00\x00\x00\x00\x00\x00\xf8?\x00\x00\x00\x00\x00\x00\x00\x80"
    ),
  )
}

///|
test "wire fixture: len_bytes byte layout" {
  let buf = Buffer()
  write_len_bytes(buf, Bytes::new(0))
  write_len_bytes(buf, b"\x0a\x0b\x0c")
  inspect(buf.to_bytes(), content="b\"\\x00\\x03\\x0a\\x0b\\x0c\"")
}
