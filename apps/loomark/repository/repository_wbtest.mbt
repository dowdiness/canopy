///| The repository core's first deterministic tracer bullets.

///|
fn restore_policy_for_tests(
  max_encoded_bytes? : Int = 1024 * 1024,
  max_decoded_operations? : Int = 10000,
  max_pending_operations? : Int = 1000,
  max_parents_per_operation? : Int = 256,
) -> LocalRestorePolicy {
  let limits = try! @markdown.MarkdownArchiveOpenLimits(
    max_encoded_bytes~,
    max_decoded_operations~,
    max_pending_operations~,
    max_parents_per_operation~,
  )
  LocalRestorePolicy(limits)
}

///|
fn captured_archive(
  agent_id : String,
  document_id : String,
  source : String,
) -> @archive.LoomarkDocumentArchive {
  let editor = try! @markdown.MarkdownEditor(agent_id~, source~)
  let id = try! @archive.LoomarkDocumentId::from_string(document_id)
  try! @archive.LoomarkDocumentArchive::capture(document_id=id, editor~)
}

///|
test "repository classifies a missing record and a valid archive" {
  let policy = restore_policy_for_tests()
  match
    classify_local_archive_record(None, agent_id="repository-missing", policy~) {
    LocalArchiveLoad::Missing => ()
    _ => fail("expected missing record")
  }

  let archive = captured_archive("repository-valid", "doc-valid", "hello")
  match
    classify_local_archive_record(
      Some(archive.to_json_string()),
      agent_id="repository-valid-writer",
      policy~,
    ) {
    LocalArchiveLoad::Valid(reopened) => {
      assert_true(reopened.document_id() == archive.document_id())
      assert_true(reopened.editor().history_since() == archive.history())
      assert_eq(reopened.editor().portable_markdown(), "hello")
      reopened.attachment().dispose()
    }
    _ => fail("expected a reopened valid archive")
  }
}

///|
test "repository maps archive decode categories without parsing messages" {
  let archive = captured_archive("repository-errors", "doc-errors", "hello")
  let encoded = archive.to_json_string()
  let policy = restore_policy_for_tests()

  match
    classify_local_archive_record(
      Some(
        "{\"schema_version\":\"2\",\"document_id\":\"x\",\"portable_markdown\":\"\",\"history\":\"\",\"extensions\":{}}",
      ),
      agent_id="repository-newer",
      policy~,
    ) {
    LocalArchiveLoad::Rejected(
      LocalArchiveLoadFailure::UnsupportedNewerVersion(version~)
    ) => assert_eq(version, "2")
    _ => fail("expected unsupported version")
  }

  match
    classify_local_archive_record(
      Some("not-json"),
      agent_id="repository-malformed",
      policy~,
    ) {
    LocalArchiveLoad::Rejected(LocalArchiveLoadFailure::MalformedArchive(_)) =>
      ()
    _ => fail("expected malformed archive")
  }

  match
    classify_local_archive_record(
      Some(
        encoded.replace(old="\"history\":\"", new="\"history\":\"not-history"),
      ),
      agent_id="repository-corrupt",
      policy~,
    ) {
    LocalArchiveLoad::Rejected(LocalArchiveLoadFailure::CorruptArchive(_)) => ()
    _ => fail("expected corrupt archive")
  }

  let mismatch_encoded = encoded.replace(
    old="\"portable_markdown\":\"hello\"",
    new="\"portable_markdown\":\"other\"",
  )
  match
    classify_local_archive_record(
      Some(mismatch_encoded),
      agent_id="repository-mismatch",
      policy~,
    ) {
    LocalArchiveLoad::Rejected(LocalArchiveLoadFailure::CorruptArchive(detail~)) =>
      assert_eq(detail, "portable text does not match canonical history")
    _ => fail("expected portable text mismatch")
  }

  match
    classify_local_archive_record(
      Some(encoded),
      agent_id="repository-over-limit",
      policy=restore_policy_for_tests(max_encoded_bytes=0),
    ) {
    LocalArchiveLoad::Rejected(LocalArchiveLoadFailure::LimitExceeded(_)) => ()
    _ => fail("expected limit failure")
  }

  let source = try! @markdown.MarkdownEditor(
    agent_id="repository-incomplete-source",
    source="x",
  )
  let cut = source.version()
  ignore(
    source.commit(
      @markdown.MarkdownEditRequest::ReplaceText(
        start=1,
        delete_len=0,
        inserted="y",
      ),
    ),
  )
  let gapped = try! source.history_since(version=cut)
  let incomplete_encoded = Json::object({
    "schema_version": Json::string("1"),
    "document_id": Json::string("doc-incomplete"),
    "portable_markdown": Json::string("xy"),
    "history": Json::string(gapped.to_json_string()),
    "extensions": Json::empty_object(),
  }).stringify()
  match
    classify_local_archive_record(
      Some(incomplete_encoded),
      agent_id="repository-incomplete",
      policy=restore_policy_for_tests(max_pending_operations=1),
    ) {
    LocalArchiveLoad::Rejected(LocalArchiveLoadFailure::IncompleteHistory) => ()
    _ => fail("expected incomplete history")
  }
}

