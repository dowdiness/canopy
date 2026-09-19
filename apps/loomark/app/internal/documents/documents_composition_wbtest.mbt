/// Tests are organized by reducer contract; fixtures and extraction helpers remain shared.

///|
test "composition blocks persistence but keeps fresh revision" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(CompositionStarted(source_key("one")))
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("one"), "one!"),
  )
  assert_true(decisions.is_empty())
  guard find_record(documents.records, source_key("one")).unwrap().save
    is Waiting(_) else {
    fail("waiting checkpoint")
  }
  assert_eq(pending_revision(documents, source_key("one")), 1)
  let (documents, decisions) = documents.reduce(
    CompositionEnded(source_key("one")),
  )
  guard decisions is [Effect::ArmMaximum(_, _)] else { fail("maximum") }
  assert_true(has_pending(documents, source_key("one")))
}

///|
test "pending revision advances while maximum identity stays fresh" {
  let documents = State::State(documents_test_snapshot())
  let (documents, first) = documents.reduce(TextChanged(source_key("one"), "b"))
  guard first is [Effect::ArmMaximum(_, maximum)] else {
    fail("initial timers")
  }
  assert_eq(pending_revision(documents, source_key("one")), 1)
  assert_eq(maximum, 1)
  let (documents, second) = documents.reduce(
    TextChanged(source_key("one"), "c"),
  )
  assert_true(second.is_empty())
  assert_eq(pending_revision(documents, source_key("one")), 2)
}

///|
test "maximum eligibility persists latest text during uninterrupted editing" {
  let documents = State::State(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("one"), "b"),
  )
  guard decisions is [Effect::ArmMaximum(_, maximum)] else {
    fail("initial timers")
  }
  let (documents, _) = documents.reduce(TextChanged(source_key("one"), "c"))
  let (_, decisions) = documents.reduce(
    FeedbackReceived(MaximumElapsed(source_key("one"), maximum)),
  )
  guard decisions is [Effect::PersistSource(operation)] else {
    fail("maximum persist")
  }
  assert_eq(operation.document.text(), "c")
  guard find_record(documents.records, source_key("one")).unwrap().save
    is Waiting(_) ||
    find_record(documents.records, source_key("one")).unwrap().save
    is Saving(_, _) else {
    fail("pending")
  }
}

///|
test "composition defers timers for an in-flight save until it ends" {
  let documents = State::State(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("one"), "one!"),
  )
  guard decisions is [Effect::ArmMaximum(_, _)] else { fail("timers") }
  let (documents, decisions) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  guard decisions[0] is Effect::PersistSource(_) else {
    fail("expected in-flight save")
  }
  let (documents, _) = documents.reduce(CompositionStarted(source_key("one")))
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("one"), "one!!"),
  )
  assert_true(decisions.is_empty())
  guard documents.save_phase(source_key("one")) is Some(Saving(_, Some(_))) else {
    fail("composition change should be pending")
  }
  let (documents, decisions) = documents.reduce(
    CompositionEnded(source_key("one")),
  )
  guard decisions is [Effect::ArmMaximum(_, _)] else { fail("maximum") }
  assert_true(has_pending(documents, source_key("one")))
}

///|
test "visibility makes an in-flight save's latest checkpoint eligible" {
  let documents = State::State(documents_test_snapshot())
  let (documents, timers) = documents.reduce(
    TextChanged(source_key("one"), "first"),
  )
  guard timers is [Effect::ArmMaximum(_, _)] else { fail("initial timers") }
  let (documents, persist) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  guard persist is [Effect::PersistSource(operation)] else {
    fail("first save")
  }
  let (documents, _) = documents.reduce(
    TextChanged(source_key("one"), "latest"),
  )
  let (documents, flush) = documents.reduce(VisibilityFlush(source_key("one")))
  assert_true(flush.is_empty())
  let (_, follow_up) = documents.reduce(
    FeedbackReceived(SaveCompleted(operation, Stored(operation.document))),
  )
  guard follow_up is [Effect::PersistSource(latest)] else {
    fail("eligible follow-up")
  }
  assert_eq(latest.document.text(), "latest")
}

///|
test "duplicate composition end emits one maximum decision" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(CompositionStarted(source_key("one")))
  let (documents, _) = documents.reduce(TextChanged(source_key("one"), "first"))
  let (documents, first) = documents.reduce(CompositionEnded(source_key("one")))
  guard first is [Effect::ArmMaximum(_, _)] else {
    fail("first composition end should arm maximum")
  }
  let (_, second) = documents.reduce(CompositionEnded(source_key("one")))
  assert_true(second.is_empty())
}

