///|
priv enum DocumentFailure {
  OpeningFault(String)
  Create
  Example
  Delete(@source_repository.DeleteFailure)
  DeletePersistence(@source_repository.ReplicaFailure)
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
    Some(Delete(failure)) => {
      let reason = match failure {
        InvalidSource => "The document is no longer available."
        StorageUnavailable => "Browser storage is unavailable."
        QuotaExceeded => "Browser storage is full."
        WriteFailed => "Browser storage failed while deleting the document."
      }
      messages.push("The document was not deleted. " + reason)
    }
    Some(DeletePersistence(failure)) => {
      let reason = match failure {
        InvalidReplica => "The synchronized document state is invalid."
        StorageUnavailable => "Browser storage is unavailable."
        QuotaExceeded => "Browser storage is full."
        WriteFailed => "Browser storage failed while saving the deletion."
      }
      messages.push("The deletion was not saved. " + reason)
    }
  }
  let account = account_notice_message(account_controls_input(model))
  if !account.is_empty() {
    messages.push(account)
  }
  messages
}
