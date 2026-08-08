///|
fn version_benchmark_source(block_count : Int) -> String {
  Array::makei(block_count, index => {
    "## Heading " +
    index.to_string() +
    "\n\nParagraph " +
    index.to_string() +
    " with **bold**.\n"
  }).join("\n")
}

///|
test "perf: cached SyncEditor version read (250 blocks)" (b : @bench.T) {
  let editor = try! @probe.new_test_editor("cached-version-benchmark")
  try! editor.set_text(version_benchmark_source(250))
  b.bench(() => b.keep(editor.get_version()))
}

///|
test "perf: TextState version expansion (250 blocks)" (b : @bench.T) {
  let editor = try! @probe.new_test_editor("expanded-version-benchmark")
  try! editor.set_text(version_benchmark_source(250))
  b.bench(() => b.keep(editor.doc.version()))
}
