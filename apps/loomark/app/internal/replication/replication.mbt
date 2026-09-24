///|
/// Work whose state has already been recorded by Replication.
pub(all) enum Effect {
  Persist(@replica_persistence.Attempt)
  Network(@sync.Action)
} derive(Eq, Debug)

///|
pub(all) suberror ExpiredRetry {
  ExpiredRetry
} derive(Eq, Debug)

///|
/// The canonical durable Replica produced by one consumed selection.
pub struct SelectedReplica {
  priv replica : @source_repository.DocumentReplica
} derive(Eq, Debug)

///|
pub fn SelectedReplica::replica(
  self : Self,
) -> @source_repository.DocumentReplica {
  self.replica
}

///|
/// Owns the ordering between durable Replica writes and remote work.
pub struct State {
  priv protocol : @sync.State
  priv persistence : @replica_persistence.State
} derive(Eq, Debug)

///|
pub fn State::State(
  protocol? : @sync.State = @sync.State(),
  persistence? : @replica_persistence.State = @replica_persistence.State(),
) -> State {
  { protocol, persistence, }
}

///|
pub fn State::protocol(self : Self) -> @sync.State {
  self.protocol
}

///|
pub fn State::persistence(self : Self) -> @replica_persistence.State {
  self.persistence
}

///|
pub fn State::with_protocol(self : Self, protocol : @sync.State) -> Self {
  { ..self, protocol, }
}

///|
pub fn State::editing_base(
  self : Self,
  durable : @source_repository.DocumentReplica,
) -> @source_repository.DocumentReplica {
  self.persistence.editing_base(durable)
}

///|
/// Admit eligible local text before any retry can replay an obsolete candidate.
/// Matching failed live Stores retain their protocol facts; returning to durable
/// text replaces an obsolete Store through the ordinary persistence lane.
pub fn State::save_local(
  self : Self,
  durable : @source_repository.DocumentReplica,
  text : String,
) -> (Self, Effect?) {
  if self.persistence.failed_write(durable.account(), durable.document_id())
    is Some(@source_repository.ReplicaWrite::Store(retained)) &&
    retained.document() is Some(current) &&
    durable.document() is Some(committed) {
    if current.text() == text {
      return self.retry_document(durable.account(), durable.document_id())
    }
    if committed.text() == text {
      return self.submit(durable.rewrite())
    }
  }
  let base = self.persistence.editing_base(durable)
  let (protocol, write) = self.protocol.save(base, text)
  let self = { ..self, protocol, }
  match write {
    Some(write) => self.submit(write)
    None => (self, None)
  }
}

///|
/// The newest Replica fact available to pure projections. Failed writes remain
/// visible here even though new edits correctly branch from durable state.
pub fn State::head(
  self : Self,
  durable : @source_repository.DocumentReplica,
) -> @source_repository.DocumentReplica {
  self.persistence
  .pending(durable.account(), durable.document_id())
  .unwrap_or(durable)
}

///|
pub fn State::protocol_base(
  self : Self,
  durable : @source_repository.DocumentReplica,
) -> @source_repository.DocumentReplica {
  self.persistence.protocol_base(durable)
}

///|
pub fn State::pending(
  self : Self,
  account : @source_repository.AccountId,
  document_id : @source_repository.DocumentId,
) -> @source_repository.DocumentReplica? {
  self.persistence.pending(account, document_id)
}

///|
pub fn State::status(
  self : Self,
  account : @source_repository.AccountId,
  document_id : @source_repository.DocumentId,
) -> @replica_persistence.Status {
  self.persistence.status(account, document_id)
}

///|
pub fn State::submit(
  self : Self,
  write : @source_repository.ReplicaWrite,
) -> (Self, Effect?) {
  let (persistence, attempt) = self.persistence.submit(write)
  ({ ..self, persistence, }, attempt.map(value => Effect::Persist(value)))
}

///|
pub fn State::retry_save(
  self : Self,
  retry : @replica_persistence.Retry,
) -> (Self, Effect) raise ExpiredRetry {
  let (persistence, attempt) = self.persistence.retry(retry) catch {
    _ => raise ExpiredRetry
  }
  ({ ..self, persistence, }, Persist(attempt))
}

