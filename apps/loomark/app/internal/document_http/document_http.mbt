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
pub(all) enum DiscoveryResult {
  Discovered(Array[@source_repository.RemoteEntry])
  AccountChanged
  Unavailable
} derive(Eq, Debug)

///|
extenum @cmd.Extension += {
  Deliver(
    @source_repository.AccountId,
    @source_repository.DocumentId,
    @source_repository.PendingOperation,
    (DeliveryResult) -> @cmd.Cmd
  )
  Get(
    @source_repository.AccountId,
    @source_repository.DocumentId,
    (RemoteResult) -> @cmd.Cmd
  )
  Discover(@source_repository.AccountId, (DiscoveryResult) -> @cmd.Cmd)
}

///|
fn operation_json(operation : @source_repository.PendingOperation) -> String {
  let fields : Map[String, Json] = {
    "operationId": operation.operation_id().value(),
    "baseRevision": operation.base_revision(),
  }
  match operation.content() {
    @source_repository.PendingContent::Save(text) =>
      fields["text"] = text.to_json()
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
  guard value is Json::Object(fields) &&
    fields.length() == 3 &&
    fields.get("id") is Some(Json::String(id)) &&
    fields.get("operationId") is Some(Json::String(operation)) &&
    fields.get("revision") is Some(Json::Number(revision, ..)) &&
    id == document_id.value() &&
    operation == pending.operation_id().value() else {
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
  guard value is Json::Object(fields) &&
    fields.length() == 4 &&
    fields.get("id") is Some(Json::String(id)) &&
    id == document_id.value() &&
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
priv struct DiscoveryPage {
  documents : Array[@source_repository.RemoteEntry]
  next : String?
}

///|
fn discovery_page(body : String, after : String?) -> DiscoveryPage? {
  let value = @json.parse(body) catch { _ => return None }
  guard value is Json::Object(fields) &&
    fields.length() == 2 &&
    fields.get("documents") is Some(Json::Array(documents)) else {
    return None
  }
  let parsed : Array[@source_repository.RemoteEntry] = []
  let mut previous = after
  for value in documents {
    guard value is Json::Object(entry) &&
      entry.get("id") is Some(Json::String(raw_id)) &&
      entry.get("revision") is Some(Json::Number(raw_revision, ..)) else {
      return None
    }
    let id = @source_repository.DocumentId::parse(raw_id) catch {
      _ => return None
    }
    let revision = @source_repository.SavedRevision::parse(raw_revision) catch {
      _ => return None
    }
    guard previous.map(value => value < raw_id).unwrap_or(true) else {
      return None
    }
    let document = match
      (entry.get("deleted"), entry.get("preview"), entry.length()) {
      (Some(Json::False), Some(Json::String(preview)), 4) if preview.char_length() <=
        80 => @source_repository.RemoteEntry::Present(id, revision, preview)
      (Some(Json::True), None, 3) =>
        @source_repository.RemoteEntry::Deleted(id, revision)
      _ => return None
    }
    parsed.push(document)
    previous = Some(raw_id)
  }
  let next = match fields.get("next") {
    Some(Json::Null) => None
    Some(Json::String(next)) if documents.length() > 0 && previous == Some(next) =>
      Some(next)
    _ => return None
  }
  Some({ documents: parsed, next, })
}

///|
async fn request_discovery(
  origin : String,
  account : @source_repository.AccountId,
) -> DiscoveryResult noraise {
  try {
    let documents : Array[@source_repository.RemoteEntry] = []
    let mut after : String? = None
    while true {
      let suffix = after.map(cursor => "?after=" + cursor).unwrap_or("")
      let response = complete_get(
        origin + "/api/documents" + suffix,
        account.value(),
      ).wait()
      match response.status() {
        200 =>
          match discovery_page(response.body(), after) {
            Some(page) => {
              documents.append(page.documents)
              match page.next {
                Some(next) => after = Some(next)
                None => return Discovered(documents)
              }
            }
            None => return Unavailable
          }
        401 => return AccountChanged
        409 if error_code(response.body()) == Some("account_changed") =>
          return AccountChanged
        _ => return Unavailable
      }
    }
    DiscoveryResult::Unavailable
  } catch {
    _ => Unavailable
  } noraise {
    result => result
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
    let response = complete_mutation(url, http_method, account.value(), body).wait()
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
    Get(account, document_id, done) =>
      @cmd.Async(() => {
        done(request_remote(context.get_origin(), account, document_id))
      })
    Discover(account, done) =>
      @cmd.Async(() => done(request_discovery(context.get_origin(), account)))
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
pub fn get(
  account : @source_repository.AccountId,
  document_id : @source_repository.DocumentId,
  emit : @cmd.Emit[RemoteResult],
) -> @cmd.Cmd {
  op.request(Get(account, document_id, result => emit(result)))
}

///|
pub fn discover(
  account : @source_repository.AccountId,
  emit : @cmd.Emit[DiscoveryResult],
) -> @cmd.Cmd {
  op.request(Discover(account, result => emit(result)))
}
