///|
test "stored document codec preserves identity and text" {
  let encoded = encode_document("document-1", "# Text\n")
  inspect(
    decode_document(encoded) == OpenResult::Loaded("document-1", "# Text\n"),
    content="true",
  )
}

///|
test "stored document decoder rejects malformed JSON" {
  inspect(decode_document("not-json") == Failed(InvalidRecord), content="true")
}

///|
test "stored document decoder rejects missing fields" {
  inspect(
    decode_document("{\"document_id\":\"document-1\"}") == Failed(InvalidRecord),
    content="true",
  )
}

///|
test "stored document decoder rejects extra fields" {
  inspect(
    decode_document(
      "{\"document_id\":\"document-1\",\"text\":\"# Text\\n\",\"extra\":\"unexpected\"}",
    ) ==
    Failed(InvalidRecord),
    content="true",
  )
}

///|
test "stored document decoder rejects an empty identity" {
  inspect(
    decode_document("{\"document_id\":\"\",\"text\":\"# Text\\n\"}") ==
    Failed(InvalidRecord),
    content="true",
  )
}

///|
test "stored document decoder rejects a non-string identity" {
  inspect(
    decode_document("{\"document_id\":1,\"text\":\"# Text\\n\"}") ==
    Failed(InvalidRecord),
    content="true",
  )
}

///|
test "stored document decoder rejects non-string text" {
  inspect(
    decode_document("{\"document_id\":\"document-1\",\"text\":null}") ==
    Failed(InvalidRecord),
    content="true",
  )
}
