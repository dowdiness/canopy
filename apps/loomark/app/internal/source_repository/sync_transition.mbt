///|
/// The action implied by a checkpoint. It is derived rather than stored beside
/// transition results, so checkpoint state remains the single source of truth.
pub(all) enum SyncDirective {
  Synchronized
  SaveRequired
  Send(PendingOperation)
  UpdateAvailable(RemoteDocument)
  RecoveryRequired
  Conflict(DocumentId, RemoteDocument)
} derive(Eq, Debug)

///|
pub fn SyncCheckpoint::directive(self : Self) -> SyncDirective {
  match self.phase {
    Sending(operation) => Send(operation)
    Ready =>
      if self.baseline is Deleted(_) ||
        self.baseline.same_present_text(self.document.text()) {
        Synchronized
      } else {
        SaveRequired
      }
    Available(remote) => UpdateAvailable(remote)
    Diverged(_) => RecoveryRequired
    Conflict(recovery) => Conflict(recovery.id(), self.baseline)
  }
}

///|
pub enum EditPlan {
  Unchanged
  Persist(CheckpointWrite)
} derive(Eq, Debug)

///|
pub fn SyncCheckpoint::edit(self : Self, text : String) -> EditPlan {
  guard text != self.document.text() else { return Unchanged }
  let edited = { ..self, document: self.document.update(text), }
    |> SyncCheckpoint::advance
  let checkpoint = match self.phase {
    Available(remote) | Diverged(remote) if remote.same_present_text(text) =>
      { ..edited, baseline: remote, phase: Ready, }
    Available(remote) | Diverged(remote) if self.baseline.same_present_text(
        text,
      ) => { ..edited, phase: Available(remote), }
    Available(remote) | Diverged(remote) =>
      { ..edited, phase: Diverged(remote), }
    Ready | Sending(_) | Conflict(_) => edited
  }
  Persist(CheckpointOnly(checkpoint))
}

///|
/// An operation waiting only for an identifier from the effect boundary.
pub struct OperationDraft {
  checkpoint : SyncCheckpoint
  content : PendingContent
} derive(Eq, Debug)

///|
/// Planning never asks for an operation ID unless a new request can start.
pub enum OperationPlan {
  Current
  Start(OperationDraft)
} derive(Eq, Debug)

///|
fn plan_operation(
  checkpoint : SyncCheckpoint,
  content : PendingContent,
) -> OperationPlan {
  guard checkpoint.phase is Ready else { return Current }
  let synchronized = match content {
    Save(text) =>
      checkpoint.baseline is Deleted(_) ||
      checkpoint.baseline.same_present_text(text)
    Delete => checkpoint.baseline is Deleted(_)
  }
  if synchronized {
    Current
  } else {
    Start({ checkpoint, content, })
  }
}

///|
pub fn SyncCheckpoint::plan_save(self : Self) -> OperationPlan {
  plan_operation(self, Save(self.document.text()))
}

///|
pub fn SyncCheckpoint::plan_delete(self : Self) -> OperationPlan {
  plan_operation(self, Delete)
}

///|
pub fn OperationDraft::start(
  self : Self,
  operation_id : OperationId,
) -> CheckpointWrite {
  let operation = {
    operation_id,
    base_revision: self.checkpoint.baseline.revision(),
    content: self.content,
  }
  CheckpointOnly(
    { ..self.checkpoint, phase: Sending(operation), } |> SyncCheckpoint::advance,
  )
}

///|
pub(all) suberror ReceiptMismatch {
  NoPendingOperation
  OperationMismatch
  RevisionMismatch
} derive(Eq, Debug)

///|
pub fn SyncCheckpoint::acknowledge(
  self : Self,
  operation_id : OperationId,
  revision : SavedRevision,
) -> CheckpointWrite raise ReceiptMismatch {
  guard self.phase is Sending(operation) else { raise NoPendingOperation }
  guard operation.operation_id == operation_id else { raise OperationMismatch }
  guard revision.value() == operation.base_revision + 1.0 else {
    raise RevisionMismatch
  }
  let baseline = match operation.content {
    Save(text) => RemoteDocument::Present(revision, text)
    Delete => RemoteDocument::Deleted(revision)
  }
  CheckpointOnly({ ..self, baseline, phase: Ready, } |> SyncCheckpoint::advance)
}

