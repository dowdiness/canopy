/// Tests are organized by reducer contract; fixtures and extraction helpers remain shared.

///|
test "stale timers and mismatched stored records are ignored" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "b"),
  )
  guard decisions is [DocumentsDecision::DocumentsArmMaximum(_, _)] else {
    fail("timers")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "c"),
  )
  let (documents, stale_max) = documents.reduce(
    DocumentsFeedbackReceived(MaximumElapsed("one", 99)),
  )
  assert_true(stale_max.is_empty())
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  guard decisions is [DocumentsDecision::DocumentsPersist(operation)] else {
    fail("latest quiet")
  }
  let bogus = documents_test_document("one", "not-the-operation-text")
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(operation, Stored(bogus))),
  )
  assert_eq(documents.snapshot().find("one").unwrap().text(), "one")
}

///|
test "page-local revision orders edits across documents" {
  let saved = documents_test_snapshot()
  let documents = initial_documents(saved)
  let (documents, first_decisions) = documents.reduce(
    DocumentsTextChanged("two", "two!"),
  )
  guard first_decisions is [DocumentsDecision::DocumentsArmMaximum(_, max_two)] else {
    fail("two timers")
  }
  assert_eq(pending_revision(documents, "two"), 1)
  assert_eq(max_two, 1)
  let (documents, second_decisions) = documents.reduce(
    DocumentsTextChanged("one", "one!"),
  )
  guard second_decisions is [DocumentsDecision::DocumentsArmMaximum(_, max_one)] else {
    fail("one independent timers")
  }
  assert_eq(pending_revision(documents, "one"), 2)
  assert_eq(max_one, 2)
  guard find_record(documents.records, "two").unwrap().save is Waiting(cp_two) else {
    fail("two waiting")
  }
  assert_eq(pending_revision(documents, "two"), 1)
  guard find_record(documents.records, "one").unwrap().save is Waiting(cp_one) else {
    fail("one waiting")
  }
  assert_eq(pending_revision(documents, "one"), 2)
  assert_eq(cp_one.maximum_id, 2)
}

///|
test "page-local revision retains authority unchanged and re-arms after stale timers" {
  let saved = @source_repository.SavedDocuments::from_documents([
    documents_test_document("one", "one"),
  ]).unwrap()
  let documents = initial_documents(saved)
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "changed"),
  )
  guard decisions is [DocumentsDecision::DocumentsArmMaximum(_, mid)] else {
    fail("timers")
  }
  assert_eq(pending_revision(documents, "one"), 1)
  assert_eq(mid, 1)
  // Stale pending_revision(documents, "one") revision is ignored
  let (documents, stale) = documents.reduce(ApplyPendingEdit("one", 99))
  assert_true(stale.is_empty())
  // Correct revision still arms persist
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  guard decisions[0] is DocumentsDecision::DocumentsPersist(operation) else {
    fail("persist")
  }
  assert_eq(operation.document.text(), "changed")
  // Import with same saved still persists via page-local revision
  let (documents, decisions) = documents.reduce(
    DocumentsImported("imported", "text"),
  )
  guard decisions is [DocumentsDecision::DocumentsPersist(op2)] else {
    fail("imported persist")
  }
  assert_eq(op2.document.text(), "text")
  assert_eq(documents.text("imported"), Some("text"))
}

///|
test "delete and recreate keeps pending revisions monotonic and isolated" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsNew("new"))
  let (documents, _) = documents.reduce(DocumentsTextChanged("new", "first"))
  let old_revision = pending_revision(documents, "new")
  let (documents, _) = documents.reduce(DeleteConfirmed("new"))
  let (documents, _) = documents.reduce(DocumentsNew("new"))
  let (documents, _) = documents.reduce(DocumentsTextChanged("new", "second"))
  let current_revision = pending_revision(documents, "new")
  assert_true(current_revision > old_revision)
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "other"))
  assert_true(has_pending(documents, "new"))
  assert_true(has_pending(documents, "one"))
}

///|
test "matching maximum after delete confirmation is ignored" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "changed"),
  )
  guard decisions is [DocumentsArmMaximum("one", maximum)] else {
    fail("maximum")
  }
  let (documents, decisions) = documents.reduce(DeleteConfirmed("one"))
  guard decisions is [DeleteDocument(_)] else { fail("delete") }
  let before = documents
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(MaximumElapsed("one", maximum)),
  )
  assert_true(documents == before)
  assert_true(decisions.is_empty())
}

/// The same fence applies when a newer checkpoint is queued behind a save.

///|
test "matching maximum during waiting deletion of in-flight save is ignored" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "first"),
  )
  guard decisions is [DocumentsArmMaximum("one", _)] else { fail("maximum") }
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  guard decisions is [DocumentsPersist(save)] else { fail("save") }
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "latest"),
  )
  guard decisions is [DocumentsArmMaximum("one", maximum)] else {
    fail("follow-up maximum")
  }
  let (documents, decisions) = documents.reduce(DeleteConfirmed("one"))
  assert_true(decisions.is_empty())
  let before = documents
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(MaximumElapsed("one", maximum)),
  )
  assert_true(documents == before)
  assert_true(decisions.is_empty())
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(save, Stored(save.document))),
  )
  guard decisions is [DeleteDocument(delete)] else {
    fail("original save remains valid")
  }
  assert_true(delete.document_id == "one")
}

/// Duplicate composition starts preserve the accepted lifecycle state.

///|
test "old pending callback after recreate is ignored" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsNew("new"))
  let (documents, _) = documents.reduce(DocumentsTextChanged("new", "first"))
  let old_revision = pending_revision(documents, "new")
  let (documents, _) = documents.reduce(DeleteConfirmed("new"))
  let (documents, _) = documents.reduce(DocumentsNew("new"))
  let (documents, _) = documents.reduce(DocumentsTextChanged("new", "second"))
  let before = documents
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit("new", old_revision),
  )
  assert_true(documents == before)
  assert_true(decisions.is_empty())
}

/// Completion facts are validated once before the delete lane is selected.

///|
test "waiting delete rejects mismatched stored completion" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "first"))
  let (documents, persist) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  guard persist is [DocumentsPersist(save)] else { fail("save") }
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "latest"))
  let (documents, _) = documents.reduce(DeleteConfirmed("one"))
  let before = documents
  let bogus = documents_test_document("one", "not-save")
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(save, Stored(bogus))),
  )
  assert_true(documents == before)
  assert_true(decisions.is_empty())
}

///|
test "duplicate save completion after delete issue is ignored" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "x"))
  let (documents, persist) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  guard persist is [DocumentsPersist(save)] else { fail("save") }
  let (documents, _) = documents.reduce(DeleteConfirmed("one"))
  let (documents, first) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(save, Stored(save.document))),
  )
  guard first is [DeleteDocument(delete)] else { fail("delete") }
  let (documents, second) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(save, Stored(save.document))),
  )
  assert_true(documents.delete_status("one") is Some(Deleting(_)))
  assert_true(second.is_empty())
  ignore(delete)
}

///|
test "stale save completion cannot finish a replacement operation" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "first"))
  let (documents, persist) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  guard persist is [DocumentsPersist(first)] else { fail("first save") }
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "latest"))
  let (documents, _) = documents.reduce(DocumentsVisibilityFlush("one"))
  let (documents, retry) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(first, SaveFailed(WriteFailed))),
  )
  guard retry is [DocumentsPersist(second)] else { fail("replacement save") }
  let before = documents
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(first, Stored(first.document))),
  )
  assert_true(documents == before)
  assert_true(decisions.is_empty())
  ignore(second)
}
