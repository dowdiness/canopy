///|
/// Construct a CRDT with the benchmark source already present so the measured
/// operation is only the tail range mutation.
fn apply_phase_text_state(source : String) -> @text.TextState {
  let doc = try! @text.TextState::new("markdown-apply-phase")
  try! doc.insert(@text.Pos::at(0), source)
  doc
}

///|
/// Construct a parser with the source already parsed. The parser has no
/// projection attachment here, so this isolates Parser::apply_edit and its
/// incremental engine from projection reconciliation.
fn apply_phase_parser(source : String) -> @loom.Parser[@md_markdown.Block] {
  @loom.new_parser(
    @loom_core.SourceId("canopy:markdown-apply-phase"),
    source,
    @md_markdown.markdown_grammar,
  )
}

///|
/// This alternates an append and its inverse so one mutable document can be
/// reused by the benchmark harness. Divide the reported time by two when
/// comparing one CRDT mutation with one parser mutation below.
test "perf: CRDT tail range mutation pair (250 blocks)" (b : @bench.T) {
  let source = commit_phase_source(250)
  let doc = apply_phase_text_state(source)
  let mut tick = 0
  b.bench(() => {
    if tick % 2 == 0 {
      let end = doc.len()
      try! doc.replace_range(@text.Range::from_ints(end, end), "x")
    } else {
      let end = doc.len()
      try! doc.replace_range(@text.Range::from_ints(end - 1, end), "")
    }
    tick += 1
    b.keep(doc.len())
  })
}

///|
test "perf: parser incremental edit pair without projection (250 blocks)" (
  b : @bench.T,
) {
  let source = commit_phase_source(250)
  let parser = apply_phase_parser(source)
  let append = @loom_core.Edit::new(source.length(), 0, 1)
  let delete = @loom_core.Edit::new(source.length(), 1, 0)
  let mut tick = 0
  b.bench(() => {
    if tick % 2 == 0 {
      parser.apply_edit(append, source + "x")
    } else {
      parser.apply_edit(delete, source)
    }
    tick += 1
    b.keep(tick)
  })
}

///|
test "perf: parser incremental edit pair with AST read (250 blocks)" (
  b : @bench.T,
) {
  let source = commit_phase_source(250)
  let parser = apply_phase_parser(source)
  let append = @loom_core.Edit::new(source.length(), 0, 1)
  let delete = @loom_core.Edit::new(source.length(), 1, 0)
  let mut tick = 0
  b.bench(() => {
    if tick % 2 == 0 {
      parser.apply_edit(append, source + "x")
    } else {
      parser.apply_edit(delete, source)
    }
    let ast = parser.ast().read_or_abort()
    tick += 1
    b.keep(ast)
  })
}