///|
test "genuine composition cycles arm maximum once with saving pending" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(CompositionStarted(source_key("one")))
  let (documents, _) = documents.reduce(TextChanged(source_key("one"), "first"))
  let (documents, first) = documents.reduce(CompositionEnded(source_key("one")))
  guard first is [Effect::ArmMaximum(_, _)] else { fail("first cycle maximum") }
  let (documents, _) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  guard documents.save_phase(source_key("one")) is Some(Saving(_, _)) else {
    fail("first cycle should be saving")
  }
  let (documents, _) = documents.reduce(CompositionStarted(source_key("one")))
  let (documents, _) = documents.reduce(
    TextChanged(source_key("one"), "second"),
  )
  let (documents, second) = documents.reduce(
    CompositionEnded(source_key("one")),
  )
  guard second is [Effect::ArmMaximum(_, _)] else {
    fail("second cycle maximum")
  }
  let (_, duplicate) = documents.reduce(CompositionEnded(source_key("one")))
  assert_true(duplicate.is_empty())
}

///|
test "queued composition callback applies immediately at composition end" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(TextChanged(source_key("one"), "new"))
  let revision = pending_revision(documents, source_key("one"))
  let (documents, _) = documents.reduce(CompositionStarted(source_key("one")))
  let (documents, _) = documents.reduce(
    ApplyPendingEdit(source_key("one"), revision),
  )
  let (documents, _) = documents.reduce(CompositionEnded(source_key("one")))
  assert_true(
    find_record(documents.records, source_key("one")).unwrap().lead_source
    is LeadSource::Available("new"),
  )
  assert_true(!has_pending(documents, source_key("one")))
}

///|
test "composition end without callback does not accept the edit" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(CompositionStarted(source_key("one")))
  let (documents, _) = documents.reduce(TextChanged(source_key("one"), "ime"))
  let (documents, _) = documents.reduce(CompositionEnded(source_key("one")))
  assert_true(
    find_record(documents.records, source_key("one")).unwrap().lead_source
    is LeadSource::Available("one"),
  )
  assert_true(has_pending(documents, source_key("one")))
}

///|
test "IME callback then newer edit waits for latest pending revision" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(
    TextChanged(source_key("one"), "composed"),
  )
  let initial_revision = pending_revision(documents, source_key("one"))
  let (documents, _) = documents.reduce(CompositionStarted(source_key("one")))
  let (documents, _) = documents.reduce(
    ApplyPendingEdit(source_key("one"), initial_revision),
  )
  let (documents, _) = documents.reduce(TextChanged(source_key("one"), "newer"))
  let (documents, _) = documents.reduce(CompositionEnded(source_key("one")))
  assert_true(
    find_record(documents.records, source_key("one")).unwrap().lead_source
    is LeadSource::Available("one"),
  )
  let revision = pending_revision(documents, source_key("one"))
  let (documents, _) = documents.reduce(
    ApplyPendingEdit(source_key("one"), revision),
  )
  assert_true(
    find_record(documents.records, source_key("one")).unwrap().lead_source
    is LeadSource::Available("newer"),
  )
}

///|
test "composition end with no newer edit starts one pending subscription" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(CompositionStarted(source_key("one")))
  let (documents, _) = documents.reduce(
    TextChanged(source_key("one"), "composed"),
  )
  let (documents, decisions) = documents.reduce(
    CompositionEnded(source_key("one")),
  )
  guard decisions is [ArmMaximum(_, _)] else { fail("maximum") }
  assert_true(has_pending(documents, source_key("one")))
}

///|
test "composition end does not duplicate an already pending edit" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(
    TextChanged(source_key("one"), "changed"),
  )
  let (documents, _) = documents.reduce(CompositionStarted(source_key("one")))
  let (documents, _) = documents.reduce(CompositionEnded(source_key("one")))
  assert_true(has_pending(documents, source_key("one")))
}

///|
test "eligible maximum during composition persists at composition end" {
  let documents = State::State(documents_test_snapshot())
  let (documents, decisions) = documents.reduce(
    TextChanged(source_key("one"), "changed"),
  )
  guard decisions is [ArmMaximum(_, maximum)] else { fail("maximum") }
  let (documents, decisions) = documents.reduce(
    CompositionStarted(source_key("one")),
  )
  assert_true(decisions.is_empty())
  let (documents, decisions) = documents.reduce(
    FeedbackReceived(MaximumElapsed(source_key("one"), maximum)),
  )
  assert_true(decisions.is_empty())
  let (documents, decisions) = documents.reduce(
    CompositionEnded(source_key("one")),
  )
  guard decisions is [PersistSource(_)] else { fail("persist") }
  assert_true(has_pending(documents, source_key("one")))
}

