///|
async test "SHA256 uses standard UTF8 and lowercase hexadecimal" {
  inspect(
    @crypto.sha256("abc"),
    content="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
}

///|
extern "js" fn from_units(units : FixedArray[Int]) -> String =
  #|(units) => String.fromCharCode(...units)

///|
extern "js" fn platform_utf8(text : String) -> Bytes =
  #|(text) => new TextEncoder().encode(text)

///|
test "core UTF8 preserves platform encoding including unpaired surrogates" {
  let cases : Array[(String, Bytes)] = [
    ("", b""),
    ("文🌳", [0xe6, 0x96, 0x87, 0xf0, 0x9f, 0x8c, 0xb3]),
    ("\uFEFF\u0000", [0xef, 0xbb, 0xbf, 0x00]),
    (from_units([0x41, 0xd800, 0x5a]), [0x41, 0xef, 0xbf, 0xbd, 0x5a]),
    (from_units([0x41, 0xdfff, 0x5a]), [0x41, 0xef, 0xbf, 0xbd, 0x5a]),
    (from_units([0xdc00, 0xd800]), [0xef, 0xbf, 0xbd, 0xef, 0xbf, 0xbd]),
    (from_units([0xd800, 0xdc00]), [0xf0, 0x90, 0x80, 0x80]),
    (from_units([0xdbff, 0xdfff]), [0xf4, 0x8f, 0xbf, 0xbf]),
  ]
  for (text, expected) in cases {
    assert_eq(platform_utf8(text), expected)
    assert_eq(@utf8.encode(text), expected)
  }
}

///|
async test "SHA256 preserves empty Unicode and replacement-character fingerprints" {
  // Expected values obtained independently with Node's createHash, not this binding.
  let cases = [
    ("", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
    (
      "文🌳", "db37d49874ba67f3154c8870349762c5bdf94ae1872a22115adb3183adae19e1",
    ),
    (
      from_units([0x41, 0xd800, 0x5a]),
      "1dbad52b4840c58a645cb742112894d0bae85b97e87e1942ec04559a72937998",
    ),
    (
      "\uFEFF\u0000", "d90004879d3206361b4d16d8dcc8005882aecd94cd65670c07c466f64ecc055b",
    ),
  ]
  for (text, expected) in cases {
    assert_eq(@crypto.sha256(text), expected)
  }
}
