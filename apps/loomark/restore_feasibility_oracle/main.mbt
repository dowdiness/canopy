///|
/// Full-history Markdown oracle process for Gate R0.
///
/// The only restore operation is the existing public `MarkdownEditor::open`
/// façade, supplied an opaque `MarkdownDocumentHistory` decoded from the v1
/// archive bytes.  The source editor is not consulted after `encoded` is made;
/// the shell may transport that string to a separately started consumer.

///|
fn limits() -> @markdown.MarkdownArchiveOpenLimits {
  try! @markdown.MarkdownArchiveOpenLimits(
    max_encoded_bytes=1024 * 1024,
    max_decoded_operations=10000,
    max_pending_operations=1000,
    max_parents_per_operation=256,
  )
}

///|
fn producer() -> Unit {
  let source = try! @markdown.MarkdownEditor(
    agent_id="gate-r0-markdown-producer",
    source="# Gate R0\n\nalpha 😀 omega\n",
  )
  let document_id = try! @archive.LoomarkDocumentId::from_string(
    "gate-r0-oracle",
  )
  let captured = try! @archive.LoomarkDocumentArchive::capture(
    document_id~,
    editor=source,
  )
  let encoded = captured.to_json_string()
  println(
    Json::object({
      "schema_version": Json::number(1.0),
      "run_id": Json::string("gate-r0-v1"),
      "case_id": Json::string("full-history-oracle"),
      "producer": Json::string("markdown_archive_producer"),
      "status": Json::string("pass"),
      "payload": Json::object({
        "archive_json": Json::string(encoded),
        "archive_bytes": Json::number(encoded.length().to_double()),
        "source_writer_id": Json::string("gate-r0-markdown-producer"),
        "expected_before_text": Json::string(source.portable_markdown()),
        "expected_after_text": Json::string(
          source.portable_markdown() + "restored\n",
        ),
        "source_frontier": Json::string(source.version().to_json_string()),
      }),
    }).stringify(),
  )
}

///|
fn consumer(archive_path : String, mode : String) -> Unit {
  // The producer process has exited.  This fresh process receives only the
  // opaque archive-bytes file, never a source editor or history object.
  let encoded = try! @fs.read_file_to_string(archive_path)
  let decoded = try! @archive.LoomarkDocumentArchive::decode_json_string(
    encoded,
  )
  let restored = try! @markdown.MarkdownEditor::open(
    agent_id="gate-r0-markdown-fresh-writer",
    history=decoded.history(),
    open_limits=limits(),
  )
  let before = restored.portable_markdown()
  let frontier_before = restored.version().to_json_string()
  if mode != "restore" {
    ignore(
      try! restored.commit(
        @markdown.MarkdownEditRequest::ReplaceText(
          start=before.length(),
          delete_len=0,
          inserted="restored\n",
        ),
      ),
    )
  }
  let after_insert = restored.portable_markdown()
  if mode == "delete" || mode == "undelete" {
    ignore(
      try! restored.commit(
        @markdown.MarkdownEditRequest::ReplaceText(
          start=before.length(),
          delete_len="restored\n".length(),
          inserted="",
        ),
      ),
    )
  }
  let after_delete = restored.portable_markdown()
  if mode == "undelete" {
    ignore(
      try! restored.commit(
        @markdown.MarkdownEditRequest::ReplaceText(
          start=after_delete.length(),
          delete_len=0,
          inserted="restored\n",
        ),
      ),
    )
  }
  let payload = Json::object({
    "archive_bytes": Json::number(encoded.length().to_double()),
    "history_bytes": Json::number(
      decoded.history().to_json_string().length().to_double(),
    ),
    "coarse_archive_loads": Json::number(1.0),
    "text": Json::string(restored.portable_markdown()),
    "frontier_before": Json::string(frontier_before),
    "frontier_after": Json::string(restored.version().to_json_string()),
    "fresh_writer_id": Json::string("gate-r0-markdown-fresh-writer"),
    "editable": Json::boolean(true),
    "recovery": Json::string("none"),
    "first_edit": Json::string("insert"),
    "immediate_insert_text": Json::string(after_insert),
    "visible_delete_text": Json::string(after_delete),
    "undelete_text": Json::string(restored.portable_markdown()),
    "target_visibility": Json::string(
      if after_delete == before {
        "hidden"
      } else {
        "unexpected"
      },
    ),
    "normalized_next_operation": Json::string("replace-text"),
    "measurement_mode": Json::string(mode),
    "operation_count": Json::number(
      (if mode == "restore" {
        0
      } else if mode == "insert" {
        1
      } else if mode == "delete" {
        2
      } else {
        3
      }).to_double(),
    ),
  })
  println(
    Json::object({
      "schema_version": Json::number(1.0),
      "run_id": Json::string("gate-r0-v1"),
      "case_id": Json::string("full-history-oracle"),
      "producer": Json::string("markdown_oracle"),
      "status": Json::string("pass"),
      "payload": payload,
    }).stringify(),
  )
}

///|
fn main {
  match @env.args().get(1) {
    Some("producer") => producer()
    Some("consumer") =>
      match @env.get_env_var("GATE_R0_ARCHIVE_PATH") {
        Some(archive_path) =>
          consumer(archive_path, @env.args().get(2).unwrap_or("undelete"))
        None => panic()
      }
    _ => panic()
  }
}
