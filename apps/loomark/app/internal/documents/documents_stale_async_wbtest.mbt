/// Tests are organized by reducer contract; fixtures and extraction helpers remain shared.

///|
test "stale timers and mismatched stored records are ignored" {
  let documents = State::State(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("one"), "b"),
  )
  guard decisions is [Effect::ArmMaximum(_, _)] else { fail("timers") }
  let (documents, _) = documents.reduce(TextChanged(source_key("one"), "c"))
  let (documents, stale_max) = documents.reduce(
    FeedbackReceived(MaximumElapsed(source_key("one"), 99)),
  )
  assert_true(stale_max.is_empty())
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  guard decisions is [Effect::PersistSource(operation)] else {
    fail("latest quiet")
  }
  let bogus = documents_test_document("one", "not-the-operation-text")
  let (documents, _) = documents.reduce(
    FeedbackReceived(SaveCompleted(operation, Stored(bogus))),
  )
  assert_eq(
    documents.snapshot().find(document_id("one")).unwrap().text(),
    "one",
  )
}

///|
test "page-local revision orders edits across documents" {
  let saved = documents_test_snapshot()
  let documents = State::State(saved)
  let (documents, first_decisions) = documents.reduce(
    TextChanged(source_key("two"), "two!"),
  )
  guard first_decisions is [Effect::ArmMaximum(_, max_two)] else {
    fail("two timers")
  }
  assert_eq(pending_revision(documents, source_key("two")), 1)
  assert_eq(max_two, 1)
  let (documents, second_decisions) = documents.reduce(
    TextChanged(source_key("one"), "one!"),
  )
  guard second_decisions is [Effect::ArmMaximum(_, max_one)] else {
    fail("one independent timers")
  }
  assert_eq(pending_revision(documents, source_key("one")), 2)
  assert_eq(max_one, 2)
  guard find_record(documents.records, source_key("two")).unwrap().save
    is Waiting(_) else {
    fail("two waiting")
  }
  assert_eq(pending_revision(documents, source_key("two")), 1)
  guard find_record(documents.records, source_key("one")).unwrap().save
    is Waiting(cp_one) else {
    fail("one waiting")
  }
  assert_eq(pending_revision(documents, source_key("one")), 2)
  assert_eq(cp_one.maximum_id, 2)
}

///|
test "page-local revision retains authority unchanged and re-arms after stale timers" {
  let saved = @source_repository.SavedDocuments::from_documents([
    documents_test_document("one", "one"),
  ]).unwrap()
  let documents = State::State(saved)
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("one"), "changed"),
  )
  guard decisions is [Effect::ArmMaximum(_, mid)] else { fail("timers") }
  assert_eq(pending_revision(documents, source_key("one")), 1)
  assert_eq(mid, 1)
  // Stale pending_revision(documents, source_key("one")) revision is ignored
  let (documents, stale) = documents.reduce(
    ApplyPendingEdit(source_key("one"), 99),
  )
  assert_true(stale.is_empty())
  // Correct revision still arms persist
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  guard decisions[0] is Effect::PersistSource(operation) else {
    fail("persist")
  }
  assert_eq(operation.document.text(), "changed")
  // Import with same saved still persists via page-local revision
  let (documents, decisions) = documents.reduce(
    Imported(document_id("imported"), "text"),
  )
  guard decisions is [Effect::PersistSource(op2)] else {
    fail("imported persist")
  }
  assert_eq(op2.document.text(), "text")
  assert_eq(documents.text(source_key("imported")), Some("text"))
}

///|
test "delete and recreate keeps pending revisions monotonic and isolated" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(New(document_id("new")))
  let (documents, _) = documents.reduce(TextChanged(source_key("new"), "first"))
  let old_revision = pending_revision(documents, source_key("new"))
  let (documents, _) = documents.reduce(DeleteConfirmed(source_key("new")))
  let (documents, _) = documents.reduce(New(document_id("new")))
  let (documents, _) = documents.reduce(
    TextChanged(source_key("new"), "second"),
  )
  let current_revision = pending_revision(documents, source_key("new"))
  assert_true(current_revision > old_revision)
  let (documents, _) = documents.reduce(TextChanged(source_key("one"), "other"))
  assert_true(has_pending(documents, source_key("new")))
  assert_true(has_pending(documents, source_key("one")))
}

