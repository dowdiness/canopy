///|
fn fixture_document(text : String) -> @source_repository.Document {
  let id = @source_repository.DocumentId::parse(
    "a0000000-0000-4000-8000-000000000001",
  ) catch {
    _ => abort("invalid fixture identity")
  }
  @source_repository.Document::create(id, text)
}

///|
fn fixture_model() -> @documents.Model {
  @documents.Model(
    @source_repository.SavedDocuments::from_documents([
      fixture_document("stored"),
    ]).unwrap(),
  )
}

///|
fn edited(
  model : @documents.Model,
  key : @documents.Key,
  text : String,
) -> @documents.Transition raise {
  guard model.edit(key, text) is Changed(transition) else {
    fail("fixture edit must change text")
  }
  transition
}

///|
fn applied(
  model : @documents.Model,
  msg : @documents.Msg,
) -> @documents.Transition raise {
  guard model.update(msg) is Applied(transition) else {
    fail("current lifecycle input must be applied")
  }
  transition
}

///|
test "edit refusal and duplicate deletion are distinct public outcomes" {
  let document = fixture_document("stored")
  let key = @documents.Key::source(document.id())
  let model = fixture_model()
  let missing = @documents.Key::source(
    @source_repository.DocumentId::parse("a0000000-0000-4000-8000-000000000002"),
  )
  let missing_edit = try {
    ignore(model.edit(missing, "text"))
    false
  } catch {
    @documents.EditError::DocumentMissing(actual) => actual == missing
    _ => false
  }
  assert_true(missing_edit)
  guard model.delete(key) is Accepted(deletion) else {
    fail("first deletion must be accepted")
  }
  let deleting = deletion.model
  assert_true(deleting.delete(key) is AlreadyPending)
  let blocked_edit = try {
    ignore(deleting.edit(key, "must not replace text"))
    false
  } catch {
    @documents.EditError::PendingDeletion(actual) => actual == key
    _ => false
  }
  assert_true(blocked_edit)
  assert_eq(deleting.text(key), Some("stored"))
  assert_true(deleting.delete_status(key) is Some(DeletePending))
}

///|
test "current acknowledgment mismatch raises while duplicate completion is superseded" {
  let original = fixture_document("stored")
  let key = @documents.Key::source(original.id())
  let changed = edited(fixture_model(), key, "working")
  let saving = applied(changed.model, VisibilityFlush(key))
  guard saving.effects is [PersistSource(operation)] else {
    fail("visibility flush must persist the current source")
  }
  let mismatch = try {
    ignore(saving.model.update(Saved(operation, fixture_document("wrong"))))
    false
  } catch {
    @documents.UpdateError::DocumentMismatch(actual) => actual == key
    _ => false
  }
  assert_true(mismatch)
  assert_eq(saving.model.text(key), Some("working"))
  assert_eq(saving.model.snapshot().find(original.id()), Some(original))
  let stored = applied(saving.model, Saved(operation, operation.document))
  assert_eq(
    stored.model.snapshot().find(original.id()),
    Some(operation.document),
  )
  assert_true(stored.model.save_status(key) is Some(Clean))
  assert_true(
    stored.model.update(Saved(operation, operation.document)) is Superseded,
  )
}

///|
test "failed deletion resumes newer text and stale deletion cannot remove its retry" {
  let key = @documents.Key::source(fixture_document("stored").id())
  let first_edit = edited(fixture_model(), key, "first")
  let saving = applied(first_edit.model, VisibilityFlush(key))
  guard saving.effects is [PersistSource(first_save)] else {
    fail("first save")
  }
  let newer = edited(saving.model, key, "latest")
  let eligible = applied(newer.model, VisibilityFlush(key))
  guard eligible.model.delete(key) is Accepted(waiting) else {
    fail("delete must wait for existing save")
  }
  assert_true(waiting.effects.is_empty())
  let deleting = applied(waiting.model, Saved(first_save, first_save.document))
  guard deleting.effects is [DeleteSource(first_delete)] else {
    fail("saved acknowledgment must start deletion without a newer write")
  }
  let resumed = applied(deleting.model, DeleteFailed(first_delete, WriteFailed))
  guard resumed.effects is [PersistSource(latest_save)] else {
    fail("failed deletion must resume the eligible latest text")
  }
  assert_eq(latest_save.document.text(), "latest")
  assert_eq(resumed.model.text(key), Some("latest"))
  assert_eq(
    resumed.model.snapshot().find(first_save.document.id()),
    Some(first_save.document),
  )
  guard resumed.model.delete(key) is Accepted(retrying) else {
    fail("explicit retry must wait for resumed save")
  }
  assert_true(
    retrying.model.update(Deleted(first_delete, first_delete.document_id))
    is Superseded,
  )
  let retrying_delete = applied(
    retrying.model,
    Saved(latest_save, latest_save.document),
  )
  guard retrying_delete.effects is [DeleteSource(current_delete)] else {
    fail("retry must start after the resumed save")
  }
  assert_true(current_delete != first_delete)
  let removed = applied(
    retrying_delete.model,
    Deleted(current_delete, current_delete.document_id),
  )
  assert_eq(removed.model.text(key), None)
  assert_eq(removed.model.snapshot().find(current_delete.document_id), None)
}

