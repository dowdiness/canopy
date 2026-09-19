/// Tests are organized by reducer contract; fixtures and extraction helpers remain shared.

///|
test "failed Import remains available through the existing Retry" {
  let documents = State::State(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    Imported(document_id("imported"), "text"),
  )
  guard decisions is [PersistSource(operation)] else { fail("persist") }
  let (documents, _) = documents.reduce(
    FeedbackReceived(SaveCompleted(operation, SaveFailed(WriteFailed))),
  )
  assert_eq(documents.text(source_key("imported")), Some("text"))
  guard documents.save_phase(source_key("imported"))
    is Some(Failed(WriteFailed)) else {
    fail("expected retryable failure")
  }
  let (_, decisions) = documents.reduce(RetrySave(source_key("imported")))
  guard decisions is [PersistSource(retry)] else { fail("retry") }
  assert_eq(retry.document, operation.document)
}

///|
test "failed Import deletion is local because it was never saved" {
  let documents = State::State(documents_test_snapshot())
  let before = documents.snapshot()
  let (documents, decisions) = documents.reduce(
    Imported(document_id("imported"), "text"),
  )
  guard decisions is [PersistSource(operation)] else { fail("persist") }
  let (documents, _) = documents.reduce(
    FeedbackReceived(SaveCompleted(operation, SaveFailed(WriteFailed))),
  )
  let (documents, decisions) = documents.reduce(
    DeleteConfirmed(source_key("imported")),
  )
  assert_true(decisions.is_empty())
  assert_eq(documents.snapshot(), before)
  assert_eq(documents.text(source_key("imported")), None)
}

///|
test "a second document persists while the first document is in flight" {
  let documents = State::State(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("one"), "one!"),
  )
  guard decisions is [Effect::ArmMaximum(_, _)] else { fail("initial timers") }
  let (documents, first) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  guard first.length() == 1 &&
    first[0] is Effect::PersistSource(first_operation) else {
    fail("first document should persist")
  }
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("two"), "two!"),
  )
  guard decisions is [Effect::ArmMaximum(_, _)] else { fail("two timers") }
  let (documents, second) = documents.reduce(
    ApplyPendingEdit(
      source_key("two"),
      pending_revision(documents, source_key("two")),
    ),
  )
  guard second.length() == 1 &&
    second[0] is Effect::PersistSource(second_operation) else {
    fail("second document should persist")
  }
  assert_true(first_operation != second_operation)
  guard documents.save_phase(source_key("one")) is Some(Saving(_, _)) else {
    fail("one remains in flight")
  }
  guard documents.save_phase(source_key("two")) is Some(Saving(_, _)) else {
    fail("two is in flight")
  }
}

///|
test "reverse save acknowledgments merge into the latest snapshot" {
  let documents = State::State(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("one"), "one!"),
  )
  guard decisions is [Effect::ArmMaximum(_, _)] else { fail("one timers") }
  let (documents, one_decisions) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  guard one_decisions[0] is PersistSource(one) else { fail("one save") }
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("two"), "two!"),
  )
  guard decisions is [Effect::ArmMaximum(_, _)] else { fail("two timers") }
  let (documents, two_decisions) = documents.reduce(
    ApplyPendingEdit(
      source_key("two"),
      pending_revision(documents, source_key("two")),
    ),
  )
  guard two_decisions[0] is PersistSource(two) else { fail("two save") }
  let (documents, _) = documents.reduce(
    FeedbackReceived(SaveCompleted(two, Stored(two.document))),
  )
  let (documents, _) = documents.reduce(
    FeedbackReceived(SaveCompleted(one, Stored(one.document))),
  )
  assert_eq(
    documents.snapshot().find(document_id("one")).unwrap().text(),
    "one!",
  )
  assert_eq(
    documents.snapshot().find(document_id("two")).unwrap().text(),
    "two!",
  )
}

///|
test "inactive save completion updates the latest snapshot" {
  let documents = State::State(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("two"), "two!"),
  )
  guard decisions is [Effect::ArmMaximum(_, _)] else { fail("timers") }
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit(
      source_key("two"),
      pending_revision(documents, source_key("two")),
    ),
  )
  guard decisions[0] is Effect::PersistSource(operation) else {
    fail("expected persist")
  }
  let (documents, decisions) = documents.reduce(
    FeedbackReceived(SaveCompleted(operation, Stored(operation.document))),
  )
  assert_true(decisions.is_empty())
  assert_eq(
    documents.snapshot().find(document_id("two")).unwrap().text(),
    "two!",
  )
  assert_eq(documents.text(source_key("one")), Some("one"))
}

