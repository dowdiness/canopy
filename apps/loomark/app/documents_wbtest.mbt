///|
fn documents_test_snapshot() -> @source_repository.SavedDocuments {
  @source_repository.SavedDocuments::from_documents([
    @source_repository.Document::create("one", "one") catch {
      _ => abort("invalid id")
    },
    @source_repository.Document::create("two", "two") catch {
      _ => abort("invalid id")
    },
  ]).unwrap()
}

///|
fn documents_test_document(
  id : String,
  text : String,
) -> @source_repository.Document {
  @source_repository.Document::create(id, text) catch {
    _ => abort("invalid id")
  }
}

///|
test "activation target preserves current text and parsed resume eligibility" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "one!"))
  guard documents.activation_target("one") is Some(saved) else {
    fail("saved activation target")
  }
  assert_eq(saved.document.text(), "one!")
  assert_true(saved.resume_hint is Some(_))
  let (documents, _) = documents.reduce(DocumentsNew("new"))
  guard documents.activation_target("new") is Some(ephemeral) else {
    fail("ephemeral activation target")
  }
  assert_eq(ephemeral.document.text(), "")
  assert_eq(ephemeral.resume_hint, None)
  assert_true(documents.activation_target("missing") is None)
}

///|
test "Import accepts empty text and persists it immediately as New" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DocumentsImported("imported", ""),
  )
  assert_eq(documents.text("imported"), Some(""))
  guard decisions is [DocumentsDecision::DocumentsPersist(operation)] &&
    operation.origin == DocumentOrigin::ImportedNew else {
    fail("expected one ImportedNew persistence decision")
  }
  assert_eq(operation.document, documents_test_document("imported", ""))
}

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
  guard decisions
    is [
      DocumentsDecision::DocumentsArmQuiet(_, quiet),
      DocumentsDecision::DocumentsArmMaximum(_, _),
    ] else {
    fail("initial timers")
  }
  let (documents, first) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", quiet)),
  )
  guard first.length() == 1 &&
    first[0] is DocumentsDecision::DocumentsPersist(first_operation) else {
    fail("first document should persist")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("two", "two!"),
  )
  guard decisions
    is [
      DocumentsDecision::DocumentsArmQuiet(_, quiet_two),
      DocumentsDecision::DocumentsArmMaximum(_, _),
    ] else {
    fail("two timers")
  }
  let (documents, second) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("two", quiet_two)),
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
  guard decisions
    is [
      DocumentsDecision::DocumentsArmQuiet(_, quiet_one),
      DocumentsDecision::DocumentsArmMaximum(_, _),
    ] else {
    fail("one timers")
  }
  let (documents, one_decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", quiet_one)),
  )
  guard one_decisions[0] is DocumentsPersist(one) else { fail("one save") }
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("two", "two!"),
  )
  guard decisions
    is [
      DocumentsDecision::DocumentsArmQuiet(_, quiet_two),
      DocumentsDecision::DocumentsArmMaximum(_, _),
    ] else {
    fail("two timers")
  }
  let (documents, two_decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("two", quiet_two)),
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
  guard decisions
    is [
      DocumentsDecision::DocumentsArmQuiet(_, quiet),
      DocumentsDecision::DocumentsArmMaximum(_, _),
    ] else {
    fail("timers")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("two", quiet)),
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
test "composition blocks persistence but keeps fresh revision" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsCompositionStarted("one"))
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "one!"),
  )
  assert_true(decisions.is_empty())
  guard find_record(documents.records, "one").unwrap().save
    is Waiting(checkpoint) else {
    fail("waiting checkpoint")
  }
  assert_eq(checkpoint.quiet_revision, 1)
  let (_, decisions) = documents.reduce(DocumentsCompositionEnded("one"))
  assert_eq(decisions.length(), 2)
  guard decisions[0] is DocumentsDecision::DocumentsArmQuiet(_, rev) else {
    fail("quiet timer")
  }
  assert_eq(rev, 1)
}

///|
test "checkpoint quiet identity changes while maximum identity stays fresh" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, first) = documents.reduce(DocumentsTextChanged("one", "b"))
  guard first
    is [
      DocumentsDecision::DocumentsArmQuiet(_, quiet),
      DocumentsDecision::DocumentsArmMaximum(_, maximum),
    ] else {
    fail("initial timers")
  }
  assert_eq(quiet, 1)
  assert_eq(maximum, 1)
  let (_, second) = documents.reduce(DocumentsTextChanged("one", "c"))
  guard second is [DocumentsDecision::DocumentsArmQuiet(_, quiet)] else {
    fail("only quiet is rearmed")
  }
  assert_eq(quiet, 2)
}