///|
test "matching maximum after delete confirmation is ignored" {
  let documents = State::State(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("one"), "changed"),
  )
  guard decisions is [ArmMaximum(_, maximum)] else { fail("maximum") }
  let (documents, decisions) = documents.reduce(
    DeleteConfirmed(source_key("one")),
  )
  guard decisions is [DeleteSource(_)] else { fail("delete") }
  let before = documents
  let (documents, decisions) = documents.reduce(
    FeedbackReceived(MaximumElapsed(source_key("one"), maximum)),
  )
  assert_true(documents == before)
  assert_true(decisions.is_empty())
}

/// The same fence applies when a newer checkpoint is queued behind a save.

///|
test "matching maximum during waiting deletion of in-flight save is ignored" {
  let documents = State::State(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("one"), "first"),
  )
  guard decisions is [ArmMaximum(_, _)] else { fail("maximum") }
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  guard decisions is [PersistSource(save)] else { fail("save") }
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("one"), "latest"),
  )
  guard decisions is [ArmMaximum(_, maximum)] else { fail("follow-up maximum") }
  let (documents, decisions) = documents.reduce(
    DeleteConfirmed(source_key("one")),
  )
  assert_true(decisions.is_empty())
  let before = documents
  let (documents, decisions) = documents.reduce(
    FeedbackReceived(MaximumElapsed(source_key("one"), maximum)),
  )
  assert_true(documents == before)
  assert_true(decisions.is_empty())
  let (_, decisions) = documents.reduce(
    FeedbackReceived(SaveCompleted(save, Stored(save.document))),
  )
  guard decisions is [DeleteSource(delete)] else {
    fail("original save remains valid")
  }
  assert_true(delete.document_id == document_id("one"))
}

/// Duplicate composition starts preserve the accepted lifecycle state.

///|
test "old pending callback after recreate is ignored" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(New(document_id("new")))
  let (documents, _) = documents.reduce(TextChanged(source_key("new"), "first"))
  let old_revision = pending_revision(documents, source_key("new"))
  let (documents, _) = documents.reduce(DeleteConfirmed(source_key("new")))
  let (documents, _) = documents.reduce(New(document_id("new")))
  let (documents, _) = documents.reduce(
    TextChanged(source_key("new"), "second"),
  )
  let before = documents
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit(source_key("new"), old_revision),
  )
  assert_true(documents == before)
  assert_true(decisions.is_empty())
}

/// Completion facts are validated once before the delete lane is selected.

///|
test "waiting delete rejects mismatched stored completion" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(TextChanged(source_key("one"), "first"))
  let (documents, persist) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  guard persist is [PersistSource(save)] else { fail("save") }
  let (documents, _) = documents.reduce(
    TextChanged(source_key("one"), "latest"),
  )
  let (documents, _) = documents.reduce(DeleteConfirmed(source_key("one")))
  let before = documents
  let bogus = documents_test_document("one", "not-save")
  let (documents, decisions) = documents.reduce(
    FeedbackReceived(SaveCompleted(save, Stored(bogus))),
  )
  assert_true(documents == before)
  assert_true(decisions.is_empty())
}

///|
test "duplicate save completion after delete issue is ignored" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(TextChanged(source_key("one"), "x"))
  let (documents, persist) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  guard persist is [PersistSource(save)] else { fail("save") }
  let (documents, _) = documents.reduce(DeleteConfirmed(source_key("one")))
  let (documents, first) = documents.reduce(
    FeedbackReceived(SaveCompleted(save, Stored(save.document))),
  )
  guard first is [DeleteSource(delete)] else { fail("delete") }
  let (documents, second) = documents.reduce(
    FeedbackReceived(SaveCompleted(save, Stored(save.document))),
  )
  assert_true(
    documents.delete_phase_status(source_key("one")) is Some(Deleting(_)),
  )
  assert_true(second.is_empty())
  ignore(delete)
}

///|
test "stale save completion cannot finish a replacement operation" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(TextChanged(source_key("one"), "first"))
  let (documents, persist) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  guard persist is [PersistSource(first)] else { fail("first save") }
  let (documents, _) = documents.reduce(
    TextChanged(source_key("one"), "latest"),
  )
  let (documents, _) = documents.reduce(VisibilityFlush(source_key("one")))
  let (documents, retry) = documents.reduce(
    FeedbackReceived(SaveCompleted(first, SaveFailed(WriteFailed))),
  )
  guard retry is [PersistSource(second)] else { fail("replacement save") }
  let before = documents
  let (documents, decisions) = documents.reduce(
    FeedbackReceived(SaveCompleted(first, Stored(first.document))),
  )
  assert_true(documents == before)
  assert_true(decisions.is_empty())
  ignore(second)
}
