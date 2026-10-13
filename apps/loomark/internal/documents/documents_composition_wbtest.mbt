/// Tests are organized by reducer contract; fixtures and extraction helpers remain shared.

///|
test "composition blocks persistence but keeps fresh revision" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match
    documents.update(CompositionStarted(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  let (documents, decisions) = match documents.edit(source_key("one"), "one!") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  assert_true(decisions.is_empty())
  guard documents.save_status(source_key("one")) is Some(SaveStatus::Unsaved) else {
    fail("waiting replica")
  }
  assert_eq(pending_revision(documents, source_key("one")), 1)
  let (documents, decisions) = match
    documents.update(CompositionEnded(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  guard decisions is [Action::ArmMaximum(_)] else { fail("maximum") }
  assert_true(has_pending(documents, source_key("one")))
}

///|
test "pending revision advances while maximum identity stays fresh" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, first) = match documents.edit(source_key("one"), "b") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  guard first is [Action::ArmMaximum(maximum)] else { fail("initial timers") }
  assert_eq(pending_revision(documents, source_key("one")), 1)
  assert_eq(maximum, 1)
  let (documents, second) = match documents.edit(source_key("one"), "c") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  assert_true(second.is_empty())
  assert_eq(pending_revision(documents, source_key("one")), 2)
}

///|
test "maximum eligibility persists latest text during uninterrupted editing" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, decisions) = match documents.edit(source_key("one"), "b") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  guard decisions is [Action::ArmMaximum(maximum)] else {
    fail("initial timers")
  }
  let (documents, _) = match documents.edit(source_key("one"), "c") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let (_, decisions) = match documents.update(MaximumElapsed(maximum)) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  guard decisions is [Action::PersistSource(operation)] else {
    fail("maximum persist")
  }
  assert_eq(operation.document.text(), "c")
  assert_true(
    documents.save_status(source_key("one")) is Some(SaveStatus::Unsaved),
  )
}

