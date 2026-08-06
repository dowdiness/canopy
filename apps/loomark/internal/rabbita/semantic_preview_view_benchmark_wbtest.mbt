///|
/// Build the 2,500-block workload once. Parsing belongs to Loom's semantic
/// attachment benchmarks; this file isolates the pure Preview materializer.
fn preview_view_benchmark_source(block_count : Int) -> String {
  let out = StringBuilder::StringBuilder()
  for index = 0; index < block_count; index = index + 1 {
    out.write_string(
      "Paragraph \{index} contains *emphasis*, **strong text**, a [link](https://example.test/\{index}), and `code`.\n\n",
    )
  }
  out.to_string()
}

///|
fn preview_view_benchmark_replace_middle(source : String) -> String {
  let target = "Paragraph 1250"
  match source.find(target) {
    Some(position) =>
      source[:position].to_owned() +
      "Edited paragraph 1250" +
      source[position + target.length():].to_owned()
    None => abort("preview view benchmark middle paragraph not found")
  }
}

///|
fn wbtest_markdown_ir(
  source_id : @loom.SourceId,
  source : String,
) -> @md_markdown.MarkdownIR {
  let parser = @loom.new_parser(
    source_id, source, @md_markdown.markdown_grammar,
  )
  let snapshot = parser.snapshot().read_or_abort()
  @md_markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
    parser.source_id(),
    snapshot.syntax,
    snapshot.diagnostics,
  )
}

///|
priv struct PreviewViewBenchmarkInput {
  source : String
  edited : String
  source_ir : @md_markdown.MarkdownIR
  edited_ir : @md_markdown.MarkdownIR
}

///|
fn preview_view_benchmark_input() -> PreviewViewBenchmarkInput {
  let source = preview_view_benchmark_source(2500)
  let edited = preview_view_benchmark_replace_middle(source)
  {
    source,
    edited,
    source_ir: wbtest_markdown_ir(
      @loom.SourceId("loomark-preview-materialize"),
      source,
    ),
    edited_ir: wbtest_markdown_ir(
      @loom.SourceId("loomark-preview-materialize"),
      edited,
    ),
  }
}

///|
test "loomark Preview materialization: initial 2500 blocks" (b : @bench.T) {
  let input = preview_view_benchmark_input()
  b.bench(() => b.keep(semantic_preview_view(input.source, input.source_ir)))
}

///|
test "loomark Preview materialization: edited IR 2500 blocks" (b : @bench.T) {
  let input = preview_view_benchmark_input()
  b.bench(() => b.keep(semantic_preview_view(input.edited, input.edited_ir)))
}

///|
/// Measure the requested edit-and-exact-reversal materialization as one cycle.
test "loomark Preview materialization: edit and reversal cycle 2500 blocks" (
  b : @bench.T,
) {
  let input = preview_view_benchmark_input()
  b.bench(() => {
    b.keep(semantic_preview_view(input.edited, input.edited_ir))
    b.keep(semantic_preview_view(input.source, input.source_ir))
  })
}

///|
/// Isolate the semantic-document component of DriverModel's structural Eq on
/// a Preview no-op; the complete model also compares its other fields.
test "loomark Preview MarkdownIR Eq: same 2500 blocks" (b : @bench.T) {
  let input = preview_view_benchmark_input()
  b.bench(() => b.keep(input.source_ir == input.source_ir))
}

///|
/// A middle edit gives a conservative isolated cost for comparing two owning
/// semantic documents; the complete model may short-circuit on an earlier
/// changed field.
test "loomark Preview MarkdownIR Eq: middle edit 2500 blocks" (b : @bench.T) {
  let input = preview_view_benchmark_input()
  b.bench(() => b.keep(input.source_ir == input.edited_ir))
}
