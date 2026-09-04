///|
fn documents_test_snapshot() -> @source_repository.RepositorySnapshot {
  @source_repository.RepositorySnapshot::from_sources([
    @source_repository.SourceRecord::new("one", "one").unwrap(),
    @source_repository.SourceRecord::new("two", "two").unwrap(),
  ]).unwrap()
}

///|
fn documents_test_order(value : Int64) -> @source_repository.ChangeOrder {
  @source_repository.ChangeOrder::from_int64(value).unwrap()
}

///|
fn documents_test_current_order(
  documents : Documents,
  document_id : String,
) -> @source_repository.ChangeOrder {
  find_record(documents.records, document_id).unwrap().source.change_order()
}

///|
test "Import accepts empty text and persists it immediately as New" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DocumentsImported("imported", "", documents_test_order(7L)),
  )
  assert_eq(documents.text("imported"), Some(""))
  guard decisions is [DocumentsDecision::DocumentsPersist(operation)] &&
    operation.origin == DocumentOrigin::New else {
    fail("expected one New persistence decision")
  }
  assert_eq(
    operation.source,
    @source_repository.SourceRecord::new(
      "imported",
      "",
      change_order=documents_test_order(7L),
    ).unwrap(),
  )
}

///|
test "failed Import remains available through the existing Retry" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    DocumentsImported("imported", "text", documents_test_order(7L)),
  )
  guard decisions is [DocumentsPersist(operation)] else { fail("persist") }
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(operation, Failed(WriteFailed))),
  )
  assert_eq(documents.text("imported"), Some("text"))
  guard documents.save_status("imported") is Some(Failed(WriteFailed)) else {
    fail("expected retryable failure")
  }
  let (_, decisions) = documents.reduce(DocumentsRetrySave("imported"))
  guard decisions is [DocumentsPersist(retry)] else { fail("retry") }
  assert_eq(retry.source, operation.source)
}

///|
test "a second document persists while the first document is in flight" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(
    DocumentsTextChanged("one", "one!", documents_test_order(0L)),
  )
  let (documents, first) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", documents_test_order(1L))),
  )
  guard first.length() == 1 &&
    first[0] is DocumentsDecision::DocumentsPersist(first_operation) else {
    fail("first document should persist")
  }
  let (documents, _) = documents.reduce(
    DocumentsTextChanged("two", "two!", documents_test_order(0L)),
  )
  let (documents, second) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("two", documents_test_order(2L))),
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
  let (documents, _) = documents.reduce(
    DocumentsTextChanged("one", "one!", documents_test_order(0L)),
  )
  let (documents, one_decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", documents_test_order(1L))),
  )
  guard one_decisions[0] is DocumentsPersist(one) else { fail("one save") }
  let (documents, _) = documents.reduce(
    DocumentsTextChanged("two", "two!", documents_test_order(0L)),
  )
  let (documents, two_decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("two", documents_test_order(2L))),
  )
  guard two_decisions[0] is DocumentsPersist(two) else { fail("two save") }
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(two, Stored(two.source))),
  )
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(one, Stored(one.source))),
  )
  assert_eq(documents.snapshot().source("one").unwrap().text(), "one!")
  assert_eq(documents.snapshot().source("two").unwrap().text(), "two!")
}

///|
test "inactive save completion updates the latest snapshot" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(
    DocumentsTextChanged("two", "two!", documents_test_order(0L)),
  )
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("two", documents_test_order(1L))),
  )
  guard decisions[0] is DocumentsDecision::DocumentsPersist(operation) else {
    fail("expected persist")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(
      SaveCompleted(
        operation,
        @source_repository.SaveResult::Stored(operation.source),
      ),
    ),
  )
  assert_true(decisions.is_empty())
  assert_eq(documents.snapshot().source("two").unwrap().text(), "two!")
  assert_eq(documents.text("one"), Some("one"))
}

///|
test "composition blocks persistence but keeps fresh order" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsCompositionStarted("one"))
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "one!", documents_test_order(3L)),
  )
  assert_true(decisions.is_empty())
  assert_eq(documents_test_current_order(documents, "one").value(), 3L)
  let (_, decisions) = documents.reduce(DocumentsCompositionEnded("one"))
  assert_eq(decisions.length(), 2)
  guard decisions[0] is DocumentsDecision::DocumentsArmQuiet(_, order) else {
    fail("quiet timer")
  }
  assert_eq(order.value(), 3L)
}

