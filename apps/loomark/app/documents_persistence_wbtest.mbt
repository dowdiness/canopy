/// Tests are organized by reducer contract; fixtures and extraction helpers remain shared.

///|
test "failed Import remains available through the existing Retry" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DocumentsImported("imported", "text"),
  )
  guard decisions is [DocumentsPersist(operation)] else { fail("persist") }
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(operation, SaveFailed(WriteFailed))),
  )
  assert_eq(documents.text("imported"), Some("text"))
  guard documents.save_status("imported") is Some(Failed(WriteFailed)) else {
    fail("expected retryable failure")
  }
  let (_, decisions) = documents.reduce(DocumentsRetrySave("imported"))
  guard decisions is [DocumentsPersist(retry)] else { fail("retry") }
  assert_eq(retry.document, operation.document)
}

///|
test "failed Import deletion is local because it was never saved" {
  let documents = initial_documents(documents_test_snapshot())
  let before = documents.snapshot()
  let (documents, decisions) = documents.reduce(
    DocumentsImported("imported", "text"),
  )
  guard decisions is [DocumentsPersist(operation)] else { fail("persist") }
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(operation, SaveFailed(WriteFailed))),
  )
  let (documents, decisions) = documents.reduce(DeleteConfirmed("imported"))
  assert_true(decisions.is_empty())
  assert_eq(documents.snapshot(), before)
  assert_eq(documents.text("imported"), None)
}

///|
test "a second document persists while the first document is in flight" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "one!"),
  )
  guard decisions is [DocumentsDecision::DocumentsArmMaximum(_, _)] else {
    fail("initial timers")
  }
  let (documents, first) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  guard first.length() == 1 &&
    first[0] is DocumentsDecision::DocumentsPersist(first_operation) else {
    fail("first document should persist")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("two", "two!"),
  )
  guard decisions is [DocumentsDecision::DocumentsArmMaximum(_, _)] else {
    fail("two timers")
  }
  let (documents, second) = documents.reduce(
    ApplyPendingEdit("two", pending_revision(documents, "two")),
  )
  guard second.length() == 1 &&
    second[0] is DocumentsDecision::DocumentsPersist(second_operation) else {
    fail("second document should persist")
  }
  assert_true(first_operation != second_operation)
  guard documents.save_status("one") is Some(Saving(_, _)) else {
    fail("one remains in flight")
  }
  guard documents.save_status("two") is Some(Saving(_, _)) else {
    fail("two is in flight")
  }
}

///|
test "reverse save acknowledgments merge into the latest snapshot" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "one!"),
  )
  guard decisions is [DocumentsDecision::DocumentsArmMaximum(_, _)] else {
    fail("one timers")
  }
  let (documents, one_decisions) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  guard one_decisions[0] is DocumentsPersist(one) else { fail("one save") }
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("two", "two!"),
  )
  guard decisions is [DocumentsDecision::DocumentsArmMaximum(_, _)] else {
    fail("two timers")
  }
  let (documents, two_decisions) = documents.reduce(
    ApplyPendingEdit("two", pending_revision(documents, "two")),
  )
  guard two_decisions[0] is DocumentsPersist(two) else { fail("two save") }
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(two, Stored(two.document))),
  )
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(one, Stored(one.document))),
  )
  assert_eq(documents.snapshot().find("one").unwrap().text(), "one!")
  assert_eq(documents.snapshot().find("two").unwrap().text(), "two!")
}

///|
test "inactive save completion updates the latest snapshot" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("two", "two!"),
  )
  guard decisions is [DocumentsDecision::DocumentsArmMaximum(_, _)] else {
    fail("timers")
  }
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit("two", pending_revision(documents, "two")),
  )
  guard decisions[0] is DocumentsDecision::DocumentsPersist(operation) else {
    fail("expected persist")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(
      SaveCompleted(operation, Stored(operation.document)),
    ),
  )
  assert_true(decisions.is_empty())
  assert_eq(documents.snapshot().find("two").unwrap().text(), "two!")
  assert_eq(documents.text("one"), Some("one"))
}

