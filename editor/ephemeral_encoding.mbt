///|
priv struct Reader {
  data : Bytes
  mut pos : Int
}

///|
fn Reader::new(data : Bytes) -> Reader {
  { data, pos: 0 }
}

///|
fn Reader::read_byte(self : Reader) -> Byte raise {
  if self.pos >= self.data.length() {
    raise Failure::Failure("unexpected end of input")
  }
  let b = self.data[self.pos]
  self.pos += 1
  b
}

///|
fn Reader::read_bytes(self : Reader, n : Int) -> Bytes raise {
  if self.pos + n > self.data.length() {
    raise Failure::Failure("unexpected end of input")
  }
  let out = self.data.view(start=self.pos, end=self.pos + n).to_bytes()
  self.pos += n
  out
}

///|
fn write_uvarint(buf : @buffer.Buffer, value : UInt64) -> Unit {
  let mut v = value
  while v >= 0x80UL {
    buf.write_byte((v.to_byte().to_int() | 0x80).to_byte())
    v = v >> 7
  }
  buf.write_byte(v.to_byte())
}

///|
fn read_uvarint(reader : Reader) -> UInt64 raise {
  let mut result : UInt64 = 0UL
  let mut shift = 0
  for i = 0; i < 10; i = i + 1 {
    let b = reader.read_byte()
    result = result | ((b.to_int() & 0x7F).to_uint64() << shift)
    if (b.to_int() & 0x80) == 0 {
      return result
    }
    shift += 7
  }
  raise Failure::Failure("varint too long")
}

///|
fn safe_uvarint_to_int(v : UInt64) -> Int raise {
  if v > 2147483647UL {
    raise Failure::Failure("varint value exceeds maximum safe Int size")
  }
  v.to_int()
}

///|
fn write_ivarint(buf : @buffer.Buffer, value : Int64) -> Unit {
  // zigzag encoding: (value << 1) ^ (value >> 63)
  let zigzag = ((value << 1) ^ (value >> 63)).reinterpret_as_uint64()
  write_uvarint(buf, zigzag)
}

///|
fn read_ivarint(reader : Reader) -> Int64 raise {
  let zigzag = read_uvarint(reader)
  // zigzag decoding: (zigzag >>> 1) ^ -(zigzag & 1)
  let signed = (zigzag >> 1).reinterpret_as_int64() ^
    -(zigzag & 1UL).reinterpret_as_int64()
  signed
}

///|
fn write_string(buf : @buffer.Buffer, s : String) -> Unit {
  let tmp = @buffer.new()
  tmp.write_string(s)
  let bytes = tmp.to_bytes()
  write_uvarint(buf, bytes.length().to_uint64())
  buf.write_bytes(bytes)
}

///|
fn read_string(reader : Reader) -> String raise {
  let len = safe_uvarint_to_int(read_uvarint(reader))
  let bytes = reader.read_bytes(len)
  bytes.to_unchecked_string()
}

///|
fn write_len_bytes(buf : @buffer.Buffer, b : Bytes) -> Unit {
  write_uvarint(buf, b.length().to_uint64())
  buf.write_bytes(b)
}

///|
fn read_len_bytes(reader : Reader) -> Bytes raise {
  let len = safe_uvarint_to_int(read_uvarint(reader))
  reader.read_bytes(len)
}

///|
let tag_null : Byte = b'\x00'

///|
let tag_bool : Byte = b'\x01'

///|
let tag_f64 : Byte = b'\x02'

///|
let tag_i64 : Byte = b'\x03'

///|
let tag_string : Byte = b'\x04'

///|
let tag_list : Byte = b'\x05'

///|
let tag_map : Byte = b'\x06'

///|
let tag_bytes : Byte = b'\x08'

///|
fn write_ephemeral_value(buf : @buffer.Buffer, value : EphemeralValue) -> Unit {
  match value {
    EphemeralValue::Null => buf.write_byte(tag_null)
    EphemeralValue::Bool(v) => {
      buf.write_byte(tag_bool)
      buf.write_byte(if v { b'\x01' } else { b'\x00' })
    }
    EphemeralValue::F64(v) => {
      buf.write_byte(tag_f64)
      write_f64_le(buf, v)
    }
    EphemeralValue::I64(v) => {
      buf.write_byte(tag_i64)
      write_ivarint(buf, v)
    }
    EphemeralValue::String(v) => {
      buf.write_byte(tag_string)
      write_string(buf, v)
    }
    EphemeralValue::Bytes(v) => {
      buf.write_byte(tag_bytes)
      write_len_bytes(buf, v)
    }
    EphemeralValue::List(items) => {
      buf.write_byte(tag_list)
      write_uvarint(buf, items.length().to_uint64())
      for item in items {
        write_ephemeral_value(buf, item)
      }
    }
    EphemeralValue::Map(map) => {
      buf.write_byte(tag_map)
      write_uvarint(buf, map.length().to_uint64())
      for key, item in map {
        write_string(buf, key)
        write_ephemeral_value(buf, item)
      }
    }
  }
}

