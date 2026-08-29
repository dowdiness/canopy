///|
test "source key and strict codec preserve identity and exact text" {
  let source = SourceRecord::new("document-1", "# Text\r\n").unwrap()
  assert_eq(source_key(source.document_id()), Some("source/v1/document-1"))
  guard decode_source("source/v1/document-1", encode_source(source))
    is Ok(decoded) else {
    fail("expected valid Source round-trip")
  }
  assert_eq(decoded, source)
}

///|
test "source key and payload identity must match" {
  let source = SourceRecord::new("document-1", "# Text\n").unwrap()
  assert_eq(source_key(""), None)
  assert_true(
    decode_source("source/v1/document-2", encode_source(source))
    is Err(SourceDecodeFailure::IdentityMismatch),
  )
}

///|
test "source decoder rejects malformed missing and extra fields" {
  for
    encoded in [
      "not-json", "{\"document_id\":\"document-1\"}", "{\"document_id\":\"document-1\",\"text\":\"# Text\\n\",\"extra\":\"unexpected\"}",
    ] {
    assert_true(
      decode_source("source/v1/document-1", encoded)
      is Err(SourceDecodeFailure::InvalidRecord),
    )
  }
}

///|
test "source decoder rejects empty or wrongly typed fields" {
  for
    encoded in [
      "{\"document_id\":\"\",\"text\":\"# Text\\n\"}", "{\"document_id\":1,\"text\":\"# Text\\n\"}",
      "{\"document_id\":\"document-1\",\"text\":null}",
    ] {
    assert_true(
      decode_source("source/v1/document-1", encoded)
      is Err(SourceDecodeFailure::InvalidRecord),
    )
  }
}
