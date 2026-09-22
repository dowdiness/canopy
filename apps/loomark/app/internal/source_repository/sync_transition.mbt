///|
/// The action implied by a replica. It is derived rather than stored beside
/// transition results, so replica state remains the single source of truth.
pub(all) enum ReplicaDirective {
  Synchronized
  SaveRequired
  Send(PendingOperation)
  UpdateAvailable(RemoteDocument)
  RecoveryRequired
} derive(Eq, Debug)

///|
pub fn DocumentReplica::directive(self : Self) -> ReplicaDirective {
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
  }
}

///|
pub enum EditPlan {
  Unchanged
  Persist(ReplicaWrite)
} derive(Eq, Debug)

///|
pub fn DocumentReplica::edit(self : Self, text : String) -> EditPlan {
  guard text != self.document.text() else { return Unchanged }
  let edited = { ..self, document: self.document.update(text), }
    |> DocumentReplica::advance
  let replica = match self.phase {
    Available(remote) | Diverged(remote) if remote.same_present_text(text) =>
      { ..edited, baseline: remote, phase: Ready, }
    Available(remote) | Diverged(remote) if self.baseline.same_present_text(
        text,
      ) => { ..edited, phase: Available(remote), }
    Available(remote) | Diverged(remote) =>
      { ..edited, phase: Diverged(remote), }
    Ready | Sending(_) => edited
  }
  Persist(Store(replica))
}

///|
/// Open the parsed remote revision as the Replica's current content. The
/// mounted editor lifecycle decides when to expose that document to the user.
pub fn RemoteUpdate::accept(self : Self) -> ReplicaWrite {
  let (document, baseline) = match self.content {
    PresentUpdate(revision, text) =>
      (
        self.replica.document.update(text),
        RemoteDocument::Present(revision, text),
      )
    DeletedUpdate(revision) =>
      (self.replica.document, RemoteDocument::Deleted(revision))
  }
  Store(
    { ..self.replica, document, baseline, phase: ReplicaPhase::Ready, }
    |> DocumentReplica::advance,
  )
}

///|
/// An operation waiting only for an identifier from the effect boundary.
pub struct OperationDraft {
  replica : DocumentReplica
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
  replica : DocumentReplica,
  content : PendingContent,
) -> OperationPlan {
  guard replica.phase is Ready else { return Current }
  let synchronized = match content {
    Save(text) =>
      replica.baseline is Deleted(_) || replica.baseline.same_present_text(text)
    Delete => replica.baseline is Deleted(_)
  }
  if synchronized {
    Current
  } else {
    Start({ replica, content, })
  }
}

///|
pub fn DocumentReplica::plan_save(self : Self) -> OperationPlan {
  plan_operation(self, Save(self.document.text()))
}

///|
pub fn DocumentReplica::plan_delete(self : Self) -> OperationPlan {
  plan_operation(self, Delete)
}

///|
pub fn OperationDraft::start(
  self : Self,
  operation_id : OperationId,
) -> ReplicaWrite {
  let operation = {
    operation_id,
    base_revision: self.replica.baseline.revision(),
    content: self.content,
  }
  Store(
    { ..self.replica, phase: Sending(operation), } |> DocumentReplica::advance,
  )
}

///|
pub(all) suberror ReceiptMismatch {
  NoPendingOperation
  OperationMismatch
  RevisionMismatch
} derive(Eq, Debug)

///|
pub fn DocumentReplica::acknowledge(
  self : Self,
  operation_id : OperationId,
  revision : SavedRevision,
) -> ReplicaWrite raise ReceiptMismatch {
  guard self.phase is Sending(operation) else { raise NoPendingOperation }
  guard operation.operation_id == operation_id else { raise OperationMismatch }
  guard revision.value() == operation.base_revision + 1.0 else {
    raise RevisionMismatch
  }
  let baseline = match operation.content {
    Save(text) => RemoteDocument::Present(revision, text)
    Delete => RemoteDocument::Deleted(revision)
  }
  Store({ ..self, baseline, phase: Ready, } |> DocumentReplica::advance)
}

