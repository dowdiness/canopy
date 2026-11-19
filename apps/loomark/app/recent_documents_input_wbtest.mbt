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
    @documents.Msg::Imported(document_id("empty"), "", test_change_time(0.0)),
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
  let transition = documents.create(document_id("new"), test_change_time(0.0))
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
  let transition = documents.create(document_id("new"), test_change_time(0.0))
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
  guard documents.edit(source_key("two"), "second", test_change_time(1.0))
    is @documents.Edit::Changed(transition) else {
    fail("edit two")
  }
  let documents = transition.model
  let two_revision = pending_revision(documents, source_key("two"))
  let transition = expect_document_update(
    documents,
    @documents.Msg::ApplyPendingEdit(source_key("two"), two_revision),
  )
  let documents = transition.model
  guard documents.edit(source_key("one"), "first", test_change_time(2.0))
    is @documents.Edit::Changed(transition) else {
    fail("edit one")
  }
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

///|
test "local and remote documents share one Change time order" {
  fn at(id : String, time : Double) -> @source_repository.Document {
    @source_repository.Document::create(
      document_id(id),
      id,
      test_change_time(time),
    )
  }

  let saved = @source_repository.SavedDocuments::from_documents([
    at("older local", 10.0),
    at("newer local", 30.0),
  ]).unwrap()
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("account")
  }
  fn remote(id : String, time : Double) -> @source_repository.RemoteEntry {
    @source_repository.RemoteEntry::Present(
      document_id(id),
      @source_repository.SavedRevision::parse(1.0) catch {
        _ => abort("rev")
      },
      id,
      test_change_time(time),
    )
  }

  let remote_seeds = remote_document_seeds(
    {
      account: Some(account),
      entries: [remote("middle remote", 20.0), remote("newest remote", 40.0)],
    },
    { keys: [], can_activate: true, },
  )
  let seeds = recent_document_seeds(
    { ..test_editing(), documents: @documents.Model(saved), },
    remote_seeds,
  ).to_array()
  assert_eq(seeds.map(seed => seed.source()), [
    "newest remote", "newer local", "middle remote", "older local",
  ])
}