///|
test "checkpoint quiet identity changes while maximum identity stays fresh" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, first) = documents.reduce(
    DocumentsTextChanged("one", "b", documents_test_order(0L)),
  )
  guard first
    is [
      DocumentsDecision::DocumentsArmQuiet(_, quiet),
      DocumentsDecision::DocumentsArmMaximum(_, maximum),
    ] else {
    fail("initial timers")
  }
  assert_eq(quiet.value(), 1L)
  assert_eq(maximum, 1)
  let (_, second) = documents.reduce(
    DocumentsTextChanged("one", "c", documents_test_order(1L)),
  )
  guard second is [DocumentsDecision::DocumentsArmQuiet(_, quiet)] else {
    fail("only quiet is rearmed")
  }
  assert_eq(quiet.value(), 2L)
}

///|
test "returning to operation text while saving preserves final fresh order" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(
    DocumentsTextChanged("one", "b", documents_test_order(0L)),
  )
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", documents_test_order(1L))),
  )
  guard decisions[0] is DocumentsDecision::DocumentsPersist(operation) else {
    fail("expected persist")
  }
  let (documents, _) = documents.reduce(
    DocumentsTextChanged("one", "one", documents_test_order(1L)),
  )
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", documents_test_order(2L))),
  )
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(
      SaveCompleted(
        operation,
        @source_repository.SaveResult::Stored(operation.source),
      ),
    ),
  )
  guard decisions[0] is DocumentsDecision::DocumentsPersist(next) else {
    fail("latest candidate must persist")
  }
  assert_eq(next.source.text(), "one")
  assert_eq(next.source.change_order().value(), 2L)
  assert_eq(documents.snapshot().source("one").unwrap().text(), "b")
}

///|
test "deferred and eligible failures preserve or promote pending checkpoint" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(
    DocumentsTextChanged("one", "b", documents_test_order(0L)),
  )
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", documents_test_order(1L))),
  )
  guard decisions[0] is DocumentsDecision::DocumentsPersist(operation) else {
    fail("expected persist")
  }
  let (documents, _) = documents.reduce(
    DocumentsTextChanged("one", "c", documents_test_order(1L)),
  )
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(
      SaveCompleted(
        operation,
        @source_repository.SaveResult::Failed(
          @source_repository.SaveFailure::WriteFailed,
        ),
      ),
    ),
  )
  guard documents.save_status("one") is Some(Waiting(_)) else {
    fail("deferred failure waits")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", documents_test_order(2L))),
  )
  guard decisions[0] is DocumentsDecision::DocumentsPersist(retry_operation) else {
    fail("waiting retry")
  }
  let (documents, _) = documents.reduce(
    DocumentsTextChanged("one", "d", documents_test_order(2L)),
  )
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", documents_test_order(3L))),
  )
  let (_, retry) = documents.reduce(
    DocumentsFeedbackReceived(
      SaveCompleted(
        retry_operation,
        @source_repository.SaveResult::Failed(
          @source_repository.SaveFailure::WriteFailed,
        ),
      ),
    ),
  )
  guard retry[0] is DocumentsDecision::DocumentsPersist(latest) else {
    fail("eligible failure promotes")
  }
  assert_eq(latest.source.text(), "d")
}

///|
test "stale timers and mismatched stored records are ignored" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(
    DocumentsTextChanged("one", "b", documents_test_order(0L)),
  )
  let (documents, _) = documents.reduce(
    DocumentsTextChanged("one", "c", documents_test_order(1L)),
  )
  let (documents, stale_max) = documents.reduce(
    DocumentsFeedbackReceived(MaximumElapsed("one", 99)),
  )
  assert_true(stale_max.is_empty())
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", documents_test_order(2L))),
  )
  guard decisions is [DocumentsDecision::DocumentsPersist(operation)] else {
    fail("latest quiet")
  }
  let bogus = @source_repository.SourceRecord::new(
    "one",
    "c",
    change_order=documents_test_order(99L),
  ).unwrap()
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(
      SaveCompleted(operation, @source_repository.SaveResult::Stored(bogus)),
    ),
  )
  assert_eq(documents.snapshot().source("one").unwrap().text(), "one")
}

///|
test "the global floor orders edits across old documents" {
  let snapshot = @source_repository.RepositorySnapshot::from_sources([
    @source_repository.SourceRecord::new(
      "one",
      "one",
      change_order=documents_test_order(100L),
    ).unwrap(),
    @source_repository.SourceRecord::new(
      "two",
      "two",
      change_order=documents_test_order(5L),
    ).unwrap(),
  ]).unwrap()
  let documents = initial_documents(snapshot)
  let (documents, _) = documents.reduce(
    DocumentsTextChanged("two", "two!", documents_test_order(10L)),
  )
  assert_eq(documents_test_current_order(documents, "two").value(), 101L)
  let (documents, _) = documents.reduce(
    DocumentsTextChanged("one", "one!", documents_test_order(0L)),
  )
  assert_eq(documents_test_current_order(documents, "one").value(), 102L)
}