///|
test "maximum eligibility persists latest text during uninterrupted editing" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "b"),
  )
  guard decisions
    is [
      DocumentsDecision::DocumentsArmQuiet(_, _),
      DocumentsDecision::DocumentsArmMaximum(_, maximum),
    ] else {
    fail("initial timers")
  }
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "c"))
  let (_, decisions) = documents.reduce(
    DocumentsFeedbackReceived(MaximumElapsed("one", maximum)),
  )
  guard decisions is [DocumentsDecision::DocumentsPersist(operation)] else {
    fail("maximum persist")
  }
  assert_eq(operation.document.text(), "c")
  guard find_record(documents.records, "one").unwrap().save is Waiting(_) ||
    find_record(documents.records, "one").unwrap().save is Saving(_, _) else {
    fail("pending")
  }
}

///|
test "returning to operation text while saving preserves final fresh revision" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "b"),
  )
  guard decisions
    is [
      DocumentsDecision::DocumentsArmQuiet(_, quiet),
      DocumentsDecision::DocumentsArmMaximum(_, _),
    ] else {
    fail("timers")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", quiet)),
  )
  guard decisions[0] is DocumentsDecision::DocumentsPersist(operation) else {
    fail("expected persist")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "one"),
  )
  guard decisions
    is [
      DocumentsDecision::DocumentsArmQuiet(_, quiet_two),
      DocumentsDecision::DocumentsArmMaximum(_, _),
    ] else {
    fail("new save window timers")
  }
  assert_eq(quiet_two, 2)
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", quiet_two)),
  )
  assert_true(decisions.is_empty())
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(
      SaveCompleted(operation, Stored(operation.document)),
    ),
  )
  guard decisions[0] is DocumentsDecision::DocumentsPersist(next) else {
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
  guard decisions
    is [
      DocumentsDecision::DocumentsArmQuiet(_, quiet),
      DocumentsDecision::DocumentsArmMaximum(_, _),
    ] else {
    fail("timers")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", quiet)),
  )
  guard decisions[0] is DocumentsDecision::DocumentsPersist(operation) else {
    fail("expected persist")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "c"),
  )
  guard decisions
    is [
      DocumentsDecision::DocumentsArmQuiet(_, quiet_two),
      DocumentsDecision::DocumentsArmMaximum(_, _),
    ] else {
    fail("pending save window timers")
  }
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(operation, SaveFailed(WriteFailed))),
  )
  guard documents.save_status("one") is Some(Waiting(_)) else {
    fail("deferred failure waits")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", quiet_two)),
  )
  guard decisions[0] is DocumentsDecision::DocumentsPersist(retry_operation) else {
    fail("waiting retry")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "d"),
  )
  guard decisions
    is [
      DocumentsDecision::DocumentsArmQuiet(_, quiet_three),
      DocumentsDecision::DocumentsArmMaximum(_, _),
    ] else {
    fail("latest save window timers")
  }
  let (documents, eligible) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", quiet_three)),
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
test "stale timers and mismatched stored records are ignored" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "b"),
  )
  guard decisions
    is [
      DocumentsDecision::DocumentsArmQuiet(_, _),
      DocumentsDecision::DocumentsArmMaximum(_, _),
    ] else {
    fail("timers")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "c"),
  )
  guard decisions is [DocumentsDecision::DocumentsArmQuiet(_, quiet_two)] else {
    fail("second")
  }
  let (documents, stale_max) = documents.reduce(
    DocumentsFeedbackReceived(MaximumElapsed("one", 99)),
  )
  assert_true(stale_max.is_empty())
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", quiet_two)),
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
  guard first_decisions
    is [
      DocumentsDecision::DocumentsArmQuiet(_, quiet_two),
      DocumentsDecision::DocumentsArmMaximum(_, max_two),
    ] else {
    fail("two timers")
  }
  assert_eq(quiet_two, 1)
  assert_eq(max_two, 1)
  let (documents, second_decisions) = documents.reduce(
    DocumentsTextChanged("one", "one!"),
  )
  guard second_decisions
    is [
      DocumentsDecision::DocumentsArmQuiet(_, quiet_one),
      DocumentsDecision::DocumentsArmMaximum(_, max_one),
    ] else {
    fail("one independent timers")
  }
  assert_eq(quiet_one, 2)
  assert_eq(max_one, 2)
  guard find_record(documents.records, "two").unwrap().save is Waiting(cp_two) else {
    fail("two waiting")
  }
  assert_eq(cp_two.quiet_revision, 1)
  guard find_record(documents.records, "one").unwrap().save is Waiting(cp_one) else {
    fail("one waiting")
  }
  assert_eq(cp_one.quiet_revision, 2)
  assert_eq(cp_one.maximum_id, 2)
}

