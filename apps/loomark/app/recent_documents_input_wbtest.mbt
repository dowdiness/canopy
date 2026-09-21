///|
fn input_for(
  documents : @documents.State,
) -> Array[@recent_documents.Seed[@documents.Key]] {
  recent_document_seeds({ ..test_editing(), documents, }, []).to_array()
}

///|
test "empty imported document remains listed after failed save and deletes locally" {
  let documents = @documents.State::State(test_snapshot())
  let (documents, decisions) = documents.reduce(
    @documents.Msg::Imported(document_id("empty"), ""),
  )
  guard decisions is [@documents.Action::PersistSource(operation)] else {
    fail("import save")
  }
  let (documents, _) = documents.reduce(
    @documents.Msg::FeedbackReceived(
      @documents.Feedback::SaveCompleted(operation, SaveFailed(WriteFailed)),
    ),
  )
  let seeds = input_for(documents)
  assert_true(
    seeds.exists(seed => {
      seed.docid() == source_key("empty") && seed.source() == ""
    }),
  )
  let (documents, decisions) = documents.reduce(
    @documents.Msg::DeleteConfirmed(source_key("empty")),
  )
  assert_true(decisions.is_empty())
  assert_true(
    !input_for(documents).exists(seed => seed.docid() == source_key("empty")),
  )
}

///|
test "edited New returning empty stays listed before and after lead acceptance" {
  let documents = @documents.State::State(test_snapshot())
  let (documents, _) = documents.reduce(@documents.Msg::New(document_id("new")))
  let (documents, _) = documents.reduce(
    @documents.Msg::TextChanged(source_key("new"), "first"),
  )
  let (documents, _) = documents.reduce(
    @documents.Msg::TextChanged(source_key("new"), ""),
  )
  assert_true(
    input_for(documents).exists(seed => {
      seed.docid() == source_key("new") && seed.source() == "first"
    }),
  )
  let revision = pending_revision(documents, source_key("new"))
  let (documents, _) = documents.reduce(
    @documents.Msg::ApplyPendingEdit(source_key("new"), revision),
  )
  assert_true(
    input_for(documents).exists(seed => {
      seed.docid() == source_key("new") && seed.source() == ""
    }),
  )
}

///|
test "untouched New is excluded while loaded saved empty is admitted" {
  let saved = @source_repository.SavedDocuments::from_documents([
    documents_test_document("empty", ""),
  ]).unwrap()
  let documents = @documents.State::State(saved)
  let (documents, _) = documents.reduce(@documents.Msg::New(document_id("new")))
  let seeds = input_for(documents)
  assert_true(
    seeds.exists(seed => {
      seed.docid() == source_key("empty") && seed.source() == ""
    }),
  )
  assert_false(seeds.exists(seed => seed.docid() == source_key("new")))
}

///|
test "creation gating produces blocked typed deletion presentation" {
  let editing = { ..test_editing(), creation: Creating(0), }
  let seeds = recent_document_seeds(editing, []).to_array()
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
  let seeds = input_for(@documents.State::State(saved))
  assert_true(
    seeds.map(seed => seed.docid()) == [source_key("a"), source_key("z")],
  )
}

///|
test "adapter preserves accepted sources and page-local row order" {
  let documents = @documents.State::State(test_snapshot())
  let (documents, _) = documents.reduce(
    @documents.Msg::TextChanged(source_key("two"), "second"),
  )
  let two_revision = pending_revision(documents, source_key("two"))
  let (documents, _) = documents.reduce(
    @documents.Msg::ApplyPendingEdit(source_key("two"), two_revision),
  )
  let (documents, _) = documents.reduce(
    @documents.Msg::TextChanged(source_key("one"), "first"),
  )
  let one_revision = pending_revision(documents, source_key("one"))
  let (documents, _) = documents.reduce(
    @documents.Msg::ApplyPendingEdit(source_key("one"), one_revision),
  )
  let seeds = input_for(documents)
  assert_true(
    seeds.map(seed => seed.docid()) == [source_key("one"), source_key("two")],
  )
  assert_eq(seeds.map(seed => seed.source()), ["first", "second"])
}

///|
test "adapter selects the Editing Document by ID" {
  let seeds = input_for(test_editing().documents)
  let one = seeds
    .iter()
    .find_first(seed => seed.docid() == source_key("one"))
    .unwrap()
  let two = seeds
    .iter()
    .find_first(seed => seed.docid() == source_key("two"))
    .unwrap()
  assert_true(one.selection() is @recent_documents.Selection::Editing)
  assert_true(two.selection() is @recent_documents.Selection::Selectable)
}
