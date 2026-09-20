///|
/// Work whose state has already been recorded by Replication.
pub(all) enum Effect {
  Persist(@replica_persistence.Attempt)
  Network(@sync.Action)
} derive(Eq, Debug)

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
pub fn State::head(
  self : Self,
  durable : @source_repository.DocumentReplica,
) -> @source_repository.DocumentReplica {
  self.persistence.head(durable)
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
pub fn State::retry(
  self : Self,
  retry : @replica_persistence.Retry,
) -> (Self, Effect) raise @replica_persistence.ExpiredRetry {
  let (persistence, attempt) = self.persistence.retry(retry)
  ({ ..self, persistence, }, Persist(attempt))
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
/// Record a remote selection and admit at most one effect. Existing or pending
/// Replica durability always precedes a per-document remote read.
pub fn State::select(
  self : Self,
  entry : @source_repository.RemoteEntry,
  durable : @source_repository.DocumentReplica?,
) -> (Self, Effect?) {
  guard entry is @source_repository.RemoteEntry::Present(document_id, _, _) &&
    self.protocol.session() is @sync.Session::Current(account, _) else {
    return (self, None)
  }
  let protocol = self.protocol.select_open(entry)
  let self = { ..self, protocol, }
  let replica = match durable {
    Some(value) => Some(self.persistence.head(value))
    None => self.persistence.pending(account, document_id)
  }
  match self.persistence.status(account, document_id) {
    @replica_persistence.Status::Current => {
      let (protocol, action) = self.protocol.advance_open(replica)
      ({ ..self, protocol, }, action.map(value => Effect::Network(value)))
    }
    Persisting => (self, None)
    Retryable(retry, _) => {
      let (self, effect) = self.retry(retry) catch {
        _ => (self, abort("projected retry must remain current"))
      }
      (self, Some(effect))
    }
  }
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
    self.persistence.status(account, replica.document().id())
    is @replica_persistence.Status::Current else {
    return (self, None)
  }
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
      replication.status(account, replica.document().id()) {
      @replica_persistence.Status::Retryable(retry, _) => {
        let (replication, effect) = replication.retry(retry) catch {
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