///|
test "duplicate text changes preserve documents and decisions" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "one!"))
  let before = documents
  let (after, decisions) = documents.reduce(DocumentsTextChanged("one", "one!"))
  assert_true(after == before)
  assert_true(decisions.is_empty())
}

///|
test "composition defers timers for an in-flight save until it ends" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "one!"),
  )
  guard decisions
    is [
      DocumentsDecision::DocumentsArmQuiet(_, quiet),
      DocumentsDecision::DocumentsArmMaximum(_, _),
    ] else {
    fail("timers")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", quiet)),
  )
  guard decisions[0] is DocumentsDecision::DocumentsPersist(_) else {
    fail("expected in-flight save")
  }
  let (documents, _) = documents.reduce(DocumentsCompositionStarted("one"))
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "one!!"),
  )
  assert_true(decisions.is_empty())
  guard documents.save_status("one") is Some(Saving(_, Some(_))) else {
    fail("composition change should be pending")
  }
  let (_, decisions) = documents.reduce(DocumentsCompositionEnded("one"))
  assert_eq(decisions.length(), 2)
}

///|
test "visibility makes an in-flight save's latest checkpoint eligible" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, timers) = documents.reduce(
    DocumentsTextChanged("one", "first"),
  )
  guard timers
    is [
      DocumentsDecision::DocumentsArmQuiet(_, quiet),
      DocumentsDecision::DocumentsArmMaximum(_, _),
    ] else {
    fail("initial timers")
  }
  let (documents, persist) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", quiet)),
  )
  guard persist is [DocumentsDecision::DocumentsPersist(operation)] else {
    fail("first save")
  }
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "latest"))
  let (documents, flush) = documents.reduce(DocumentsVisibilityFlush("one"))
  assert_true(flush.is_empty())
  let (_, follow_up) = documents.reduce(
    DocumentsFeedbackReceived(
      SaveCompleted(operation, Stored(operation.document)),
    ),
  )
  guard follow_up is [DocumentsDecision::DocumentsPersist(latest)] else {
    fail("eligible follow-up")
  }
  assert_eq(latest.document.text(), "latest")
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
  guard decisions
    is [
      DocumentsDecision::DocumentsArmQuiet(_, quiet),
      DocumentsDecision::DocumentsArmMaximum(_, _),
    ] else {
    fail("timers")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", quiet)),
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
  guard documents.delete_status("one") is Some(Deleting(current)) &&
    current == delete else {
    fail("delete operation should be preserved")
  }
  assert_true(documents.save_status("one") == Some(Saved))
}

///|
test "failed existing save still releases a waiting delete" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "new"),
  )
  guard decisions
    is [
      DocumentsDecision::DocumentsArmQuiet(_, quiet),
      DocumentsDecision::DocumentsArmMaximum(_, _),
    ] else {
    fail("timers")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", quiet)),
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
  guard decisions
    is [
      DocumentsDecision::DocumentsArmQuiet(_, quiet),
      DocumentsDecision::DocumentsArmMaximum(_, _),
    ] else {
    fail("timers")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("new", quiet)),
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
  guard decisions
    is [
      DocumentsDecision::DocumentsArmQuiet(_, quiet),
      DocumentsDecision::DocumentsArmMaximum(_, _),
    ] else {
    fail("timers")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("new", quiet)),
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
  guard decisions
    is [
      DocumentsDecision::DocumentsArmQuiet(_, quiet),
      DocumentsDecision::DocumentsArmMaximum(_, _),
    ] else {
    fail("timers")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", quiet)),
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
test "page-local revision retains authority unchanged and re-arms after stale timers" {
  let saved = @source_repository.SavedDocuments::from_documents([
    documents_test_document("one", "one"),
  ]).unwrap()
  let documents = initial_documents(saved)
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "changed"),
  )
  guard decisions
    is [
      DocumentsDecision::DocumentsArmQuiet(_, rev),
      DocumentsDecision::DocumentsArmMaximum(_, mid),
    ] else {
    fail("timers")
  }
  assert_eq(rev, 1)
  assert_eq(mid, 1)
  // Stale quiet revision is ignored
  let (documents, stale) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", 99)),
  )
  assert_true(stale.is_empty())
  // Correct revision still arms persist
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", rev)),
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
