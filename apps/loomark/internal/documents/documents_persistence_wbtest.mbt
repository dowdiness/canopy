///|
fn persistence_applied(outcome : Update) -> (Model, ReadOnlyArray[Action]) {
  match outcome {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => abort("expected current update to apply")
  }
}

///|
fn persistence_changed(
  _model : Model,
  outcome : Edit,
) -> (Model, ReadOnlyArray[Action]) {
  match outcome {
    Changed(transition) => (transition.model, transition.effects)
    SameText => abort("expected changed text")
  }
}

///|
fn persistence_deleted(
  _model : Model,
  outcome : Delete,
) -> (Model, ReadOnlyArray[Action]) {
  match outcome {
    Accepted(transition) => (transition.model, transition.effects)
    AlreadyPending => abort("expected accepted deletion")
  }
}

///|
test "failed Import remains available through the existing Retry" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, decisions) = persistence_applied(
    documents.update(Imported(document_id("imported"), "text")),
  )
  guard decisions is [PersistSource(operation)] else { fail("persist") }
  let (documents, _) = persistence_applied(
    documents.update(SaveFailed(operation, WriteFailed)),
  )
  assert_eq(documents.text(source_key("imported")), Some("text"))
  guard documents.save_status(source_key("imported"))
    is Some(SaveStatus::SaveFailed(WriteFailed)) else {
    fail("expected retryable failure")
  }
  let (_, decisions) = persistence_applied(
    documents.update(RetrySave(source_key("imported"))),
  )
  guard decisions is [PersistSource(retry)] else { fail("retry") }
  assert_eq(retry.document, operation.document)
}

///|
test "failed Import deletion is local because it was never saved" {
  let documents = Model::Model(documents_test_snapshot())
  let before = documents.snapshot()
  let (documents, decisions) = persistence_applied(
    documents.update(Imported(document_id("imported"), "text")),
  )
  guard decisions is [PersistSource(operation)] else { fail("persist") }
  let (documents, _) = persistence_applied(
    documents.update(SaveFailed(operation, WriteFailed)),
  )
  let (documents, decisions) = persistence_deleted(
    documents,
    documents.delete(source_key("imported")),
  )
  assert_true(decisions.is_empty())
  assert_eq(documents.snapshot(), before)
  assert_eq(documents.text(source_key("imported")), None)
}

///|
test "a second document persists while the first document is in flight" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, decisions) = persistence_changed(
    documents,
    documents.edit(source_key("one"), "one!"),
  )
  guard decisions is [Action::ArmMaximum(_)] else { fail("initial timers") }
  let (documents, first) = persistence_applied(
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ),
  )
  guard first.length() == 1 &&
    first[0] is Action::PersistSource(first_operation) else {
    fail("first document should persist")
  }
  let (documents, decisions) = persistence_changed(
    documents,
    documents.edit(source_key("two"), "two!"),
  )
  guard decisions is [Action::ArmMaximum(_)] else { fail("two timers") }
  let (documents, second) = persistence_applied(
    documents.update(
      ApplyPendingEdit(
        source_key("two"),
        pending_revision(documents, source_key("two")),
      ),
    ),
  )
  guard second.length() == 1 &&
    second[0] is Action::PersistSource(second_operation) else {
    fail("second document should persist")
  }
  assert_true(first_operation != second_operation)
  guard documents.save_status(source_key("one")) is Some(SaveStatus::Unsaved) else {
    fail("one remains in flight")
  }
  guard documents.save_status(source_key("two")) is Some(SaveStatus::Unsaved) else {
    fail("two is in flight")
  }
}

