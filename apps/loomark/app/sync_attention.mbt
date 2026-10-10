///|
fn sync_attention_view(
  remote : @documents.RemoteState?,
  persistence : @replica_persistence.Status?,
  activity : @sync.Activity?,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let (notice, action) : (String, (String, Msg)?) = match remote {
    Some(@documents.RemoteState::UpdateAvailable(action)) =>
      ("", Some(("Open update", AcceptRemote(action))))
    Some(@documents.RemoteState::DeletionAvailable(action)) =>
      ("", Some(("Remove deleted document", AcceptRemote(action))))
    Some(@documents.RemoteState::Diverged) => ("Conflicting changes", None)
    Some(@documents.RemoteState::DeletedRemotely) => ("Deletion pending", None)
    _ =>
      match persistence {
        Some(@replica_persistence.Status::Retryable(action, _)) =>
          ("", Some(("Retry saving", RetrySaving(action))))
        _ =>
          match activity {
            Some(@sync.Activity::Retryable(action)) =>
              ("", Some(("Retry sync", RetrySync(action))))
            _ => ("", None)
          }
      }
  }
  let (action_label, message) = match action {
    Some((label, message)) => (label, Some(message))
    None => ("", None)
  }
  @html.fragment([
    sync_status_label(notice),
    sync_status_button(action_label, message, emit),
  ])
}
