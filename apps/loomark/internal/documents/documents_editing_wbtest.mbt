/// Tests are organized by reducer contract; fixtures and extraction helpers remain shared.

///|
test "activation target preserves current text and parsed resume eligibility" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match documents.edit(source_key("one"), "one!") {
  Changed(transition) => (documents, transition.effects),
  SameText => fail("unexpected unchanged edit")
}
  guard documents.document(source_key("one")) is Some(saved) else {
    fail("saved activation target")
  }
  assert_eq(saved.text(), "one!")
  assert_true(documents.resume_hint(source_key("one")) is Some(_))
  let (documents, _) = match documents.update(New(document_id("new"))) {
  Applied(transition) => (documents, transition.effects),
  Superseded => fail("unexpected superseded callback")
}
  guard documents.document(source_key("new")) is Some(ephemeral) else {
    fail("ephemeral activation target")
  }
  assert_eq(ephemeral.text(), "")
  assert_eq(documents.resume_hint(source_key("new")), None)
  assert_true(documents.document(source_key("missing")) is None)
}

///|
test "Import accepts empty text and persists it immediately as New" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, decisions) = match documents.update(Imported(document_id("imported"), ""),) {
  Applied(transition) => (documents, transition.effects),
  Superseded => fail("unexpected superseded callback")
}
  assert_eq(documents.text(source_key("imported")), Some(""))
  guard decisions is [Action::PersistSource(operation)] &&
    operation.key == source_key("imported") else {
    fail("expected one ImportedNew persistence decision")
  }
  assert_eq(operation.document, documents_test_document("imported", ""))
}

///|
test "duplicate text changes preserve documents and decisions" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match documents.edit(source_key("one"), "one!") {
  Changed(transition) => (documents, transition.effects),
  SameText => fail("unexpected unchanged edit")
}
  let before = documents
  let (after, decisions) = match documents.edit(source_key("one"), "one!")) {
  Changed(transition) => (documents, transition.effects),
  SameText => fail("unexpected unchanged edit")
}
  assert_true(after == before)
  assert_true(decisions.is_empty())
}

///|
test "lead source remains available while an existing edit is pending" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match documents.edit(source_key("one"), "changed")) {
  Changed(transition) => (documents, transition.effects),
  SameText => fail("unexpected unchanged edit")
}
  assert_true(
    find_record(documents.records, source_key("one")).unwrap().lead_source
    is LeadSource::Available("one"),
  )
  assert_true(has_pending(documents, source_key("one")))
}

///|
test "matching callback adopts source and stale callback does not" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match documents.edit(source_key("one"), "changed")) {
  Changed(transition) => (documents, transition.effects),
  SameText => fail("unexpected unchanged edit")
}
  let revision = pending_revision(documents, source_key("one"))
  let (documents, _) = match documents.edit(source_key("one"), "newer") {
  Changed(transition) => (documents, transition.effects),
  SameText => fail("unexpected unchanged edit")
}
  let (documents, _) = match documents.update(ApplyPendingEdit(source_key("one"), revision),) {
  Applied(transition) => (documents, transition.effects),
  Superseded => fail("unexpected superseded callback")
}
  assert_true(has_pending(documents, source_key("one")))
  let revision = pending_revision(documents, source_key("one"))
  let (documents, _) = match documents.update(ApplyPendingEdit(source_key("one"), revision),) {
  Applied(transition) => (documents, transition.effects),
  Superseded => fail("unexpected superseded callback")
}
  assert_true(
    find_record(documents.records, source_key("one")).unwrap().lead_source
    is LeadSource::Available("newer"),
  )
  assert_true(!has_pending(documents, source_key("one")))
}

///|
test "exact clean return has no pending subscription" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match documents.edit(source_key("one"), "changed")) {
  Changed(transition) => (documents, transition.effects),
  SameText => fail("unexpected unchanged edit")
}
  let (documents, _) = match documents.edit(source_key("one"), "one") {
  Changed(transition) => (documents, transition.effects),
  SameText => fail("unexpected unchanged edit")
}
  assert_true(
    find_record(documents.records, source_key("one")).unwrap().lead_source
    is LeadSource::Available("one"),
  )
  assert_true(!has_pending(documents, source_key("one")))
}

///|
test "first new edit immediately establishes its source" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match documents.update(New(document_id("new"))) {
  Applied(transition) => (documents, transition.effects),
  Superseded => fail("unexpected superseded callback")
}
  let (documents, _) = match documents.edit(source_key("new"), "first") {
  Changed(transition) => (documents, transition.effects),
  SameText => fail("unexpected unchanged edit")
}
  assert_true(
    find_record(documents.records, source_key("new")).unwrap().lead_source
    is LeadSource::Available("first"),
  )
}

///|
test "exact clean return restores saved without lead delay" {
  let documents = Model::Model(documents_test_snapshot())
  let (documents, _) = match documents.edit(source_key("one"), "changed")) {
  Changed(transition) => (documents, transition.effects),
  SameText => fail("unexpected unchanged edit")
}
  let (documents, decisions) = match documents.edit(source_key("one"), "one")) {
  Changed(transition) => (documents, transition.effects),
  SameText => fail("unexpected unchanged edit")
}
  assert_true(documents.save_phase(source_key("one")) is Some(Saved))
  assert_eq(decisions.length(), 0)
  assert_true(
    find_record(documents.records, source_key("one")).unwrap().lead_source
    is LeadSource::Available("one"),
  )
}

/// A deletion lane blocks a matching maximum callback without mutating state.

///|
