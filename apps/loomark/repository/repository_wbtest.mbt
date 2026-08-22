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
test "persistence queue reports applied then durable local" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="repository-queue",
    source="before",
  )
  let initial_version = editor.version()
  let document_id = try! @archive.LoomarkDocumentId::from_string("doc-queue")
  ignore(editor.commit(@markdown.MarkdownEditRequest::ReplaceSource("after")))
  let current_version = editor.version()
  let archive = try! prepare_local_archive(document_id~, editor~)
  let queue = LocalArchivePersistenceQueue::LocalArchivePersistenceQueue(
    document_id~,
    current=initial_version,
    durable=None,
  )
  let (queue, write) = queue.enqueue(document_version=current_version, archive~)
  guard write is Some(write) else { fail("expected first write") }
  match queue.status() {
    LocalArchivePersistenceStatus::Applied(current~, durable~) => {
      assert_true(current == current_version)
      assert_true(durable is None)
    }
    _ => fail("expected applied status")
  }
  let (queue, completion) = queue.complete(
    write,
    LocalArchiveWriteOutcome::Stored,
  )
  assert_true(completion is LocalArchiveQueueCompletion::Completed)
  match queue.status() {
    LocalArchivePersistenceStatus::DurableLocal(version) =>
      assert_true(version == current_version)
    _ => fail("expected durable-local status")
  }
}

///|
test "persistence queue coalesces and promotes the latest archive" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="repository-queue-coalesce",
    source="zero",
  )
  let initial_version = editor.version()
  let document_id = try! @archive.LoomarkDocumentId::from_string(
    "doc-queue-coalesce",
  )
  ignore(editor.commit(@markdown.MarkdownEditRequest::ReplaceSource("one")))
  let first_version = editor.version()
  let first_archive = try! prepare_local_archive(document_id~, editor~)
  let queue = LocalArchivePersistenceQueue::LocalArchivePersistenceQueue(
    document_id~,
    current=initial_version,
    durable=None,
  )
  let (queue, first_write) = queue.enqueue(
    document_version=first_version,
    archive=first_archive,
  )
  guard first_write is Some(first_write) else { fail("expected first write") }

  ignore(editor.commit(@markdown.MarkdownEditRequest::ReplaceSource("two")))
  let second_version = editor.version()
  let second_archive = try! prepare_local_archive(document_id~, editor~)
  let (queue, second_write) = queue.enqueue(
    document_version=second_version,
    archive=second_archive,
  )
  assert_true(second_write is None)
  match queue.status() {
    LocalArchivePersistenceStatus::Applied(current~, durable~) => {
      assert_true(current == second_version)
      assert_true(durable is None)
    }
    _ => fail("expected latest applied status")
  }

  let (queue, completion) = queue.complete(
    first_write,
    LocalArchiveWriteOutcome::Stored,
  )
  let promoted = match completion {
    LocalArchiveQueueCompletion::Promoted(write) => write
    _ => fail("expected pending write promotion")
  }
  match queue.status() {
    LocalArchivePersistenceStatus::Applied(current~, durable~) => {
      assert_true(current == second_version)
      guard durable is Some(durable) else {
        fail("expected first durable version")
      }
      assert_true(durable == first_version)
    }
    _ => fail("expected applied status while latest write runs")
  }

  let (queue, completion) = queue.complete(
    promoted,
    LocalArchiveWriteOutcome::Failed(
      LocalArchiveStorageWriteFailure::QuotaExceeded,
    ),
  )
  assert_true(completion is LocalArchiveQueueCompletion::Completed)
  match queue.status() {
    LocalArchivePersistenceStatus::StorageFailed(current~, durable~, error~) => {
      assert_true(current == second_version)
      guard durable is Some(durable) else {
        fail("expected first durable version")
      }
      assert_true(durable == first_version)
      assert_true(error == LocalArchiveStorageWriteFailure::QuotaExceeded)
    }
    _ => fail("expected storage-failed status")
  }
}

///|
test "persistence queue retries the latest failed version only once" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="repository-queue-retry",
    source="before",
  )
  let initial_version = editor.version()
  let document_id = try! @archive.LoomarkDocumentId::from_string(
    "doc-queue-retry",
  )
  ignore(editor.commit(@markdown.MarkdownEditRequest::ReplaceSource("after")))
  let current_version = editor.version()
  let archive = try! prepare_local_archive(document_id~, editor~)
  let queue = LocalArchivePersistenceQueue::LocalArchivePersistenceQueue(
    document_id~,
    current=initial_version,
    durable=None,
  )
  let (queue, write) = queue.enqueue(document_version=current_version, archive~)
  guard write is Some(write) else { fail("expected first write") }
  let (queue, _) = queue.complete(
    write,
    LocalArchiveWriteOutcome::Failed(LocalArchiveStorageWriteFailure::Failed),
  )
  match queue.status() {
    LocalArchivePersistenceStatus::StorageFailed(current~, durable~, error~) => {
      assert_true(current == current_version)
      assert_true(durable is None)
      assert_true(error == LocalArchiveStorageWriteFailure::Failed)
    }
    _ => fail("expected storage-failed status")
  }

  let retry_archive = try! prepare_local_archive(document_id~, editor~)
  let (queue, retry_write) = queue.retry(
    document_version=current_version,
    archive=retry_archive,
  )
  guard retry_write is Some(retry_write) else { fail("expected retry write") }
  let (busy_queue, duplicate_retry) = queue.retry(
    document_version=current_version,
    archive=try! prepare_local_archive(document_id~, editor~),
  )
  assert_true(duplicate_retry is None)
  assert_true(busy_queue.status() is LocalArchivePersistenceStatus::Applied(..))

  let (queue, completion) = queue.complete(
    retry_write,
    LocalArchiveWriteOutcome::Stored,
  )
  assert_true(completion is LocalArchiveQueueCompletion::Completed)
  assert_true(queue.status() is LocalArchivePersistenceStatus::DurableLocal(_))
}

