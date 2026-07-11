// Presence value codec and peer-id wire mapping.
//
// The generic byte-level primitives (varints, length-prefixed strings/bytes,
// f64, the `Reader` cursor) live in `dowdiness/byte_codec`. Pure encoders are
// used directly through the `using` block below; the decoders raise
// `@byte_codec.CodecError`, which the seam wrappers convert into
// `EphemeralError::Codec` so this package's public error type stays
// `EphemeralError`.

///|
using @byte_codec {
  type Reader,
  write_uvarint,
  write_ivarint,
  write_string,
  write_len_bytes,
  write_f64_le,
}

// --- byte-codec read seam: CodecError -> EphemeralError::Codec ---

///|
fn read_byte(reader : Reader) -> Byte raise EphemeralError {
  reader.read_byte() catch {
    e => raise EphemeralError::Codec(e)
  }
}

///|
fn read_uvarint(reader : Reader) -> UInt64 raise EphemeralError {
  @byte_codec.read_uvarint(reader) catch {
    e => raise EphemeralError::Codec(e)
  }
}

///|
fn safe_uvarint_to_int(v : UInt64) -> Int raise EphemeralError {
  @byte_codec.safe_uvarint_to_int(v) catch {
    e => raise EphemeralError::Codec(e)
  }
}

///|
fn read_ivarint(reader : Reader) -> Int64 raise EphemeralError {
  @byte_codec.read_ivarint(reader) catch {
    e => raise EphemeralError::Codec(e)
  }
}

///|
fn read_string(reader : Reader) -> String raise EphemeralError {
  @byte_codec.read_string(reader) catch {
    e => raise EphemeralError::Codec(e)
  }
}

///|
fn read_len_bytes(reader : Reader) -> Bytes raise EphemeralError {
  @byte_codec.read_len_bytes(reader) catch {
    e => raise EphemeralError::Codec(e)
  }
}

///|
fn read_f64_le(reader : Reader) -> Double raise EphemeralError {
  @byte_codec.read_f64_le(reader) catch {
    e => raise EphemeralError::Codec(e)
  }
}

// --- presence value tags ---

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
fn write_ephemeral_value(buf : Buffer, value : EphemeralValue) -> Unit {
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
fn read_ephemeral_value(reader : Reader) -> EphemeralValue raise EphemeralError {
  let tag = read_byte(reader)
  if tag == tag_null {
    EphemeralValue::Null
  } else if tag == tag_bool {
    let raw = read_byte(reader)
    if raw == b'\x00' {
      EphemeralValue::Bool(false)
    } else if raw == b'\x01' {
      EphemeralValue::Bool(true)
    } else {
      raise EphemeralError::InvalidBoolValue
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
    for _ in 0..<count {
      items.push(read_ephemeral_value(reader))
    }
    EphemeralValue::List(items)
  } else if tag == tag_map {
    let count = safe_uvarint_to_int(read_uvarint(reader))
    let map : Map[String, EphemeralValue] = {}
    for _ in 0..<count {
      let key = read_string(reader)
      let item = read_ephemeral_value(reader)
      map[key] = item
    }
    EphemeralValue::Map(map)
  } else {
    raise EphemeralError::InvalidValueTag
  }
}

// --- peer-id wire mapping ---

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
    if !ch.is_ascii_digit() {
      return None
    }
  }
  Some(@string.parse_uint64(key.view(), base=10)) catch {
    _ => None
  }
}

///|
let hashed_peer_mask : UInt64 = 0x8000000000000000UL

///|
let unhashed_peer_mask : UInt64 = 0x7FFFFFFFFFFFFFFFUL

///|
fn wire_peer_id(key : String) -> UInt64 {
  match parse_peer_id(key) {
    Some(value) => value
    None => (stable_peer_hash(key) & unhashed_peer_mask) | hashed_peer_mask
  }
}

///|
/// Presence wire format still encodes peer IDs as uvarints. Preserve existing
/// numeric IDs and map arbitrary agent IDs into a reserved high-bit range.
fn to_wire_peer_id(key : String) -> String {
  wire_peer_id(key).to_string()
}

///|
fn stable_peer_hash(key : String) -> UInt64 {
  let buf = Buffer()
  buf.write_string_utf16le(key.view())
  let bytes = buf.to_bytes()
  let mut hash = 14695981039346656037UL
  for b in bytes {
    hash = hash ^ b.to_uint64()
    hash = hash * 1099511628211UL
  }
  hash
}

///|
fn encode_entries(entries : Array[(String, EphemeralRecord)]) -> Bytes {
  let filtered : Array[(UInt64, Int64, EphemeralValue)] = []
  for entry in entries {
    let (key, record) = entry
    let peer = wire_peer_id(key)
    let value = match record.value {
      Some(value) => value
      None => EphemeralValue::Null
    }
    filtered.push((peer, record.clock, value))
  }
  if filtered.length() == 0 {
    return Bytes::new(0)
  }
  let buf = Buffer()
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
fn decode_entries(
  data : Bytes,
) -> Array[(String, EphemeralRecord)] raise EphemeralError {
  if data.length() == 0 {
    return []
  }
  let reader = Reader::new(data)
  let count = safe_uvarint_to_int(read_uvarint(reader))
  let out : Array[(String, EphemeralRecord)] = []
  for _ in 0..<count {
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
