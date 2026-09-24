///|
priv enum AccountStatus {
  Checking
  SignedOut
  SignedIn(String)
  Unavailable
  SyncUnavailable
} derive(Eq)

///|
/// Whether the current working copy is recoverable from this device.
priv enum LocalDurability {
  Saving
  Stored
  NotStored
} derive(Eq)

///|
priv enum DocumentSync {
  DeviceOnly
  SyncAvailable(@documents.StartSync)
  Linking
  Unavailable
  Linked
} derive(Eq)

///|
fn account_status(sync : @sync.State) -> AccountStatus {
  match sync.session() {
    @sync.Session::Resolving(_) => AccountStatus::Checking
    NoAccount => SignedOut
    Current(_, _) if sync.observation() is @sync.Observation::Unavailable =>
      SyncUnavailable
    Current(_, name) => SignedIn(name)
    SessionUnavailable => Unavailable
  }
}

///|
fn local_durability(
  editing : EditingState,
  key : @documents.Key,
) -> LocalDurability? {
  match editing.documents.save_status(key) {
    Some(Clean) => Some(LocalDurability::Stored)
    Some(SaveFailed(_)) => Some(LocalDurability::NotStored)
    Some(@documents.SaveStatus::Unsaved) => Some(LocalDurability::Saving)
    None => None
  }
}

///|
fn document_durability(model : Model) -> LocalDurability? {
  guard model.page is Editing(editing) else { return None }
  local_durability(editing, editing.activation.key)
}

///|
/// Replica durability belongs to the local persistence lane, not to the
/// current account session. It therefore remains actionable while account
/// lookup is unavailable and while a recovery Source still has Replica
/// ownership.
fn document_replica_persistence(model : Model) -> @replica_persistence.Status? {
  guard model.page is Editing(editing) &&
    editing.documents.replica_owner(editing.activation.key)
    is Some((account, document_id)) else {
    return None
  }
  Some(model.replication.status(account, document_id))
}

///|
fn document_sync(model : Model) -> DocumentSync? {
  guard model.page is Editing(editing) else { return None }
  let key = editing.activation.key
  match key {
    @documents.Key::Source(_) => {
      let sync = match model.sync().session() {
        @sync.Session::Current(account, _) =>
          match editing.documents.sync_start(key, account) {
            @documents.SyncStart::Ready(action) =>
              DocumentSync::SyncAvailable(action)
            Starting => DocumentSync::Linking
            Unavailable => DocumentSync::DeviceOnly
          }
        NoAccount | Resolving(_) | SessionUnavailable =>
          DocumentSync::DeviceOnly
      }
      Some(sync)
    }
    Replica(account, document_id) => {
      guard editing.documents.snapshot().replica(account, document_id)
        is Some(_) else {
        return Some(DocumentSync::Unavailable)
      }
      guard model.sync().session() is @sync.Session::Current(current, _) &&
        current == account else {
        return Some(DocumentSync::Unavailable)
      }
      Some(DocumentSync::Linked)
    }
  }
}

///|
fn document_remote_state(model : Model) -> @documents.RemoteState? {
  guard model.page is Editing(editing) &&
    editing.activation.key is @documents.Key::Replica(account, document_id) &&
    editing.documents.snapshot().replica(account, document_id) is Some(durable) &&
    model.sync().session() is @sync.Session::Current(current, _) &&
    current == account else {
    return None
  }
  let candidate = model.replication.head(durable)
  Some(
    editing.documents.remote_state(
      candidate,
      model.sync().remote_head(document_id),
    ),
  )
}

///|
fn document_sync_activity(model : Model) -> @sync.Activity? {
  guard model.page is Editing(editing) &&
    editing.activation.key is @documents.Key::Replica(account, document_id) &&
    editing.documents.snapshot().replica(account, document_id) is Some(durable) &&
    model.sync().session() is @sync.Session::Current(current, _) &&
    current == account else {
    return None
  }
  Some(model.replication.activity(durable))
}

///|
fn selection_activity(model : Model) -> @sync.SelectionActivity {
  model.sync().selection_activity()
}