///|
test "persistence queue ignores wrong document and delayed acknowledgments" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="repository-queue-stale",
    source="before",
  )
  let initial_version = editor.version()
  let document_id = try! @archive.LoomarkDocumentId::from_string(
    "doc-queue-stale",
  )
  ignore(editor.commit(@markdown.MarkdownEditRequest::ReplaceSource("after")))
  let current_version = editor.version()
  let archive = try! prepare_local_archive(document_id~, editor~)
  let queue = LocalArchivePersistenceQueue::LocalArchivePersistenceQueue(
    document_id~,
    current=initial_version,
    durable=None,
  )
  let (queue, write) = queue.enqueue(document_version=current_version, archive~)
  guard write is Some(write) else { fail("expected first write") }

  let other_id = try! @archive.LoomarkDocumentId::from_string("doc-queue-other")
  let other_queue = LocalArchivePersistenceQueue::LocalArchivePersistenceQueue(
    document_id=other_id,
    current=initial_version,
    durable=None,
  )
  let other_archive = try! prepare_local_archive(document_id=other_id, editor~)
  let (_other_queue, wrong_write) = other_queue.enqueue(
    document_version=current_version,
    archive=other_archive,
  )
  guard wrong_write is Some(wrong_write) else { fail("expected wrong write") }
  let (queue, ignored) = queue.complete(
    wrong_write,
    LocalArchiveWriteOutcome::Stored,
  )
  assert_true(ignored is LocalArchiveQueueCompletion::Ignored)
  assert_true(queue.status() is LocalArchivePersistenceStatus::Applied(..))

  let (queue, completed) = queue.complete(
    write,
    LocalArchiveWriteOutcome::Stored,
  )
  assert_true(completed is LocalArchiveQueueCompletion::Completed)
  let (queue, delayed) = queue.complete(
    write,
    LocalArchiveWriteOutcome::Failed(LocalArchiveStorageWriteFailure::Failed),
  )
  assert_true(delayed is LocalArchiveQueueCompletion::Ignored)
  assert_true(queue.status() is LocalArchivePersistenceStatus::DurableLocal(_))
}

///|
test "persistence failure supersedes an older pending archive" {
  let editor = try! @markdown.MarkdownEditor(
    agent_id="repository-queue-supersede-failure",
    source="zero",
  )
  let initial_version = editor.version()
  let document_id = try! @archive.LoomarkDocumentId::from_string(
    "doc-queue-supersede-failure",
  )
  ignore(editor.commit(@markdown.MarkdownEditRequest::ReplaceSource("one")))
  let first_version = editor.version()
  let first_archive = try! prepare_local_archive(document_id~, editor~)
  let queue = LocalArchivePersistenceQueue::LocalArchivePersistenceQueue(
    document_id~,
    current=initial_version,
    durable=None,
  )
  let (queue, first_write) = queue.enqueue(
    document_version=first_version,
    archive=first_archive,
  )
  guard first_write is Some(first_write) else { fail("expected first write") }
  ignore(editor.commit(@markdown.MarkdownEditRequest::ReplaceSource("two")))
  let second_version = editor.version()
  let second_archive = try! prepare_local_archive(document_id~, editor~)
  let (queue, second_write) = queue.enqueue(
    document_version=second_version,
    archive=second_archive,
  )
  assert_true(second_write is None)
  let queue = queue.mark_failed(
    document_version=second_version,
    error=LocalArchiveStorageWriteFailure::Failed,
  )
  match queue.status() {
    LocalArchivePersistenceStatus::StorageFailed(current~, durable~, error~) => {
      ignore(error)
      assert_true(current == second_version)
      assert_true(durable is None)
    }
    _ => fail("expected latest failure")
  }
  let (queue, completion) = queue.complete(
    first_write,
    LocalArchiveWriteOutcome::Stored,
  )
  assert_true(completion is LocalArchiveQueueCompletion::Completed)
  match queue.status() {
    LocalArchivePersistenceStatus::StorageFailed(current~, durable~, error~) => {
      ignore(error)
      assert_true(current == second_version)
      guard durable is Some(durable) else {
        fail("expected first durable version")
      }
      assert_true(durable == first_version)
    }
    _ => fail("older success must not clear latest failure")
  }
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
