///|
priv enum AccountStatus {
  Checking
  SignedOut
  SignedIn(String)
  Unavailable
} derive(Eq)

///|
priv enum DocumentSyncStatus {
  SavingOnDevice
  NotSaved
  SignInRequired
  LocalOnly
  ReadyToSync(@documents.StartSync)
  SavedOnDevice
  WaitingToSync
  Synced
  RetryAvailable(SyncRetry)
  SyncBlocked
  UpdateAvailable
  Conflict
} derive(Eq)

///|
fn account_status(sync : @sync.State) -> AccountStatus {
  match sync.session() {
    @sync.Session::Resolving(_) => AccountStatus::Checking
    NoAccount => SignedOut
    Current(_, name) => SignedIn(name)
    SessionUnavailable => Unavailable
  }
}

///|
fn replica_status(
  sync : @sync.State,
  replica : @source_repository.DocumentReplica,
) -> DocumentSyncStatus {
  match sync.progress(replica) {
    Working => WaitingToSync
    Retryable(action) => RetryAvailable(RetryNetwork(action))
    Blocked => SyncBlocked
    Inactive =>
      match replica.directive() {
        @source_repository.ReplicaDirective::Synchronized => Synced
        SaveRequired | Send(_) | RecoveryRequired => WaitingToSync
        UpdateAvailable(_) => UpdateAvailable
        Conflict(_, _) => DocumentSyncStatus::Conflict
      }
  }
}

///|
fn document_sync_status(model : Model) -> DocumentSyncStatus? {
  guard model.page is Editing(editing) else { return None }
  let key = editing.activation.key
  match key {
    @documents.Key::Replica(account, document_id) =>
      match model.replication.status(account, document_id) {
        @replica_persistence.Status::Persisting => return Some(SavingOnDevice)
        Retryable(action, _) =>
          return Some(RetryAvailable(RetryPersistence(action)))
        Current => ()
      }
    Source(_) => ()
  }
  match editing.documents.save_status(key) {
    Some(@documents.SaveStatus::Unsaved) => return Some(SavingOnDevice)
    Some(SaveFailed(_)) => return Some(NotSaved)
    Some(Clean) => ()
    None => return None
  }
  match key {
    @documents.Key::Source(_) =>
      match model.sync().session() {
        @sync.Session::Current(account, _) =>
          match editing.documents.sync_start(key, account) {
            @documents.SyncStart::Ready(action) => Some(ReadyToSync(action))
            Starting => Some(WaitingToSync)
            Unavailable => Some(SavedOnDevice)
          }
        NoAccount => Some(SignInRequired)
        Resolving(_) | SessionUnavailable => Some(LocalOnly)
      }
    Replica(account, document_id) => {
      guard editing.documents.snapshot().replica(account, document_id)
        is Some(replica) else {
        return Some(NotSaved)
      }
      match model.sync().session() {
        @sync.Session::Current(current, _) if current == account =>
          Some(replica_status(model.sync(), replica))
        Resolving(_) | NoAccount | Current(_, _) | SessionUnavailable =>
          Some(SavedOnDevice)
      }
    }
  }
}
