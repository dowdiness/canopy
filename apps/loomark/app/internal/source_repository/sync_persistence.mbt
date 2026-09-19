///|
/// The complete state space of one document's serialized checkpoint writer.
pub enum CheckpointWriter {
  Available
  Storing(CheckpointWrite, CheckpointWrite?)
  RetryPending(CheckpointWrite)
} derive(Eq, Debug)

///|
pub(all) suberror WriterError {
  StaleCompletion
  RetryUnavailable
} derive(Eq, Debug)

///|
pub fn CheckpointWriter::new() -> CheckpointWriter {
  Available
}

///|
fn preserve_recovery(
  older : CheckpointWrite,
  newer : CheckpointWrite,
) -> CheckpointWrite {
  match (older, newer) {
    (CheckpointAndRecovery(_, recovery), CheckpointOnly(checkpoint)) =>
      match checkpoint.phase {
        SyncPhase::Conflict(recovery_identity) if recovery_identity.id() ==
          recovery.id() => CheckpointAndRecovery(checkpoint, recovery)
        Ready | Sending(_) | RemoteUpdate(_) | Conflict(_) =>
          CheckpointOnly(checkpoint)
      }
    (_, newer) => newer
  }
}

///|
fn same_checkpoint(
  active : CheckpointWrite,
  completed : SyncCheckpoint,
) -> Bool {
  let expected = active.checkpoint()
  expected.account == completed.account &&
  expected.document.id() == completed.document.id() &&
  expected.generation == completed.generation
}

///|
/// Invocation order determines the newest queued write; no identity or
/// generation value is reparsed here.
pub fn CheckpointWriter::enqueue(
  self : Self,
  requested : CheckpointWrite,
) -> (Self, CheckpointWrite?) {
  match self {
    Available => (Storing(requested, None), Some(requested))
    Storing(active, waiting) => {
      let waiting = match waiting {
        Some(current) => preserve_recovery(current, requested)
        None => requested
      }
      (Storing(active, Some(waiting)), None)
    }
    RetryPending(retained) =>
      (RetryPending(preserve_recovery(retained, requested)), None)
  }
}

///|
/// Only the active write can complete. Delayed completions are explicit
/// asynchronous errors, not successful no-ops.
pub fn CheckpointWriter::stored(
  self : Self,
  completed : SyncCheckpoint,
) -> (Self, CheckpointWrite?) raise WriterError {
  match self {
    Storing(active, waiting) if same_checkpoint(active, completed) =>
      match waiting {
        Some(next) => (Storing(next, None), Some(next))
        None => (Available, None)
      }
    Available | RetryPending(_) | Storing(_, _) => raise StaleCompletion
  }
}

///|
pub fn CheckpointWriter::failed(
  self : Self,
  completed : SyncCheckpoint,
) -> Self raise WriterError {
  match self {
    Storing(active, waiting) if same_checkpoint(active, completed) =>
      RetryPending(
        match waiting {
          Some(next) => preserve_recovery(active, next)
          None => active
        },
      )
    Available | RetryPending(_) | Storing(_, _) => raise StaleCompletion
  }
}

///|
pub fn CheckpointWriter::retry(
  self : Self,
) -> (Self, CheckpointWrite) raise WriterError {
  match self {
    RetryPending(retained) => (Storing(retained, None), retained)
    Available | Storing(_, _) => raise RetryUnavailable
  }
}
