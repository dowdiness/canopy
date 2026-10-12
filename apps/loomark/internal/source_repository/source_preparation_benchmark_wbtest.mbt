///|
fn preparation_document(size : Int) -> Document {
  Document::create(
    test_document_id("bench-document"),
    "# Stable\n" + String::make(size, 'x'),
  )
}

///|
test "bench: encode large document" (b : @bench.T) {
  let document = preparation_document(64 * 1024)
  b.bench(fn() { b.keep(encode_document(document)) })
}

///|
test "bench: derive catalog name for large document" (b : @bench.T) {
  let document = preparation_document(256 * 1024)
  b.bench(fn() { b.keep(@document_lead.derive_name(document.text())) })
}

///|
test "bench: encode shared 1 MiB sync replica text" (b : @bench.T) {
  let text = String::make(1024 * 1024, 'x')
  let replica = DocumentReplica(
    test_account(value="bench-account"),
    Document::create(test_document_id("bench-document"), text),
  )
  let pending = start_save(replica, "11111111-1111-4111-8111-111111111111")
  let acknowledged = pending
    .replica()
    .acknowledge(
      test_operation("11111111-1111-4111-8111-111111111111"),
      test_revision(1.0),
    )
  let replica = acknowledged.replica()
  b.bench(fn() { b.keep(encode_replica(replica)) })
}