///|
/// Retire an operation that the server definitively did not apply. Delivery
/// failures with an uncertain outcome must retain the Sending phase instead.
pub fn DocumentReplica::reject_operation(
  self : Self,
  operation_id : OperationId,
) -> ReplicaWrite raise ReceiptMismatch {
  guard self.phase is Sending(operation) else { raise NoPendingOperation }
  guard operation.operation_id == operation_id else { raise OperationMismatch }
  Store({ ..self, phase: Ready, } |> DocumentReplica::advance)
}

///|
/// Retire an operation that the server definitively rejected because a newer
/// remote revision exists. Uncertain delivery failures must keep using the
/// persisted operation instead.
pub fn DocumentReplica::reject_conflict(
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
  Persist(ReplicaWrite)
} derive(Eq, Debug)

///|
pub fn DocumentReplica::fork(
  self : Self,
  value : DocumentId,
) -> ReplicaWrite raise InvalidRecoveryId {
  guard self.phase is Diverged(remote) else { raise InvalidRecoveryId }
  let recovery = recovery_identity(self.document.id(), value)
  let recovery_document = recovery.document(self.document.text())
  let document = match remote {
    RemoteDocument::Present(_, text) => self.document.update(text)
    Deleted(_) => self.document
    Missing => raise InvalidRecoveryId
  }
  let next = {
      ..self,
      document,
      baseline: remote,
      phase: Ready,
      recovery: Some(recovery),
    }
    |> DocumentReplica::advance
  Fork(next, recovery_document)
}

///|
pub fn DocumentReplica::reconcile(
  self : Self,
  remote : RemoteDocument,
) -> ReconcilePlan {
  match self.phase {
    Sending(_) => return Unchanged
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
      |> DocumentReplica::advance
    return Persist(Store(next))
  }
  if self.baseline.same_present_text(self.document.text()) {
    let next = { ..self, phase: Available(remote), } |> DocumentReplica::advance
    return Persist(Store(next))
  }
  let next = { ..self, phase: Diverged(remote), } |> DocumentReplica::advance
  Persist(Store(next))
}

///|
pub(all) enum OpenOutcome {
  Ready
  PersistAndOpen(ReplicaWrite)
  PersistOnly(ReplicaWrite)
  Unavailable
} derive(Eq, Debug)

///|
pub(all) suberror InvalidOpen derive(Eq, Debug)

///|
/// Open the newest known present revision of an unmounted Replica. This is the
/// only transition allowed to replace unmounted content with a remote value.
pub fn DocumentReplica::open(
  self : Self,
  received : RemoteDocument,
) -> OpenOutcome raise InvalidOpen {
  let remote = match self.phase {
    Sending(_) | Diverged(_) => raise InvalidOpen
    Ready => received
    Available(observed) =>
      if received.revision() < observed.revision() {
        observed
      } else if received.revision() == observed.revision() &&
        received != observed {
        raise InvalidOpen
      } else {
        received
      }
  }
  guard remote is RemoteDocument::Present(_, text) else {
    return match self.reconcile(remote) {
      ReconcilePlan::Persist(write) => PersistOnly(write)
      Unchanged => Unavailable
    }
  }
  if remote.revision() < self.baseline.revision() {
    return if self.baseline is RemoteDocument::Deleted(_) {
      Unavailable
    } else {
      Ready
    }
  }
  if remote == self.baseline {
    return Ready
  }
  guard remote.revision() > self.baseline.revision() &&
    (
      self.phase is Available(_) ||
      self.baseline.same_present_text(self.document.text()) ||
      self.baseline is RemoteDocument::Deleted(_) ||
      remote.same_present_text(self.document.text())
    ) else {
    raise InvalidOpen
  }
  PersistAndOpen(
    Store(
      {
        ..self,
        document: self.document.update(text),
        baseline: remote,
        phase: Ready,
      }
      |> DocumentReplica::advance,
    ),
  )
}
