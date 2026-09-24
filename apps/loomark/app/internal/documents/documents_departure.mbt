///|
/// Recovery of accepted local intent, independent of remote synchronization.
pub enum DepartureStatus {
  AwaitingInput
  Saving
  Failed(DepartureFailure)
  Ready
} derive(Eq)

///|
pub enum DepartureFailure {
  Save(Key, @source_repository.SaveFailure)
  Delete(Key, @source_repository.DeleteFailure)
  Replica(Key, @source_repository.ReplicaFailure)
} derive(Eq)

///|
/// Flush accepted edits and retry failed document operations once. The root
/// also retries persistence lanes that have no live document projection.
pub fn State::prepare_departure(self : Self) -> (Self, Array[Action]) {
  let mut next = self
  let actions : Array[Action] = []
  for record in self.records {
    let key = record.key()
    let (updated, effects) = match record.edit {
      Waiting(revision) => next.reduce(Msg::ApplyPendingEdit(key, revision))
      Idle | ComposingIdle | ComposingWaiting(_) | ComposingReady => (next, [])
    }
    next = updated
    for effect in effects {
      actions.push(effect)
    }
    let event = match record.persistence {
      Source(_, SourceDeletePhase::Failed(_, _)) => Msg::RetryDelete(key)
      Replica(_, ReplicaFailed(_)) => Msg::RetryDelete(key)
      _ =>
        match record.save {
          Failed(_) => Msg::RetrySave(key)
          _ => Msg::VisibilityFlush(key)
        }
    }
    let (updated, effects) = next.reduce(event)
    next = updated
    for effect in effects {
      actions.push(effect)
    }
  }
  (next, actions)
}

///|
fn same_local_intent(
  durable : @source_repository.DocumentReplica,
  candidate : @source_repository.DocumentReplica,
) -> Bool {
  // A durable delete remains recoverable while delivery/acknowledgment metadata
  // moves from Deleting to Tombstone. Neither phase requires network drainage.
  let durable_deleted = durable.is_deleting() || durable.is_deleted()
  let candidate_deleted = candidate.is_deleting() || candidate.is_deleted()
  durable_deleted == candidate_deleted &&
  durable.document() == candidate.document()
}

///|
fn replica_write_recoverable(
  saved : @source_repository.SavedDocuments,
  write : @source_repository.ReplicaWrite,
) -> Bool {
  let candidate = write.replica()
  let durable = saved.replica(candidate.account(), candidate.document_id())
  match write {
    Remove(_) =>
      match durable {
        None => true
        Some(durable) => durable.is_deleting() || durable.is_deleted()
      }
    Store(_) =>
      durable.map(value => same_local_intent(value, candidate)).unwrap_or(false)
    PromoteSource(_) =>
      saved.find(candidate.document_id()) is None &&
      durable.map(value => same_local_intent(value, candidate)).unwrap_or(false)
    Fork(_, recovery) =>
      saved.find(recovery.id()) == Some(recovery) &&
      durable.map(value => same_local_intent(value, candidate)).unwrap_or(false)
  }
}

///|
fn DepartureStatus::combine(self : Self, next : Self) -> Self {
  match (self, next) {
    (Failed(_), _) => self
    (_, Failed(_)) => next
    (AwaitingInput, _) | (_, AwaitingInput) => AwaitingInput
    (Saving, _) | (_, Saving) => Saving
    (Ready, Ready) => Ready
  }
}

///|
fn State::record_departure(self : Self, record : Record) -> DepartureStatus {
  let key = record.key()
  if is_composing(record.edit) {
    return AwaitingInput
  }
  match record.persistence {
    Source(_, SourceDeletePhase::Failed(_, failure)) =>
      Failed(DepartureFailure::Delete(key, failure))
    Source(_, SourceDeletePhase::Waiting(_) | SourceDeletePhase::Deleting(_)) =>
      Saving
    Source(origin, SourceDeletePhase::Available) => {
      match record.save {
        Waiting(_) | Saving(_, _) => return DepartureStatus::Saving
        Failed(failure) if self.saved.find(record.document.id()) !=
          Some(record.document) =>
          return DepartureStatus::Failed(DepartureFailure::Save(key, failure))
        Saved | Failed(_) => ()
      }
      if origin is EphemeralNew ||
        self.saved.find(record.document.id()) == Some(record.document) {
        Ready
      } else {
        Saving
      }
    }
    StartingSync(account, _) => {
      let ready = self.saved.find(record.document.id()) is None &&
        self.saved
        .replica(account, record.document.id())
        .map(replica => replica.document() == Some(record.document))
        .unwrap_or(false)
      if ready {
        Ready
      } else {
        Saving
      }
    }
    Replica(account, phase) => {
      let durable = self.saved.replica(account, record.document.id())
      let ready = match phase {
        ReplicaAvailable =>
          durable
          .map(replica => replica.document() == Some(record.document))
          .unwrap_or(false)
        ReplicaPending | ReplicaFailed(_) =>
          match durable {
            None => true
            Some(replica) => replica.is_deleting() || replica.is_deleted()
          }
      }
      if ready {
        return Ready
      }
      match phase {
        ReplicaFailed(failure) =>
          Failed(DepartureFailure::Replica(key, failure))
        ReplicaAvailable | ReplicaPending =>
          match record.save {
            Failed(failure) =>
              DepartureStatus::Failed(DepartureFailure::Save(key, failure))
            _ => Saving
          }
      }
    }
    Forking(ownership) =>
      if self.saved.find(ownership.recovery.id()) == Some(record.document) {
        Ready
      } else {
        Saving
      }
  }
}

///|
pub fn State::departure_status(
  self : Self,
  persistence : @replica_persistence.State,
) -> DepartureStatus {
  let mut status : DepartureStatus = Ready
  for record in self.records {
    status = status.combine(self.record_departure(record))
  }
  // Include in-flight AND queued candidates. Even when the latest queued text
  // equals durable text, an older write can overwrite it before the queue drains.
  for write in persistence.pending_writes() {
    if !replica_write_recoverable(self.saved, write) {
      let replica = write.replica()
      let next : DepartureStatus = match
        persistence.status(replica.account(), replica.document_id()) {
        Retryable(_, failure) =>
          Failed(
            DepartureFailure::Replica(
              Key::replica(replica.account(), replica.document_id()),
              failure,
            ),
          )
        Current | Persisting => Saving
      }
      status = status.combine(next)
    }
  }
  status
}
