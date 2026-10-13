///|
/// Recovery of accepted local intent, independent of remote synchronization.
pub enum LocalDurability {
  AwaitingInput
  Saving
  Failed(LocalSaveFailure)
  Durable
} derive(Eq)

///|
pub enum LocalSaveFailure {
  Save(Key, @source_repository.SaveFailure)
  Delete(Key, @source_repository.DeleteFailure)
  Replica(Key, @source_repository.ReplicaFailure)
} derive(Eq)

///|
/// Flush accepted edits and retry failed operations once. Admission failures
/// leave the caller's model untouched; effects are returned only on success.
pub fn Model::save_changes(self : Self) -> Transition raise DeleteError {
  let mut next = self
  let actions : Array[Action] = []
  for previous in self.records {
    let key = previous.key()
    let (record, effects) = match previous.edit {
      Waiting(_) if previous.delete_status() != DeletePending =>
        accept_pending(next.saved, previous)
      _ => (previous, [])
    }
    for effect in effects {
      actions.push(effect)
    }
    next = { ..next, records: replace_record(next.records, key, _ => record), }
    match previous.delete_status() {
      DeleteFailed(_) | DeletePersistenceFailed(_) =>
        match next.delete(key) {
          Accepted(transition) => {
            next = transition.model
            for effect in transition.effects {
              actions.push(effect)
            }
          }
          AlreadyPending => ()
        }
      _ => {
        let (updated, record, effects) = if record.save_failure() is Some(_) &&
          !is_composing(record.edit) &&
          record.delete_status() != DeletePending {
          request_save(next, record)
        } else {
          let (record, effects) = flush_visibility(next.saved, record)
          (next, record, effects)
        }
        next = {
          ..updated,
          records: replace_record(updated.records, key, _ => record),
        }
        for effect in effects {
          actions.push(effect)
        }
      }
    }
  }
  transition(next, ReadOnlyArray::from_array(actions))
}

///|
fn same_local_intent(
  durable : @source_repository.DocumentReplica,
  candidate : @source_repository.DocumentReplica,
) -> Bool {
  // Deleting and Tombstone carry the same recoverable local deletion intent.
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
fn LocalDurability::combine(self : Self, next : Self) -> Self {
  match (self, next) {
    (Failed(_), _) => self
    (_, Failed(_)) => next
    (AwaitingInput, _) | (_, AwaitingInput) => AwaitingInput
    (Saving, _) | (_, Saving) => Saving
    (Durable, Durable) => Durable
  }
}

///|
fn Model::record_local_durability(
  self : Self,
  record : Record,
) -> LocalDurability {
  let key = record.key()
  if is_composing(record.edit) {
    return AwaitingInput
  }
  match record.persistence {
    Source(_, Writable(_, Some(failure))) =>
      Failed(LocalSaveFailure::Delete(key, failure.cause))
    Source(_, WaitingToDelete(_, _, _) | Deleting(_, _)) => Saving
    Source(origin, Writable(save, None)) => {
      match save {
        Waiting(_) | Saving(_, _) => return LocalDurability::Saving
        Failed(failure) if self.saved.find(record.document.id()) !=
          Some(record.document) =>
          return LocalDurability::Failed(LocalSaveFailure::Save(key, failure))
        Idle | Failed(_) => ()
      }
      if origin is EphemeralNew ||
        self.saved.find(record.document.id()) == Some(record.document) {
        Durable
      } else {
        Saving
      }
    }
    StartingSync(account, _, _) => {
      let ready = self.saved.find(record.document.id()) is None &&
        self.saved
        .replica(account, record.document.id())
        .map(replica => replica.document() == Some(record.document))
        .unwrap_or(false)
      if ready {
        Durable
      } else {
        Saving
      }
    }
    Replica(account, deletion, autosave) => {
      let durable = self.saved.replica(account, record.document.id())
      let ready = match deletion {
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
        return Durable
      }
      match deletion {
        ReplicaFailed(failure) =>
          Failed(LocalSaveFailure::Replica(key, failure))
        ReplicaAvailable | ReplicaPending =>
          match autosave {
            Failed(failure) =>
              LocalDurability::Failed(LocalSaveFailure::Save(key, failure))
            _ => Saving
          }
      }
    }
    Forking(ownership, _) =>
      if self.saved.find(ownership.recovery.id()) == Some(record.document) {
        Durable
      } else {
        Saving
      }
  }
}

///|
pub fn Model::local_durability(
  self : Self,
  persistence : @replica_persistence.State,
) -> LocalDurability {
  let mut status : LocalDurability = Durable
  for record in self.records {
    status = status.combine(self.record_local_durability(record))
  }
  // Queued candidates count too: an older active write may overwrite the
  // current durable text before the lane reaches its latest candidate.
  for write in persistence.pending_writes() {
    if !replica_write_recoverable(self.saved, write) {
      let replica = write.replica()
      let next : LocalDurability = match
        persistence.status(replica.account(), replica.document_id()) {
        Retryable(_, failure) =>
          Failed(
            LocalSaveFailure::Replica(
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

///|
pub extend LocalSaveFailure with Eq::{equal, not_equal}

///|
pub extend LocalDurability with Eq::{equal, not_equal}
