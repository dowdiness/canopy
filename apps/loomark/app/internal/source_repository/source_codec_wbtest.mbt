///|
test "source key and strict codec preserve identity exact text and Change order" {
  let order = ChangeOrder::from_int64(1_700_000_000_123L).unwrap()
  let source = SourceRecord::new("document-1", "# Text\r\n", change_order=order).unwrap()
  assert_eq(source_key(source.document_id()), Some("source/v1/document-1"))
  guard decode_source("source/v1/document-1", encode_source(source))
    is Ok(decoded) else {
    fail("expected valid Source round-trip")
  }
  assert_eq(decoded, source)
  assert_eq(decoded.change_order(), order)
}

///|
test "ChangeOrder advance chooses the greater safe successor" {
  assert_eq(
    ChangeOrder::from_int64(4L)
    .unwrap()
    .advance(ChangeOrder::from_int64(2L).unwrap())
    .unwrap()
    .value(),
    5L,
  )
  assert_eq(
    ChangeOrder::from_int64(4L)
    .unwrap()
    .advance(ChangeOrder::from_int64(9L).unwrap())
    .unwrap()
    .value(),
    9L,
  )
  assert_eq(
    ChangeOrder::from_int64(9_007_199_254_740_991L)
    .unwrap()
    .advance(ChangeOrder::from_int64(0L).unwrap()),
    None,
  )
}

///|
test "Change order is restricted to JavaScript safe integers" {
  assert_true(ChangeOrder::from_int64(9_007_199_254_740_991L) is Some(_))
  assert_eq(ChangeOrder::from_int64(9_007_199_254_740_992L), None)
  assert_eq(ChangeOrder::from_int64(-1L), None)
  for
    encoded in [
      "{\"document_id\":\"document-1\",\"text\":\"# Text\\n\",\"change_order\":9007199254740992}",
      "{\"document_id\":\"document-1\",\"text\":\"# Text\\n\",\"change_order\":1.5}",
      "{\"document_id\":\"document-1\",\"text\":\"# Text\\n\",\"change_order\":-1}",
    ] {
    assert_true(
      decode_source("source/v1/document-1", encoded)
      is Err(SourceDecodeFailure::InvalidRecord),
    )
  }
}

///|
test "source encoder round-trips valid browser text through strict decoder" {
  for
    text in [
      "", "plain text", "quote: \" reverse solidus: \\ solidus: /", "controls: \u{0000}\b\t\n\r",
      "line endings: LF\nCRLF\r\nCR\r", "日本語 café e\u{0301} 😀 \u{2028} \u{2029}",
      "</script><script>alert(1)</script>",
    ] {
    let source = SourceRecord::new("document-\"-日本語", text).unwrap()
    guard decode_source(
        source_key(source.document_id()).unwrap(),
        encode_source(source),
      )
      is Ok(decoded) else {
      fail("expected strict Source round-trip")
    }
    assert_eq(decoded, source)
  }
}

///|
test "source encoder exactly round-trips a 1 MiB Source" {
  let prefix = "# Stable\r\n"
  let text = prefix + String::make(1024 * 1024 - prefix.length(), 'x')
  assert_eq(text.length(), 1024 * 1024)
  let source = SourceRecord::new("document-1-mib", text).unwrap()
  guard decode_source(
      source_key(source.document_id()).unwrap(),
      encode_source(source),
    )
    is Ok(decoded) else {
    fail("expected exact 1 MiB Source round-trip")
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
