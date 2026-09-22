///|
fn document_id() -> @source_repository.DocumentId {
  @source_repository.DocumentId::parse("10000000-0000-4000-8000-000000000001") catch {
    _ => abort("valid document id")
  }
}

///|
fn operation_id() -> @source_repository.OperationId {
  @source_repository.OperationId::parse("20000000-0000-4000-8000-000000000002") catch {
    _ => abort("valid operation id")
  }
}

///|
fn second_operation_id() -> @source_repository.OperationId {
  @source_repository.OperationId::parse("20000000-0000-4000-8000-000000000003") catch {
    _ => abort("valid operation id")
  }
}

///|
fn pending_save() -> @source_repository.PendingOperation {
  let replica = @source_repository.DocumentReplica(
    @source_repository.AccountId::parse("account") catch {
      _ => abort("valid account")
    },
    @source_repository.Document::create(document_id(), "exact text"),
  )
  guard replica.directive()
    is @source_repository.ReplicaDirective::CreateOperation(draft) else {
    abort("save draft")
  }
  guard draft.start(operation_id()).replica().directive()
    is @source_repository.ReplicaDirective::Send(operation) else {
    abort("pending save")
  }
  operation
}

///|
fn parse_json(value : String) -> Json {
  @json.parse(value) catch {
    _ => abort("valid JSON")
  }
}

///|
extern "js" fn install_test_fetch(
  receipt : String,
  first : String,
  second : String,
  partial : String,
) -> Unit =
  #| (receipt, first, second, partial) => {
  #|   globalThis.__loomarkDocumentHttpFetch = globalThis.fetch;
  #|   globalThis.fetch = async url => {
  #|     const request = new URL(String(url));
  #|     if (request.hostname === "discovery.test") {
  #|       return new Response(request.search ? second : first, { status: 200 });
  #|     }
  #|     const body = request.hostname === "delivery.test" ? receipt : partial;
  #|     return new Response(
  #|       new ReadableStream({
  #|         start(controller) {
  #|           controller.enqueue(new TextEncoder().encode(body));
  #|           controller.error(new Error("interrupted response"));
  #|         },
  #|       }),
  #|       { status: 200 },
  #|     );
  #|   };
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

  let replica = @source_repository.DocumentReplica(
    @source_repository.AccountId::parse("account") catch {
      _ => abort("valid account")
    },
    @source_repository.Document::create(document_id(), "exact text"),
  )
  guard replica.directive()
    is @source_repository.ReplicaDirective::CreateOperation(save_draft) else {
    abort("save draft")
  }
  let acknowledged = save_draft
    .start(operation_id())
    .replica()
    .acknowledge(
      operation_id(),
      @source_repository.SavedRevision::parse(1.0) catch {
        _ => abort("valid revision")
      },
    )
    .replica()
  let deleting = acknowledged.request_deletion().replica()
  guard deleting.directive()
    is @source_repository.ReplicaDirective::CreateOperation(delete_draft) else {
    abort("delete draft")
  }
  guard delete_draft.start(second_operation_id()).replica().directive()
    is @source_repository.ReplicaDirective::Send(deletion) else {
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
  let valid = "{\"id\":\"10000000-0000-4000-8000-000000000001\",\"operationId\":\"20000000-0000-4000-8000-000000000002\",\"revision\":1}"
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
test "discovery parser admits only ordered bounded metadata" {
  let first = "10000000-0000-4000-8000-000000000001"
  let second = "10000000-0000-4000-8000-000000000002"
  let body = "{\"documents\":[{\"id\":\"\{first}\",\"revision\":1,\"deleted\":false,\"preview\":\"First\"},{\"id\":\"\{second}\",\"revision\":2,\"deleted\":true}],\"next\":\"\{second}\"}"
  guard discovery_page(body, None) is Some(page) else {
    fail("valid discovery page")
  }
  assert_eq(page.documents.length(), 2)
  assert_eq(page.next, Some(second))
  assert_true(discovery_page(body.replace(old=second, new=first), None) is None)
  assert_true(
    discovery_page(
      body.replace(old="\"next\":\"\{second}\"", new="\"next\":\"other\""),
      None,
    )
    is None,
  )
}

///|
async test "HTTP requests complete pagination and reject interrupted bodies" {
  let first_id = "10000000-0000-4000-8000-000000000001"
  let second_id = "10000000-0000-4000-8000-000000000002"
  install_test_fetch(
    "{\"id\":\"\{first_id}\",\"operationId\":\"20000000-0000-4000-8000-000000000002\",\"revision\":1}",
    "{\"documents\":[{\"id\":\"\{first_id}\",\"revision\":1,\"deleted\":false,\"preview\":\"First\"}],\"next\":\"\{first_id}\"}",
    "{\"documents\":[{\"id\":\"\{second_id}\",\"revision\":2,\"deleted\":false,\"preview\":\"Second\"}],\"next\":null}",
    "{\"documents\":[{\"id\":\"\{first_id}\",\"revision\":1,\"deleted\":false,\"preview\":\"Partial\"}],\"next\":null}",
  )
  defer restore_fetch()
  let account = @source_repository.AccountId::parse("account") catch {
    _ => abort("valid account")
  }
  guard request_discovery("https://discovery.test", account)
    is DiscoveryResult::Discovered(entries) else {
    fail("discovered documents")
  }
  assert_eq(entries.length(), 2)
  assert_eq(entries[0].document_id().value(), first_id)
  assert_eq(entries[1].document_id().value(), second_id)
  assert_eq(
    request("https://delivery.test", account, document_id(), pending_save()),
    DeliveryResult::Unavailable,
  )
  assert_eq(
    request_discovery("https://interrupted.test", account),
    DiscoveryResult::Unavailable,
  )
}

///|
test "error parser rejects ambiguous response shapes" {
  assert_eq(
    error_code("{\"error\":\"revision_conflict\"}"),
    Some("revision_conflict"),
  )
  assert_eq(
    error_code("{\"error\":\"revision_conflict\",\"extra\":true}"),
    None,
  )
}
