///|
/// Browser-sized source used to measure the fast append decision itself.
fn sync_text_benchmark_source(block_count : Int) -> String {
  Array::makei(block_count, index => {
    let number = index.to_string()
    "## Heading " +
    number +
    "\n\nParagraph " +
    number +
    " with **bold** and [link](https://example.com/" +
    number +
    ").\n"
  }).join("\n")
}

///|
test "perf: shared text change append (250 blocks)" (b : @bench.T) {
  let source = sync_text_benchmark_source(250)
  let mut tick = 0
  b.bench(() => {
    let suffix = if tick % 2 == 0 { "x" } else { "y" }
    tick += 1
    b.keep(@text_change.compute_text_change(source, source + suffix))
  })
}

///|
test "perf: fast text change append (250 blocks)" (b : @bench.T) {
  let source = sync_text_benchmark_source(250)
  let mut tick = 0
  b.bench(() => {
    let suffix = if tick % 2 == 0 { "x" } else { "y" }
    tick += 1
    b.keep(fast_append_text_change(source, source + suffix))
  })
}