///|
test "reverse save acknowledgments merge into the latest snapshot" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, decisions) = persistence_changed(
    documents,
    documents.edit(source_key("one"), "one!"),
  )
  guard decisions is [Action::ArmMaximum(_)] else { fail("one timers") }
  let (documents, one_decisions) = persistence_applied(
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ),
  )
  guard one_decisions[0] is PersistSource(one) else { fail("one save") }
  let (documents, decisions) = persistence_changed(
    documents,
    documents.edit(source_key("two"), "two!"),
  )
  guard decisions is [Action::ArmMaximum(_)] else { fail("two timers") }
  let (documents, two_decisions) = persistence_applied(
    documents.update(
      ApplyPendingEdit(
        source_key("two"),
        pending_revision(documents, source_key("two")),
      ),
    ),
  )
  guard two_decisions[0] is PersistSource(two) else { fail("two save") }
  let (documents, _) = persistence_applied(
    documents.update(Saved(two, two.document)),
  )
  let (documents, _) = persistence_applied(
    documents.update(Saved(one, one.document)),
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
  let documents = Model::Model(documents_test_snapshot())
  let (documents, decisions) = persistence_changed(
    documents,
    documents.edit(source_key("two"), "two!"),
  )
  guard decisions is [Action::ArmMaximum(_)] else { fail("timers") }
  let (documents, decisions) = persistence_applied(
    documents.update(
      ApplyPendingEdit(
        source_key("two"),
        pending_revision(documents, source_key("two")),
      ),
    ),
  )
  guard decisions[0] is Action::PersistSource(operation) else {
    fail("expected persist")
  }
  let (documents, decisions) = persistence_applied(
    documents.update(Saved(operation, operation.document)),
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
  let documents = Model::Model(documents_test_snapshot())
  let (documents, decisions) = persistence_changed(
    documents,
    documents.edit(source_key("one"), "b"),
  )
  guard decisions is [Action::ArmMaximum(_)] else { fail("timers") }
  let (documents, decisions) = persistence_applied(
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ),
  )
  guard decisions[0] is Action::PersistSource(operation) else {
    fail("expected persist")
  }
  let (documents, decisions) = persistence_changed(
    documents,
    documents.edit(source_key("one"), "one"),
  )
  guard decisions is [Action::ArmMaximum(_)] else {
    fail("new save window timers")
  }
  assert_true(has_pending(documents, source_key("one")))
  let (documents, decisions) = persistence_applied(
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ),
  )
  assert_true(decisions.is_empty())
  let (documents, decisions) = persistence_applied(
    documents.update(Saved(operation, operation.document)),
  )
  guard decisions is [Action::PersistSource(next)] else {
    fail("latest candidate must persist")
  }
  assert_eq(next.document.text(), "one")
  assert_eq(next.document.id(), document_id("one"))
  assert_eq(documents.snapshot().find(document_id("one")).unwrap().text(), "b")
}

///|
test "deferred and eligible failures preserve or promote pending replica" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, decisions) = persistence_changed(
    documents,
    documents.edit(source_key("one"), "b"),
  )
  guard decisions is [Action::ArmMaximum(_)] else { fail("timers") }
  let (documents, decisions) = persistence_applied(
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ),
  )
  guard decisions[0] is Action::PersistSource(operation) else {
    fail("expected persist")
  }
  let (documents, decisions) = persistence_changed(
    documents,
    documents.edit(source_key("one"), "c"),
  )
  guard decisions is [Action::ArmMaximum(_)] else {
    fail("pending save window timers")
  }
  let (documents, _) = persistence_applied(
    documents.update(SaveFailed(operation, WriteFailed)),
  )
  guard documents.save_status(source_key("one")) is Some(SaveStatus::Unsaved) else {
    fail("deferred failure waits")
  }
  let (documents, decisions) = persistence_applied(
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ),
  )
  guard decisions[0] is Action::PersistSource(retry_operation) else {
    fail("waiting retry")
  }
  let (documents, decisions) = persistence_changed(
    documents,
    documents.edit(source_key("one"), "d"),
  )
  guard decisions is [Action::ArmMaximum(_)] else {
    fail("latest save window timers")
  }
  let (documents, eligible) = persistence_applied(
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ),
  )
  assert_true(eligible.is_empty())
  let (_, retry) = persistence_applied(
    documents.update(SaveFailed(retry_operation, WriteFailed)),
  )
  guard retry[0] is Action::PersistSource(latest) else {
    fail("eligible failure promotes")
  }
  assert_eq(latest.document.text(), "d")
}

///|
test "delete success removes only the target record" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, decisions) = persistence_deleted(
    documents,
    documents.delete(source_key("one")),
  )
  guard decisions is [DeleteSource(operation)] else {
    fail("delete should issue immediately")
  }
  let (documents, _) = persistence_applied(
    documents.update(Deleted(operation, document_id("one"))),
  )
  assert_eq(documents.text(source_key("one")), None)
  assert_eq(documents.text(source_key("two")), Some("two"))
  assert_eq(documents.snapshot().find(document_id("one")), None)
}

