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
        keys: editing.documents.known_keys(),
        can_activate: editing.can_activate(),
      }
    Loading(_, _) | OpeningNew(_, _) | Recovery(_, _) =>
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
) -> Array[
  (@source_repository.IndexKey, @recent_documents.Seed[@documents.Key]),
] {
  match remote.account {
    Some(account) =>
      remote.entries.filter_map(entry => {
        guard entry
          is @source_repository.RemoteEntry::Present(id, _, preview, changed_at) else {
          return None
        }
        let key = @documents.Key::replica(account, id)
        guard !membership.keys.contains(key) else { return None }
        Some(
          (
            @source_repository.IndexKey(changed_at, id),
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
          ),
        )
      })
    None => []
  }
}

///|
/// Resolve app state into the narrow Recent documents feature input.
/// A document being deleted keeps its entry, showing its Pending deletion,
/// until it is gone.
fn recent_document_seeds(
  editing : EditingDocument,
  remote : Array[
    (@source_repository.IndexKey, @recent_documents.Seed[@documents.Key]),
  ],
) -> @vector.Vector[@recent_documents.Seed[@documents.Key]] {
  @vector.Vector(listed_rows(editing, remote).map(row => row.1)[:])
}

///|
/// Every listed document with its index key, most recently changed first.
fn listed_rows(
  editing : EditingDocument,
  remote : Array[
    (@source_repository.IndexKey, @recent_documents.Seed[@documents.Key]),
  ],
) -> Array[
  (@source_repository.IndexKey, @recent_documents.Seed[@documents.Key]),
] {
  let saved = editing.documents
    .recent()
    .map(item => {
      let {
        key: id,
        source,
        save_status: save,
        delete_status: deletion_status,
        index_key,
      } = item
      let selection = if id == editing.activation.key {
        @recent_documents.Selection::Editing
      } else if editing.can_select(id) {
        @recent_documents.Selection::Selectable
      } else {
        @recent_documents.Selection::Blocked
      }
      let deletion = if creation_in_progress(editing.creation) {
        @recent_documents.DeletionAvailability::Blocked
      } else {
        let scope = match id {
          @documents.Key::Source(_) =>
            @recent_documents.DeletionScope::ThisBrowser
          @documents.Key::Replica(_, _) =>
            @recent_documents.DeletionScope::AllDevices
        }
        match deletion_status {
          @documents.DeleteStatus::Deletable =>
            @recent_documents.DeletionAvailability::Available(scope)
          @documents.DeleteStatus::DeleteFailed(_) =>
            @recent_documents.DeletionAvailability::Failed(scope)
          @documents.DeleteStatus::DeletePersistenceFailed(_) =>
            @recent_documents.DeletionAvailability::Failed(scope)
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
      (
        index_key,
        @recent_documents.Seed::Seed(
          docid=id,
          source~,
          selection~,
          deletion~,
          status~,
        ),
      )
    })
  let rows = saved + remote
  rows.sort_by((left, right) => @source_repository.index_order(left.0, right.0))
  rows
}
