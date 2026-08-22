///| The product-visible local durability state for one accepted document.
pub(all) enum LocalArchivePersistenceStatus {
  DurableLocal(@markdown.MarkdownDocumentVersion)
  Applied(
    current~ : @markdown.MarkdownDocumentVersion,
    durable~ : @markdown.MarkdownDocumentVersion?
  )
  StorageFailed(
    current~ : @markdown.MarkdownDocumentVersion,
    durable~ : @markdown.MarkdownDocumentVersion?,
    error~ : LocalArchiveStorageWriteFailure
  )
} derive(Eq, Debug)

///| The provider-neutral outcome consumed by the persistence queue.
pub(all) enum LocalArchiveWriteOutcome {
  Stored
  Failed(LocalArchiveStorageWriteFailure)
} derive(Eq, Debug)

///| The result of applying one correlated write acknowledgment.
pub(all) enum LocalArchiveQueueCompletion {
  Ignored
  Completed
  Promoted(LocalArchivePendingWrite)
} derive(Eq)

///| One complete immutable archive replacement and its Session correlation.
pub struct LocalArchivePendingWrite {
  priv request_id : LocalArchiveRequestId
  priv document_id : @archive.LoomarkDocumentId
  priv document_version : @markdown.MarkdownDocumentVersion
  priv archive : PreparedLocalArchive
} derive(Eq)

///|
pub fn LocalArchivePendingWrite::request_id(
  self : Self,
) -> LocalArchiveRequestId {
  self.request_id
}

///|
pub fn LocalArchivePendingWrite::document_id(
  self : Self,
) -> @archive.LoomarkDocumentId {
  self.document_id
}

///|
pub fn LocalArchivePendingWrite::document_version(
  self : Self,
) -> @markdown.MarkdownDocumentVersion {
  self.document_version
}

///|
pub fn LocalArchivePendingWrite::encoded(self : Self) -> String {
  self.archive.encoded()
}

///| Pure per-document single-flight persistence state.
pub struct LocalArchivePersistenceQueue {
  priv document_id : @archive.LoomarkDocumentId
  priv current : @markdown.MarkdownDocumentVersion
  priv durable : @markdown.MarkdownDocumentVersion?
  priv in_flight : LocalArchivePendingWrite?
  priv pending_latest : LocalArchivePendingWrite?
  priv next_request_value : Int
  priv failure : LocalArchiveStorageWriteFailure?
} derive(Eq)

///|
pub fn LocalArchivePersistenceQueue::LocalArchivePersistenceQueue(
  document_id~ : @archive.LoomarkDocumentId,
  current~ : @markdown.MarkdownDocumentVersion,
  durable~ : @markdown.MarkdownDocumentVersion?,
) -> LocalArchivePersistenceQueue {
  {
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
        Some(durable) if durable == self.current =>
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
  archive~ : PreparedLocalArchive,
) -> (LocalArchivePersistenceQueue, LocalArchivePendingWrite) {
  let pending = LocalArchivePendingWrite::{
    request_id: LocalArchiveRequestId::{ value: self.next_request_value },
    document_id: self.document_id,
    document_version,
    archive,
  }
  ({ ..self, next_request_value: self.next_request_value + 1 }, pending)
}

///| Accept a complete archive, starting it or coalescing it as the latest.
pub fn LocalArchivePersistenceQueue::enqueue(
  self : Self,
  document_version~ : @markdown.MarkdownDocumentVersion,
  archive~ : PreparedLocalArchive,
) -> (LocalArchivePersistenceQueue, LocalArchivePendingWrite?) {
  let (next, pending) = self.allocate_pending(document_version~, archive~)
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

///| Retry only the current failed version; an active write makes it busy.
pub fn LocalArchivePersistenceQueue::retry(
  self : Self,
  document_version~ : @markdown.MarkdownDocumentVersion,
  archive~ : PreparedLocalArchive,
) -> (LocalArchivePersistenceQueue, LocalArchivePendingWrite?) {
  guard self.failure is Some(_) && self.in_flight is None else {
    return (self, None)
  }
  guard self.current == document_version else { return (self, None) }
  self.enqueue(document_version~, archive~)
}

///| Record a current-version failure and supersede older pending work.
pub fn LocalArchivePersistenceQueue::mark_failed(
  self : Self,
  document_version~ : @markdown.MarkdownDocumentVersion,
  error~ : LocalArchiveStorageWriteFailure,
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
  self.request_id == other.request_id &&
  self.document_id == other.document_id &&
  self.document_version == other.document_version
}

///| Apply one acknowledgment and optionally promote the latest pending archive.
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
  let current_write = pending.document_version()
  let is_current = self.current == current_write
  match self.pending_latest {
    Some(next_pending) => {
      let durable = match outcome {
        LocalArchiveWriteOutcome::Stored => Some(current_write)
        LocalArchiveWriteOutcome::Failed(_) => self.durable
      }
      let failure = if next_pending.document_version() == self.current {
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
          (Some(current_write), if is_current { None } else { self.failure })
        LocalArchiveWriteOutcome::Failed(error) =>
          (self.durable, if is_current { Some(error) } else { self.failure })
      }
      (
        { ..self, durable, in_flight: None, failure },
        LocalArchiveQueueCompletion::Completed,
      )
    }
  }
}

///| Monotonic identity assigned to one repository replacement request.
pub struct LocalArchiveRequestId {
  priv value : Int
} derive(Eq, Debug)

///| Storage-write categories reserved for the imperative provider shell.
pub(all) enum LocalArchiveStorageWriteFailure {
  Unavailable
  QuotaExceeded
  Failed
} derive(Eq, Debug)
