///|
fn bench_document(index : Int, large : Bool) -> Document {
  let text = if large {
    "# Document \{index}\n" + String::make(4096, 'x')
  } else {
    "# Document \{index}\n"
  }
  Document::create(test_document_id("document-\{index}"), text)
}

///|
test "bench: reconcile representative documents" (b : @bench.T) {
  let documents = Array::makei(100, i => bench_document(i, i % 20 == 0))
  let entries = documents.map(d => {
    @indexed_db.Entry::StringRecord(source_key(d.id()), encode_document(d))
  })
  b.bench(fn() { b.keep(reconcile_scan(entries)) })
}

///|
test "bench: decode representative documents" (b : @bench.T) {
  let documents = Array::makei(100, i => bench_document(i, i % 20 == 0))
  let entries = documents.map(d => (source_key(d.id()), encode_document(d)))
  b.bench(fn() { b.keep(entries.map(pair => decode_document(pair.0, pair.1))) })
}

///|
test "bench: complete a tail edit without reinterpreting unchanged names" (
  b : @bench.T,
) {
  let body = String::make(1024 * 1024, 'x')
  let original = doc("active", "# Stable\n\n" + body)
  let unrelated = doc("other", "# [Unresolved]\n\n" + body)
  let saved = SavedDocuments::from_documents([original, unrelated]).unwrap()
  let edits = Array::makei(8, index => {
    original.update(original.text() + "\{index}")
  })
  let mut index = 0
  b.bench(fn() {
    b.keep(saved.apply(Stored(edits[index])))
    index = (index + 1) % edits.length()
  })
}