///|
test "wrong deletion identity is an error and preserves the current operation" {
  let original = fixture_document("stored")
  let key = @documents.Key::source(original.id())
  guard fixture_model().delete(key) is Accepted(deleting) else {
    fail("delete must be accepted")
  }
  guard deleting.effects is [DeleteSource(operation)] else {
    fail("existing source requires a storage delete")
  }
  let wrong_id = @source_repository.DocumentId::parse(
    "a0000000-0000-4000-8000-000000000002",
  )
  let mismatch = try {
    ignore(deleting.model.update(Deleted(operation, wrong_id)))
    false
  } catch {
    @documents.UpdateError::DocumentMismatch(actual) => actual == key
    _ => false
  }
  assert_true(mismatch)
  assert_eq(deleting.model.snapshot().find(original.id()), Some(original))
  assert_eq(deleting.model.text(key), Some("stored"))
  let removed = applied(deleting.model, Deleted(operation, original.id()))
  assert_eq(removed.model.snapshot().find(original.id()), None)
  assert_eq(removed.model.text(key), None)
}

///|
test "ownership transfer accepts edits but rejects deletion until promotion settles" {
  let key = @documents.Key::source(fixture_document("stored").id())
  let account = @source_repository.AccountId::parse("lifecycle-account")
  let model = fixture_model()
  guard model.sync_start(key, account) is Ready(start) else {
    fail("acknowledged source can start synchronization")
  }
  let (promoting, effects) = model.start_sync(start)
  guard effects is [StoreReplica(write)] else { fail("promotion effect") }
  let changed = edited(promoting, key, "edited during promotion")
  let refused = try {
    ignore(changed.model.delete(key))
    false
  } catch {
    @documents.DeleteError::OwnershipTransferInProgress(actual) => actual == key
    _ => false
  }
  assert_true(refused)
  assert_eq(changed.model.text(key), Some("edited during promotion"))
  let eligible = applied(changed.model, VisibilityFlush(key))
  let resumed = applied(eligible.model, PromotionFailed(write, WriteFailed))
  guard resumed.effects is [PersistSource(operation)] else {
    fail("failed promotion must resume the eligible local edit")
  }
  assert_eq(operation.document.text(), "edited during promotion")
  assert_true(resumed.model.delete_status(key) is Some(Deletable))
}

///|
test "save attempts fence duplicate failures after retrying identical text" {
  let key = @documents.Key::source(fixture_document("stored").id())
  let changed = edited(fixture_model(), key, "retry this text")
  let saving = applied(changed.model, VisibilityFlush(key))
  guard saving.effects is [PersistSource(first)] else { fail("first save") }
  let failed = applied(saving.model, SaveFailed(first, WriteFailed))
  let retrying = applied(failed.model, RetrySave(key))
  guard retrying.effects is [PersistSource(retry)] else { fail("retry save") }
  assert_true(
    retrying.model.update(SaveFailed(first, WriteFailed)) is Superseded,
  )
  assert_true(retrying.model.update(Saved(first, first.document)) is Superseded)
  let stored = applied(retrying.model, Saved(retry, retry.document))
  assert_eq(
    stored.model.snapshot().find(retry.document.id()),
    Some(retry.document),
  )
}

///|
test "save attempts fence callbacks after reimporting identical identity and text" {
  let document = fixture_document("imported text")
  let key = @documents.Key::source(document.id())
  let empty = @documents.Model(
    @source_repository.SavedDocuments::from_documents([]).unwrap(),
  )
  let importing = applied(empty, Imported(document.id(), document.text()))
  guard importing.effects is [PersistSource(first)] else {
    fail("first import")
  }
  let failed = applied(importing.model, SaveFailed(first, WriteFailed))
  guard failed.model.delete(key) is Accepted(removed) else {
    fail("remove unsaved import")
  }
  let importing = applied(
    removed.model,
    Imported(document.id(), document.text()),
  )
  guard importing.effects is [PersistSource(current)] else {
    fail("second import")
  }
  assert_true(
    importing.model.update(Saved(first, first.document)) is Superseded,
  )
  assert_true(
    importing.model.update(SaveFailed(first, WriteFailed)) is Superseded,
  )
  assert_eq(importing.model.snapshot().find(document.id()), None)
  let stored = applied(importing.model, Saved(current, current.document))
  assert_eq(stored.model.snapshot().find(document.id()), Some(document))
}

