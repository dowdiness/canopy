///|
/// The action implied by a checkpoint. It is derived rather than stored beside
/// transition results, so checkpoint state remains the single source of truth.
pub(all) enum SyncDirective {
  Synchronized
  SaveRequired
  Send(PendingOperation)
  UpdateAvailable(RemoteDocument)
  Conflict(String, RemoteDocument)
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
    RemoteUpdate(remote) => UpdateAvailable(remote)
    Conflict(recovery) => Conflict(recovery.id(), self.baseline)
  }
}

///|
pub fn SyncCheckpoint::edit(self : Self, text : String) -> CheckpointWrite? {
  guard text != self.document.text() else { return None }
  Some(
    CheckpointOnly(
      { ..self, document: self.document.update(text), }
      |> SyncCheckpoint::advance,
    ),
  )
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
/// A detected divergence waiting only for a recovery identity. No recovery ID
/// is requested for the non-conflict reconciliation paths.
pub struct ConflictDraft {
  checkpoint : SyncCheckpoint
  remote : RemoteDocument
} derive(Eq, Debug)

///|
pub enum ReconcilePlan {
  Unchanged
  Persist(CheckpointWrite)
  ConflictDetected(ConflictDraft)
} derive(Eq, Debug)

///|
pub fn ConflictDraft::preserve(
  self : Self,
  value : String,
) -> CheckpointWrite raise InvalidRecoveryId {
  let recovery = recovery_identity(self.checkpoint.document.id(), value)
  let recovery_document = recovery.document(self.checkpoint.document.text())
  let next = {
      ..self.checkpoint,
      baseline: self.remote,
      phase: Conflict(recovery),
    }
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
    SyncPhase::RemoteUpdate(available) if remote.revision() <
      available.revision() ||
      (remote.revision() == available.revision() && remote != available) =>
      return Unchanged
    SyncPhase::RemoteUpdate(available) if remote == available &&
      self.baseline.same_present_text(self.document.text()) => return Unchanged
    Ready | RemoteUpdate(_) => ()
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
    let next = { ..self, phase: RemoteUpdate(remote), }
      |> SyncCheckpoint::advance
    return Persist(CheckpointOnly(next))
  }
  ConflictDetected({ checkpoint: self, remote, })
}
