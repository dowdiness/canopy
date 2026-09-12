/// Tests are organized by reducer contract; fixtures and extraction helpers remain shared.

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
  assert_eq(pending_revision(documents, "one"), 1)
  let (documents, decisions) = documents.reduce(
    DocumentsCompositionEnded("one"),
  )
  guard decisions is [DocumentsDecision::DocumentsArmMaximum("one", _)] else {
    fail("maximum")
  }
  assert_true(has_pending(documents, "one"))
}

///|
test "pending revision advances while maximum identity stays fresh" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, first) = documents.reduce(DocumentsTextChanged("one", "b"))
  guard first is [DocumentsDecision::DocumentsArmMaximum(_, maximum)] else {
    fail("initial timers")
  }
  assert_eq(pending_revision(documents, "one"), 1)
  assert_eq(maximum, 1)
  let (documents, second) = documents.reduce(DocumentsTextChanged("one", "c"))
  assert_true(second.is_empty())
  assert_eq(pending_revision(documents, "one"), 2)
}

///|
test "maximum eligibility persists latest text during uninterrupted editing" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "b"),
  )
  guard decisions is [DocumentsDecision::DocumentsArmMaximum(_, maximum)] else {
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
test "composition defers timers for an in-flight save until it ends" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "one!"),
  )
  guard decisions is [DocumentsDecision::DocumentsArmMaximum(_, _)] else {
    fail("timers")
  }
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
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
  let (documents, decisions) = documents.reduce(
    DocumentsCompositionEnded("one"),
  )
  guard decisions is [DocumentsDecision::DocumentsArmMaximum("one", _)] else {
    fail("maximum")
  }
  assert_true(has_pending(documents, "one"))
}

///|
test "visibility makes an in-flight save's latest checkpoint eligible" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, timers) = documents.reduce(
    DocumentsTextChanged("one", "first"),
  )
  guard timers is [DocumentsDecision::DocumentsArmMaximum(_, _)] else {
    fail("initial timers")
  }
  let (documents, persist) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
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
test "duplicate composition end emits one maximum decision" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsCompositionStarted("one"))
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "first"))
  let (documents, first) = documents.reduce(DocumentsCompositionEnded("one"))
  guard first is [DocumentsDecision::DocumentsArmMaximum("one", _)] else {
    fail("first composition end should arm maximum")
  }
  let (_, second) = documents.reduce(DocumentsCompositionEnded("one"))
  assert_true(second.is_empty())
}

///|
test "genuine composition cycles arm maximum once with saving pending" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsCompositionStarted("one"))
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "first"))
  let (documents, first) = documents.reduce(DocumentsCompositionEnded("one"))
  guard first is [DocumentsDecision::DocumentsArmMaximum("one", _)] else {
    fail("first cycle maximum")
  }
  let (documents, _) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  guard documents.save_status("one") is Some(Saving(_, _)) else {
    fail("first cycle should be saving")
  }
  let (documents, _) = documents.reduce(DocumentsCompositionStarted("one"))
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "second"))
  let (documents, second) = documents.reduce(DocumentsCompositionEnded("one"))
  guard second is [DocumentsDecision::DocumentsArmMaximum("one", _)] else {
    fail("second cycle maximum")
  }
  let (_, duplicate) = documents.reduce(DocumentsCompositionEnded("one"))
  assert_true(duplicate.is_empty())
}

///|
test "queued composition callback applies immediately at composition end" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "new"))
  let revision = pending_revision(documents, "one")
  let (documents, _) = documents.reduce(DocumentsCompositionStarted("one"))
  let (documents, _) = documents.reduce(ApplyPendingEdit("one", revision))
  let (documents, _) = documents.reduce(DocumentsCompositionEnded("one"))
  assert_true(
    find_record(documents.records, "one").unwrap().lead_source
    is LeadSource::Available("new"),
  )
  assert_true(!has_pending(documents, "one"))
}

///|
test "composition end without callback does not accept the edit" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsCompositionStarted("one"))
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "ime"))
  let (documents, _) = documents.reduce(DocumentsCompositionEnded("one"))
  assert_true(
    find_record(documents.records, "one").unwrap().lead_source
    is LeadSource::Available("one"),
  )
  assert_true(has_pending(documents, "one"))
}

///|
test "IME callback then newer edit waits for latest pending revision" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "composed"))
  let initial_revision = pending_revision(documents, "one")
  let (documents, _) = documents.reduce(DocumentsCompositionStarted("one"))
  let (documents, _) = documents.reduce(
    ApplyPendingEdit("one", initial_revision),
  )
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "newer"))
  let (documents, _) = documents.reduce(DocumentsCompositionEnded("one"))
  assert_true(
    find_record(documents.records, "one").unwrap().lead_source
    is LeadSource::Available("one"),
  )
  let revision = pending_revision(documents, "one")
  let (documents, _) = documents.reduce(ApplyPendingEdit("one", revision))
  assert_true(
    find_record(documents.records, "one").unwrap().lead_source
    is LeadSource::Available("newer"),
  )
}