///|
test "returning to operation text while saving preserves final fresh revision" {
  let documents = State::State(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("one"), "b"),
  )
  guard decisions is [Effect::ArmMaximum(_, _)] else { fail("timers") }
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  guard decisions[0] is Effect::PersistSource(operation) else {
    fail("expected persist")
  }
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("one"), "one"),
  )
  guard decisions is [Effect::ArmMaximum(_, _)] else {
    fail("new save window timers")
  }
  assert_true(has_pending(documents, source_key("one")))
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  assert_true(decisions.is_empty())
  let (documents, decisions) = documents.reduce(
    FeedbackReceived(SaveCompleted(operation, Stored(operation.document))),
  )
  guard decisions is [Effect::PersistSource(next)] else {
    fail("latest candidate must persist")
  }
  assert_eq(next.document.text(), "one")
  assert_eq(next.document.id(), document_id("one"))
  assert_eq(documents.snapshot().find(document_id("one")).unwrap().text(), "b")
}

///|
test "deferred and eligible failures preserve or promote pending checkpoint" {
  let documents = State::State(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("one"), "b"),
  )
  guard decisions is [Effect::ArmMaximum(_, _)] else { fail("timers") }
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  guard decisions[0] is Effect::PersistSource(operation) else {
    fail("expected persist")
  }
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("one"), "c"),
  )
  guard decisions is [Effect::ArmMaximum(_, _)] else {
    fail("pending save window timers")
  }
  let (documents, _) = documents.reduce(
    FeedbackReceived(SaveCompleted(operation, SaveFailed(WriteFailed))),
  )
  guard documents.save_phase(source_key("one")) is Some(Waiting(_)) else {
    fail("deferred failure waits")
  }
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  guard decisions[0] is Effect::PersistSource(retry_operation) else {
    fail("waiting retry")
  }
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("one"), "d"),
  )
  guard decisions is [Effect::ArmMaximum(_, _)] else {
    fail("latest save window timers")
  }
  let (documents, eligible) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  assert_true(eligible.is_empty())
  let (_, retry) = documents.reduce(
    FeedbackReceived(SaveCompleted(retry_operation, SaveFailed(WriteFailed))),
  )
  guard retry[0] is Effect::PersistSource(latest) else {
    fail("eligible failure promotes")
  }
  assert_eq(latest.document.text(), "d")
}

///|
test "delete success removes only the target record" {
  let documents = State::State(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DeleteConfirmed(source_key("one")),
  )
  guard decisions is [DeleteSource(operation)] else {
    fail("delete should issue immediately")
  }
  let (documents, _) = documents.reduce(
    FeedbackReceived(DeleteCompleted(operation, Deleted(document_id("one")))),
  )
  assert_eq(documents.text(source_key("one")), None)
  assert_eq(documents.text(source_key("two")), Some("two"))
  assert_eq(documents.snapshot().find(document_id("one")), None)
}

///|
test "confirmation waits for the matching save and then deletes" {
  let documents = State::State(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("one"), "new"),
  )
  guard decisions is [Effect::ArmMaximum(_, _)] else { fail("timers") }
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  guard decisions is [Effect::PersistSource(save)] else {
    fail("expected save")
  }
  let (documents, decisions) = documents.reduce(
    DeleteConfirmed(source_key("one")),
  )
  assert_true(decisions.is_empty())
  guard documents.delete_phase_status(source_key("one"))
    is Some(Waiting(delete)) else {
    fail("confirmation must wait")
  }
  let (documents, decisions) = documents.reduce(
    FeedbackReceived(SaveCompleted(save, Stored(save.document))),
  )
  guard decisions is [DeleteSource(_)] else {
    fail("stored save must release delete")
  }
  guard documents.delete_phase_status(source_key("one"))
    is Some(Deleting(active_delete)) &&
    active_delete == delete else {
    fail("delete operation should be preserved")
  }
  assert_true(documents.save_phase(source_key("one")) == Some(Saved))
}

///|
test "duplicate confirmation during waiting deletion preserves original operation" {
  let documents = State::State(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("one"), "new"),
  )
  guard decisions is [Effect::ArmMaximum(_, _)] else { fail("timers") }
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  guard decisions is [Effect::PersistSource(save)] else {
    fail("expected save")
  }
  let (documents, decisions) = documents.reduce(
    DeleteConfirmed(source_key("one")),
  )
  assert_true(decisions.is_empty())
  let before = documents
  let (documents, decisions) = documents.reduce(RetryDelete(source_key("one")))
  assert_true(documents == before)
  assert_true(decisions.is_empty())
  let (documents, decisions) = documents.reduce(
    FeedbackReceived(SaveCompleted(save, Stored(save.document))),
  )
  guard decisions is [DeleteSource(delete)] else { fail("original operation") }
  assert_true(
    documents.delete_phase_status(source_key("one")) == Some(Deleting(delete)),
  )
}

