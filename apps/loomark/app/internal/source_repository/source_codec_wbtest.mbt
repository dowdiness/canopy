///|
fn codec_doc(id : String, text : String) -> Document {
  Document::create(id, text) catch {
    _ => abort("invalid test id")
  }
}

///|
test "two-field codec round trips exact text" {
  let value = codec_doc("id", "# Text\r\n\u{0000}日本語")
  assert_eq(
    decode_document("source/v1/id", encode_document(value)),
    Some(value),
  )
}

///|
test "codec rejects old three-field schema" {
  assert_eq(
    decode_document(
      "source/v1/id", "{\"document_id\":\"id\",\"text\":\"x\",\"change_order\":0}",
    ),
    None,
  )
}

///|
test "codec rejects malformed missing and extra fields" {
  for
    encoded in [
      "bad", "{}", "{\"document_id\":\"id\"}", "{\"document_id\":\"id\",\"text\":\"x\",\"extra\":1}",
    ] {
    assert_eq(decode_document("source/v1/id", encoded), None)
  }
}

///|
test "codec rejects identity mismatch and invalid keys" {
  let value = codec_doc("id", "x")
  assert_eq(decode_document("source/v1/other", encode_document(value)), None)
  assert_eq(source_key(""), None)
  assert_eq(decode_document("source/v1/", encode_document(value)), None)
}

///|
test "codec requires string fields" {
  assert_eq(
    decode_document("source/v1/id", "{\"document_id\":1,\"text\":\"x\"}"),
    None,
  )
  assert_eq(
    decode_document("source/v1/id", "{\"document_id\":\"id\",\"text\":null}"),
    None,
  )
}