///|
fn read_ephemeral_value(reader : Reader) -> EphemeralValue raise {
  let tag = reader.read_byte()
  if tag == tag_null {
    EphemeralValue::Null
  } else if tag == tag_bool {
    let raw = reader.read_byte()
    if raw == b'\x00' {
      EphemeralValue::Bool(false)
    } else if raw == b'\x01' {
      EphemeralValue::Bool(true)
    } else {
      raise Failure::Failure("invalid bool value")
    }
  } else if tag == tag_f64 {
    EphemeralValue::F64(read_f64_le(reader))
  } else if tag == tag_i64 {
    EphemeralValue::I64(read_ivarint(reader))
  } else if tag == tag_string {
    EphemeralValue::String(read_string(reader))
  } else if tag == tag_bytes {
    EphemeralValue::Bytes(read_len_bytes(reader))
  } else if tag == tag_list {
    let count = safe_uvarint_to_int(read_uvarint(reader))
    let items : Array[EphemeralValue] = []
    for i = 0; i < count; i = i + 1 {
      items.push(read_ephemeral_value(reader))
    }
    EphemeralValue::List(items)
  } else if tag == tag_map {
    let count = safe_uvarint_to_int(read_uvarint(reader))
    let map : Map[String, EphemeralValue] = {}
    for i = 0; i < count; i = i + 1 {
      let key = read_string(reader)
      let item = read_ephemeral_value(reader)
      map[key] = item
    }
    EphemeralValue::Map(map)
  } else {
    raise Failure::Failure("invalid ephemeral value tag")
  }
}

///|
fn write_f64_le(buf : @buffer.Buffer, value : Double) -> Unit {
  let bits = value.reinterpret_as_uint64()
  for i = 0; i < 8; i = i + 1 {
    buf.write_byte(((bits >> (i * 8)) & 0xFFUL).to_byte())
  }
}

///|
fn read_f64_le(reader : Reader) -> Double raise {
  let bytes = reader.read_bytes(8)
  let mut bits : UInt64 = 0UL
  for i = 0; i < 8; i = i + 1 {
    bits = bits | (bytes[i].to_uint64() << (i * 8))
  }
  bits.reinterpret_as_double()
}

///|
fn parse_peer_id(key : String) -> UInt64? {
  let chars = key.to_array()
  if chars.length() == 0 {
    return None
  }
  if chars.length() > 1 && chars[0] == '0' {
    return None
  }
  for ch in chars {
    if not(ch.is_ascii_digit()) {
      return None
    }
  }
  Some(@strconv.parse_uint64(key.view(), base=10)) catch {
    _ => None
  }
}

///|
fn encode_entries(entries : Array[(String, EphemeralRecord)]) -> Bytes {
  let filtered : Array[(UInt64, Int64, EphemeralValue)] = []
  for entry in entries {
    let (key, record) = entry
    let peer = match parse_peer_id(key) {
      Some(value) => value
      None => continue
    }
    let value = match record.value {
      Some(value) => value
      None => EphemeralValue::Null
    }
    filtered.push((peer, record.clock, value))
  }
  if filtered.length() == 0 {
    return Bytes::new(0)
  }
  let buf = @buffer.new()
  write_uvarint(buf, filtered.length().to_uint64())
  for entry in filtered {
    let (peer, clock, value) = entry
    write_uvarint(buf, peer)
    write_ivarint(buf, clock)
    write_ephemeral_value(buf, value)
  }
  buf.to_bytes()
}

///|
fn decode_entries(data : Bytes) -> Array[(String, EphemeralRecord)] raise {
  if data.length() == 0 {
    return []
  }
  let reader = Reader::new(data)
  let count = safe_uvarint_to_int(read_uvarint(reader))
  let out : Array[(String, EphemeralRecord)] = []
  for i = 0; i < count; i = i + 1 {
    let peer = read_uvarint(reader)
    let clock = read_ivarint(reader)
    let value = read_ephemeral_value(reader)
    let value_opt : EphemeralValue? = match value {
      EphemeralValue::Null => None
      _ => Some(value)
    }
    out.push((peer.to_string(), { value: value_opt, clock, updated_at: 0UL }))
  }
  out
}