///|
test "duplicate text changes preserve documents and decisions" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(
    DocumentsTextChanged("one", "one!", documents_test_order(0L)),
  )
  let before = documents
  let (after, decisions) = documents.reduce(
    DocumentsTextChanged("one", "one!", documents_test_order(99L)),
  )
  assert_true(after == before)
  assert_true(decisions.is_empty())
}

///|
test "composition defers timers for an in-flight save until it ends" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(
    DocumentsTextChanged("one", "one!", documents_test_order(0L)),
  )
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", documents_test_order(1L))),
  )
  guard decisions[0] is DocumentsDecision::DocumentsPersist(_) else {
    fail("expected in-flight save")
  }
  let (documents, _) = documents.reduce(DocumentsCompositionStarted("one"))
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "one!!", documents_test_order(1L)),
  )
  assert_true(decisions.is_empty())
  guard documents.save_status("one") is Some(Saving(_, Some(_))) else {
    fail("composition change should be pending")
  }
  let (_, decisions) = documents.reduce(DocumentsCompositionEnded("one"))
  assert_eq(decisions.length(), 2)
}

///|
test "delete success removes only the target record" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(DeleteConfirmed("one"))
  guard decisions is [DeleteSource(operation), ArmDeleteWatchdog(_)] else {
    fail("delete should issue immediately")
  }
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(
      DeleteCompleted(
        operation,
        @source_repository.DeleteResult::Deleted("one"),
      ),
    ),
  )
  assert_eq(documents.text("one"), None)
  assert_eq(documents.text("two"), Some("two"))
  assert_eq(documents.snapshot().source("one"), None)
}

///|
test "delete watchdog probes and missing confirms deletion" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(DeleteConfirmed("one"))
  guard decisions is [DeleteSource(operation), ArmDeleteWatchdog(_)] else {
    fail("delete should issue immediately")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(DeleteWatchdogElapsed(operation)),
  )
  guard decisions is [ProbeDelete(_), ArmProbeWatchdog(_)] else {
    fail("watchdog should probe")
  }
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(DeleteProbeCompleted(operation, Missing)),
  )
  assert_eq(documents.text("one"), None)
}

///|
test "confirmation waits for the matching save and then deletes" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(
    DocumentsTextChanged("one", "new", documents_test_order(0L)),
  )
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", documents_test_order(1L))),
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
    DocumentsFeedbackReceived(SaveCompleted(save, Stored(save.source))),
  )
  guard decisions is [DeleteSource(_), ArmDeleteWatchdog(_)] else {
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
  let (documents, _) = documents.reduce(
    DocumentsTextChanged("one", "new", documents_test_order(0L)),
  )
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", documents_test_order(1L))),
  )
  guard decisions[0] is DocumentsPersist(save) else { fail("save") }
  let (documents, _) = documents.reduce(DeleteConfirmed("one"))
  let (_, decisions) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(save, Failed(WriteFailed))),
  )
  guard decisions is [DeleteSource(_), ArmDeleteWatchdog(_)] else {
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
  let (documents, _) = documents.reduce(
    DocumentsTextChanged("new", "hello", documents_test_order(0L)),
  )
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("new", documents_test_order(1L))),
  )
  guard decisions[0] is DocumentsPersist(save) else { fail("save") }
  let (documents, _) = documents.reduce(DeleteConfirmed("new"))
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(save, Stored(save.source))),
  )
  guard decisions[0] is DeleteSource(_) else { fail("delete") }
  guard documents.snapshot().source("new") is Some(_) else {
    fail("stored new document must be acknowledged first")
  }
}

///|
test "new in-flight failed save is removed locally" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsNew("new"))
  let (documents, _) = documents.reduce(
    DocumentsTextChanged("new", "hello", documents_test_order(0L)),
  )
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("new", documents_test_order(1L))),
  )
  guard decisions[0] is DocumentsPersist(save) else { fail("save") }
  let (documents, _) = documents.reduce(DeleteConfirmed("new"))
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(save, Failed(WriteFailed))),
  )
  assert_true(decisions.is_empty())
  assert_eq(documents.text("new"), None)
  assert_eq(documents.snapshot().source("new"), None)
}

