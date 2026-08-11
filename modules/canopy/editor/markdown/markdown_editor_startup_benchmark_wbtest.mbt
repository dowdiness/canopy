///| Startup restore phase measurements for the Eg-walker-backed Markdown façade.
///
/// These benchmarks keep fixture construction outside the timed closure and
/// separate history JSON decode, CRDT admission, and semantic attachment.
/// They are diagnostic evidence, not a startup budget or a production cache.

///|
fn startup_phase_source(block_count : Int) -> String {
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
fn startup_phase_history(cycles : Int) -> MarkdownDocumentHistory {
  let source = startup_phase_source(100)
  let editor = try! MarkdownEditor(
    agent_id="markdown-startup-fixture",
    source="",
  )
  ignore(try! editor.commit(MarkdownEditRequest::ReplaceSource(source)))
  for index = 0; index < cycles; index = index + 1 {
    let intermediate = source +
      "\nIntermediate revision " +
      index.to_string() +
      "\n"
    ignore(try! editor.commit(MarkdownEditRequest::ReplaceSource(intermediate)))
    ignore(try! editor.commit(MarkdownEditRequest::ReplaceSource(source)))
  }
  try! editor.history_since()
}

///|
fn startup_phase_limits() -> MarkdownArchiveOpenLimits {
  try! MarkdownArchiveOpenLimits(
    max_encoded_bytes=256 * 1024 * 1024,
    max_decoded_operations=100000,
    max_pending_operations=100000,
    max_parents_per_operation=1024,
  )
}

///|
test "perf: startup history JSON decode (41 operations)" (b : @bench.T) {
  let history = startup_phase_history(20)
  let encoded = history.to_json_string()
  b.bench(() => {
    let decoded = try! MarkdownDocumentHistory::from_json_string(encoded)
    b.keep(decoded)
  })
}

///|
test "perf: startup CRDT admission (41 operations)" (b : @bench.T) {
  let history = startup_phase_history(20)
  b.bench(() => {
    let editor = try! MarkdownEditor::open(
      agent_id="markdown-startup-open",
      history~,
      open_limits=startup_phase_limits(),
    )
    b.keep(editor.portable_markdown())
  })
}

///|
test "perf: startup CRDT admission with semantic attachment (41 operations)" (
  b : @bench.T,
) {
  let history = startup_phase_history(20)
  b.bench(() => {
    let (editor, attachment) = try! MarkdownEditor::open_with_semantic_attachment(
      agent_id="markdown-startup-semantic-open",
      history~,
      open_limits=startup_phase_limits(),
    )
    let source = editor.portable_markdown()
    attachment.dispose()
    b.keep(source)
  })
}

///|
test "perf: startup semantic attachment from source (100 blocks)" (b : @bench.T) {
  let source = startup_phase_source(100)
  b.bench(() => {
    let (editor, attachment) = try! MarkdownEditor::with_semantic_attachment(
      agent_id="markdown-startup-semantic-source",
      source~,
    )
    let current = editor.portable_markdown()
    attachment.dispose()
    b.keep(current)
  })
}
