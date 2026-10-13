///|
fn input_for(
  documents : @documents.Model,
) -> Array[@recent_documents.Seed[@documents.Key]] {
  recent_document_seeds({ ..test_editing(), documents, }, []).to_array()
}

///|
test "empty imported document remains listed after failed save and deletes locally" {
  let documents = @documents.Model(test_snapshot())
  let transition = expect_document_update(
    documents,
    @documents.Msg::Imported(document_id("empty"), ""),
  )
  let documents = transition.model
  let decisions = transition.effects
  guard decisions is [@documents.Action::PersistSource(operation)] else {
    fail("import save")
  }
  let transition = expect_document_update(
    documents,
    @documents.Msg::SaveFailed(operation, WriteFailed),
  )
  let documents = transition.model
  let seeds = input_for(documents)
  assert_true(
    seeds.exists(seed => {
      seed.docid() == source_key("empty") && seed.source() == ""
    }),
  )
  let transition = expect_document_delete(documents, source_key("empty"))
  let documents = transition.model
  let decisions = transition.effects
  assert_true(decisions.is_empty())
  assert_true(
    !input_for(documents).exists(seed => seed.docid() == source_key("empty")),
  )
}

///|
test "edited New returning empty stays listed before and after lead acceptance" {
  let documents = @documents.Model(test_snapshot())
  let transition = expect_document_update(
    documents,
    @documents.Msg::New(document_id("new")),
  )
  let documents = transition.model
  let transition = expect_document_edit(documents, source_key("new"), "first")
  let documents = transition.model
  let transition = expect_document_edit(documents, source_key("new"), "")
  let documents = transition.model
  assert_true(
    input_for(documents).exists(seed => {
      seed.docid() == source_key("new") && seed.source() == "first"
    }),
  )
  let revision = pending_revision(documents, source_key("new"))
  let transition = expect_document_update(
    documents,
    @documents.Msg::ApplyPendingEdit(source_key("new"), revision),
  )
  let documents = transition.model
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
  let documents = @documents.Model(saved)
  let transition = expect_document_update(
    documents,
    @documents.Msg::New(document_id("new")),
  )
  let documents = transition.model
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
  let editing = {
    ..test_editing(),
    creation: Some({ request_id: 0, intent: NewDocument, status: InProgress, }),
  }
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
  let seeds = input_for(@documents.Model(saved))
  assert_true(
    seeds.map(seed => seed.docid()) == [source_key("a"), source_key("z")],
  )
}

///|
test "adapter preserves accepted sources and page-local row order" {
  let documents = @documents.Model(test_snapshot())
  let transition = expect_document_edit(documents, source_key("two"), "second")
  let documents = transition.model
  let two_revision = pending_revision(documents, source_key("two"))
  let transition = expect_document_update(
    documents,
    @documents.Msg::ApplyPendingEdit(source_key("two"), two_revision),
  )
  let documents = transition.model
  let transition = expect_document_edit(documents, source_key("one"), "first")
  let documents = transition.model
  let one_revision = pending_revision(documents, source_key("one"))
  let transition = expect_document_update(
    documents,
    @documents.Msg::ApplyPendingEdit(source_key("one"), one_revision),
  )
  let documents = transition.model
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
