///|
priv enum DocumentFailure {
  Save(@source_repository.SaveFailure)
  Create(@source_repository.CreateFailure)
  OpeningCreate(@source_repository.CreateFailure)
  Example(Activation, String, @source_repository.CreateFailure)
  Delete(@documents.Key, @source_repository.DeleteFailure)
  DeletePersistence(@documents.Key, @source_repository.ReplicaFailure)
} derive(Eq)

///|
priv struct NoticesInput {
  failure : DocumentFailure?
  import_failed : Bool
  lifecycle_error : String?
} derive(Eq)

///|
fn import_failure_view(dismiss : @rabbita.Cmd) -> @rabbita.Html {
  failure_notice(
    "The Markdown file could not be imported.",
    "Dismiss",
    on_action=Some(dismiss),
  )
}

///|
fn creation_failure_view(
  failure : @source_repository.CreateFailure,
  retry : @rabbita.Cmd,
) -> @rabbita.Html {
  let reason = match failure {
    @source_repository.CreateFailure::DocumentIdentityUnavailable =>
      "This browser cannot create a document identity."
  }
  failure_notice(
    "A new document could not be created. " + reason,
    "Retry creating",
    on_action=Some(retry),
  )
}

///|
fn example_creation_failure_view(
  failure : @source_repository.CreateFailure,
  retry : @rabbita.Cmd,
) -> @rabbita.Html {
  let reason = match failure {
    @source_repository.CreateFailure::DocumentIdentityUnavailable =>
      "This browser cannot create a document identity."
  }
  failure_notice(
    "The example document could not be created. " + reason,
    "Try again",
    on_action=Some(retry),
  )
}

///|
fn delete_failure_view(
  failure : @source_repository.DeleteFailure,
  retry : @rabbita.Cmd,
  dismiss : @rabbita.Cmd,
) -> @rabbita.Html {
  let reason = match failure {
    InvalidSource => "The document is no longer available."
    StorageUnavailable => "Browser storage is unavailable."
    QuotaExceeded => "Browser storage is full."
    WriteFailed => "Browser storage failed while deleting the document."
  }
  @html.div(
    class="flex min-h-12 shrink-0 items-center justify-between gap-4 bg-lm-danger-soft px-4 py-2.5 text-sm text-lm-danger",
    attrs=@html.Attrs::build().role("alert"),
    [
      @html.p("The document was not deleted. " + reason),
      @html.div(class="flex shrink-0 gap-2", [
        @html.button(
          class="min-h-8 rounded-md border border-current px-2.5 py-1",
          on_click=retry,
          "Try again",
        ),
        @html.button(
          class="min-h-8 rounded-md border border-current px-2.5 py-1",
          on_click=dismiss,
          "Dismiss",
        ),
      ]),
    ],
  )
}

///|
fn delete_persistence_failure_view(
  failure : @source_repository.ReplicaFailure,
  retry : @rabbita.Cmd,
) -> @rabbita.Html {
  let reason = match failure {
    InvalidReplica => "The synchronized document state is invalid."
    StorageUnavailable => "Browser storage is unavailable."
    QuotaExceeded => "Browser storage is full."
    WriteFailed => "Browser storage failed while saving the deletion."
  }
  failure_notice(
    "The deletion was not saved. " + reason,
    "Try again",
    on_action=Some(retry),
  )
}

///|
fn save_failure_view(
  failure : @source_repository.SaveFailure?,
  retry : @rabbita.Cmd,
) -> @rabbita.Html {
  let message = match failure {
    None => ""
    Some(failure) => {
      let reason = match failure {
        @source_repository.SaveFailure::InvalidSource =>
          " The document identity is invalid."
        @source_repository.SaveFailure::StorageUnavailable =>
          " Browser storage is unavailable."
        @source_repository.SaveFailure::QuotaExceeded =>
          " Browser storage is full."
        @source_repository.SaveFailure::WriteFailed =>
          " Browser storage failed while writing the document."
      }
      "Changes are not saved in this browser." + reason
    }
  }
  failure_notice(message, "Retry saving", on_action=failure.map(_ => retry))
}
