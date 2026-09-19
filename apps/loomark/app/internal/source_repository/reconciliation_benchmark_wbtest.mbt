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
