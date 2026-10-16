///|
priv enum DocumentFailure {
  OpeningFault(String)
  Create
  Example
}

///|
priv struct NoticesInput {
  failure : DocumentFailure?
  import_failed : Bool
  lifecycle_error : String?
}

///|
fn error_messages(model : Model) -> Array[String] {
  let input = notices_input(model)
  let messages : Array[String] = []
  if input.lifecycle_error is Some(message) {
    messages.push(message)
  }
  if input.import_failed {
    messages.push("The Markdown file could not be imported.")
  }
  match input.failure {
    None => ()
    Some(OpeningFault(message)) => messages.push(message)
    Some(Create) => messages.push("A new document could not be created.")
    Some(Example) => messages.push("The example document could not be created.")
  }
  let account = account_notice_message(account_controls_input(model))
  if !account.is_empty() {
    messages.push(account)
  }
  messages
}

///|
fn deletion_error(before : Page, after : Page, msg : Msg) -> String? {
  let key = match msg {
    DocumentDeleteFailed(operation, _) => operation.key
    Sync(ReplicaWriteCompleted(attempt, Err(_))) => {
      let replica = attempt.write().replica()
      @documents.Key::replica(replica.account(), replica.document_id())
    }
    _ => return None
  }
  let status = fn(page : Page) {
    match page {
      Editing(editing) => editing.documents.delete_status(key)
      OpeningNew(opening, _) => opening.documents.delete_status(key)
      _ => None
    }
  }
  let next = status(after)
  // Only accepted failure transitions notify. Stale completions and navigation
  // must not replay an error, even when another document is being edited.
  guard status(before) != next else { return None }
  match next {
    Some(@documents.DeleteStatus::DeleteFailed(failure)) => {
      let reason = match failure {
        InvalidSource => "The document is no longer available."
        StorageUnavailable => "Browser storage is unavailable."
        QuotaExceeded => "Browser storage is full."
        WriteFailed => "Browser storage failed while deleting the document."
      }
      Some("The document was not deleted. " + reason)
    }
    Some(@documents.DeleteStatus::DeletePersistenceFailed(failure)) => {
      let reason = match failure {
        InvalidReplica => "The synchronized document state is invalid."
        StorageUnavailable => "Browser storage is unavailable."
        QuotaExceeded => "Browser storage is full."
        WriteFailed => "Browser storage failed while saving the deletion."
      }
      Some("The deletion was not saved. " + reason)
    }
    _ => None
  }
}
