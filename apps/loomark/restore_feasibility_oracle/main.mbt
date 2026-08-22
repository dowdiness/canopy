///|
/// Full-history Markdown oracle process for Gate R0.
///
/// Restore is classified by Loomark's existing local-archive repository seam,
/// which delegates to the public Markdown façade. The source editor is not
/// consulted after `encoded` is made; the shell may transport that string to a
/// separately started consumer.

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
/// Limits for the largest required 10,000-event browser fixture.
fn browser_limits() -> @markdown.MarkdownArchiveOpenLimits {
  try! @markdown.MarkdownArchiveOpenLimits(
    max_encoded_bytes=32 * 1024 * 1024,
    max_decoded_operations=20000,
    max_pending_operations=20000,
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
  let oracle_load = try! @repository.classify_local_archive_record(
    Some(encoded),
    agent_id="gate-r0-markdown-oracle-writer",
    policy=@repository.LocalRestorePolicy(limits()),
  )
  let oracle_reopened = match oracle_load {
    @repository.LocalArchiveLoad::Valid(reopened) => reopened
    @repository.LocalArchiveLoad::Missing => panic()
    @repository.LocalArchiveLoad::Rejected(_) => panic()
  }
  let oracle = oracle_reopened.editor()
  let oracle_before = oracle.portable_markdown()
  ignore(
    try! oracle.commit(
      @markdown.MarkdownEditRequest::ReplaceText(
        start=oracle_before.length(),
        delete_len=0,
        inserted="restored\n",
      ),
    ),
  )
  let oracle_history = try! oracle.history_since()
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
        "oracle_post_edit_history": Json::string(
          oracle_history.to_json_string(),
        ),
        "oracle_post_edit_frontier": Json::string(
          oracle.version().to_json_string(),
        ),
        "oracle_writer_id": Json::string("gate-r0-markdown-oracle-writer"),
        "open_succeeded": Json::boolean(true),
        "representative_commit_succeeded": Json::boolean(true),
        "product_recovery_classification": Json::string("valid"),
        "recovery_observability": Json::string("loomark-local-archive-load"),
      }),
    }).stringify(),
  )
  let oracle_attachment : @md_markdown.MarkdownSemanticAttachment = oracle_reopened.attachment()
  oracle_attachment.dispose()
}

///|
fn consumer(encoded : String, mode : String) -> Unit {
  let decoded = try! @archive.LoomarkDocumentArchive::decode_json_string(
    encoded,
  )
  let restored_load = try! @repository.classify_local_archive_record(
    Some(encoded),
    agent_id="gate-r0-markdown-fresh-writer",
    policy=@repository.LocalRestorePolicy(limits()),
  )
  let reopened = match restored_load {
    @repository.LocalArchiveLoad::Valid(value) => value
    @repository.LocalArchiveLoad::Missing => panic()
    @repository.LocalArchiveLoad::Rejected(_) => panic()
  }
  let restored = reopened.editor()
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
  let frontier_after_insert = restored.version().to_json_string()
  let history_after_insert = try! restored.history_since()
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
    "open_succeeded": Json::boolean(true),
    "representative_commit_succeeded": Json::boolean(mode != "restore"),
    "product_recovery_classification": Json::string("valid"),
    "recovery_observability": Json::string("loomark-local-archive-load"),
    "first_edit": Json::string("insert"),
    "immediate_insert_text": Json::string(after_insert),
    "post_insert_history": Json::string(history_after_insert.to_json_string()),
    "frontier_after_insert": Json::string(frontier_after_insert),
    "visible_delete_text": Json::string(after_delete),
    "undelete_text": Json::string(restored.portable_markdown()),
    "target_visibility": Json::string(
      if after_delete == before {
        "hidden"
      } else {
        "unexpected"
      },
    ),
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
  let attachment : @md_markdown.MarkdownSemanticAttachment = reopened.attachment()
  attachment.dispose()
}

///|
/// Encode immutable legacy-oracle history through the production archive encoder.
fn browser_fixture(
  history_path : String,
  document_id_value : String,
  output_path : String,
) -> Unit {
  let history_json = try! @fs.read_file_to_string(history_path)
  let history = try! @markdown.MarkdownDocumentHistory::from_json_string(
    history_json,
  )
  let editor = try! @markdown.MarkdownEditor::open(
    agent_id="gate-r0-browser-fixture",
    history~,
    open_limits=browser_limits(),
  )
  let document_id = try! @archive.LoomarkDocumentId::from_string(
    document_id_value,
  )
  let archive = try! @archive.LoomarkDocumentArchive::capture(
    document_id~,
    editor~,
  )
  try! @fs.write_string_to_file(output_path, archive.to_json_string())
}

///|
fn main {
  let args = @env.args()
  let mut command_index = -1
  for index = 0; index < args.length(); index = index + 1 {
    match args.get(index) {
      Some("producer" | "consumer" | "browser-fixture") => command_index = index
      _ => ()
    }
  }
  match args.get(command_index) {
    Some("producer") => producer()
    Some("consumer") =>
      match @env.get_env_var("GATE_R0_ARCHIVE_JSON") {
        Some(encoded) =>
          consumer(encoded, args.get(command_index + 1).unwrap_or("undelete"))
        None => panic()
      }
    Some("browser-fixture") => {
      guard args.get(command_index + 1) is Some(history_path) else { panic() }
      guard args.get(command_index + 2) is Some(document_id) else { panic() }
      guard args.get(command_index + 3) is Some(output_path) else { panic() }
      browser_fixture(history_path, document_id, output_path)
    }
    _ => panic()
  }
}
