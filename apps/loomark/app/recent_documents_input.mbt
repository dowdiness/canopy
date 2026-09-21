///|
priv struct RemoteDocuments {
  account : @source_repository.AccountId?
  entries : Array[@source_repository.RemoteEntry]
} derive(Eq)

///|
priv struct DocumentMembership {
  keys : Array[@documents.Key]
  can_activate : Bool
} derive(Eq)

///|
fn document_membership(page : Page) -> DocumentMembership {
  match page {
    Editing(editing) =>
      {
        keys: editing.documents.recent().map(item => item.0),
        can_activate: editing.can_activate(),
      }
    Loading(_) | PreparingNew(_) | Recovery(_, _) =>
      { keys: [], can_activate: false, }
  }
}

///|
fn remote_documents(sync : @sync.State) -> RemoteDocuments {
  {
    account: match sync.session() {
      @sync.Session::Current(account, _) => Some(account)
      _ => None
    },
    entries: sync.catalog(),
  }
}

///|
fn remote_document_seeds(
  remote : RemoteDocuments,
  membership : DocumentMembership,
) -> Array[@recent_documents.Seed[@documents.Key]] {
  match remote.account {
    Some(account) =>
      remote.entries.filter_map(entry => {
        guard entry is @source_repository.RemoteEntry::Present(id, _, preview) else {
          return None
        }
        let key = @documents.Key::replica(account, id)
        guard !membership.keys.contains(key) else { return None }
        Some(
          @recent_documents.Seed::Seed(
            docid=key,
            source=preview,
            selection=if membership.can_activate {
              @recent_documents.Selection::Selectable
            } else {
              @recent_documents.Selection::Blocked
            },
            deletion=@recent_documents.DeletionAvailability::Blocked,
            status=@recent_documents.RowStatus::Saved,
          ),
        )
      })
    None => []
  }
}

///|
/// Resolve app state into the narrow Recent documents feature input.
fn recent_document_seeds(
  editing : EditingState,
  remote : Array[@recent_documents.Seed[@documents.Key]],
) -> @vector.Vector[@recent_documents.Seed[@documents.Key]] {
  let saved = editing.documents
    .recent()
    .map(item => {
      let (id, source, save, deletion_status) = item
      let selection = if id == editing.activation.key {
        @recent_documents.Selection::Editing
      } else if editing.can_select(id) {
        @recent_documents.Selection::Selectable
      } else {
        @recent_documents.Selection::Blocked
      }
      let deletion = if editing.creation is Creating(_) {
        @recent_documents.DeletionAvailability::Blocked
      } else {
        match deletion_status {
          @documents.DeleteStatus::Deletable =>
            @recent_documents.DeletionAvailability::Available
          @documents.DeleteStatus::DeleteFailed(_) =>
            @recent_documents.DeletionAvailability::Failed
          @documents.DeleteStatus::NotDeletable =>
            @recent_documents.DeletionAvailability::Blocked
          @documents.DeleteStatus::DeletePending =>
            @recent_documents.DeletionAvailability::Pending
        }
      }
      let status = match save {
        @documents.SaveStatus::Clean => @recent_documents.RowStatus::Saved
        _ => @recent_documents.RowStatus::Unsaved
      }
      @recent_documents.Seed::Seed(
        docid=id,
        source~,
        selection~,
        deletion~,
        status~,
      )
    })
  @vector.Vector((saved + remote)[:])
}
