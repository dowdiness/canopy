///|
/// Match the release-browser corpus while isolating archive preparation.
fn archive_benchmark_source(line_count : Int) -> String {
  let out = StringBuilder::StringBuilder()
  for index = 0; index < line_count; index = index + 1 {
    if index % 2 == 0 {
      out.write_string("Paragraph \{index / 2} alpha beta gamma.")
    }
    if index + 1 < line_count {
      out.write_char('\n')
    }
  }
  out.to_string()
}

///|
fn archive_benchmark_editor(line_count : Int) -> @markdown.MarkdownEditor raise {
  @markdown.MarkdownEditor(
    agent_id="archive-preparation-benchmark-\{line_count}",
    source=archive_benchmark_source(line_count),
  )
}

///|
fn benchmark_complete_history_export(
  b : @bench.T,
  line_count : Int,
) -> Unit raise {
  let editor = archive_benchmark_editor(line_count)
  b.bench(() => {
    b.keep(
      editor.history_since() catch {
        _ => abort("complete history export failed")
      },
    )
  })
}

///|
fn benchmark_history_json_encoding(
  b : @bench.T,
  line_count : Int,
) -> Unit raise {
  let editor = archive_benchmark_editor(line_count)
  let history = editor.history_since()
  b.bench(() => b.keep(history.to_json_string()))
}

///|
fn benchmark_archive_envelope_encoding(
  b : @bench.T,
  line_count : Int,
) -> Unit raise {
  let editor = archive_benchmark_editor(line_count)
  let document_id = LoomarkDocumentId::from_string(
    "archive-preparation-benchmark-\{line_count}",
  ) catch {
    _ => abort("benchmark document id must construct")
  }
  let archive = LoomarkDocumentArchive::capture(document_id~, editor~)
  b.bench(() => b.keep(archive.to_json_string()))
}

///|
test "archive complete history export: 2000 lines" (b : @bench.T) {
  try! benchmark_complete_history_export(b, 2000)
}

///|
test "archive complete history export: 10000 lines" (b : @bench.T) {
  try! benchmark_complete_history_export(b, 10000)
}

///|
test "archive complete history export: 50000 lines" (b : @bench.T) {
  try! benchmark_complete_history_export(b, 50000)
}

///|
test "archive history JSON encoding: 2000 lines" (b : @bench.T) {
  try! benchmark_history_json_encoding(b, 2000)
}

///|
test "archive history JSON encoding: 10000 lines" (b : @bench.T) {
  try! benchmark_history_json_encoding(b, 10000)
}

///|
test "archive history JSON encoding: 50000 lines" (b : @bench.T) {
  try! benchmark_history_json_encoding(b, 50000)
}

///|
test "archive envelope encoding: 2000 lines" (b : @bench.T) {
  try! benchmark_archive_envelope_encoding(b, 2000)
}

///|
test "archive envelope encoding: 10000 lines" (b : @bench.T) {
  try! benchmark_archive_envelope_encoding(b, 10000)
}

///|
test "archive envelope encoding: 50000 lines" (b : @bench.T) {
  try! benchmark_archive_envelope_encoding(b, 50000)
}