///|
test "repository prepares one complete immutable encoded archive" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="repository-prepare",
    source="# Title\n",
  )
  let document_id = try! @archive.LoomarkDocumentId::from_string("doc-prepare")
  let prepared = try! prepare_local_archive(document_id~, editor~)
  let decoded = try! @archive.LoomarkDocumentArchive::from_json_string(
    prepared.encoded(),
    validation_agent_id="repository-prepare-decode",
    open_limits=restore_policy_for_tests().open_limits,
  )
  assert_true(decoded.document_id() == document_id)
  assert_eq(decoded.portable_markdown(), "# Title\n")
}

///|
test "history trigger follows receipt history rather than source equality" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="repository-trigger",
    source="hello",
  )
  let receipt = match
    (try! editor.commit_with_receipt(
      @markdown.MarkdownEditRequest::ReplaceText(
        start=0,
        delete_len=1,
        inserted="h",
      ),
    )) {
    Ok(receipt) => receipt
    Err(_) => fail("expected history-changing receipt")
  }
  assert_eq(editor.snapshot().source(), "hello")
  assert_true(receipt.result() is @markdown.MarkdownCommitResult::Unchanged(_))
  assert_eq(history_trigger(receipt), LocalArchivePersistenceDecision::Replace)

  let no_op = match
    (try! editor.commit_with_receipt(
      @markdown.MarkdownEditRequest::ReplaceSource("hello"),
    )) {
    Ok(receipt) => receipt
    Err(_) => fail("expected no-op receipt")
  }
  assert_eq(history_trigger(no_op), LocalArchivePersistenceDecision::Skip)
}

///|
test "request tracker ignores stale completions" {
  let tracker = LocalArchiveRequestTracker::new()
  let (tracker, first) = tracker.request()
  let (tracker, second) = tracker.request()
  assert_false(second == first)

  let tracker = tracker.complete_failure(first)
  assert_false(tracker.has_warning())
  let tracker = tracker.complete_failure(second)
  assert_true(tracker.has_warning())
  let tracker = tracker.complete_success(first)
  assert_true(tracker.has_warning())
  let tracker = tracker.complete_success(second)
  assert_true(tracker.has_warning())

  let (tracker, third) = tracker.request()
  let tracker = tracker.complete_success(third)
  assert_false(tracker.has_warning())
  let tracker = tracker.complete_failure(third)
  assert_false(tracker.has_warning())

  let (tracker, fourth) = tracker.request()
  let tracker = tracker.complete_failure(fourth)
  assert_true(tracker.has_warning())
  let tracker = tracker.complete_success(fourth)
  assert_true(tracker.has_warning())
}

///|
test "reopen preserves identity and history for continued convergence" {
  let archive = captured_archive(
    "repository-reopen-source", "doc-reopen", "hello world",
  )
  let reopened = try! reopen_local_archive(
    archive,
    agent_id="repository-reopen-fresh-writer",
    policy=restore_policy_for_tests(),
  )
  assert_true(reopened.document_id() == archive.document_id())
  assert_true(reopened.editor().history_since() == archive.history())
  assert_eq(reopened.editor().snapshot().source(), "hello world")

  let peer = try! @markdown.MarkdownEditor::open(
    agent_id="repository-reopen-peer",
    history=archive.history(),
    open_limits=restore_policy_for_tests().open_limits,
  )
  assert_true(
    reopened
    .editor()
    .commit(
      @markdown.MarkdownEditRequest::ReplaceText(
        start=0,
        delete_len=0,
        inserted="A",
      ),
    )
    is Ok(_),
  )
  assert_true(
    peer.commit(
      @markdown.MarkdownEditRequest::ReplaceText(
        start=11,
        delete_len=0,
        inserted="B",
      ),
    )
    is Ok(_),
  )
  assert_true(
    reopened.editor().admit(peer.history_since())
    is @markdown.MarkdownAdmitReport::Complete,
  )
  assert_true(
    peer.admit(reopened.editor().history_since())
    is @markdown.MarkdownAdmitReport::Complete,
  )
  assert_eq(reopened.editor().snapshot().source(), peer.snapshot().source())
  reopened.attachment().dispose()
}
