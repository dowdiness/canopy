///| Generic byte-level wire primitives.
///
/// LEB128 varints (unsigned + zigzag-signed), length-prefixed UTF-16LE
/// strings, length-prefixed byte blobs, and little-endian f64. A `Reader`
/// carries a mutable cursor over an immutable `Bytes` buffer so nested decoders
/// compose without threading an offset. No domain knowledge lives here.

///|
pub struct Reader {
  data : Bytes
  mut pos : Int
}

///|
pub fn Reader::new(data : Bytes) -> Reader {
  { data, pos: 0 }
}

///|
pub fn Reader::read_byte(self : Reader) -> Byte raise CodecError {
  if self.pos >= self.data.length() {
    raise CodecError::UnexpectedEndOfInput
  }
  let b = self.data[self.pos]
  self.pos += 1
  b
}

///|
fn Reader::read_bytes(self : Reader, n : Int) -> Bytes raise CodecError {
  if self.pos + n > self.data.length() {
    raise CodecError::UnexpectedEndOfInput
  }
  let out = self.data.view(start=self.pos, end=self.pos + n).to_owned()
  self.pos += n
  out
}

///|
pub fn write_uvarint(buf : Buffer, value : UInt64) -> Unit {
  let mut v = value
  while v >= 0x80UL {
    buf.write_byte((v.to_byte().to_int() | 0x80).to_byte())
    v = v >> 7
  }
  buf.write_byte(v.to_byte())
}

///|
pub fn read_uvarint(reader : Reader) -> UInt64 raise CodecError {
  let mut result : UInt64 = 0UL
  let mut shift = 0
  for _ in 0..<10 {
    let b = reader.read_byte()
    result = result | ((b.to_int() & 0x7F).to_uint64() << shift)
    if (b.to_int() & 0x80) == 0 {
      return result
    }
    shift += 7
  }
  raise CodecError::VarintTooLong
}

///|
pub fn safe_uvarint_to_int(v : UInt64) -> Int raise CodecError {
  if v > 2147483647UL {
    raise CodecError::VarintValueTooLarge
  }
  v.to_int()
}

///|
pub fn write_ivarint(buf : Buffer, value : Int64) -> Unit {
  // zigzag encoding: (value << 1) ^ (value >> 63)
  let zigzag = ((value << 1) ^ (value >> 63)).reinterpret_as_uint64()
  write_uvarint(buf, zigzag)
}

///|
pub fn read_ivarint(reader : Reader) -> Int64 raise CodecError {
  let zigzag = read_uvarint(reader)
  // zigzag decoding: (zigzag >>> 1) ^ -(zigzag & 1)
  let signed = (zigzag >> 1).reinterpret_as_int64() ^
    -(zigzag & 1UL).reinterpret_as_int64()
  signed
}

///|
pub fn write_string(buf : Buffer, s : String) -> Unit {
  let tmp = Buffer()
  tmp.write_string_utf16le(s.view())
  let bytes = tmp.to_bytes()
  write_uvarint(buf, bytes.length().to_uint64())
  buf.write_bytes(bytes)
}

///|
pub fn read_string(reader : Reader) -> String raise CodecError {
  let len = safe_uvarint_to_int(read_uvarint(reader))
  let bytes = reader.read_bytes(len)
  // Wire data is written via Buffer.write_string_utf16le (matching MoonBit's
  // internal String encoding), and Bytes.to_unchecked_string round-trips that
  // same UTF-16LE representation. Callers should treat decoded strings as
  // untrusted display data, not executable content.
  bytes.to_unchecked_string()
}

///|
pub fn write_len_bytes(buf : Buffer, b : Bytes) -> Unit {
  write_uvarint(buf, b.length().to_uint64())
  buf.write_bytes(b)
}

///|
pub fn read_len_bytes(reader : Reader) -> Bytes raise CodecError {
  let len = safe_uvarint_to_int(read_uvarint(reader))
  reader.read_bytes(len)
}

///|
pub fn write_f64_le(buf : Buffer, value : Double) -> Unit {
  let bits = value.reinterpret_as_uint64()
  for i in 0..<8 {
    buf.write_byte(((bits >> (i * 8)) & 0xFFUL).to_byte())
  }
}

///|
pub fn read_f64_le(reader : Reader) -> Double raise CodecError {
  let bytes = reader.read_bytes(8)
  let mut bits : UInt64 = 0UL
  for i in 0..<8 {
    bits = bits | (bytes[i].to_uint64() << (i * 8))
  }
  bits.reinterpret_as_double()
}