///|
test "composition end with no newer edit starts one pending subscription" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsCompositionStarted("one"))
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "composed"))
  let (documents, decisions) = documents.reduce(
    DocumentsCompositionEnded("one"),
  )
  guard decisions is [DocumentsArmMaximum("one", _)] else { fail("maximum") }
  assert_true(has_pending(documents, "one"))
}

///|
test "composition end does not duplicate an already pending edit" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "changed"))
  let (documents, _) = documents.reduce(DocumentsCompositionStarted("one"))
  let (documents, _) = documents.reduce(DocumentsCompositionEnded("one"))
  assert_true(has_pending(documents, "one"))
}

///|
test "eligible maximum during composition persists at composition end" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "changed"),
  )
  guard decisions is [DocumentsArmMaximum("one", maximum)] else {
    fail("maximum")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsCompositionStarted("one"),
  )
  assert_true(decisions.is_empty())
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(MaximumElapsed("one", maximum)),
  )
  assert_true(decisions.is_empty())
  let (documents, decisions) = documents.reduce(
    DocumentsCompositionEnded("one"),
  )
  guard decisions is [DocumentsPersist(_)] else { fail("persist") }
  assert_true(has_pending(documents, "one"))
}

///|
test "duplicate composition starts preserve waiting and ready evidence" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "changed"))
  let revision = pending_revision(documents, "one")
  let (documents, _) = documents.reduce(DocumentsCompositionStarted("one"))
  let (documents, _) = documents.reduce(DocumentsCompositionStarted("one"))
  match find_record(documents.records, "one").unwrap().edit {
    ComposingWaiting(waiting_revision) => assert_eq(waiting_revision, revision)
    _ => fail("waiting evidence")
  }
  let (documents, _) = documents.reduce(ApplyPendingEdit("one", revision))
  let (documents, _) = documents.reduce(DocumentsCompositionStarted("one"))
  assert_true(
    find_record(documents.records, "one").unwrap().edit is ComposingReady,
  )
}

/// A ready composition end accepts the record and starts exactly one save.

///|
test "ready composition end persists once" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsCompositionStarted("one"))
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "composed"))
  let revision = pending_revision(documents, "one")
  let (documents, _) = documents.reduce(ApplyPendingEdit("one", revision))
  let (documents, decisions) = documents.reduce(
    DocumentsCompositionEnded("one"),
  )
  guard decisions is [DocumentsPersist(operation)] else { fail("persist") }
  assert_true(find_record(documents.records, "one").unwrap().edit is Idle)
  let (_, duplicate) = documents.reduce(DocumentsCompositionEnded("one"))
  assert_true(duplicate.is_empty())
  ignore(operation)
}

/// A ready callback remains evidence when the final text event is unchanged.

///|
test "matching final text keeps ready evidence" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsCompositionStarted("one"))
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "same"))
  let revision = pending_revision(documents, "one")
  let (documents, _) = documents.reduce(ApplyPendingEdit("one", revision))
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "same"))
  assert_true(
    find_record(documents.records, "one").unwrap().edit is ComposingReady,
  )
  let (documents, decisions) = documents.reduce(
    DocumentsCompositionEnded("one"),
  )
  guard decisions is [DocumentsPersist(_)] else { fail("persist") }
  assert_true(
    find_record(documents.records, "one").unwrap().lead_source
    is LeadSource::Available("same"),
  )
}

/// An accepted composition queues exactly one follow-up behind an in-flight save.

///|
test "ready composition end marks in-flight follow-up eligible once" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, first) = documents.reduce(
    DocumentsTextChanged("one", "first"),
  )
  guard first is [DocumentsArmMaximum("one", _)] else { fail("timer") }
  let (documents, first) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  guard first is [DocumentsPersist(operation)] else { fail("first save") }
  let (documents, _) = documents.reduce(DocumentsCompositionStarted("one"))
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "latest"))
  let (documents, _) = documents.reduce(
    ApplyPendingEdit("one", pending_revision(documents, "one")),
  )
  let (documents, decisions) = documents.reduce(
    DocumentsCompositionEnded("one"),
  )
  assert_true(decisions.is_empty())
  guard documents.save_status("one") is Some(Saving(_, Some(checkpoint))) else {
    fail("eligible queued checkpoint")
  }
  assert_true(
    checkpoint.eligibility == DocumentsCheckpointEligibility::Eligible,
  )
  let (_, follow_up) = documents.reduce(
    DocumentsFeedbackReceived(
      SaveCompleted(operation, Stored(operation.document)),
    ),
  )
  guard follow_up is [DocumentsPersist(latest)] else { fail("one follow-up") }
  assert_eq(latest.document.text(), "latest")
}

/// A composition end outside composition is not a save event.

///|
test "composition end outside composition is ignored" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "changed"))
  let before = documents
  let (documents, decisions) = documents.reduce(
    DocumentsCompositionEnded("one"),
  )
  assert_true(documents == before)
  assert_true(decisions.is_empty())
}

/// A stale callback must not reach a replacement record with the same ID.

///|
