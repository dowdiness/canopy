///|
fn preparation_document(size : Int) -> Document {
  Document::create("bench-document", "# Stable\n" + String::make(size, 'x')) catch {
    _ => abort("invalid")
  }
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
test "bench: encode shared 1 MiB sync checkpoint text" (b : @bench.T) {
  let text = String::make(1024 * 1024, 'x')
  let enrolled = SyncCheckpoint::enroll(
    test_account(value="bench-account"),
    Document::create("bench-document", text) catch {
      _ => abort("invalid")
    },
  )
  let pending = start_save(enrolled, "11111111-1111-4111-8111-111111111111")
  let acknowledged = pending
    .checkpoint()
    .acknowledge(
      test_operation("11111111-1111-4111-8111-111111111111"),
      test_revision(1.0),
    )
  let checkpoint = acknowledged.checkpoint()
  b.bench(fn() { b.keep(encode_checkpoint(checkpoint)) })
}