///|
test "duplicate confirmation during deleting preserves original operation" {
  let documents = State::State(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DeleteConfirmed(source_key("one")),
  )
  guard decisions is [DeleteSource(delete)] else { fail("delete") }
  let before = documents
  let (documents, decisions) = documents.reduce(
    DeleteConfirmed(source_key("one")),
  )
  assert_true(documents == before)
  assert_true(decisions.is_empty())
  let (documents, decisions) = documents.reduce(
    FeedbackReceived(DeleteCompleted(delete, Deleted(document_id("one")))),
  )
  assert_true(decisions.is_empty())
  assert_eq(documents.text(source_key("one")), None)
}

///|
test "failed existing save still releases a waiting delete" {
  let documents = State::State(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("one"), "new"),
  )
  guard decisions is [Effect::ArmMaximum(_, _)] else { fail("timers") }
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  guard decisions[0] is PersistSource(save) else { fail("save") }
  let (documents, _) = documents.reduce(DeleteConfirmed(source_key("one")))
  let (_, decisions) = documents.reduce(
    FeedbackReceived(SaveCompleted(save, SaveFailed(WriteFailed))),
  )
  guard decisions is [DeleteSource(_)] else {
    fail("failed existing save must still delete")
  }
}

///|
test "new document deletion is local and does not change snapshot" {
  let documents = State::State(documents_test_snapshot())
  let before = documents.snapshot()
  let (documents, _) = documents.reduce(New(document_id("new")))
  let (documents, decisions) = documents.reduce(
    DeleteConfirmed(source_key("new")),
  )
  assert_true(decisions.is_empty())
  assert_eq(documents.snapshot(), before)
  assert_eq(documents.text(source_key("new")), None)
}

///|
test "new in-flight stored save promotes before deletion" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(New(document_id("new")))
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("new"), "hello"),
  )
  guard decisions is [Effect::ArmMaximum(_, _)] else { fail("timers") }
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit(
      source_key("new"),
      pending_revision(documents, source_key("new")),
    ),
  )
  guard decisions[0] is PersistSource(save) else { fail("save") }
  let (documents, _) = documents.reduce(DeleteConfirmed(source_key("new")))
  let (documents, decisions) = documents.reduce(
    FeedbackReceived(SaveCompleted(save, Stored(save.document))),
  )
  guard decisions[0] is DeleteSource(_) else { fail("delete") }
  guard documents.snapshot().find(document_id("new")) is Some(_) else {
    fail("stored new document must be acknowledged first")
  }
}

///|
test "new in-flight failed save is removed locally" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(New(document_id("new")))
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("new"), "hello"),
  )
  guard decisions is [Effect::ArmMaximum(_, _)] else { fail("timers") }
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit(
      source_key("new"),
      pending_revision(documents, source_key("new")),
    ),
  )
  guard decisions[0] is PersistSource(save) else { fail("save") }
  let (documents, _) = documents.reduce(DeleteConfirmed(source_key("new")))
  let (documents, decisions) = documents.reduce(
    FeedbackReceived(SaveCompleted(save, SaveFailed(WriteFailed))),
  )
  assert_true(decisions.is_empty())
  assert_eq(documents.text(source_key("new")), None)
  assert_eq(documents.snapshot().find(document_id("new")), None)
}

///|
test "retry allocates a fresh operation and fences an active save" {
  let documents = State::State(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DeleteConfirmed(source_key("one")),
  )
  guard decisions[0] is DeleteSource(first) else { fail("delete") }
  let (documents, _) = documents.reduce(
    FeedbackReceived(DeleteCompleted(first, DeleteFailed(WriteFailed))),
  )
  let (documents, stale) = documents.reduce(
    FeedbackReceived(DeleteCompleted(first, Deleted(document_id("one")))),
  )
  assert_true(stale.is_empty())
  assert_eq(documents.text(source_key("one")), Some("one"))
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("one"), "edited"),
  )
  guard decisions is [Effect::ArmMaximum(_, _)] else { fail("timers") }
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  guard decisions[0] is PersistSource(save) else { fail("save") }
  let (documents, decisions) = documents.reduce(RetryDelete(source_key("one")))
  assert_true(decisions.is_empty())
  guard documents.delete_phase_status(source_key("one"))
    is Some(Waiting(second)) else {
    fail("retry must wait for save")
  }
  assert_true(second != first)
  let (_, decisions) = documents.reduce(
    FeedbackReceived(SaveCompleted(save, SaveFailed(WriteFailed))),
  )
  guard decisions[0] is DeleteSource(third) else { fail("release retry") }
  assert_true(third != first && third == second)
}