///|
test "current satisfied inputs are unchanged rather than superseded" {
  let model = fixture_model()
  let key = @documents.Key::source(fixture_document("stored").id())
  for
    msg in [
      @documents.Msg::RetrySave(key),
      DismissDeleteFailure(key),
      VisibilityFlush(key),
      VisibilityFlushAll,
      CompositionEnded(key),
    ] {
    assert_true(model.update(msg) is Unchanged)
  }
  let composing = applied(model, CompositionStarted(key))
  assert_true(composing.model.update(CompositionStarted(key)) is Unchanged)
  assert_true(composing.model.is_composing(key))
}

///|
test "requests require a document while notifications for a removed document expire" {
  let key = @documents.Key::source(fixture_document("stored").id())
  let model = @documents.Model(
    @source_repository.SavedDocuments::from_documents([]).unwrap(),
  )
  for msg in [@documents.Msg::RetrySave(key), DismissDeleteFailure(key)] {
    let refusal = try {
      ignore(model.update(msg))
      false
    } catch {
      @documents.UpdateError::DocumentMissing(actual) => actual == key
      _ => false
    }
    assert_true(refusal)
  }
  for
    msg in [
      @documents.Msg::CompositionStarted(key),
      CompositionEnded(key),
      VisibilityFlush(key),
    ] {
    assert_true(model.update(msg) is Superseded)
  }
}

///|
test "retry during composition is refused without losing the failure or text" {
  let key = @documents.Key::source(fixture_document("stored").id())
  let changed = edited(fixture_model(), key, "unsaved")
  let saving = applied(changed.model, VisibilityFlush(key))
  guard saving.effects is [PersistSource(first)] else { fail("source save") }
  let failed = applied(saving.model, SaveFailed(first, WriteFailed))
  let composing = applied(failed.model, CompositionStarted(key))
  let refusal = try {
    ignore(composing.model.update(RetrySave(key)))
    false
  } catch {
    @documents.UpdateError::CompositionInProgress(actual) => actual == key
    _ => false
  }
  assert_true(refusal)
  assert_eq(composing.model.text(key), Some("unsaved"))
  assert_true(composing.model.save_status(key) is Some(SaveFailed(WriteFailed)))
  let ended = applied(composing.model, CompositionEnded(key))
  assert_true(ended.effects.is_empty())
  let retry = applied(ended.model, RetrySave(key))
  guard retry.effects is [PersistSource(current)] else {
    fail("retry source save")
  }
  assert_eq(current.document.text(), "unsaved")
  assert_true(retry.model.update(RetrySave(key)) is Unchanged)
  let saved = applied(retry.model, Saved(current, current.document))
  assert_true(saved.model.save_status(key) is Some(Clean))
}

///|
test "retry cannot override an accepted deletion" {
  let key = @documents.Key::source(fixture_document("stored").id())
  guard fixture_model().delete(key) is Accepted(deleting) else {
    fail("delete source")
  }
  let refusal = try {
    ignore(deleting.model.update(RetrySave(key)))
    false
  } catch {
    @documents.UpdateError::PendingDeletion(actual) => actual == key
    _ => false
  }
  assert_true(refusal)
  assert_eq(deleting.model.text(key), Some("stored"))
  guard deleting.effects is [DeleteSource(operation)] else {
    fail("source deletion")
  }
  let deleted = applied(
    deleting.model,
    Deleted(operation, operation.document_id),
  )
  assert_eq(deleted.model.document(key), None)
}

///|
test "dismissing a deletion failure clears only the failure and is idempotent" {
  let key = @documents.Key::source(fixture_document("stored").id())
  guard fixture_model().delete(key) is Accepted(deleting) else {
    fail("delete source")
  }
  guard deleting.effects is [DeleteSource(operation)] else {
    fail("source deletion")
  }
  let failed = applied(deleting.model, DeleteFailed(operation, WriteFailed))
  let dismissed = applied(failed.model, DismissDeleteFailure(key))
  assert_true(dismissed.model.delete_status(key) is Some(Deletable))
  assert_eq(dismissed.model.text(key), Some("stored"))
  assert_true(dismissed.effects.is_empty())
  assert_true(dismissed.model.update(DismissDeleteFailure(key)) is Unchanged)
}

///|
test "repeated visibility flush keeps one eligible follow-up behind a source save" {
  let key = @documents.Key::source(fixture_document("stored").id())
  let changed = edited(fixture_model(), key, "first")
  let saving = applied(changed.model, VisibilityFlush(key))
  guard saving.effects is [PersistSource(first)] else {
    fail("first source save")
  }
  let newer = edited(saving.model, key, "latest")
  let eligible = applied(newer.model, VisibilityFlush(key))
  assert_true(eligible.effects.is_empty())
  assert_true(eligible.model.update(VisibilityFlush(key)) is Unchanged)
  let settled = applied(eligible.model, Saved(first, first.document))
  guard settled.effects is [PersistSource(latest)] else {
    fail("one follow-up source save")
  }
  assert_eq(latest.document.text(), "latest")
}
