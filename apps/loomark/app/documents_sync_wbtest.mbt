///|
fn sync_test_account(value : String) -> @source_repository.AccountId {
  @source_repository.AccountId::parse(value) catch {
    _ => abort("valid test account")
  }
}

///|
fn sync_test_document(
  id : String,
  text : String,
) -> @source_repository.Document {
  @source_repository.Document::create(document_id(id), text)
}

///|
fn sync_test_key(
  account : @source_repository.AccountId,
  id : String,
) -> @documents.Key {
  @documents.Key::checkpoint(account, document_id(id))
}

///|
fn sync_test_saved() -> @source_repository.SavedDocuments {
  let account_a = sync_test_account("account-a")
  let account_b = sync_test_account("account-b")
  let saved = @source_repository.SavedDocuments::from_documents([
    sync_test_document("local", "local"),
  ]).unwrap()
  let saved = saved.apply_checkpoint(
    @source_repository.SyncCheckpoint::enroll(
      account_a,
      sync_test_document("shared", "A"),
    ),
  ) catch {
    _ => abort("valid account A checkpoint")
  }
  saved.apply_checkpoint(
    @source_repository.SyncCheckpoint::enroll(
      account_b,
      sync_test_document("shared", "B"),
    ),
  ) catch {
    _ => abort("valid account B checkpoint")
  }
}

///|
test "account projection exposes local documents and only its checkpoints" {
  let account_a = sync_test_account("account-a")
  let account_b = sync_test_account("account-b")
  let saved = sync_test_saved()
  let account_a_documents = @documents.State::State(saved).project_account(
    account_a,
  )
  assert_eq(account_a_documents.text(source_key("local")), Some("local"))
  assert_eq(
    account_a_documents.text(sync_test_key(account_a, "shared")),
    Some("A"),
  )

  let account_b_documents = account_a_documents.project_account(account_b)
  assert_eq(account_b_documents.text(source_key("local")), Some("local"))
  assert_eq(
    account_b_documents.text(sync_test_key(account_b, "shared")),
    Some("B"),
  )
}

///|
test "account switch retains optimistic text under its original owner" {
  let account_a = sync_test_account("account-a")
  let account_b = sync_test_account("account-b")
  let token_a = sync_test_key(account_a, "shared")
  let token_b = sync_test_key(account_b, "shared")
  let documents = @documents.State::State(sync_test_saved()).project_account(
    account_a,
  )
  let (documents, _) = documents.reduce(
    @documents.Msg::TextChanged(token_a, "A unsaved"),
  )

  let account_b_documents = documents.project_account(account_b)
  assert_eq(account_b_documents.text(token_a), Some("A unsaved"))
  assert_eq(account_b_documents.text(token_b), Some("B"))
  let editing = {
    ..test_editing(),
    activation: { key: token_a, generation: 0, },
    documents: account_b_documents,
  }
  let visible = recent_document_seeds(editing).to_array()
  assert_false(visible.exists(seed => seed.docid() == token_a))
  assert_true(visible.exists(seed => seed.docid() == token_b))

  let restored = account_b_documents.project_account(account_a)
  assert_eq(restored.text(token_a), Some("A unsaved"))
}

///|
test "synced deletion stays unavailable until its network path is connected" {
  let account = sync_test_account("account-a")
  let documents = @documents.State::State(sync_test_saved()).project_account(
    account,
  )
  let token = sync_test_key(account, "shared")
  let (unchanged, decisions) = documents.reduce(
    @documents.Msg::DeleteConfirmed(token),
  )
  assert_true(unchanged == documents)
  assert_true(decisions.is_empty())
  assert_true(documents.delete_status(token) is Some(NotDeletable))
}

///|
test "synced document remains selectable while deletion is unavailable" {
  let account = sync_test_account("account-a")
  let documents = @documents.State::State(sync_test_saved()).project_account(
    account,
  )
  let editing = { ..test_editing(), documents, }
  let token = sync_test_key(account, "shared")
  let shared = recent_document_seeds(editing)
    .iter()
    .find_first(seed => seed.docid() == token)
    .unwrap()
  assert_true(shared.selection() is @recent_documents.Selection::Selectable)
  assert_true(
    shared.deletion() is @recent_documents.DeletionAvailability::Blocked,
  )
}
