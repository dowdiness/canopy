///|
fn source_preparation_bench_sources(size : Int) -> Array[SourceRecord] {
  Array::makei(8, index => {
    SourceRecord::new(
      "bench-document",
      "# Stable\n" + String::make(size - 1, 'x') + "\{index}",
    ).unwrap()
  })
}

///|
fn benchmark_source_encoding(b : @bench.T, size : Int) -> Unit {
  let sources = source_preparation_bench_sources(size)
  let mut index = 0
  b.bench(fn() {
    let encoded = encode_source(sources[index])
    index = (index + 1) % sources.length()
    b.keep(encoded)
  })
}

///|
test "bench: encode Source 64 KiB" (b : @bench.T) {
  benchmark_source_encoding(b, 64 * 1024)
}

///|
test "bench: encode Source 256 KiB" (b : @bench.T) {
  benchmark_source_encoding(b, 256 * 1024)
}

///|
test "bench: encode Source 1 MiB" (b : @bench.T) {
  benchmark_source_encoding(b, 1024 * 1024)
}

///|
test "bench: accept 1 MiB Source with unchanged certified title" (b : @bench.T) {
  let snapshot = RepositorySnapshot::from_sources([
    SourceRecord::new(
      "bench-document",
      "# Stable\n" + String::make(1024 * 1024, 'x'),
    ).unwrap(),
  ]).unwrap()
  let sources = source_preparation_bench_sources(1024 * 1024)
  let mut index = 0
  b.bench(fn() {
    let accepted = accepted_source(snapshot, sources[index])
    index = (index + 1) % sources.length()
    b.keep(accepted)
  })
}

///|
test "bench: accept 1 MiB Source after title change" (b : @bench.T) {
  let snapshot = RepositorySnapshot::from_sources([
    SourceRecord::new(
      "bench-document",
      "# Stable\n" + String::make(1024 * 1024, 'x'),
    ).unwrap(),
  ]).unwrap()
  let sources = Array::makei(8, index => {
    SourceRecord::new(
      "bench-document",
      "# Changed \{index}\n" + String::make(1024 * 1024, 'x'),
    ).unwrap()
  })
  let mut index = 0
  b.bench(fn() {
    let accepted = accepted_source(snapshot, sources[index])
    index = (index + 1) % sources.length()
    b.keep(accepted)
  })
}