///|
pub fn State::retry_sync(
  self : Self,
  saved : @source_repository.SavedDocuments,
  retry : @sync.Retry,
) -> (Self, Effect) raise ExpiredRetry {
  guard self.persistence.status(retry.account(), retry.document_id())
    is @replica_persistence.Status::Current &&
    saved.replica(retry.account(), retry.document_id()) is Some(durable) else {
    raise ExpiredRetry
  }
  let (protocol, action) = self.protocol.retry(durable, retry) catch {
    _ => raise ExpiredRetry
  }
  ({ ..self, protocol, }, Effect::Network(action))
}

///|
pub fn State::retry_selection(
  self : Self,
  saved : @source_repository.SavedDocuments,
  retry : @sync.SelectionRetry,
) -> (Self, Effect) raise ExpiredRetry {
  guard saved.replica(retry.account(), retry.document_id()) is None &&
    self.persistence.pending(retry.account(), retry.document_id()) is None else {
    raise ExpiredRetry
  }
  let (protocol, action) = self.protocol.retry_selection(retry) catch {
    _ => raise ExpiredRetry
  }
  ({ ..self, protocol, }, Effect::Network(action))
}

///|
pub fn State::activity(
  self : Self,
  durable : @source_repository.DocumentReplica,
) -> @sync.Activity {
  self.protocol.activity(durable)
}

///|
pub fn State::retry_document(
  self : Self,
  account : @source_repository.AccountId,
  document_id : @source_repository.DocumentId,
) -> (Self, Effect?) {
  match self.persistence.status(account, document_id) {
    @replica_persistence.Status::Retryable(retry, _) => {
      let result = Some(self.retry_save(retry)) catch { _ => None }
      match result {
        Some((self, effect)) => (self, Some(effect))
        None => (self, None)
      }
    }
    Current | Persisting => (self, None)
  }
}

///|
pub fn State::complete(
  self : Self,
  attempt : @replica_persistence.Attempt,
  result : Result[Unit, @source_repository.ReplicaFailure],
) -> (Self, @replica_persistence.Completion) raise @replica_persistence.StaleAttempt {
  let (persistence, completion) = self.persistence.complete(attempt, result)
  ({ ..self, persistence, }, completion)
}

///|
fn State::advance_selection(
  self : Self,
  replica : @source_repository.DocumentReplica?,
) -> (Self, Effect?) {
  let (protocol, step) = self.protocol.advance_selection(replica)
  let self = { ..self, protocol, }
  match step {
    @sync.SelectionStep::Wait => (self, None)
    Fetch(attempt) =>
      (self, Some(Effect::Network(@sync.Action::OpenRemote(attempt))))
    Persist(write) => self.submit(write)
  }
}

///|
/// Record a remote selection. Existing Replicas use their ordinary sync lane;
/// only a remote-only document requires a selection-specific fetch.
pub fn State::select(
  self : Self,
  saved : @source_repository.SavedDocuments,
  document_id : @source_repository.DocumentId,
) -> (Self, Array[Effect]) {
  guard self.protocol.remote_entry(document_id)
    is Some(@source_repository.RemoteEntry::Present(_, _, _)) &&
    self.protocol.session() is @sync.Session::Current(account, _) else {
    return (self, [])
  }
  let protocol = self.protocol.select(document_id)
  let self = { ..self, protocol, }
  match self.persistence.status(account, document_id) {
    @replica_persistence.Status::Current => {
      let replica = saved.replica(account, document_id)
      let (self, selection) = self.advance_selection(replica)
      let (self, sync) = match replica {
        Some(replica) => self.settle_replica(replica)
        None => (self, None)
      }
      let effects = [selection, sync].filter_map(effect => effect)
      (self, effects)
    }
    Persisting => (self, [])
    Retryable(retry, _) => {
      let (self, effect) = self.retry_save(retry) catch {
        _ => (self, abort("projected retry must remain current"))
      }
      (self, [effect])
    }
  }
}