///|
test "confirmation waits for the matching save and then deletes" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, decisions) = persistence_changed(
    documents,
    documents.edit(source_key("one"), "new"),
  )
  guard decisions is [Action::ArmMaximum(_)] else { fail("timers") }
  let (documents, decisions) = persistence_applied(
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ),
  )
  guard decisions is [Action::PersistSource(save)] else {
    fail("expected save")
  }
  let (documents, decisions) = persistence_deleted(
    documents,
    documents.delete(source_key("one")),
  )
  assert_true(decisions.is_empty())
  guard documents.delete_status(source_key("one"))
    is Some(DeleteStatus::DeletePending) else {
    fail("confirmation must wait")
  }
  let (documents, decisions) = persistence_applied(
    documents.update(Saved(save, save.document)),
  )
  guard decisions is [DeleteSource(_)] else {
    fail("stored save must release delete")
  }
  guard documents.delete_status(source_key("one"))
    is Some(DeleteStatus::DeletePending) else {
    fail("delete operation should be preserved")
  }
  assert_true(
    documents.save_status(source_key("one")) is Some(SaveStatus::Clean),
  )
}

///|
test "duplicate confirmation during waiting deletion preserves original operation" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, decisions) = persistence_changed(
    documents,
    documents.edit(source_key("one"), "new"),
  )
  guard decisions is [Action::ArmMaximum(_)] else { fail("timers") }
  let (documents, decisions) = persistence_applied(
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ),
  )
  guard decisions is [Action::PersistSource(save)] else {
    fail("expected save")
  }
  let (documents, decisions) = persistence_deleted(
    documents,
    documents.delete(source_key("one")),
  )
  assert_true(decisions.is_empty())
  let before = documents
  assert_true(documents.delete(source_key("one")) is AlreadyPending)
  assert_true(documents == before)
  let (documents, decisions) = persistence_applied(
    documents.update(Saved(save, save.document)),
  )
  guard decisions is [DeleteSource(_)] else { fail("original operation") }
  assert_true(
    documents.delete_status(source_key("one")) ==
    Some(DeleteStatus::DeletePending),
  )
}

///|
test "duplicate confirmation during deleting preserves original operation" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, decisions) = persistence_deleted(
    documents,
    documents.delete(source_key("one")),
  )
  guard decisions is [DeleteSource(delete)] else { fail("delete") }
  let before = documents
  assert_true(documents.delete(source_key("one")) is AlreadyPending)
  assert_true(documents == before)
  let (documents, decisions) = persistence_applied(
    documents.update(Deleted(delete, document_id("one"))),
  )
  assert_true(decisions.is_empty())
  assert_eq(documents.text(source_key("one")), None)
}

///|
test "failed existing save still releases a waiting delete" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, decisions) = persistence_changed(
    documents,
    documents.edit(source_key("one"), "new"),
  )
  guard decisions is [Action::ArmMaximum(_)] else { fail("timers") }
  let (documents, decisions) = persistence_applied(
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ),
  )
  guard decisions[0] is PersistSource(save) else { fail("save") }
  let (documents, _) = persistence_deleted(
    documents,
    documents.delete(source_key("one")),
  )
  let (_, decisions) = persistence_applied(
    documents.update(SaveFailed(save, WriteFailed)),
  )
  guard decisions is [DeleteSource(_)] else {
    fail("failed existing save must still delete")
  }
}

///|
test "new document deletion is local and does not change snapshot" {
  let documents = Model::Model(documents_test_snapshot())
  let before = documents.snapshot()
  let (documents, _) = persistence_applied(
    documents.update(New(document_id("new"))),
  )
  let (documents, decisions) = persistence_deleted(
    documents,
    documents.delete(source_key("new")),
  )
  assert_true(decisions.is_empty())
  assert_eq(documents.snapshot(), before)
  assert_eq(documents.text(source_key("new")), None)
}