///|
test "retry allocates a fresh operation and fences an active save" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(DeleteConfirmed("one"))
  guard decisions[0] is DeleteSource(first) else { fail("delete") }
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(
      DeleteCompleted(
        first,
        @source_repository.DeleteResult::Failed(
          @source_repository.DeleteFailure::WriteFailed,
        ),
      ),
    ),
  )
  let (documents, _) = documents.reduce(
    DocumentsTextChanged("one", "edited", documents_test_order(0L)),
  )
  let (documents, decisions) = documents.reduce(
    DocumentsFeedbackReceived(QuietElapsed("one", documents_test_order(1L))),
  )
  guard decisions[0] is DocumentsPersist(save) else { fail("save") }
  let (documents, decisions) = documents.reduce(RetryDelete("one"))
  assert_true(decisions.is_empty())
  guard documents.delete_status("one") is Some(Waiting(second)) else {
    fail("retry must wait for save")
  }
  assert_true(second != first)
  let (_, decisions) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(save, Failed(WriteFailed))),
  )
  guard decisions[0] is DeleteSource(third) else { fail("release retry") }
  assert_true(third != first && third == second)
}

///|
test "probe outcomes and timeout become unknown while unrelated work proceeds" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(DeleteConfirmed("one"))
  guard decisions[0] is DeleteSource(operation) else { fail("delete") }
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(DeleteWatchdogElapsed(operation)),
  )
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(
      DeleteProbeCompleted(
        operation,
        @source_repository.ProbeResult::Present(
          documents_test_snapshot().source("one").unwrap(),
        ),
      ),
    ),
  )
  guard documents.delete_status("one") is Some(Unknown(_)) else {
    fail("present probe")
  }
  let (_, decisions) = documents.reduce(
    DocumentsTextChanged("two", "two!", documents_test_order(0L)),
  )
  assert_true(decisions.length() > 0)
}

///|
test "unsupported failed and timed out probes become unknown" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(DeleteConfirmed("one"))
  guard decisions[0] is DeleteSource(operation) else { fail("delete") }
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(DeleteWatchdogElapsed(operation)),
  )
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(DeleteProbeCompleted(operation, Unsupported)),
  )
  guard documents.delete_status("one") is Some(Unknown(_)) else {
    fail("unsupported probe")
  }
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(DeleteConfirmed("one"))
  guard decisions[0] is DeleteSource(operation) else { fail("delete") }
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(DeleteWatchdogElapsed(operation)),
  )
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(
      DeleteProbeCompleted(
        operation,
        @source_repository.ProbeResult::Failed(
          @source_repository.ProbeFailure::ReadFailed,
        ),
      ),
    ),
  )
  guard documents.delete_status("one") is Some(Unknown(_)) else {
    fail("failed probe")
  }
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(DeleteConfirmed("one"))
  guard decisions[0] is DeleteSource(operation) else { fail("delete") }
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(DeleteWatchdogElapsed(operation)),
  )
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(DeleteProbeElapsed(operation)),
  )
  guard documents.delete_status("one") is Some(Unknown(_)) else {
    fail("probe timeout")
  }
}

///|
test "late delete failure restores availability and late success empties snapshot" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(DeleteConfirmed("one"))
  guard decisions[0] is DeleteSource(operation) else { fail("delete") }
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(DeleteWatchdogElapsed(operation)),
  )
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(DeleteProbeElapsed(operation)),
  )
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(
      DeleteCompleted(
        operation,
        @source_repository.DeleteResult::Failed(
          @source_repository.DeleteFailure::WriteFailed,
        ),
      ),
    ),
  )
  guard documents.delete_status("one") is Some(Failed(_, _)) else {
    fail("late failure restores")
  }
  let (documents, decisions) = documents.reduce(RetryDelete("one"))
  guard decisions[0] is DeleteSource(next) else { fail("retry") }
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(
      DeleteCompleted(next, @source_repository.DeleteResult::Deleted("one")),
    ),
  )
  assert_eq(documents.snapshot().source("one"), None)
}

///|
test "change order exhaustion keeps authority unchanged and fails" {
  let max = documents_test_order(9_007_199_254_740_991L)
  let snapshot = @source_repository.RepositorySnapshot::from_sources([
    @source_repository.SourceRecord::new("one", "one", change_order=max).unwrap(),
  ]).unwrap()
  let documents = initial_documents(snapshot)
  let (documents, _) = documents.reduce(
    DocumentsTextChanged("one", "changed", max),
  )
  assert_eq(documents.text("one"), Some("one"))
  assert_eq(documents_test_current_order(documents, "one").value(), max.value())
  guard documents.save_status("one")
    is Some(Failed(@source_repository.SaveFailure::ChangeOrderExhausted)) else {
    fail("exhaustion fails")
  }
  let (documents, decisions) = documents.reduce(
    DocumentsImported("imported", "text", max),
  )
  assert_eq(documents.text("imported"), None)
  assert_true(decisions.is_empty())
}
