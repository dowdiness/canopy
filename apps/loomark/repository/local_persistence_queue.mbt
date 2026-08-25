///|
/// The product-visible local durability state for one accepted document.
///
/// `MarkdownDocumentVersion` is opaque: states compare versions for equality
/// and never infer ordering from their representation. `DurableLocal` is only
/// reported when the current accepted version equals the last acknowledged
/// durable version.
pub(all) enum LocalArchivePersistenceStatus {
  DurableLocal(@markdown.MarkdownDocumentVersion)
  Applied(
    current~ : @markdown.MarkdownDocumentVersion,
    durable~ : @markdown.MarkdownDocumentVersion?
  )
  StorageFailed(
    current~ : @markdown.MarkdownDocumentVersion,
    durable~ : @markdown.MarkdownDocumentVersion?,
    error~ : LocalArchivePersistenceFailure
  )
} derive(Eq, Debug)

///|
/// The provider-neutral outcome consumed by the persistence queue.
pub(all) enum LocalArchiveWriteOutcome {
  Stored
  Failed(LocalArchiveStorageWriteFailure)
} derive(Eq, Debug)

///|
/// Failure categories retained by the product-visible persistence state.
///
/// Provider failures and archive-preparation failures have different owners;
/// keeping them distinct prevents the UI and retry policy from inferring the
/// origin from a generic storage error.
pub(all) enum LocalArchivePersistenceFailure {
  Storage(LocalArchiveStorageWriteFailure)
  PreparationFailed
} derive(Eq, Debug)

///|
/// The result of applying one correlated write acknowledgment.
///
/// `Ignored` means the queue was not changed. `Promoted` means exactly one
/// immutable latest archive became the next in-flight write.
pub(all) enum LocalArchiveQueueCompletion {
  Ignored
  Completed
  Promoted(LocalArchivePendingWrite)
} derive(Eq)

///|
/// The immutable payload held by a queued write.
///
/// FullHistory is already prepared by its capability-owned shell. LocalText
/// remains unencoded until this queue selects it and the storage shell requests
/// its encoded replacement.
priv enum LocalArchivePendingPayload {
  Prepared(PreparedLocalArchive)
  LocalText(String)
} derive(Eq)

///|
/// One selected immutable replacement and its Session correlation.
///
/// The queue epoch prevents a delayed write from a previous queue lifetime
/// from matching a newly created queue for the same logical document.
pub struct LocalArchivePendingWrite {
  priv queue_epoch : String
  priv request_id : Int
  priv document_id : @archive.LoomarkDocumentId
  priv document_version : @markdown.MarkdownDocumentVersion
  priv payload : LocalArchivePendingPayload
} derive(Eq)

///|
/// Materialize the selected replacement for the storage shell.
///
/// Pending LocalText values never escape the queue, so superseded source is
/// not encoded. Prepared FullHistory bytes pass through unchanged.
pub fn LocalArchivePendingWrite::encoded(self : Self) -> String {
  match self.payload {
    LocalArchivePendingPayload::Prepared(archive) => archive.encoded()
    LocalArchivePendingPayload::LocalText(source) =>
      prepare_local_text(document_id=self.document_id, source~).encoded()
  }
}

///|
/// Return the selected record format without materializing LocalText.
pub fn LocalArchivePendingWrite::record_kind(
  self : Self,
) -> LocalArchiveRecordKind {
  match self.payload {
    LocalArchivePendingPayload::Prepared(archive) => archive.record_kind()
    LocalArchivePendingPayload::LocalText(_) =>
      LocalArchiveRecordKind::LocalText
  }
}

///|
/// Pure per-document single-flight persistence state.
///
/// Invariants:
/// - at most one archive is in flight;
/// - at most one immutable latest archive is pending;
/// - only a matching acknowledgment can advance `durable`;
/// - queue epoch, request ID, document ID, and opaque version all correlate an acknowledgment;
/// - a stale or deactivated-document acknowledgment leaves the queue unchanged.
pub struct LocalArchivePersistenceQueue {
  priv queue_epoch : String
  priv document_id : @archive.LoomarkDocumentId
  priv current : @markdown.MarkdownDocumentVersion
  priv durable : @markdown.MarkdownDocumentVersion?
  priv in_flight : LocalArchivePendingWrite?
  priv pending_latest : LocalArchivePendingWrite?
  priv next_request_value : Int
  priv failure : LocalArchivePersistenceFailure?
} derive(Eq)