///|
test "returning to operation text while saving preserves final fresh revision" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "b"),
  )
  guard decisions is [DocumentsDecision::DocumentsArmMaximum(_, _)] else {
    fail("timers")
  }
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  guard decisions[0] is DocumentsDecision::DocumentsPersist(operation) else {
    fail("expected persist")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "one"),
  )
  guard decisions is [DocumentsDecision::DocumentsArmMaximum(_, _)] else {
    fail("new save window timers")
  }
  assert_true(has_pending(documents, "one"))
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  assert_true(decisions.is_empty())
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(
      SaveCompleted(operation, Stored(operation.document)),
    ),
  )
  guard decisions is [DocumentsDecision::DocumentsPersist(next)] else {
    fail("latest candidate must persist")
  }
  assert_eq(next.document.text(), "one")
  assert_eq(next.document.id(), "one")
  assert_eq(documents.snapshot().find("one").unwrap().text(), "b")
}

///|
test "deferred and eligible failures preserve or promote pending checkpoint" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "b"),
  )
  guard decisions is [DocumentsDecision::DocumentsArmMaximum(_, _)] else {
    fail("timers")
  }
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  guard decisions[0] is DocumentsDecision::DocumentsPersist(operation) else {
    fail("expected persist")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "c"),
  )
  guard decisions is [DocumentsDecision::DocumentsArmMaximum(_, _)] else {
    fail("pending save window timers")
  }
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(operation, SaveFailed(WriteFailed))),
  )
  guard documents.save_status("one") is Some(Waiting(_)) else {
    fail("deferred failure waits")
  }
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  guard decisions[0] is DocumentsDecision::DocumentsPersist(retry_operation) else {
    fail("waiting retry")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "d"),
  )
  guard decisions is [DocumentsDecision::DocumentsArmMaximum(_, _)] else {
    fail("latest save window timers")
  }
  let (documents, eligible) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  assert_true(eligible.is_empty())
  let (_, retry) = documents.reduce(
    DocumentsFeedbackReceived(
      SaveCompleted(retry_operation, SaveFailed(WriteFailed)),
    ),
  )
  guard retry[0] is DocumentsDecision::DocumentsPersist(latest) else {
    fail("eligible failure promotes")
  }
  assert_eq(latest.document.text(), "d")
}

///|
test "delete success removes only the target record" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(DeleteConfirmed("one"))
  guard decisions is [DeleteDocument(operation)] else {
    fail("delete should issue immediately")
  }
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(DeleteCompleted(operation, Deleted("one"))),
  )
  assert_eq(documents.text("one"), None)
  assert_eq(documents.text("two"), Some("two"))
  assert_eq(documents.snapshot().find("one"), None)
}

///|
test "confirmation waits for the matching save and then deletes" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "new"),
  )
  guard decisions is [DocumentsDecision::DocumentsArmMaximum(_, _)] else {
    fail("timers")
  }
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  guard decisions is [DocumentsDecision::DocumentsPersist(save)] else {
    fail("expected save")
  }
  let (documents, decisions) = documents.reduce(DeleteConfirmed("one"))
  assert_true(decisions.is_empty())
  guard documents.delete_status("one") is Some(Waiting(delete)) else {
    fail("confirmation must wait")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(save, Stored(save.document))),
  )
  guard decisions is [DeleteDocument(_)] else {
    fail("stored save must release delete")
  }
  guard documents.delete_status("one") is Some(Deleting(active_delete)) &&
    active_delete == delete else {
    fail("delete operation should be preserved")
  }
  assert_true(documents.save_status("one") == Some(Saved))
}

///|
test "duplicate confirmation during waiting deletion preserves original operation" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "new"),
  )
  guard decisions is [DocumentsDecision::DocumentsArmMaximum(_, _)] else {
    fail("timers")
  }
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  guard decisions is [DocumentsDecision::DocumentsPersist(save)] else {
    fail("expected save")
  }
  let (documents, decisions) = documents.reduce(DeleteConfirmed("one"))
  assert_true(decisions.is_empty())
  let before = documents
  let (documents, decisions) = documents.reduce(RetryDelete("one"))
  assert_true(documents == before)
  assert_true(decisions.is_empty())
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(save, Stored(save.document))),
  )
  guard decisions is [DeleteDocument(delete)] else {
    fail("original operation")
  }
  assert_true(documents.delete_status("one") == Some(Deleting(delete)))
}

