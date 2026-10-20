///|
fn codec_doc(id : String, text : String) -> Document {
  Document::create(test_document_id(id), text)
}

///|
test "two-field codec round trips exact text" {
  let value = codec_doc("id", "# Text\r\n\u{0000}日本語")
  assert_eq(
    decode_document(source_key(value.id()), encode_document(value)),
    Some(value),
  )
}

///|
test "codec rejects malformed schema with an otherwise valid identity" {
  let document = codec_doc("id", "x")
  let id = document.id().value()
  let key = source_key(document.id())
  let valid = "{\"document_id\":\"\{id}\",\"text\":\"x\"}"
  assert_eq(decode_document(key, valid), Some(document))
  let cases : Array[(String, String)] = [
    ("malformed JSON", "bad"),
    ("empty object", "{}"),
    ("missing text", "{\"document_id\":\"\{id}\"}"),
    ("missing identity", "{\"text\":\"x\"}"),
    (
      "old schema",
      "{\"document_id\":\"\{id}\",\"text\":\"x\",\"change_order\":0}",
    ),
    ("extra field", "{\"document_id\":\"\{id}\",\"text\":\"x\",\"extra\":1}"),
    ("numeric identity", "{\"document_id\":1,\"text\":\"x\"}"),
    ("null text", "{\"document_id\":\"\{id}\",\"text\":null}"),
  ]
  for (name, encoded) in cases {
    assert_eq(decode_document(key, encoded), None, msg=name)
  }
}

///|
test "codec rejects identity mismatch and invalid keys" {
  let value = codec_doc("id", "x")
  assert_eq(
    decode_document(
      source_key(test_document_id("other")),
      encode_document(value),
    ),
    None,
  )
  assert_eq(
    source_key(test_document_id("id")),
    "source/v1/" + test_document_id("id").value(),
  )
  assert_eq(decode_document("source/v1/", encode_document(value)), None)
  assert_eq(
    decode_document("wrong/" + value.id().value(), encode_document(value)),
    None,
  )
  assert_eq(
    decode_document("source/v1/id", "{\"document_id\":\"id\",\"text\":\"x\"}"),
    None,
  )
}