///|
test "composition defers timers for an in-flight save until it ends" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, decisions) = match documents.edit(source_key("one"), "one!") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  guard decisions is [Action::ArmMaximum(_)] else { fail("timers") }
  let (documents, decisions) = match
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  guard decisions[0] is Action::PersistSource(_) else {
    fail("expected in-flight save")
  }
  let (documents, _) = match
    documents.update(CompositionStarted(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  let (documents, decisions) = match
    documents.edit(source_key("one"), "one!!") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  assert_true(decisions.is_empty())
  guard documents.save_status(source_key("one")) is Some(SaveStatus::Unsaved) else {
    fail("composition change should be pending")
  }
  let (documents, decisions) = match
    documents.update(CompositionEnded(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  guard decisions is [Action::ArmMaximum(_)] else { fail("maximum") }
  assert_true(has_pending(documents, source_key("one")))
}

///|
test "visibility makes an in-flight save's latest replica eligible" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, timers) = match documents.edit(source_key("one"), "first") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  guard timers is [Action::ArmMaximum(_)] else { fail("initial timers") }
  let (documents, persist) = match
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  guard persist is [Action::PersistSource(operation)] else {
    fail("first save")
  }
  let (documents, _) = match documents.edit(source_key("one"), "latest") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let (documents, flush) = match
    documents.update(VisibilityFlush(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  assert_true(flush.is_empty())
  let (_, follow_up) = match
    documents.update(Saved(operation, operation.document)) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  guard follow_up is [Action::PersistSource(latest)] else {
    fail("eligible follow-up")
  }
  assert_eq(latest.document.text(), "latest")
}

///|
test "duplicate composition end emits one maximum decision" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match
    documents.update(CompositionStarted(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  let (documents, _) = match documents.edit(source_key("one"), "first") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let (documents, first) = match
    documents.update(CompositionEnded(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  guard first is [Action::ArmMaximum(_)] else {
    fail("first composition end should arm maximum")
  }
  assert_true(
    documents.update(CompositionEnded(source_key("one"))) is Superseded,
  )
}

///|
test "genuine composition cycles arm maximum once with saving pending" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match
    documents.update(CompositionStarted(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  let (documents, _) = match documents.edit(source_key("one"), "first") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let (documents, first) = match
    documents.update(CompositionEnded(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  guard first is [Action::ArmMaximum(_)] else { fail("first cycle maximum") }
  let (documents, _) = match
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  guard documents.save_status(source_key("one")) is Some(SaveStatus::Unsaved) else {
    fail("first cycle should be saving")
  }
  let (documents, _) = match
    documents.update(CompositionStarted(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  let (documents, _) = match documents.edit(source_key("one"), "second") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let (documents, second) = match
    documents.update(CompositionEnded(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  guard second is [Action::ArmMaximum(_)] else { fail("second cycle maximum") }
  assert_true(
    documents.update(CompositionEnded(source_key("one"))) is Superseded,
  )
}

///|
test "queued composition callback applies immediately at composition end" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match documents.edit(source_key("one"), "new") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let revision = pending_revision(documents, source_key("one"))
  let (documents, _) = match
    documents.update(CompositionStarted(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  let (documents, _) = match
    documents.update(ApplyPendingEdit(source_key("one"), revision)) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  let (documents, _) = match
    documents.update(CompositionEnded(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  assert_true(
    find_record(documents.records, source_key("one")).unwrap().lead_source
    is LeadSource::Available("new"),
  )
  assert_true(!has_pending(documents, source_key("one")))
}

///|
test "composition end without callback does not accept the edit" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match
    documents.update(CompositionStarted(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  let (documents, _) = match documents.edit(source_key("one"), "ime") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let (documents, _) = match
    documents.update(CompositionEnded(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  assert_true(
    find_record(documents.records, source_key("one")).unwrap().lead_source
    is LeadSource::Available("one"),
  )
  assert_true(has_pending(documents, source_key("one")))
}

///|
test "IME callback then newer edit waits for latest pending revision" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match documents.edit(source_key("one"), "composed") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let initial_revision = pending_revision(documents, source_key("one"))
  let (documents, _) = match
    documents.update(CompositionStarted(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  let (documents, _) = match
    documents.update(ApplyPendingEdit(source_key("one"), initial_revision)) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  let (documents, _) = match documents.edit(source_key("one"), "newer") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let (documents, _) = match
    documents.update(CompositionEnded(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  assert_true(
    find_record(documents.records, source_key("one")).unwrap().lead_source
    is LeadSource::Available("one"),
  )
  let revision = pending_revision(documents, source_key("one"))
  let (documents, _) = match
    documents.update(ApplyPendingEdit(source_key("one"), revision)) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  assert_true(
    find_record(documents.records, source_key("one")).unwrap().lead_source
    is LeadSource::Available("newer"),
  )
}

///|
test "composition end with no newer edit starts one pending subscription" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match
    documents.update(CompositionStarted(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  let (documents, _) = match documents.edit(source_key("one"), "composed") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let (documents, decisions) = match
    documents.update(CompositionEnded(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  guard decisions is [ArmMaximum(_)] else { fail("maximum") }
  assert_true(has_pending(documents, source_key("one")))
}

///|
test "composition end does not duplicate an already pending edit" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match documents.edit(source_key("one"), "changed") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let (documents, _) = match
    documents.update(CompositionStarted(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  let (documents, _) = match
    documents.update(CompositionEnded(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  assert_true(has_pending(documents, source_key("one")))
}

///|
test "eligible maximum during composition persists at composition end" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, decisions) = match
    documents.edit(source_key("one"), "changed") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  guard decisions is [ArmMaximum(maximum)] else { fail("maximum") }
  let (documents, decisions) = match
    documents.update(CompositionStarted(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  assert_true(decisions.is_empty())
  let (documents, decisions) = match documents.update(MaximumElapsed(maximum)) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  assert_true(decisions.is_empty())
  let (documents, decisions) = match
    documents.update(CompositionEnded(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  guard decisions is [PersistSource(_)] else { fail("persist") }
  assert_true(has_pending(documents, source_key("one")))
}

///|
test "duplicate composition starts preserve waiting and ready evidence" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match documents.edit(source_key("one"), "changed") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let revision = pending_revision(documents, source_key("one"))
  let (documents, _) = match
    documents.update(CompositionStarted(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  assert_true(
    documents.update(CompositionStarted(source_key("one"))) is Superseded,
  )
  match find_record(documents.records, source_key("one")).unwrap().edit {
    ComposingWaiting(waiting_revision) => assert_eq(waiting_revision, revision)
    _ => fail("waiting evidence")
  }
  let (documents, _) = match
    documents.update(ApplyPendingEdit(source_key("one"), revision)) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  assert_true(
    documents.update(CompositionStarted(source_key("one"))) is Superseded,
  )
  assert_true(
    find_record(documents.records, source_key("one")).unwrap().edit
    is ComposingReady,
  )
}

/// A ready composition end accepts the record and starts exactly one save.

///|
test "ready composition end persists once" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match
    documents.update(CompositionStarted(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  let (documents, _) = match documents.edit(source_key("one"), "composed") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let revision = pending_revision(documents, source_key("one"))
  let (documents, _) = match
    documents.update(ApplyPendingEdit(source_key("one"), revision)) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  let (documents, decisions) = match
    documents.update(CompositionEnded(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  guard decisions is [PersistSource(operation)] else { fail("persist") }
  assert_true(
    find_record(documents.records, source_key("one")).unwrap().edit is Idle,
  )
  assert_true(
    documents.update(CompositionEnded(source_key("one"))) is Superseded,
  )
  ignore(operation)
}

/// A ready callback remains evidence when the final text event is unchanged.

///|
test "matching final text keeps ready evidence" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match
    documents.update(CompositionStarted(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  let (documents, _) = match documents.edit(source_key("one"), "same") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let revision = pending_revision(documents, source_key("one"))
  let (documents, _) = match
    documents.update(ApplyPendingEdit(source_key("one"), revision)) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  assert_true(documents.edit(source_key("one"), "same") is SameText)
  assert_true(
    find_record(documents.records, source_key("one")).unwrap().edit
    is ComposingReady,
  )
  let (documents, decisions) = match
    documents.update(CompositionEnded(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  guard decisions is [PersistSource(_)] else { fail("persist") }
  assert_true(
    find_record(documents.records, source_key("one")).unwrap().lead_source
    is LeadSource::Available("same"),
  )
}

/// An accepted composition queues exactly one follow-up behind an in-flight save.

///|
test "ready composition end marks in-flight follow-up eligible once" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, first) = match documents.edit(source_key("one"), "first") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  guard first is [ArmMaximum(_)] else { fail("timer") }
  let (documents, first) = match
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  guard first is [PersistSource(operation)] else { fail("first save") }
  let (documents, _) = match
    documents.update(CompositionStarted(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  let (documents, _) = match documents.edit(source_key("one"), "latest") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let (documents, _) = match
    documents.update(
      ApplyPendingEdit(
        source_key("one"),
        pending_revision(documents, source_key("one")),
      ),
    ) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  let (documents, decisions) = match
    documents.update(CompositionEnded(source_key("one"))) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  assert_true(decisions.is_empty())
  assert_true(
    documents.save_status(source_key("one")) is Some(SaveStatus::Unsaved),
  )
  let (_, follow_up) = match
    documents.update(Saved(operation, operation.document)) {
    Applied(transition) => (transition.model, transition.effects)
    Superseded => fail("unexpected superseded callback")
  }
  guard follow_up is [PersistSource(latest)] else { fail("one follow-up") }
  assert_eq(latest.document.text(), "latest")
}

/// A composition end outside composition is not a save event.

///|
test "composition end outside composition is ignored" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match documents.edit(source_key("one"), "changed") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let before = documents
  assert_true(
    documents.update(CompositionEnded(source_key("one"))) is Superseded,
  )
  assert_true(documents == before)
}

/// A stale callback must not reach a replacement record with the same ID.

///|
