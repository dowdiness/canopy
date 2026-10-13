/// Tests are organized by reducer contract; fixtures and extraction helpers remain shared.

///|
test "stale timers are superseded and mismatched stored records raise" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, decisions) = match documents.edit(source_key("one"), "b") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  guard decisions is [Action::ArmMaximum(_)] else { fail("timers") }
  let (documents, _) = match documents.edit(source_key("one"), "c") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let before_stale_timer = documents
  assert_true(documents.update(MaximumElapsed(99)) is Superseded)
  assert_true(documents == before_stale_timer)
  let (documents, decisions) = match
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ) {
    Applied(transition) => (transition.model, transition.effects)
    Unchanged | Superseded => fail("expected an applied document update")
  }
  guard decisions is [Action::PersistSource(operation)] else {
    fail("latest quiet")
  }
  let bogus = documents_test_document("one", "not-the-operation-text")
  let mismatch = try {
    ignore(documents.update(Saved(operation, bogus)))
    false
  } catch {
    UpdateError::DocumentMismatch(key) => key == source_key("one")
    _ => false
  }
  assert_true(mismatch)
  assert_eq(
    documents.snapshot().find(document_id("one")).unwrap().text(),
    "one",
  )
}

///|
test "page-local revision orders edits across documents" {
  let saved = documents_test_snapshot()
  let documents = Model::Model(saved)
  let (documents, first_decisions) = match
    documents.edit(source_key("two"), "two!") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  guard first_decisions is [Action::ArmMaximum(max_two)] else {
    fail("two timers")
  }
  assert_eq(pending_revision(documents, source_key("two")), 1)
  assert_eq(max_two, 1)
  let (documents, second_decisions) = match
    documents.edit(source_key("one"), "one!") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  guard second_decisions is [Action::ArmMaximum(max_one)] else {
    fail("one independent timers")
  }
  assert_eq(pending_revision(documents, source_key("one")), 2)
  assert_eq(max_one, 2)
  guard documents.save_status(source_key("two")) is Some(SaveStatus::Unsaved) else {
    fail("two waiting")
  }
  assert_eq(pending_revision(documents, source_key("two")), 1)
  assert_true(
    documents.save_status(source_key("one")) is Some(SaveStatus::Unsaved),
  )
  assert_eq(pending_revision(documents, source_key("one")), 2)
  assert_eq(max_one, 2)
}

///|
test "page-local revision retains authority unchanged and re-arms after stale timers" {
  let saved = @source_repository.SavedDocuments::from_documents([
    documents_test_document("one", "one"),
  ]).unwrap()
  let documents = Model::Model(saved)
  let (documents, decisions) = match
    documents.edit(source_key("one"), "changed") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  guard decisions is [Action::ArmMaximum(mid)] else { fail("timers") }
  assert_eq(pending_revision(documents, source_key("one")), 1)
  assert_eq(mid, 1)
  // Stale pending_revision(documents, source_key("one")) revision is ignored
  assert_true(
    documents.update(ApplyPendingEdit(source_key("one"), 99)) is Superseded,
  )
  // Correct revision still arms persist
  let (documents, decisions) = match
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ) {
    Applied(transition) => (transition.model, transition.effects)
    Unchanged | Superseded => fail("expected an applied document update")
  }
  guard decisions[0] is Action::PersistSource(operation) else {
    fail("persist")
  }
  assert_eq(operation.document.text(), "changed")
  // Import with same saved still persists via page-local revision
  let (documents, decisions) = match
    documents.update(Imported(document_id("imported"), "text")) {
    Applied(transition) => (transition.model, transition.effects)
    Unchanged | Superseded => fail("expected an applied document update")
  }
  guard decisions is [Action::PersistSource(op2)] else {
    fail("imported persist")
  }
  assert_eq(op2.document.text(), "text")
  assert_eq(documents.text(source_key("imported")), Some("text"))
}

///|
test "delete and recreate keeps pending revisions monotonic and isolated" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match documents.update(New(document_id("new"))) {
    Applied(transition) => (transition.model, transition.effects)
    Unchanged | Superseded => fail("expected an applied document update")
  }
  let (documents, _) = match documents.edit(source_key("new"), "first") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let old_revision = pending_revision(documents, source_key("new"))
  let (documents, _) = match documents.delete(source_key("new")) {
    Accepted(transition) => (transition.model, transition.effects)
    AlreadyPending => fail("unexpected pending deletion")
  }
  let (documents, _) = match documents.update(New(document_id("new"))) {
    Applied(transition) => (transition.model, transition.effects)
    Unchanged | Superseded => fail("expected an applied document update")
  }
  let (documents, _) = match documents.edit(source_key("new"), "second") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let current_revision = pending_revision(documents, source_key("new"))
  assert_true(current_revision > old_revision)
  let (documents, _) = match documents.edit(source_key("one"), "other") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  assert_true(has_pending(documents, source_key("new")))
  assert_true(has_pending(documents, source_key("one")))
}

///|
test "matching maximum after delete confirmation is ignored" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, decisions) = match
    documents.edit(source_key("one"), "changed") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  guard decisions is [ArmMaximum(maximum)] else { fail("maximum") }
  let (documents, decisions) = match documents.delete(source_key("one")) {
    Accepted(transition) => (transition.model, transition.effects)
    AlreadyPending => fail("unexpected pending deletion")
  }
  guard decisions is [DeleteSource(_)] else { fail("delete") }
  let before = documents
  assert_true(documents.update(MaximumElapsed(maximum)) is Superseded)
  assert_true(documents == before)
}

