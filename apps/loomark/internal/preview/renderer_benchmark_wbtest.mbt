///|
fn renderer_benchmark_source(block_count : Int) -> String {
  let out = StringBuilder::StringBuilder()
  for index = 0; index < block_count; index = index + 1 {
    out.write_string(
      "Paragraph \{index} contains *emphasis*, **strong text**, a [link](https://example.test/\{index}), and `code`.\n\n",
    )
  }
  out.to_string()
}

///|
test "Loomark Preview renderer: practical 500 blocks" (b : @bench.T) {
  let root = preview_test_document(renderer_benchmark_source(500)).root()
  b.bench(() => b.keep(render(root)))
}

///|
test "Loomark Preview renderer: scaling 2500 blocks" (b : @bench.T) {
  let root = preview_test_document(renderer_benchmark_source(2500)).root()
  b.bench(() => b.keep(render(root)))
}
