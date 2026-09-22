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
  @documents.Key::replica(account, document_id(id))
}

///|
fn sync_test_saved() -> @source_repository.SavedDocuments {
  let account_a = sync_test_account("account-a")
  let account_b = sync_test_account("account-b")
  let saved = @source_repository.SavedDocuments::from_documents([
    sync_test_document("local", "local"),
  ]).unwrap()
  let revision = @source_repository.SavedRevision::parse(1.0) catch {
    _ => abort("valid synced revision")
  }
  let saved = saved.apply_replica(
    @source_repository.DocumentReplica::receive(
      account_a,
      sync_test_document("shared", "A"),
      revision,
    ),
  ) catch {
    _ => abort("valid account A replica")
  }
  saved.apply_replica(
    @source_repository.DocumentReplica::receive(
      account_b,
      sync_test_document("shared", "B"),
      revision,
    ),
  ) catch {
    _ => abort("valid account B replica")
  }
}

///|
test "account projection exposes local documents and only its replicas" {
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
  let visible = recent_document_seeds(editing, []).to_array()
  assert_false(visible.exists(seed => seed.docid() == token_a))
  assert_true(visible.exists(seed => seed.docid() == token_b))

  let restored = account_b_documents.project_account(account_a)
  assert_eq(restored.text(token_a), Some("A unsaved"))
}

///|
test "synced deletion hides a non-active row while its intent is persisted" {
  let account = sync_test_account("account-a")
  let documents = @documents.State::State(sync_test_saved()).project_account(
    account,
  )
  let token = sync_test_key(account, "shared")
  let (pending, actions) = documents.reduce(
    @documents.Msg::DeleteConfirmed(token),
  )
  guard actions is [@documents.Action::DeleteReplica(edit)] else {
    fail("durable deletion intent")
  }
  assert_eq(pending.text(token), Some("A"))
  assert_true(pending.delete_status(token) is Some(DeletePending))
  let visible = recent_document_seeds(
    { ..test_editing(), documents: pending, },
    [],
  ).to_array()
  assert_false(visible.exists(seed => seed.docid() == token))

  let write = edit.durable().request_deletion()
  let (hidden, _) = pending.reduce(
    @documents.Msg::FeedbackReceived(ReplicaSettled(write, Some(token))),
  )
  assert_eq(hidden.text(token), None)
  assert_true(
    hidden
    .snapshot()
    .replica(account, document_id("shared"))
    .unwrap()
    .is_deleting(),
  )
}

///|
test "failed deletion persistence restores the document and exact retry" {
  let account = sync_test_account("account-a")
  let documents = @documents.State::State(sync_test_saved()).project_account(
    account,
  )
  let token = sync_test_key(account, "shared")
  let (pending, actions) = documents.reduce(
    @documents.Msg::DeleteConfirmed(token),
  )
  guard actions is [@documents.Action::DeleteReplica(edit)] else {
    fail("durable deletion intent")
  }
  let write = edit.durable().request_deletion()
  let (failed, _) = pending.reduce(
    @documents.Msg::FeedbackReceived(
      ReplicaDeletionFailed(
        write,
        @source_repository.ReplicaFailure::WriteFailed,
      ),
    ),
  )
  assert_eq(failed.text(token), Some("A"))
  assert_true(
    failed.delete_status(token)
    is Some(
      DeletePersistenceFailed(@source_repository.ReplicaFailure::WriteFailed)
    ),
  )
  let (_, retry) = failed.reduce(@documents.Msg::RetryDelete(token))
  guard retry is [@documents.Action::RetryReplica(owner, document)] &&
    owner == account &&
    document == document_id("shared") else {
    fail("retry is owned by the persistence lane")
  }
}

///|
test "deletion intent remains isolated to its owning account" {
  let account_a = sync_test_account("account-a")
  let account_b = sync_test_account("account-b")
  let token_a = sync_test_key(account_a, "shared")
  let token_b = sync_test_key(account_b, "shared")
  let documents = @documents.State::State(sync_test_saved()).project_account(
    account_a,
  )
  let (pending, actions) = documents.reduce(
    @documents.Msg::DeleteConfirmed(token_a),
  )
  guard actions is [@documents.Action::DeleteReplica(edit)] else {
    fail("account A deletion")
  }
  let write = edit.durable().request_deletion()
  let (hidden, _) = pending.reduce(
    @documents.Msg::FeedbackReceived(ReplicaSettled(write, Some(token_a))),
  )
  let account_b_documents = hidden.project_account(account_b)
  assert_eq(account_b_documents.text(token_a), None)
  assert_eq(account_b_documents.text(token_b), Some("B"))
}

///|
test "delete conflict restores the working copy for a new decision" {
  let account = sync_test_account("account-a")
  let documents = @documents.State::State(sync_test_saved()).project_account(
    account,
  )
  let token = sync_test_key(account, "shared")
  let (pending, actions) = documents.reduce(
    @documents.Msg::DeleteConfirmed(token),
  )
  guard actions is [@documents.Action::DeleteReplica(edit)] else {
    fail("durable deletion intent")
  }
  let preparing = edit.durable().request_deletion()
  let (hidden, _) = pending.reduce(
    @documents.Msg::FeedbackReceived(ReplicaSettled(preparing, Some(token))),
  )
  guard preparing.replica().directive()
    is @source_repository.ReplicaDirective::CreateOperation(draft) else {
    fail("delete draft")
  }
  let operation_id = @source_repository.OperationId::parse(
    "10000000-0000-4000-8000-000000000001",
  ) catch {
    _ => abort("operation id")
  }
  let sending = draft.start(operation_id)
  let (hidden, _) = hidden.reduce(
    @documents.Msg::FeedbackReceived(ReplicaAdvanced(sending)),
  )
  let revision = @source_repository.SavedRevision::parse(2.0) catch {
    _ => abort("revision")
  }
  guard sending
    .replica()
    .reject_conflict(
      operation_id,
      @source_repository.RemoteDocument::Present(revision, "remote"),
    )
    is @source_repository.ReconcilePlan::Persist(conflict) else {
    fail("delete conflict")
  }
  let (restored, _) = hidden.reduce(
    @documents.Msg::FeedbackReceived(ReplicaSettled(conflict, None)),
  )
  assert_eq(restored.text(token), Some("A"))
  assert_true(restored.delete_status(token) is Some(Deletable))
}
