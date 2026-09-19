///|
pub(all) enum DeliveryResult {
  Acknowledged(@source_repository.SavedRevision)
  RevisionConflict
  AccountChanged
  DocumentTooLarge
  OperationRejected
  Unavailable
} derive(Eq, Debug)

///|
pub(all) enum RemoteResult {
  Found(@source_repository.RemoteDocument)
  AccountChanged
  Unavailable
} derive(Eq, Debug)

///|
extenum @cmd.Extension += {
  Deliver(
    @source_repository.AccountId,
    @source_repository.DocumentId,
    @source_repository.PendingOperation,
    (DeliveryResult) -> @cmd.Cmd,
  )
  OpenRemote(
    @source_repository.AccountId,
    @source_repository.DocumentId,
    (RemoteResult) -> @cmd.Cmd,
  )
}

///|
fn operation_json(operation : @source_repository.PendingOperation) -> String {
  let fields : Map[String, Json] = {
    "operationId": operation.operation_id().value(),
    "baseRevision": operation.base_revision(),
  }
  match operation.content() {
    @source_repository.PendingContent::Save(text) => fields["text"] = text.to_json()
    Delete => ()
  }
  Json::object(fields).stringify()
}

///|
fn error_code(body : String) -> String? {
  let value = @json.parse(body) catch { _ => return None }
  guard value is Json::Object(fields) &&
    fields.length() == 1 &&
    fields.get("error") is Some(Json::String(code)) else {
    return None
  }
  Some(code)
}

///|
fn receipt(
  body : String,
  document_id : @source_repository.DocumentId,
  pending : @source_repository.PendingOperation,
) -> @source_repository.SavedRevision? {
  let value = @json.parse(body) catch { _ => return None }
  guard value is Json::Object(fields) && fields.length() == 3 &&
    fields.get("id") is Some(Json::String(id)) &&
    fields.get("operationId") is Some(Json::String(operation)) &&
    fields.get("revision") is Some(Json::Number(revision, ..)) &&
    id == document_id.value() && operation == pending.operation_id().value() else {
    return None
  }
  let revision = @source_repository.SavedRevision::parse(revision) catch {
    _ => return None
  }
  guard revision.value() == pending.base_revision() + 1.0 else { return None }
  Some(revision)
}

///|
fn remote_document(
  body : String,
  document_id : @source_repository.DocumentId,
) -> @source_repository.RemoteDocument? {
  let value = @json.parse(body) catch { _ => return None }
  guard value is Json::Object(fields) && fields.length() == 4 &&
    fields.get("id") is Some(Json::String(id)) && id == document_id.value() &&
    fields.get("revision") is Some(Json::Number(revision, ..)) else {
    return None
  }
  let revision = @source_repository.SavedRevision::parse(revision) catch {
    _ => return None
  }
  match (fields.get("deleted"), fields.get("text")) {
    (Some(Json::False), Some(Json::String(text))) =>
      Some(@source_repository.RemoteDocument::Present(revision, text))
    (Some(Json::True), Some(Json::Null)) =>
      Some(@source_repository.RemoteDocument::Deleted(revision))
    _ => None
  }
}

///|
async fn request_remote(
  origin : String,
  account : @source_repository.AccountId,
  document_id : @source_repository.DocumentId,
) -> RemoteResult noraise {
  try {
    let response = complete_get(
      origin + "/api/documents/" + document_id.value(),
      account.value(),
    ).wait()
    match response.status() {
      200 =>
        match remote_document(response.body(), document_id) {
          Some(remote) => Found(remote)
          None => Unavailable
        }
      401 => AccountChanged
      409 if error_code(response.body()) == Some("account_changed") =>
        AccountChanged
      _ => Unavailable
    }
  } catch {
    _ => Unavailable
  } noraise {
    result => result
  }
}

///|
async fn request(
  origin : String,
  account : @source_repository.AccountId,
  document_id : @source_repository.DocumentId,
  operation : @source_repository.PendingOperation,
) -> DeliveryResult noraise {
  try {
    let url = origin + "/api/documents/" + document_id.value()
    let body = operation_json(operation)
    let http_method = match operation.content() {
      @source_repository.PendingContent::Save(_) => "PUT"
      Delete => "DELETE"
    }
    let response = complete_mutation(
      url,
      http_method,
      account.value(),
      body,
    ).wait()
    match response.status() {
      200 =>
        match receipt(response.body(), document_id, operation) {
          Some(revision) => Acknowledged(revision)
          None => Unavailable
        }
      401 => AccountChanged
      409 =>
        match error_code(response.body()) {
          Some("account_changed") => AccountChanged
          Some("revision_conflict") => RevisionConflict
          _ => Unavailable
        }
      413 => DocumentTooLarge
      422 => OperationRejected
      _ => Unavailable
    }
  } catch {
    _ => Unavailable
  } noraise {
    result => result
  }
}

///|
let op : @cmd.Op = @cmd.Op()..on_invoke((extension, context) => {
  match extension {
    Deliver(account, document_id, operation, done) =>
      @cmd.Async(() => {
        done(request(context.get_origin(), account, document_id, operation))
      })
    OpenRemote(account, document_id, done) =>
      @cmd.Async(() => {
        done(request_remote(context.get_origin(), account, document_id))
      })
    _ => raise @cmd.Unhandled
  }
})

///|
pub fn deliver(
  account : @source_repository.AccountId,
  document_id : @source_repository.DocumentId,
  operation : @source_repository.PendingOperation,
  emit : @cmd.Emit[DeliveryResult],
) -> @cmd.Cmd {
  op.request(Deliver(account, document_id, operation, result => emit(result)))
}

///|
pub fn fetch_remote(
  account : @source_repository.AccountId,
  document_id : @source_repository.DocumentId,
  emit : @cmd.Emit[RemoteResult],
) -> @cmd.Cmd {
  op.request(OpenRemote(account, document_id, result => emit(result)))
}
