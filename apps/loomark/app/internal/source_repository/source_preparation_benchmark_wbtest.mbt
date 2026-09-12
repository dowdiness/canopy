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