///|
/// `queue_epoch` identifies one active queue lifetime. Callers must provide a
/// fresh value when replacing a queue, even if the logical document is reused.
pub fn LocalArchivePersistenceQueue::LocalArchivePersistenceQueue(
  document_id~ : @archive.LoomarkDocumentId,
  queue_epoch~ : String,
  current~ : @markdown.MarkdownDocumentVersion,
  durable~ : @markdown.MarkdownDocumentVersion?,
) -> LocalArchivePersistenceQueue {
  {
    queue_epoch,
    document_id,
    current,
    durable,
    in_flight: None,
    pending_latest: None,
    next_request_value: 1,
    failure: None,
  }
}

///|
/// Begin a new active queue lifetime while preserving an older in-flight write
/// as an ordering barrier. Older pending work and failure state are discarded;
/// the old completion may only release the barrier and promote new work.
pub fn LocalArchivePersistenceQueue::rebind_epoch(
  self : Self,
  queue_epoch~ : String,
) -> LocalArchivePersistenceQueue {
  {
    ..self,
    queue_epoch,
    pending_latest: None,
    next_request_value: 1,
    failure: None,
  }
}

///|
pub fn LocalArchivePersistenceQueue::status(
  self : Self,
) -> LocalArchivePersistenceStatus {
  match self.failure {
    Some(error) =>
      LocalArchivePersistenceStatus::StorageFailed(
        current=self.current,
        durable=self.durable,
        error~,
      )
    None =>
      match self.durable {
        Some(durable) if durable == self.current &&
          self.in_flight is None &&
          self.pending_latest is None =>
          LocalArchivePersistenceStatus::DurableLocal(self.current)
        _ =>
          LocalArchivePersistenceStatus::Applied(
            current=self.current,
            durable=self.durable,
          )
      }
  }
}

///|
fn LocalArchivePersistenceQueue::allocate_pending(
  self : Self,
  document_version~ : @markdown.MarkdownDocumentVersion,
  payload : LocalArchivePendingPayload,
) -> (LocalArchivePersistenceQueue, LocalArchivePendingWrite) {
  let pending = LocalArchivePendingWrite::{
    queue_epoch: self.queue_epoch,
    request_id: self.next_request_value,
    document_id: self.document_id,
    document_version,
    payload,
  }
  ({ ..self, next_request_value: self.next_request_value + 1 }, pending)
}

///|
/// Start one payload or coalesce it as the latest pending payload.
fn LocalArchivePersistenceQueue::enqueue_payload(
  self : Self,
  document_version~ : @markdown.MarkdownDocumentVersion,
  payload : LocalArchivePendingPayload,
) -> (LocalArchivePersistenceQueue, LocalArchivePendingWrite?) {
  let (next, pending) = self.allocate_pending(document_version~, payload)
  match next.in_flight {
    None =>
      (
        {
          ..next,
          current: document_version,
          in_flight: Some(pending),
          pending_latest: None,
          failure: None,
        },
        Some(pending),
      )
    Some(_) =>
      (
        {
          ..next,
          current: document_version,
          pending_latest: Some(pending),
          failure: None,
        },
        None,
      )
  }
}

///|
/// Accept a complete archive, starting it or coalescing it as the latest.
pub fn LocalArchivePersistenceQueue::enqueue(
  self : Self,
  document_version~ : @markdown.MarkdownDocumentVersion,
  archive~ : PreparedLocalArchive,
) -> (LocalArchivePersistenceQueue, LocalArchivePendingWrite?) {
  self.enqueue_payload(
    document_version~,
    LocalArchivePendingPayload::Prepared(archive),
  )
}

///|
/// Accept unencoded source text, starting it or coalescing it as the latest.
pub fn LocalArchivePersistenceQueue::enqueue_local_text(
  self : Self,
  document_version~ : @markdown.MarkdownDocumentVersion,
  source~ : String,
) -> (LocalArchivePersistenceQueue, LocalArchivePendingWrite?) {
  self.enqueue_payload(
    document_version~,
    LocalArchivePendingPayload::LocalText(source),
  )
}