///|
test "duplicate confirmation during deleting preserves original operation" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(DeleteConfirmed("one"))
  guard decisions is [DeleteDocument(delete)] else { fail("delete") }
  let before = documents
  let (documents, decisions) = documents.reduce(DeleteConfirmed("one"))
  assert_true(documents == before)
  assert_true(decisions.is_empty())
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(DeleteCompleted(delete, Deleted("one"))),
  )
  assert_true(decisions.is_empty())
  assert_eq(documents.text("one"), None)
}

///|
test "failed existing save still releases a waiting delete" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "new"),
  )
  guard decisions is [DocumentsDecision::DocumentsArmMaximum(_, _)] else {
    fail("timers")
  }
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  guard decisions[0] is DocumentsPersist(save) else { fail("save") }
  let (documents, _) = documents.reduce(DeleteConfirmed("one"))
  let (_, decisions) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(save, SaveFailed(WriteFailed))),
  )
  guard decisions is [DeleteDocument(_)] else {
    fail("failed existing save must still delete")
  }
}

///|
test "new document deletion is local and does not change snapshot" {
  let documents = initial_documents(documents_test_snapshot())
  let before = documents.snapshot()
  let (documents, _) = documents.reduce(DocumentsNew("new"))
  let (documents, decisions) = documents.reduce(DeleteConfirmed("new"))
  assert_true(decisions.is_empty())
  assert_eq(documents.snapshot(), before)
  assert_eq(documents.text("new"), None)
}

///|
test "new in-flight stored save promotes before deletion" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsNew("new"))
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("new", "hello"),
  )
  guard decisions is [DocumentsDecision::DocumentsArmMaximum(_, _)] else {
    fail("timers")
  }
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit("new", pending_revision(documents, "new")),
  )
  guard decisions[0] is DocumentsPersist(save) else { fail("save") }
  let (documents, _) = documents.reduce(DeleteConfirmed("new"))
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(save, Stored(save.document))),
  )
  guard decisions[0] is DeleteDocument(_) else { fail("delete") }
  guard documents.snapshot().find("new") is Some(_) else {
    fail("stored new document must be acknowledged first")
  }
}

///|
test "new in-flight failed save is removed locally" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsNew("new"))
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("new", "hello"),
  )
  guard decisions is [DocumentsDecision::DocumentsArmMaximum(_, _)] else {
    fail("timers")
  }
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit("new", pending_revision(documents, "new")),
  )
  guard decisions[0] is DocumentsPersist(save) else { fail("save") }
  let (documents, _) = documents.reduce(DeleteConfirmed("new"))
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(save, SaveFailed(WriteFailed))),
  )
  assert_true(decisions.is_empty())
  assert_eq(documents.text("new"), None)
  assert_eq(documents.snapshot().find("new"), None)
}

///|
test "retry allocates a fresh operation and fences an active save" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(DeleteConfirmed("one"))
  guard decisions[0] is DeleteDocument(first) else { fail("delete") }
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(DeleteCompleted(first, DeleteFailed(WriteFailed))),
  )
  let (documents, stale) = documents.reduce(
    DocumentsFeedbackReceived(DeleteCompleted(first, Deleted("one"))),
  )
  assert_true(stale.is_empty())
  assert_eq(documents.text("one"), Some("one"))
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "edited"),
  )
  guard decisions is [DocumentsDecision::DocumentsArmMaximum(_, _)] else {
    fail("timers")
  }
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  guard decisions[0] is DocumentsPersist(save) else { fail("save") }
  let (documents, decisions) = documents.reduce(RetryDelete("one"))
  assert_true(decisions.is_empty())
  guard documents.delete_status("one") is Some(Waiting(second)) else {
    fail("retry must wait for save")
  }
  assert_true(second != first)
  let (_, decisions) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(save, SaveFailed(WriteFailed))),
  )
  guard decisions[0] is DeleteDocument(third) else { fail("release retry") }
  assert_true(third != first && third == second)
}

