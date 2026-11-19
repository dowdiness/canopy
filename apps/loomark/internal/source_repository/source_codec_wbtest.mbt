///|
fn codec_doc(id : String, text : String) -> Document {
  Document::create(test_document_id(id), text, ChangeTime(0.0))
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
  let valid = "{\"document_id\":\"\{id}\",\"text\":\"x\",\"changed_at\":0}"
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
    (
      "extra field",
      "{\"document_id\":\"\{id}\",\"text\":\"x\",\"changed_at\":0,\"extra\":1}",
    ),
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

///|
test "Change time round trips and is required" {
  let document = Document::create(
    test_document_id("id"),
    "x",
    ChangeTime(1700000000123.0),
  )
  let key = source_key(document.id())
  assert_eq(decode_document(key, encode_document(document)), Some(document))
  let id = document.id().value()
  let cases = [
    "{\"document_id\":\"\{id}\",\"text\":\"x\"}",
    "{\"document_id\":\"\{id}\",\"text\":\"x\",\"changed_at\":\"1\"}",
  ]
  for encoded in cases {
    assert_eq(decode_document(key, encoded), None, msg=encoded)
  }
}

///|
test "Change time is whole milliseconds from the epoch to 2^53 - 1" {
  for value in [0.0, 1700000000123.0, 9007199254740991.0] {
    assert_eq(ChangeTime::parse(value).value(), value)
  }
  for value in [-1.0, 1.5, 9007199254740992.0] {
    let rejected = try ChangeTime::parse(value) |> ignore catch {
      InvalidChangeTime => true
    } noraise {
      _ => false
    }
    assert_true(rejected, msg="\{value}")
  }
}