///|
/// Retire an operation that the server definitively did not apply. Delivery
/// failures with an uncertain outcome must retain the Sending phase instead.
pub fn SyncCheckpoint::reject_operation(
  self : Self,
  operation_id : OperationId,
) -> CheckpointWrite raise ReceiptMismatch {
  guard self.phase is Sending(operation) else { raise NoPendingOperation }
  guard operation.operation_id == operation_id else { raise OperationMismatch }
  CheckpointOnly({ ..self, phase: Ready, } |> SyncCheckpoint::advance)
}

///|
/// Retire an operation that the server definitively rejected because a newer
/// remote revision exists. Uncertain delivery failures must keep using the
/// persisted operation instead.
pub fn SyncCheckpoint::reject_conflict(
  self : Self,
  operation_id : OperationId,
  remote : RemoteDocument,
) -> ReconcilePlan raise ReceiptMismatch {
  guard self.phase is Sending(operation) else { raise NoPendingOperation }
  guard operation.operation_id == operation_id else { raise OperationMismatch }
  guard remote.revision() > self.baseline.revision() else {
    raise RevisionMismatch
  }
  { ..self, phase: Ready, }.reconcile(remote)
}

///|
pub enum ReconcilePlan {
  Unchanged
  Persist(CheckpointWrite)
} derive(Eq, Debug)

///|
pub fn SyncCheckpoint::preserve(
  self : Self,
  value : DocumentId,
) -> CheckpointWrite raise InvalidRecoveryId {
  guard self.phase is Diverged(remote) else { raise InvalidRecoveryId }
  let recovery = recovery_identity(self.document.id(), value)
  let recovery_document = recovery.document(self.document.text())
  let next = { ..self, baseline: remote, phase: Conflict(recovery), }
    |> SyncCheckpoint::advance
  CheckpointAndRecovery(next, recovery_document)
}

///|
pub fn SyncCheckpoint::reconcile(
  self : Self,
  remote : RemoteDocument,
) -> ReconcilePlan {
  match self.phase {
    Sending(_) | Conflict(_) => return Unchanged
    Available(observed) | Diverged(observed) if remote.revision() <
      observed.revision() ||
      (remote.revision() == observed.revision() && remote != observed) =>
      return Unchanged
    Available(observed) | Diverged(observed) if remote == observed =>
      return Unchanged
    Ready | Available(_) | Diverged(_) => ()
  }
  if remote.revision() < self.baseline.revision() || remote == self.baseline {
    return Unchanged
  }
  if remote.same_content(self.baseline) ||
    remote.same_present_text(self.document.text()) {
    let next = { ..self, baseline: remote, phase: Ready, }
      |> SyncCheckpoint::advance
    return Persist(CheckpointOnly(next))
  }
  if self.baseline.same_present_text(self.document.text()) {
    let next = { ..self, phase: Available(remote), } |> SyncCheckpoint::advance
    return Persist(CheckpointOnly(next))
  }
  let next = { ..self, phase: Diverged(remote), } |> SyncCheckpoint::advance
  Persist(CheckpointOnly(next))
}

///|
/// Advance an unopened remote document to the exact revision selected by the
/// user. Unlike background reconciliation, this may replace text because the
/// document has not yet been activated for editing.
pub fn SyncCheckpoint::refresh(
  self : Self,
  remote : RemoteDocument,
) -> CheckpointWrite? {
  guard remote is RemoteDocument::Present(_, text) &&
    remote.revision() > self.observed_revision() &&
    self.phase is Ready &&
    self.baseline.same_present_text(self.document.text()) else {
    return None
  }
  Some(
    CheckpointOnly(
      {
        ..self,
        document: self.document.update(text),
        baseline: remote,
        phase: Ready,
      }
      |> SyncCheckpoint::advance,
    ),
  )
}