///|
test "maximum save completion then pending callback accepts source" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "maximum"),
  )
  guard decisions is [DocumentsArmMaximum("one", maximum)] else {
    fail("maximum")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(MaximumElapsed("one", maximum)),
  )
  guard decisions is [DocumentsPersist(operation)] else { fail("save") }
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(
      SaveCompleted(operation, Stored(operation.document)),
    ),
  )
  assert_true(
    find_record(documents.records, "one").unwrap().lead_source
    is LeadSource::Available("one"),
  )
  let revision = pending_revision(documents, "one")
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit("one", revision),
  )
  assert_true(decisions.is_empty())
  assert_true(
    find_record(documents.records, "one").unwrap().lead_source
    is LeadSource::Available("maximum"),
  )
}

///|
test "failed accepted save then clean revert keeps lead pending without save" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "new"))
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  guard decisions is [DocumentsPersist(operation)] else { fail("save") }
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(operation, SaveFailed(WriteFailed))),
  )
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "one"),
  )
  assert_true(decisions.is_empty())
  assert_true(documents.save_status("one") is Some(Saved))
  assert_true(has_pending(documents, "one"))
}

///|
test "eligible pending latest text waits for delete without an intermediate write" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "first"))
  let (documents, persist) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  guard persist is [DocumentsPersist(first)] else { fail("first save") }
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "latest"))
  let (documents, _) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  let (documents, _) = documents.reduce(DeleteConfirmed("one"))
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(first, Stored(first.document))),
  )
  guard decisions is [DeleteDocument(_)] else { fail("delete only") }
  guard documents.save_status("one") is Some(Waiting(_)) else {
    fail("latest checkpoint must remain waiting")
  }
}

///|
test "failed absent New completion removes the record before delete" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsNew("new"))
  let (documents, timer) = documents.reduce(DocumentsTextChanged("new", "x"))
  guard timer is [DocumentsArmMaximum(_, _)] else { fail("timer") }
  let (documents, persist) = documents.reduce(
    ApplyPendingEdit("new", pending_revision(documents, "new")),
  )
  guard persist is [DocumentsPersist(save)] else { fail("save") }
  let (documents, _) = documents.reduce(DeleteConfirmed("new"))
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(save, SaveFailed(WriteFailed))),
  )
  assert_true(decisions.is_empty())
  assert_eq(documents.text("new"), None)
}

///|
test "failed absent Import completion removes the record before delete" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, persist) = documents.reduce(
    DocumentsImported("imported", "x"),
  )
  guard persist is [DocumentsPersist(save)] else { fail("save") }
  let (documents, _) = documents.reduce(DeleteConfirmed("imported"))
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(save, SaveFailed(WriteFailed))),
  )
  assert_true(decisions.is_empty())
  assert_eq(documents.text("imported"), None)
}

///|
test "delete success removes acknowledged membership" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(DeleteConfirmed("one"))
  guard decisions is [DeleteDocument(delete)] else { fail("delete") }
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(DeleteCompleted(delete, Deleted("one"))),
  )
  assert_true(decisions.is_empty())
  assert_eq(documents.snapshot().find("one"), None)
}

///|
test "delete failure resumes the retained eligible latest checkpoint" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "first"))
  let (documents, persist) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  guard persist is [DocumentsPersist(first)] else { fail("first save") }
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "latest"))
  let (documents, _) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  let (documents, _) = documents.reduce(DeleteConfirmed("one"))
  let (documents, delete_decision) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(first, Stored(first.document))),
  )
  guard delete_decision is [DeleteDocument(delete)] else { fail("delete") }
  let (_, resume) = documents.reduce(
    DocumentsFeedbackReceived(
      DeleteCompleted(delete, DeleteFailed(WriteFailed)),
    ),
  )
  guard resume is [DocumentsPersist(latest)] else { fail("resume latest") }
  assert_eq(latest.document.text(), "latest")
}

///|
