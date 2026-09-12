/// Tests are organized by reducer contract; fixtures and extraction helpers remain shared.

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
test "duplicate text changes preserve documents and decisions" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "one!"))
  let before = documents
  let (after, decisions) = documents.reduce(DocumentsTextChanged("one", "one!"))
  assert_true(after == before)
  assert_true(decisions.is_empty())
}

///|
test "lead source remains available while an existing edit is pending" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "changed"))
  assert_true(
    find_record(documents.records, "one").unwrap().lead_source
    is LeadSource::Available("one"),
  )
  assert_true(has_pending(documents, "one"))
}

///|
test "matching callback adopts source and stale callback does not" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "changed"))
  let revision = pending_revision(documents, "one")
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "newer"))
  let (documents, _) = documents.reduce(ApplyPendingEdit("one", revision))
  assert_true(has_pending(documents, "one"))
  let revision = pending_revision(documents, "one")
  let (documents, _) = documents.reduce(ApplyPendingEdit("one", revision))
  assert_true(
    find_record(documents.records, "one").unwrap().lead_source
    is LeadSource::Available("newer"),
  )
  assert_true(!has_pending(documents, "one"))
}

///|
test "exact clean return has no pending subscription" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "changed"))
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "one"))
  assert_true(
    find_record(documents.records, "one").unwrap().lead_source
    is LeadSource::Available("one"),
  )
  assert_true(!has_pending(documents, "one"))
}

///|
test "first new edit immediately establishes its source" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsNew("new"))
  let (documents, _) = documents.reduce(DocumentsTextChanged("new", "first"))
  assert_true(
    find_record(documents.records, "new").unwrap().lead_source
    is LeadSource::Available("first"),
  )
}

///|
test "exact clean return restores saved without lead delay" {
  let documents = initial_documents(documents_test_snapshot())
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "changed"))
  let (documents, decisions) = documents.reduce(
    DocumentsTextChanged("one", "one"),
  )
  assert_true(documents.save_status("one") is Some(Saved))
  assert_eq(decisions.length(), 0)
  assert_true(
    find_record(documents.records, "one").unwrap().lead_source
    is LeadSource::Available("one"),
  )
}

/// A deletion lane blocks a matching maximum callback without mutating state.

///|