///|
/// Accept a selected remote response only while the document remains
/// remote-only, then make the received Replica durable before activation.
pub fn State::opened(
  self : Self,
  saved : @source_repository.SavedDocuments,
  attempt : @sync.OpenAttempt,
  remote : @source_repository.RemoteDocument,
) -> (Self, Effect?) raise @sync.WorkError {
  let account = attempt.account()
  let document_id = attempt.document_id()
  guard saved.replica(account, document_id) is None &&
    self.persistence.pending(account, document_id) is None else {
    raise @sync.WorkError::StaleWork
  }
  let (protocol, write) = self.protocol.opened(attempt, remote)
  let self = { ..self, protocol, }
  match write {
    Some(write) => self.submit(write)
    None => (self, None)
  }
}

///|
/// Consume a selection only when its canonical Replica is durable and still
/// satisfies the current catalog requirement.
pub fn State::take_selection(
  self : Self,
  saved : @source_repository.SavedDocuments,
) -> (Self, SelectedReplica?, Effect?) {
  guard self.protocol.ready_selection() is Some((intent, account, document_id)) &&
    self.protocol.session() is @sync.Session::Current(current, _) &&
    current == account &&
    self.persistence.status(account, document_id)
    is @replica_persistence.Status::Current &&
    saved.replica(account, document_id) is Some(replica) &&
    self.protocol.remote_entry(document_id)
    is Some(@source_repository.RemoteEntry::Present(_, required, _)) &&
    replica.open(required) is @source_repository.OpenStep::Ready else {
    return (self, None, None)
  }
  let protocol = self.protocol.complete_selection(intent) catch {
    _ => abort("ready open must complete")
  }
  let (self, effect) = { ..self, protocol, }.settle_replica(replica)
  (self, Some({ replica, }), effect)
}

///|
pub fn State::cancel_selection(self : Self) -> Self {
  { ..self, protocol: self.protocol.cancel_selection(), }
}

///|
/// Start at most one next remote action for a Replica whose durable write lane
/// is current. The protocol marks the action active before exposing the effect.
pub fn State::settle_replica(
  self : Self,
  replica : @source_repository.DocumentReplica,
) -> (Self, Effect?) {
  let account = replica.account()
  guard self.protocol.session() is @sync.Session::Current(current, _) &&
    current == account &&
    self.persistence.status(account, replica.document_id())
    is @replica_persistence.Status::Current else {
    return (self, None)
  }
  let (self, selection) = self.advance_selection(Some(replica))
  guard selection is None else { return (self, selection) }
  let (protocol, action) = self.protocol.advance(replica)
  ({ ..self, protocol, }, action.map(value => Effect::Network(value)))
}

///|
/// Resume durable failures first, then start remote work only for lanes that
/// are already current. This is the single account-recovery ordering rule.
pub fn State::resume_account(
  self : Self,
  saved : @source_repository.SavedDocuments,
  account : @source_repository.AccountId,
) -> (Self, Array[Effect]) {
  saved
  .replicas_for(account)
  .fold(init=(self, []), (state, replica) => {
    let (replication, effects) = state
    let (replication, effects) = match
      replication.status(account, replica.document_id()) {
      @replica_persistence.Status::Retryable(retry, _) => {
        let (replication, effect) = replication.retry_save(retry) catch {
          _ => (replication, abort("projected retry must remain current"))
        }
        (replication, effects + [effect])
      }
      Current | Persisting => (replication, effects)
    }
    let (replication, effect) = replication.settle_replica(replica)
    (
      replication,
      match effect {
        Some(effect) => effects + [effect]
        None => effects
      },
    )
  })
}

///|
pub fn State::settle_account(
  self : Self,
  saved : @source_repository.SavedDocuments,
  account : @source_repository.AccountId,
) -> (Self, Array[Effect]) {
  saved
  .replicas_for(account)
  .fold(init=(self, []), (state, replica) => {
    let (replication, effects) = state
    let (replication, effect) = replication.settle_replica(replica)
    (
      replication,
      match effect {
        Some(effect) => effects + [effect]
        None => effects
      },
    )
  })
}