///|
/// Retry a payload only for the current failed version; an active write is busy.
fn LocalArchivePersistenceQueue::retry_payload(
  self : Self,
  document_version~ : @markdown.MarkdownDocumentVersion,
  payload : LocalArchivePendingPayload,
) -> (LocalArchivePersistenceQueue, LocalArchivePendingWrite?) {
  guard self.failure is Some(_) && self.in_flight is None else {
    return (self, None)
  }
  guard self.current == document_version else { return (self, None) }
  self.enqueue_payload(document_version~, payload)
}

///|
/// Retry only the current failed version; an active write makes it busy.
pub fn LocalArchivePersistenceQueue::retry(
  self : Self,
  document_version~ : @markdown.MarkdownDocumentVersion,
  archive~ : PreparedLocalArchive,
) -> (LocalArchivePersistenceQueue, LocalArchivePendingWrite?) {
  self.retry_payload(
    document_version~,
    LocalArchivePendingPayload::Prepared(archive),
  )
}

///|
/// Retry unencoded source text only for the current failed version.
pub fn LocalArchivePersistenceQueue::retry_local_text(
  self : Self,
  document_version~ : @markdown.MarkdownDocumentVersion,
  source~ : String,
) -> (LocalArchivePersistenceQueue, LocalArchivePendingWrite?) {
  self.retry_payload(
    document_version~,
    LocalArchivePendingPayload::LocalText(source),
  )
}

///|
/// Record a current-version failure and supersede older pending work.
pub fn LocalArchivePersistenceQueue::mark_failed(
  self : Self,
  document_version~ : @markdown.MarkdownDocumentVersion,
  error~ : LocalArchivePersistenceFailure,
) -> LocalArchivePersistenceQueue {
  {
    ..self,
    current: document_version,
    pending_latest: None,
    failure: Some(error),
  }
}

///|
fn LocalArchivePendingWrite::matches(
  self : Self,
  other : LocalArchivePendingWrite,
) -> Bool {
  self.queue_epoch == other.queue_epoch &&
  self.request_id == other.request_id &&
  self.document_id == other.document_id &&
  self.document_version == other.document_version
}

///|
/// Apply one acknowledgment and optionally promote the latest pending archive.
///
/// The queue epoch, request ID, document ID, and opaque target version must
/// all match the registered in-flight write before any state transition is
/// allowed.
pub fn LocalArchivePersistenceQueue::complete(
  self : Self,
  pending : LocalArchivePendingWrite,
  outcome : LocalArchiveWriteOutcome,
) -> (LocalArchivePersistenceQueue, LocalArchiveQueueCompletion) {
  guard self.in_flight is Some(in_flight) else {
    return (self, LocalArchiveQueueCompletion::Ignored)
  }
  guard in_flight.matches(pending) else {
    return (self, LocalArchiveQueueCompletion::Ignored)
  }
  let current_write = pending.document_version
  let is_current = self.current == current_write
  let same_epoch = pending.queue_epoch == self.queue_epoch
  match self.pending_latest {
    Some(next_pending) => {
      let durable = if same_epoch {
        match outcome {
          LocalArchiveWriteOutcome::Stored => Some(current_write)
          LocalArchiveWriteOutcome::Failed(_) => self.durable
        }
      } else {
        self.durable
      }
      let failure = if same_epoch &&
        next_pending.document_version == self.current {
        None
      } else {
        self.failure
      }
      (
        {
          ..self,
          durable,
          in_flight: Some(next_pending),
          pending_latest: None,
          failure,
        },
        LocalArchiveQueueCompletion::Promoted(next_pending),
      )
    }
    None => {
      let (durable, failure) = match outcome {
        LocalArchiveWriteOutcome::Stored =>
          (
            if same_epoch {
              Some(current_write)
            } else {
              self.durable
            },
            if same_epoch && is_current {
              None
            } else {
              self.failure
            },
          )
        LocalArchiveWriteOutcome::Failed(error) =>
          (
            self.durable,
            if same_epoch && is_current {
              Some(LocalArchivePersistenceFailure::Storage(error))
            } else {
              self.failure
            },
          )
      }
      (
        { ..self, durable, in_flight: None, failure },
        LocalArchiveQueueCompletion::Completed,
      )
    }
  }
}

///|
/// Storage-write categories reserved for the imperative provider shell.
pub(all) enum LocalArchiveStorageWriteFailure {
  Unavailable
  QuotaExceeded
  Failed
} derive(Eq, Debug)