///|
test "new in-flight stored save promotes before deletion" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = persistence_applied(
    documents.update(New(document_id("new"))),
  )
  let (documents, decisions) = persistence_changed(
    documents,
    documents.edit(source_key("new"), "hello"),
  )
  guard decisions is [Action::ArmMaximum(_)] else { fail("timers") }
  let (documents, decisions) = persistence_applied(
    documents.update(
      ApplyPendingEdit(
        source_key("new"),
        pending_revision(documents, source_key("new")),
      ),
    ),
  )
  guard decisions[0] is PersistSource(save) else { fail("save") }
  let (documents, _) = persistence_deleted(
    documents,
    documents.delete(source_key("new")),
  )
  let (documents, decisions) = persistence_applied(
    documents.update(Saved(save, save.document)),
  )
  guard decisions[0] is DeleteSource(_) else { fail("delete") }
  guard documents.snapshot().find(document_id("new")) is Some(_) else {
    fail("stored new document must be acknowledged first")
  }
}

///|
test "new in-flight failed save is removed locally" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = persistence_applied(
    documents.update(New(document_id("new"))),
  )
  let (documents, decisions) = persistence_changed(
    documents,
    documents.edit(source_key("new"), "hello"),
  )
  guard decisions is [Action::ArmMaximum(_)] else { fail("timers") }
  let (documents, decisions) = persistence_applied(
    documents.update(
      ApplyPendingEdit(
        source_key("new"),
        pending_revision(documents, source_key("new")),
      ),
    ),
  )
  guard decisions[0] is PersistSource(save) else { fail("save") }
  let (documents, _) = persistence_deleted(
    documents,
    documents.delete(source_key("new")),
  )
  let (documents, decisions) = persistence_applied(
    documents.update(SaveFailed(save, WriteFailed)),
  )
  assert_true(decisions.is_empty())
  assert_eq(documents.text(source_key("new")), None)
  assert_eq(documents.snapshot().find(document_id("new")), None)
}

///|
test "retry allocates a fresh operation and fences an active save" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, decisions) = persistence_deleted(
    documents,
    documents.delete(source_key("one")),
  )
  guard decisions[0] is DeleteSource(first) else { fail("delete") }
  let (documents, _) = persistence_applied(
    documents.update(DeleteFailed(first, WriteFailed)),
  )
  assert_true(
    documents.update(Deleted(first, document_id("one"))) is Superseded,
  )
  assert_eq(documents.text(source_key("one")), Some("one"))
  let (documents, decisions) = persistence_changed(
    documents,
    documents.edit(source_key("one"), "edited"),
  )
  guard decisions is [Action::ArmMaximum(_)] else { fail("timers") }
  let (documents, decisions) = persistence_applied(
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ),
  )
  guard decisions[0] is PersistSource(save) else { fail("save") }
  let (documents, decisions) = persistence_deleted(
    documents,
    documents.delete(source_key("one")),
  )
  assert_true(decisions.is_empty())
  guard documents.delete_status(source_key("one"))
    is Some(DeleteStatus::DeletePending) else {
    fail("retry must wait for save")
  }
  let (_, decisions) = persistence_applied(
    documents.update(SaveFailed(save, WriteFailed)),
  )
  guard decisions[0] is DeleteSource(third) else { fail("release retry") }
  assert_true(third != first)
}

///|
test "maximum save completion then pending callback accepts source" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, decisions) = persistence_changed(
    documents,
    documents.edit(source_key("one"), "maximum"),
  )
  guard decisions is [ArmMaximum(maximum)] else { fail("maximum") }
  let (documents, decisions) = persistence_applied(
    documents.update(MaximumElapsed(maximum)),
  )
  guard decisions is [PersistSource(operation)] else { fail("save") }
  let (documents, _) = persistence_applied(
    documents.update(Saved(operation, operation.document)),
  )
  assert_true(
    find_record(documents.records, source_key("one")).unwrap().lead_source
    is LeadSource::Available("one"),
  )
  let revision = pending_revision(documents, source_key("one"))
  let (documents, decisions) = persistence_applied(
    documents.update(ApplyPendingEdit(source_key("one"), revision)),
  )
  assert_true(decisions.is_empty())
  assert_true(
    find_record(documents.records, source_key("one")).unwrap().lead_source
    is LeadSource::Available("maximum"),
  )
}