/// The same fence applies when a newer replica is queued behind a save.

///|
test "matching maximum during waiting deletion of in-flight save is ignored" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, decisions) = match
    documents.edit(source_key("one"), "first") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  guard decisions is [ArmMaximum(_)] else { fail("maximum") }
  let (documents, decisions) = match
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ) {
    Applied(transition) => (transition.model, transition.effects)
    Unchanged | Superseded => fail("expected an applied document update")
  }
  guard decisions is [PersistSource(save)] else { fail("save") }
  let (documents, decisions) = match
    documents.edit(source_key("one"), "latest") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  guard decisions is [ArmMaximum(maximum)] else { fail("follow-up maximum") }
  let (documents, decisions) = match documents.delete(source_key("one")) {
    Accepted(transition) => (transition.model, transition.effects)
    AlreadyPending => fail("unexpected pending deletion")
  }
  assert_true(decisions.is_empty())
  let before = documents
  assert_true(documents.update(MaximumElapsed(maximum)) is Superseded)
  assert_true(documents == before)
  let (_, decisions) = match documents.update(Saved(save, save.document)) {
    Applied(transition) => (transition.model, transition.effects)
    Unchanged | Superseded => fail("expected an applied document update")
  }
  guard decisions is [DeleteSource(delete)] else {
    fail("original save remains valid")
  }
  assert_true(delete.document_id == document_id("one"))
}

/// Duplicate composition starts preserve the accepted lifecycle state.

///|
test "old pending callback after recreate is ignored" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match documents.update(New(document_id("new"))) {
    Applied(transition) => (transition.model, transition.effects)
    Unchanged | Superseded => fail("expected an applied document update")
  }
  let (documents, _) = match documents.edit(source_key("new"), "first") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let old_revision = pending_revision(documents, source_key("new"))
  let (documents, _) = match documents.delete(source_key("new")) {
    Accepted(transition) => (transition.model, transition.effects)
    AlreadyPending => fail("unexpected pending deletion")
  }
  let (documents, _) = match documents.update(New(document_id("new"))) {
    Applied(transition) => (transition.model, transition.effects)
    Unchanged | Superseded => fail("expected an applied document update")
  }
  let (documents, _) = match documents.edit(source_key("new"), "second") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let before = documents
  assert_true(
    documents.update(ApplyPendingEdit(source_key("new"), old_revision))
    is Superseded,
  )
  assert_true(documents == before)
}

/// Completion facts are validated once before the delete lane is selected.

///|
test "waiting delete rejects mismatched stored completion" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match documents.edit(source_key("one"), "first") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let (documents, persist) = match
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ) {
    Applied(transition) => (transition.model, transition.effects)
    Unchanged | Superseded => fail("expected an applied document update")
  }
  guard persist is [PersistSource(save)] else { fail("save") }
  let (documents, _) = match documents.edit(source_key("one"), "latest") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let (documents, _) = match documents.delete(source_key("one")) {
    Accepted(transition) => (transition.model, transition.effects)
    AlreadyPending => fail("unexpected pending deletion")
  }
  let before = documents
  let bogus = documents_test_document("one", "not-save")
  let mismatch = try {
    ignore(documents.update(Saved(save, bogus)))
    false
  } catch {
    UpdateError::DocumentMismatch(key) => key == source_key("one")
    _ => false
  }
  assert_true(mismatch)
  assert_true(documents == before)
}

///|
test "duplicate save completion after delete issue is ignored" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match documents.edit(source_key("one"), "x") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let (documents, persist) = match
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ) {
    Applied(transition) => (transition.model, transition.effects)
    Unchanged | Superseded => fail("expected an applied document update")
  }
  guard persist is [PersistSource(save)] else { fail("save") }
  let (documents, _) = match documents.delete(source_key("one")) {
    Accepted(transition) => (transition.model, transition.effects)
    AlreadyPending => fail("unexpected pending deletion")
  }
  let (documents, first) = match documents.update(Saved(save, save.document)) {
    Applied(transition) => (transition.model, transition.effects)
    Unchanged | Superseded => fail("expected an applied document update")
  }
  guard first is [DeleteSource(delete)] else { fail("delete") }
  assert_true(documents.update(Saved(save, save.document)) is Superseded)
  assert_true(
    documents.delete_status(source_key("one"))
    is Some(DeleteStatus::DeletePending),
  )
  ignore(delete)
}

///|
test "stale save completion cannot finish a replacement operation" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match documents.edit(source_key("one"), "first") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let (documents, persist) = match
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ) {
    Applied(transition) => (transition.model, transition.effects)
    Unchanged | Superseded => fail("expected an applied document update")
  }
  guard persist is [PersistSource(first)] else { fail("first save") }
  let (documents, _) = match documents.edit(source_key("one"), "latest") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let (documents, _) = match
    documents.update(VisibilityFlush(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Unchanged | Superseded => fail("expected an applied document update")
  }
  let (documents, retry) = match
    documents.update(SaveFailed(first, WriteFailed)) {
    Applied(transition) => (transition.model, transition.effects)
    Unchanged | Superseded => fail("expected an applied document update")
  }
  guard retry is [PersistSource(second)] else { fail("replacement save") }
  let before = documents
  assert_true(documents.update(Saved(first, first.document)) is Superseded)
  assert_true(documents == before)
  ignore(second)
}
