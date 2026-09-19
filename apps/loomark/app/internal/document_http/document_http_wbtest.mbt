///|
fn document_id() -> @source_repository.DocumentId {
  @source_repository.DocumentId::parse(
    "10000000-0000-4000-8000-000000000001",
  ) catch {
    _ => abort("valid document id")
  }
}

///|
fn operation_id() -> @source_repository.OperationId {
  @source_repository.OperationId::parse(
    "20000000-0000-4000-8000-000000000002",
  ) catch {
    _ => abort("valid operation id")
  }
}

///|
fn second_operation_id() -> @source_repository.OperationId {
  @source_repository.OperationId::parse(
    "20000000-0000-4000-8000-000000000003",
  ) catch {
    _ => abort("valid operation id")
  }
}

///|
fn pending_save() -> @source_repository.PendingOperation {
  let checkpoint = @source_repository.SyncCheckpoint::enroll(
    @source_repository.AccountId::parse("account") catch {
      _ => abort("valid account")
    },
    @source_repository.Document::create(document_id(), "exact text"),
  )
  guard checkpoint.plan_save() is @source_repository.OperationPlan::Start(draft) else {
    abort("save draft")
  }
  guard draft.start(operation_id()).checkpoint().directive()
    is @source_repository.SyncDirective::Send(operation) else {
    abort("pending save")
  }
  operation
}

///|
fn parse_json(value : String) -> Json {
  @json.parse(value) catch { _ => abort("valid JSON") }
}

///|
extern "js" fn install_interrupted_response(body : String) -> Unit =
  #| body => {
  #|   globalThis.__loomarkDocumentHttpFetch = globalThis.fetch;
  #|   globalThis.fetch = async () => new Response(
  #|     new ReadableStream({
  #|       start(controller) {
  #|         controller.enqueue(new TextEncoder().encode(body));
  #|         controller.error(new Error("interrupted response"));
  #|       },
  #|     }),
  #|     { status: 200 },
  #|   );
  #| }

///|
extern "js" fn restore_fetch() -> Unit =
  #| () => {
  #|   globalThis.fetch = globalThis.__loomarkDocumentHttpFetch;
  #|   delete globalThis.__loomarkDocumentHttpFetch;
  #| }

///|
test "mutation JSON is derived from a typed pending operation" {
  let save = pending_save()
  assert_eq(
    parse_json(operation_json(save)),
    parse_json(
      "{\"baseRevision\":0,\"operationId\":\"20000000-0000-4000-8000-000000000002\",\"text\":\"exact text\"}",
    ),
  )

  let checkpoint = @source_repository.SyncCheckpoint::enroll(
    @source_repository.AccountId::parse("account") catch {
      _ => abort("valid account")
    },
    @source_repository.Document::create(document_id(), "exact text"),
  )
  let acknowledged = checkpoint
    .plan_save()
  guard acknowledged is @source_repository.OperationPlan::Start(save_draft) else {
    abort("save draft")
  }
  let acknowledged = save_draft
    .start(operation_id())
    .checkpoint()
    .acknowledge(
      operation_id(),
      @source_repository.SavedRevision::parse(1.0) catch {
        _ => abort("valid revision")
      },
    )
    .checkpoint()
  guard acknowledged.plan_delete()
    is @source_repository.OperationPlan::Start(delete_draft) else {
    abort("delete draft")
  }
  guard delete_draft.start(second_operation_id()).checkpoint().directive()
    is @source_repository.SyncDirective::Send(deletion) else {
    abort("pending deletion")
  }
  assert_eq(
    parse_json(operation_json(deletion)),
    parse_json(
      "{\"baseRevision\":1,\"operationId\":\"20000000-0000-4000-8000-000000000003\"}",
    ),
  )
}

///|
test "receipt parser accepts only the matching operation" {
  let valid =
    "{\"id\":\"10000000-0000-4000-8000-000000000001\",\"operationId\":\"20000000-0000-4000-8000-000000000002\",\"revision\":1}"
  let pending = pending_save()
  assert_eq(receipt(valid, document_id(), pending).unwrap().value(), 1.0)
  assert_eq(
    receipt(
      valid.replace_all(old="000000000002", new="000000000003"),
      document_id(),
      pending,
    ),
    None,
  )
  assert_eq(
    receipt(
      valid.replace_all(old="\"revision\":1", new="\"revision\":2"),
      document_id(),
      pending,
    ),
    None,
  )
}

///|
test "remote parser distinguishes present documents and tombstones" {
  assert_true(
    remote_document(
      "{\"id\":\"10000000-0000-4000-8000-000000000001\",\"revision\":3,\"deleted\":false,\"text\":\"remote\"}",
      document_id(),
    )
    is Some(@source_repository.RemoteDocument::Present(revision, "remote")) &&
    revision.value() == 3.0,
  )
  assert_true(
    remote_document(
      "{\"id\":\"10000000-0000-4000-8000-000000000001\",\"revision\":4,\"deleted\":true,\"text\":null}",
      document_id(),
    )
    is Some(@source_repository.RemoteDocument::Deleted(revision)) &&
    revision.value() == 4.0,
  )
  assert_eq(
    remote_document(
      "{\"id\":\"10000000-0000-4000-8000-000000000001\",\"revision\":4,\"deleted\":true,\"text\":\"invalid\"}",
      document_id(),
    ),
    None,
  )
}

///|
test "error parser rejects ambiguous response shapes" {
  assert_eq(error_code("{\"error\":\"revision_conflict\"}"), Some("revision_conflict"))
  assert_eq(
    error_code("{\"error\":\"revision_conflict\",\"extra\":true}"),
    None,
  )
}

///|
async test "interrupted response cannot acknowledge a pending operation" {
  let body =
    "{\"id\":\"10000000-0000-4000-8000-000000000001\",\"operationId\":\"20000000-0000-4000-8000-000000000002\",\"revision\":1}"
  install_interrupted_response(body)
  defer restore_fetch()
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid account")
  }
  let result = request(
    "https://loomark.test",
    account,
    document_id(),
    pending_save(),
  )
  assert_eq(result, DeliveryResult::Unavailable)
}