///|
test "failed accepted save then clean revert keeps lead pending without save" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = persistence_changed(
    documents,
    documents.edit(source_key("one"), "new"),
  )
  let (documents, decisions) = persistence_applied(
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ),
  )
  guard decisions is [PersistSource(operation)] else { fail("save") }
  let (documents, _) = persistence_applied(
    documents.update(SaveFailed(operation, WriteFailed)),
  )
  let (documents, decisions) = persistence_changed(
    documents,
    documents.edit(source_key("one"), "one"),
  )
  assert_true(decisions.is_empty())
  assert_true(
    documents.save_status(source_key("one")) is Some(SaveStatus::Clean),
  )
  assert_true(has_pending(documents, source_key("one")))
}

///|
test "eligible pending latest text waits for delete without an intermediate write" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = persistence_changed(
    documents,
    documents.edit(source_key("one"), "first"),
  )
  let (documents, persist) = persistence_applied(
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ),
  )
  guard persist is [PersistSource(first)] else { fail("first save") }
  let (documents, _) = persistence_changed(
    documents,
    documents.edit(source_key("one"), "latest"),
  )
  let (documents, _) = persistence_applied(
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ),
  )
  let (documents, _) = persistence_deleted(
    documents,
    documents.delete(source_key("one")),
  )
  let (documents, decisions) = persistence_applied(
    documents.update(Saved(first, first.document)),
  )
  guard decisions is [DeleteSource(_)] else { fail("delete only") }
  guard documents.save_status(source_key("one")) is Some(SaveStatus::Unsaved) else {
    fail("latest replica must remain waiting")
  }
}

///|
test "failed absent New completion removes the record before delete" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = persistence_applied(
    documents.update(New(document_id("new"))),
  )
  let (documents, timer) = persistence_changed(
    documents,
    documents.edit(source_key("new"), "x"),
  )
  guard timer is [ArmMaximum(_)] else { fail("timer") }
  let (documents, persist) = persistence_applied(
    documents.update(
      ApplyPendingEdit(
        source_key("new"),
        pending_revision(documents, source_key("new")),
      ),
    ),
  )
  guard persist is [PersistSource(save)] else { fail("save") }
  let (documents, _) = persistence_deleted(
    documents,
    documents.delete(source_key("new")),
  )
  let (documents, decisions) = persistence_applied(
    documents.update(SaveFailed(save, WriteFailed)),
  )
  assert_true(decisions.is_empty())
  assert_eq(documents.text(source_key("new")), None)
}

///|
test "failed absent Import completion removes the record before delete" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, persist) = persistence_applied(
    documents.update(Imported(document_id("imported"), "x")),
  )
  guard persist is [PersistSource(save)] else { fail("save") }
  let (documents, _) = persistence_deleted(
    documents,
    documents.delete(source_key("imported")),
  )
  let (documents, decisions) = persistence_applied(
    documents.update(SaveFailed(save, WriteFailed)),
  )
  assert_true(decisions.is_empty())
  assert_eq(documents.text(source_key("imported")), None)
}

///|
test "delete success removes acknowledged membership" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, decisions) = persistence_deleted(
    documents,
    documents.delete(source_key("one")),
  )
  guard decisions is [DeleteSource(delete)] else { fail("delete") }
  let (documents, decisions) = persistence_applied(
    documents.update(Deleted(delete, document_id("one"))),
  )
  assert_true(decisions.is_empty())
  assert_eq(documents.snapshot().find(document_id("one")), None)
}

///|
test "delete failure resumes the retained eligible latest replica" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = persistence_changed(
    documents,
    documents.edit(source_key("one"), "first"),
  )
  let (documents, persist) = persistence_applied(
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ),
  )
  guard persist is [PersistSource(first)] else { fail("first save") }
  let (documents, _) = persistence_changed(
    documents,
    documents.edit(source_key("one"), "latest"),
  )
  let (documents, _) = persistence_applied(
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ),
  )
  let (documents, _) = persistence_deleted(
    documents,
    documents.delete(source_key("one")),
  )
  let (documents, delete_decision) = persistence_applied(
    documents.update(Saved(first, first.document)),
  )
  guard delete_decision is [DeleteSource(delete)] else { fail("delete") }
  let (_, latest_save) = persistence_applied(
    documents.update(DeleteFailed(delete, WriteFailed)),
  )
  guard latest_save is [PersistSource(latest)] else { fail("latest save") }
  assert_eq(latest.document.text(), "latest")
}

///|
