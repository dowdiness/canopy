///|
fn input_for(documents : Documents) -> Array[@recent_documents.Seed] {
  recent_document_seeds({ ..test_editing(), documents, }).to_array()
}

///|
test "empty imported document remains listed after failed save and deletes locally" {
  let documents = initial_documents(test_snapshot())
  let (documents, decisions) = documents.reduce(DocumentsImported("empty", ""))
  guard decisions is [DocumentsPersist(operation)] else { fail("import save") }
  let (documents, _) = documents.reduce(
    DocumentsFeedbackReceived(SaveCompleted(operation, SaveFailed(WriteFailed))),
  )
  let seeds = input_for(documents)
  assert_true(
    seeds.exists(seed => seed.docid() == "empty" && seed.source() == ""),
  )
  let (documents, decisions) = documents.reduce(DeleteConfirmed("empty"))
  assert_true(decisions.is_empty())
  assert_true(!input_for(documents).exists(seed => seed.docid() == "empty"))
}

///|
test "edited New returning empty stays listed before and after lead acceptance" {
  let documents = initial_documents(test_snapshot())
  let (documents, _) = documents.reduce(DocumentsNew("new"))
  let (documents, _) = documents.reduce(DocumentsTextChanged("new", "first"))
  let (documents, _) = documents.reduce(DocumentsTextChanged("new", ""))
  assert_true(
    input_for(documents).exists(seed => {
      seed.docid() == "new" && seed.source() == "first"
    }),
  )
  let revision = pending_revision(documents, "new")
  let (documents, _) = documents.reduce(ApplyPendingEdit("new", revision))
  assert_true(
    input_for(documents).exists(seed => {
      seed.docid() == "new" && seed.source() == ""
    }),
  )
}

///|
test "untouched New is excluded while loaded saved empty is admitted" {
  let saved = @source_repository.SavedDocuments::from_documents([
    documents_test_document("empty", ""),
  ]).unwrap()
  let documents = initial_documents(saved)
  let (documents, _) = documents.reduce(DocumentsNew("new"))
  let seeds = input_for(documents)
  assert_eq(seeds.length(), 1)
  assert_eq(seeds[0].docid(), "empty")
  assert_eq(seeds[0].source(), "")
}

///|
test "creation gating produces blocked typed deletion presentation" {
  let editing = { ..test_editing(), creation: Creating, }
  let seeds = recent_document_seeds(editing).to_array()
  assert_true(
    seeds.all(seed => {
      seed.deletion() is @recent_documents.DeletionAvailability::Blocked
    }),
  )
}

///|
test "loaded saved rows retain lexical order" {
  let saved = @source_repository.SavedDocuments::from_documents([
    documents_test_document("z", "z"),
    documents_test_document("a", "a"),
  ]).unwrap()
  let seeds = input_for(initial_documents(saved))
  assert_eq(seeds.map(seed => seed.docid()), ["a", "z"])
}

///|
test "adapter preserves accepted sources and page-local row order" {
  let documents = initial_documents(test_snapshot())
  let (documents, _) = documents.reduce(DocumentsTextChanged("two", "second"))
  let two_revision = pending_revision(documents, "two")
  let (documents, _) = documents.reduce(ApplyPendingEdit("two", two_revision))
  let (documents, _) = documents.reduce(DocumentsTextChanged("one", "first"))
  let one_revision = pending_revision(documents, "one")
  let (documents, _) = documents.reduce(ApplyPendingEdit("one", one_revision))
  let seeds = input_for(documents)
  assert_eq(seeds.map(seed => seed.docid()), ["one", "two"])
  assert_eq(seeds.map(seed => seed.source()), ["first", "second"])
}
