///|
fn reconciliation_bench_text(index : Int, large : Bool) -> String {
  if !large {
    return "# Document \{index}\n\nSmall body.\n"
  }
  let builder = StringBuilder()
  builder.write_string("# Document \{index}\n\n")
  for paragraph = 0; paragraph < 256; paragraph = paragraph + 1 {
    builder.write_string(
      "Paragraph \{paragraph} contains representative Markdown text for catalog name reconciliation.\n\n",
    )
  }
  builder.to_string()
}

///|
fn reconciliation_bench_sources(
  count : Int,
  large_mix : Bool,
) -> Array[SourceRecord] {
  Array::makei(count, index => {
    let document_id = "document-\{index}"
    SourceRecord::new(
      document_id,
      reconciliation_bench_text(index, large_mix && index % 100 == 0),
    ).unwrap()
  })
}

///|
fn reconciliation_bench_entries(
  sources : Array[SourceRecord],
  include_catalog : Bool,
) -> Array[@indexed_db.ScanEntry] {
  let entries = sources.map(source => {
    @indexed_db.ScanEntry::StringRecord(
      source_key(source.document_id()).unwrap(),
      encode_source(source),
    )
  })
  if include_catalog {
    let snapshot = RepositorySnapshot::from_sources(sources).unwrap()
    entries.push(
      @indexed_db.ScanEntry::StringRecord(
        CATALOG_KEY,
        encode_catalog(snapshot.catalog()),
      ),
    )
  }
  entries
}

///|
fn benchmark_reconciliation(
  b : @bench.T,
  count : Int,
  large_mix : Bool,
) -> Unit {
  let sources = reconciliation_bench_sources(count, large_mix)
  let entries = reconciliation_bench_entries(sources, true)
  b.bench(fn() { b.keep(reconcile_scan(entries)) })
}

///|
test "bench: reconcile 10 small Sources" (b : @bench.T) {
  benchmark_reconciliation(b, 10, false)
}

///|
test "bench: reconcile 100 small Sources" (b : @bench.T) {
  benchmark_reconciliation(b, 100, false)
}

///|
test "bench: reconcile 1000 Sources with large-document mix" (b : @bench.T) {
  benchmark_reconciliation(b, 1000, true)
}

///|
test "bench: decode 1000 Source records with large-document mix" (b : @bench.T) {
  let sources = reconciliation_bench_sources(1000, true)
  let entries = reconciliation_bench_entries(sources, false)
  b.bench(fn() {
    let decoded = entries.filter_map(entry => {
      match entry {
        @indexed_db.ScanEntry::StringRecord(key, value) =>
          decode_source(key, value).to_option()
        @indexed_db.ScanEntry::UnsupportedValue(_)
        | @indexed_db.ScanEntry::UnsupportedKey(_) => None
      }
    })
    b.keep(decoded)
  })
}

///|
test "bench: derive 1000 names with large-document mix" (b : @bench.T) {
  let sources = reconciliation_bench_sources(1000, true)
  b.bench(fn() { b.keep(sources.map(source => derive_name(source.text()))) })
}

///|
test "bench: compare 1000-entry Catalog" (b : @bench.T) {
  let sources = reconciliation_bench_sources(1000, true)
  let catalog = RepositorySnapshot::from_sources(sources).unwrap().catalog()
  let encoded = encode_catalog(catalog)
  b.bench(fn() { b.keep(decode_catalog(encoded) == Ok(catalog)) })
}