///|
test "duplicate composition starts preserve waiting and ready evidence" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(
    TextChanged(source_key("one"), "changed"),
  )
  let revision = pending_revision(documents, source_key("one"))
  let (documents, _) = documents.reduce(CompositionStarted(source_key("one")))
  let (documents, _) = documents.reduce(CompositionStarted(source_key("one")))
  match find_record(documents.records, source_key("one")).unwrap().edit {
    ComposingWaiting(waiting_revision) => assert_eq(waiting_revision, revision)
    _ => fail("waiting evidence")
  }
  let (documents, _) = documents.reduce(
    ApplyPendingEdit(source_key("one"), revision),
  )
  let (documents, _) = documents.reduce(CompositionStarted(source_key("one")))
  assert_true(
    find_record(documents.records, source_key("one")).unwrap().edit
    is ComposingReady,
  )
}

/// A ready composition end accepts the record and starts exactly one save.

///|
test "ready composition end persists once" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(CompositionStarted(source_key("one")))
  let (documents, _) = documents.reduce(
    TextChanged(source_key("one"), "composed"),
  )
  let revision = pending_revision(documents, source_key("one"))
  let (documents, _) = documents.reduce(
    ApplyPendingEdit(source_key("one"), revision),
  )
  let (documents, decisions) = documents.reduce(
    CompositionEnded(source_key("one")),
  )
  guard decisions is [PersistSource(operation)] else { fail("persist") }
  assert_true(
    find_record(documents.records, source_key("one")).unwrap().edit is Idle,
  )
  let (_, duplicate) = documents.reduce(CompositionEnded(source_key("one")))
  assert_true(duplicate.is_empty())
  ignore(operation)
}

/// A ready callback remains evidence when the final text event is unchanged.

///|
test "matching final text keeps ready evidence" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(CompositionStarted(source_key("one")))
  let (documents, _) = documents.reduce(TextChanged(source_key("one"), "same"))
  let revision = pending_revision(documents, source_key("one"))
  let (documents, _) = documents.reduce(
    ApplyPendingEdit(source_key("one"), revision),
  )
  let (documents, _) = documents.reduce(TextChanged(source_key("one"), "same"))
  assert_true(
    find_record(documents.records, source_key("one")).unwrap().edit
    is ComposingReady,
  )
  let (documents, decisions) = documents.reduce(
    CompositionEnded(source_key("one")),
  )
  guard decisions is [PersistSource(_)] else { fail("persist") }
  assert_true(
    find_record(documents.records, source_key("one")).unwrap().lead_source
    is LeadSource::Available("same"),
  )
}

/// An accepted composition queues exactly one follow-up behind an in-flight save.

///|
test "ready composition end marks in-flight follow-up eligible once" {
  let documents = State::State(documents_test_snapshot())
  let (documents, first) = documents.reduce(
    TextChanged(source_key("one"), "first"),
  )
  guard first is [ArmMaximum(_, _)] else { fail("timer") }
  let (documents, first) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  guard first is [PersistSource(operation)] else { fail("first save") }
  let (documents, _) = documents.reduce(CompositionStarted(source_key("one")))
  let (documents, _) = documents.reduce(
    TextChanged(source_key("one"), "latest"),
  )
  let (documents, _) = documents.reduce(
    ApplyPendingEdit(
      source_key("one"),
      pending_revision(documents, source_key("one")),
    ),
  )
  let (documents, decisions) = documents.reduce(
    CompositionEnded(source_key("one")),
  )
  assert_true(decisions.is_empty())
  guard documents.save_phase(source_key("one"))
    is Some(Saving(_, Some(checkpoint))) else {
    fail("eligible queued checkpoint")
  }
  assert_true(
    checkpoint.eligibility == DocumentsCheckpointEligibility::Eligible,
  )
  let (_, follow_up) = documents.reduce(
    FeedbackReceived(SaveCompleted(operation, Stored(operation.document))),
  )
  guard follow_up is [PersistSource(latest)] else { fail("one follow-up") }
  assert_eq(latest.document.text(), "latest")
}

/// A composition end outside composition is not a save event.

///|
test "composition end outside composition is ignored" {
  let documents = State::State(documents_test_snapshot())
  let (documents, _) = documents.reduce(
    TextChanged(source_key("one"), "changed"),
  )
  let before = documents
  let (documents, decisions) = documents.reduce(
    CompositionEnded(source_key("one")),
  )
  assert_true(documents == before)
  assert_true(decisions.is_empty())
}

/// A stale callback must not reach a replacement record with the same ID.

///|
