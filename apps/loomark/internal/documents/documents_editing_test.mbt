///|
fn editing_fixture_id(value : String) -> @source_repository.DocumentId {
  @source_repository.DocumentId::parse(value) catch {
    _ => abort("valid editing fixture identity")
  }
}

///|
fn editing_fixture_document(
  id : String,
  text : String,
) -> @source_repository.Document {
  @source_repository.Document::create(editing_fixture_id(id), text)
}

///|
fn editing_fixture_model() -> @documents.Model {
  @documents.Model(
    @source_repository.SavedDocuments::from_documents([
      editing_fixture_document("a0000000-0000-4000-8000-000000000011", "one"),
      editing_fixture_document("a0000000-0000-4000-8000-000000000012", "two"),
    ]).unwrap(),
  )
}

///|
fn editing_fixture_key(id : String) -> @documents.Key {
  @documents.Key::source(editing_fixture_id(id))
}

///|
fn editing_recent_text(
  model : @documents.Model,
  key : @documents.Key,
) -> String? {
  let entries = model.recent()
  entries
  .exact_view()
  .search_by(entry => entry.0 == key)
  .map(index => entries[index].1)
}

///|
fn editing_applied(outcome : @documents.Update) -> @documents.Transition raise {
  match outcome {
    Applied(transition) => transition
    Unchanged | Superseded => fail("expected an applied document update")
  }
}

///|
test "editing updates text immediately but publishes Recent after the quiet callback" {
  let key = editing_fixture_key("a0000000-0000-4000-8000-000000000011")
  let (documents, _) = match editing_fixture_model().edit(key, "changed") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  assert_eq(documents.text(key), Some("changed"))
  assert_eq(editing_recent_text(documents, key), Some("one"))
  guard documents.pending_edits() is [(pending_key, stale_revision)] &&
    pending_key == key else {
    fail("expected a pending edit")
  }

  let (documents, _) = match documents.edit(key, "newer") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  assert_eq(documents.text(key), Some("newer"))
  assert_true(
    documents.update(ApplyPendingEdit(key, stale_revision)) is Superseded,
  )
  assert_eq(documents.text(key), Some("newer"))
  assert_eq(editing_recent_text(documents, key), Some("one"))
  guard documents.pending_edits() is [(pending_key, revision)] &&
    pending_key == key else {
    fail("newer edit must remain pending")
  }
  let applied = editing_applied(
    documents.update(ApplyPendingEdit(key, revision)),
  )
  assert_eq(applied.model.text(key), Some("newer"))
  assert_eq(editing_recent_text(applied.model, key), Some("newer"))
  assert_true(applied.model.pending_edits().is_empty())
}

///|
test "returning exactly to saved text cancels pending work and Recent lead" {
  let key = editing_fixture_key("a0000000-0000-4000-8000-000000000011")
  let (documents, _) = match editing_fixture_model().edit(key, "changed") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  let (documents, effects) = match documents.edit(key, "one") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  assert_true(effects.is_empty())
  assert_eq(documents.text(key), Some("one"))
  assert_true(documents.save_status(key) is Some(Clean))
  assert_true(documents.pending_edits().is_empty())
  assert_eq(editing_recent_text(documents, key), Some("one"))
}

///|
test "first edit to New establishes a public Recent entry" {
  let id = editing_fixture_id("a0000000-0000-4000-8000-000000000013")
  let documents = @documents.Model(
    @source_repository.SavedDocuments::from_documents([]).unwrap(),
  )
  let created = editing_applied(documents.update(New(id)))
  let key = @documents.Key::source(id)
  assert_eq(
    created.model.document(key).map(document => document.text()),
    Some(""),
  )
  assert_eq(editing_recent_text(created.model, key), None)
  let (documents, _) = match created.model.edit(key, "first") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  assert_eq(documents.text(key), Some("first"))
  assert_eq(editing_recent_text(documents, key), Some("first"))
}

///|
test "empty Import is immediately visible and requests persistence" {
  let id = editing_fixture_id("a0000000-0000-4000-8000-000000000014")
  let key = @documents.Key::source(id)
  let created = editing_applied(
    @documents.Model(
      @source_repository.SavedDocuments::from_documents([]).unwrap(),
    ).update(Imported(id, "")),
  )
  guard created.effects is [PersistSource(operation)] else {
    fail("empty Import must persist immediately")
  }
  assert_eq(operation.key, key)
  assert_eq(operation.document.text(), "")
  assert_eq(created.model.text(key), Some(""))
  assert_eq(created.model.document(key), Some(operation.document))
  assert_true(created.model.save_status(key) is Some(Unsaved))
  assert_eq(editing_recent_text(created.model, key), Some(""))
  assert_eq(created.model.snapshot().find(id), None)
}

///|
test "saved activation remains resumable while an ephemeral New does not" {
  let original_id = editing_fixture_id("a0000000-0000-4000-8000-000000000011")
  let original_key = @documents.Key::source(original_id)
  let (documents, _) = match
    editing_fixture_model().edit(original_key, "one!") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  assert_eq(
    documents.document(original_key).map(document => document.text()),
    Some("one!"),
  )
  assert_true(documents.resume_hint(original_key) is Some(_))
  assert_eq(
    documents.snapshot().find(original_id).map(document => document.text()),
    Some("one"),
  )

  let new_id = editing_fixture_id("a0000000-0000-4000-8000-000000000015")
  let documents = editing_applied(documents.update(New(new_id))).model
  let new_key = @documents.Key::source(new_id)
  assert_eq(
    documents.document(new_key).map(document => document.text()),
    Some(""),
  )
  assert_true(documents.resume_hint(new_key) is None)
}

///|
test "duplicate text edit is SameText" {
  let key = editing_fixture_key("a0000000-0000-4000-8000-000000000011")
  let (documents, _) = match editing_fixture_model().edit(key, "one!") {
    Changed(transition) => (transition.model, transition.effects)
    SameText => fail("unexpected unchanged edit")
  }
  assert_true(documents.edit(key, "one!") is SameText)
}