///|
test "maximum save completion then pending callback accepts source" {
  let documents = State::State(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("one"), "maximum"),
  )
  guard decisions is [ArmMaximum(_, maximum)] else { fail("maximum") }
  let (documents, decisions) = documents.reduce(
    FeedbackReceived(MaximumElapsed(source_key("one"), maximum)),
  )
  guard decisions is [PersistSource(operation)] else { fail("save") }
  let (documents, _) = documents.reduce(
    FeedbackReceived(SaveCompleted(operation, Stored(operation.document))),
  )
  assert_true(
    find_record(documents.records, source_key("one")).unwrap().lead_source
    is LeadSource::Available("one"),
  )
  let revision = pending_revision(documents, source_key("one"))
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit(source_key("one"), revision),
  )
  assert_true(decisions.is_empty())
  assert_true(
    find_record(documents.records, source_key("one")).unwrap().lead_source
    is LeadSource::Available("maximum"),
  )
}

///|
test "failed accepted save then clean revert keeps lead pending without save" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(TextChanged(source_key("one"), "new"))
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  guard decisions is [PersistSource(operation)] else { fail("save") }
  let (documents, _) = documents.reduce(
    FeedbackReceived(SaveCompleted(operation, SaveFailed(WriteFailed))),
  )
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("one"), "one"),
  )
  assert_true(decisions.is_empty())
  assert_true(documents.save_phase(source_key("one")) is Some(Saved))
  assert_true(has_pending(documents, source_key("one")))
}

///|
test "eligible pending latest text waits for delete without an intermediate write" {
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
  let (documents, _) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  let (documents, _) = documents.reduce(DeleteConfirmed(source_key("one")))
  let (documents, decisions) = documents.reduce(
    FeedbackReceived(SaveCompleted(first, Stored(first.document))),
  )
  guard decisions is [DeleteSource(_)] else { fail("delete only") }
  guard documents.save_phase(source_key("one")) is Some(Waiting(_)) else {
    fail("latest checkpoint must remain waiting")
  }
}

///|
test "failed absent New completion removes the record before delete" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(New(document_id("new")))
  let (documents, timer) = documents.reduce(TextChanged(source_key("new"), "x"))
  guard timer is [ArmMaximum(_, _)] else { fail("timer") }
  let (documents, persist) = documents.reduce(
    ApplyPendingEdit(
      source_key("new"),
      pending_revision(documents, source_key("new")),
    ),
  )
  guard persist is [PersistSource(save)] else { fail("save") }
  let (documents, _) = documents.reduce(DeleteConfirmed(source_key("new")))
  let (documents, decisions) = documents.reduce(
    FeedbackReceived(SaveCompleted(save, SaveFailed(WriteFailed))),
  )
  assert_true(decisions.is_empty())
  assert_eq(documents.text(source_key("new")), None)
}

///|
test "failed absent Import completion removes the record before delete" {
  let documents = State::State(documents_test_snapshot())
  let (documents, persist) = documents.reduce(
    Imported(document_id("imported"), "x"),
  )
  guard persist is [PersistSource(save)] else { fail("save") }
  let (documents, _) = documents.reduce(DeleteConfirmed(source_key("imported")))
  let (documents, decisions) = documents.reduce(
    FeedbackReceived(SaveCompleted(save, SaveFailed(WriteFailed))),
  )
  assert_true(decisions.is_empty())
  assert_eq(documents.text(source_key("imported")), None)
}

///|
test "delete success removes acknowledged membership" {
  let documents = State::State(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DeleteConfirmed(source_key("one")),
  )
  guard decisions is [DeleteSource(delete)] else { fail("delete") }
  let (documents, decisions) = documents.reduce(
    FeedbackReceived(DeleteCompleted(delete, Deleted(document_id("one")))),
  )
  assert_true(decisions.is_empty())
  assert_eq(documents.snapshot().find(document_id("one")), None)
}

///|
test "delete failure resumes the retained eligible latest checkpoint" {
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
  let (documents, _) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  let (documents, _) = documents.reduce(DeleteConfirmed(source_key("one")))
  let (documents, delete_decision) = documents.reduce(
    FeedbackReceived(SaveCompleted(first, Stored(first.document))),
  )
  guard delete_decision is [DeleteSource(delete)] else { fail("delete") }
  let (_, latest_save) = documents.reduce(
    FeedbackReceived(DeleteCompleted(delete, DeleteFailed(WriteFailed))),
  )
  guard latest_save is [PersistSource(latest)] else { fail("latest save") }
  assert_eq(latest.document.text(), "latest")
}

///|
