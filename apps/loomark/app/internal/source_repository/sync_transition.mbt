///|
/// The action implied by a replica. It is derived rather than stored beside
/// transition results, so replica state remains the single source of truth.
pub(all) enum ReplicaDirective {
  Synchronized
  CreateOperation(OperationDraft)
  Send(PendingOperation)
  UpdateAvailable(RemoteDocument)
  RecoveryRequired
} derive(Eq, Debug)

///|
pub fn DocumentReplica::directive(self : Self) -> ReplicaDirective {
  match self.state {
    Live({ phase: Sending(operation), .. }) => Send(operation)
    Deleting({ phase: DeletionPhase::Ready, .. }) =>
      CreateOperation({ replica: self, content: PendingContent::Delete, })
    Deleting({ phase: ResolvingSave(operation) | Sending(operation), .. }) =>
      Send(operation)
    Live({ document, baseline, phase: LivePhase::Ready, }) =>
      if baseline.same_text(document.text()) {
        Synchronized
      } else {
        CreateOperation({
          replica: self,
          content: PendingContent::Save(document.text()),
        })
      }
    Live({ phase: Available(remote), .. }) => UpdateAvailable(remote)
    Live({ phase: Diverged(_), .. }) => RecoveryRequired
    Tombstone(_) => Synchronized
  }
}

///|
pub enum EditPlan {
  Unchanged
  Unavailable
  Persist(ReplicaWrite)
} derive(Eq, Debug)

///|
pub fn DocumentReplica::edit(self : Self, text : String) -> EditPlan {
  guard self.state is ReplicaState::Live(live) else { return Unavailable }
  guard text != live.document.text() else { return Unchanged }
  let edited = { ..live, document: live.document.update(text), }
  let live = match live.phase {
    Available(remote) | Diverged(remote) if remote.same_present_text(text) =>
      match remote {
        RemoteDocument::Present(revision, remote_text) =>
          {
            ..edited,
            baseline: LiveBaseline::Saved(revision, remote_text),
            phase: LivePhase::Ready,
          }
        Missing | Deleted(_) => abort("present text without a present remote")
      }
    Available(remote) | Diverged(remote) if live.baseline.same_text(text) =>
      { ..edited, phase: LivePhase::Available(remote), }
    Available(remote) | Diverged(remote) =>
      { ..edited, phase: LivePhase::Diverged(remote), }
    Ready | Sending(_) => edited
  }
  Persist(Store({ ..self, state: ReplicaState::Live(live), }.advance()))
}

///|
/// Open the parsed remote revision as the Replica's current content. The
/// mounted editor lifecycle decides when to expose that document to the user.
pub fn RemoteUpdate::accept(self : Self) -> ReplicaWrite {
  guard self.replica.state is ReplicaState::Live(live) else {
    abort("remote update without a live replica")
  }
  let state = match self.content {
    PresentUpdate(revision, text) =>
      ReplicaState::Live({
        document: live.document.update(text),
        baseline: LiveBaseline::Saved(revision, text),
        phase: LivePhase::Ready,
      })
    DeletedUpdate(revision) => ReplicaState::Tombstone(revision)
  }
  Store({ ..self.replica, state, recovery: None, }.advance())
}

///|
/// An operation waiting only for an identifier from the effect boundary.
pub struct OperationDraft {
  replica : DocumentReplica
  content : PendingContent
} derive(Eq, Debug)

///|
pub fn OperationDraft::content(self : Self) -> PendingContent {
  self.content
}

///|
/// Persist local deletion intent before creating or sending its operation. An
/// uncertain save remains attached so restart must settle that exact request
/// before deletion advances.
pub fn DocumentReplica::request_deletion(
  self : Self,
) -> ReplicaWrite raise DeletionUnavailable {
  let state = match self.state {
    Tombstone(_) => raise AlreadyDeleted
    Deleting(_) => raise AlreadyDeleting
    Live({ baseline: Unpublished, phase: Ready, .. }) => return Remove(self)
    Live({ document, baseline, phase: Ready, }) =>
      ReplicaState::Deleting({
        document,
        baseline,
        phase: DeletionPhase::Ready,
      })
    Live({ document, baseline, phase: Sending(operation), }) =>
      ReplicaState::Deleting({
        document,
        baseline,
        phase: DeletionPhase::ResolvingSave(operation),
      })
    Live({ document, phase: Available(remote) | Diverged(remote), .. }) =>
      match remote {
        Present(revision, text) =>
          ReplicaState::Deleting({
            document,
            baseline: LiveBaseline::Saved(revision, text),
            phase: DeletionPhase::Ready,
          })
        Deleted(revision) => ReplicaState::Tombstone(revision)
        Missing => return Remove(self)
      }
  }
  Store({ ..self, state, recovery: None, }.advance())
}

///|
pub(all) suberror DeletionUnavailable {
  AlreadyDeleting
  AlreadyDeleted
} derive(Eq, Debug)

///|
pub fn OperationDraft::start(
  self : Self,
  operation_id : OperationId,
) -> ReplicaWrite {
  let operation = {
    operation_id,
    base_revision: self.replica.baseline_revision(),
    content: self.content,
  }
  let state = match (self.replica.state, self.content) {
    (Live(live), Save(_)) =>
      ReplicaState::Live({ ..live, phase: LivePhase::Sending(operation), })
    (Deleting(deleting), Delete) =>
      ReplicaState::Deleting({
        ..deleting,
        phase: DeletionPhase::Sending(operation),
      })
    _ => abort("operation draft no longer matches its replica")
  }
  Store({ ..self.replica, state, }.advance())
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
  let operation = match self.state {
    Live({ phase: Sending(operation), .. })
    | Deleting({ phase: ResolvingSave(operation) | Sending(operation), .. }) =>
      operation
    Live(_) | Deleting(_) | Tombstone(_) => raise NoPendingOperation
  }
  guard operation.operation_id == operation_id else { raise OperationMismatch }
  guard revision.value() == operation.base_revision + 1.0 else {
    raise RevisionMismatch
  }
  let state = match (self.state, operation.content) {
    (Live(live), Save(text)) =>
      ReplicaState::Live({
        ..live,
        baseline: LiveBaseline::Saved(revision, text),
        phase: LivePhase::Ready,
      })
    (Deleting(deleting), Save(text)) =>
      ReplicaState::Deleting({
        ..deleting,
        baseline: LiveBaseline::Saved(revision, text),
        phase: DeletionPhase::Ready,
      })
    (Deleting(_), Delete) => ReplicaState::Tombstone(revision)
    _ => raise NoPendingOperation
  }
  Store({ ..self, state, recovery: None, }.advance())
}

///|
/// Retire an operation that the server definitively did not apply. Delivery
/// failures with an uncertain outcome must retain the Sending phase instead.
pub fn DocumentReplica::reject_operation(
  self : Self,
  operation_id : OperationId,
) -> ReplicaWrite raise ReceiptMismatch {
  let operation = match self.state {
    Live({ phase: Sending(operation), .. })
    | Deleting({ phase: ResolvingSave(operation) | Sending(operation), .. }) =>
      operation
    Live(_) | Deleting(_) | Tombstone(_) => raise NoPendingOperation
  }
  guard operation.operation_id == operation_id else { raise OperationMismatch }
  match (self.state, operation.content) {
    (Live(live), Save(_)) =>
      Store(
        {
          ..self,
          state: ReplicaState::Live({ ..live, phase: LivePhase::Ready, }),
        }.advance(),
      )
    (Deleting({ baseline: Unpublished, .. }), Save(_)) => Remove(self)
    (Deleting(deleting), Save(_)) =>
      Store(
        {
          ..self,
          state: ReplicaState::Deleting({
            ..deleting,
            phase: DeletionPhase::Ready,
          }),
        }.advance(),
      )
    (Deleting(deleting), Delete) =>
      Store(
        {
          ..self,
          state: ReplicaState::Live({
            document: deleting.document,
            baseline: deleting.baseline,
            phase: LivePhase::Ready,
          }),
        }.advance(),
      )
    _ => raise NoPendingOperation
  }
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
  let (operation, live) = match self.state {
    Live(live) =>
      match live.phase {
        Sending(operation) => (operation, { ..live, phase: LivePhase::Ready, })
        Ready | Available(_) | Diverged(_) => raise NoPendingOperation
      }
    Deleting(deleting) => {
      let operation = match deleting.phase {
        ResolvingSave(operation) | Sending(operation) => operation
        DeletionPhase::Ready => raise NoPendingOperation
      }
      (
        operation,
        {
          document: deleting.document,
          baseline: deleting.baseline,
          phase: LivePhase::Ready,
        },
      )
    }
    Tombstone(_) => raise NoPendingOperation
  }
  guard operation.operation_id == operation_id else { raise OperationMismatch }
  guard remote.revision() > live.baseline.revision() else {
    raise RevisionMismatch
  }
  { ..self, state: ReplicaState::Live(live), }.reconcile(remote)
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
  guard self.state is ReplicaState::Live(live) else { raise InvalidRecoveryId }
  guard live.phase is LivePhase::Diverged(remote) else {
    raise InvalidRecoveryId
  }
  let recovery = recovery_identity(self.document_id, value)
  let recovery_document = recovery.document(live.document.text())
  let (state, recovery_identity) = match remote {
    RemoteDocument::Present(revision, text) =>
      (
        ReplicaState::Live({
          document: live.document.update(text),
          baseline: LiveBaseline::Saved(revision, text),
          phase: LivePhase::Ready,
        }),
        Some(recovery),
      )
    Deleted(revision) => (ReplicaState::Tombstone(revision), None)
    Missing => raise InvalidRecoveryId
  }
  let next = { ..self, state, recovery: recovery_identity, }.advance()
  Fork(next, recovery_document)
}

///|
pub fn DocumentReplica::reconcile(
  self : Self,
  remote : RemoteDocument,
) -> ReconcilePlan {
  guard self.state is ReplicaState::Live(live) else { return Unchanged }
  match live.phase {
    Sending(_) => return Unchanged
    Available(observed) | Diverged(observed) if remote.revision() <
      observed.revision() ||
      (remote.revision() == observed.revision() && remote != observed) =>
      return Unchanged
    Available(observed) | Diverged(observed) if remote == observed =>
      return Unchanged
    Ready | Available(_) | Diverged(_) => ()
  }
  let baseline = live.baseline.remote()
  if remote.revision() < live.baseline.revision() || remote == baseline {
    return Unchanged
  }
  if remote.same_content(baseline) ||
    remote.same_present_text(live.document.text()) {
    guard remote is RemoteDocument::Present(revision, text) else {
      return Unchanged
    }
    let next = {
      ..self,
      state: ReplicaState::Live({
        ..live,
        baseline: LiveBaseline::Saved(revision, text),
        phase: LivePhase::Ready,
      }),
    }.advance()
    return Persist(Store(next))
  }
  if live.baseline.same_text(live.document.text()) {
    let next = {
      ..self,
      state: ReplicaState::Live({ ..live, phase: LivePhase::Available(remote), }),
    }.advance()
    return Persist(Store(next))
  }
  let next = {
    ..self,
    state: ReplicaState::Live({ ..live, phase: LivePhase::Diverged(remote), }),
  }.advance()
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
  guard self.state is ReplicaState::Live(live) else { raise InvalidOpen }
  let remote = match live.phase {
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
  if remote.revision() < live.baseline.revision() {
    return Ready
  }
  if remote == live.baseline.remote() {
    return Ready
  }
  guard remote.revision() > live.baseline.revision() &&
    (
      live.phase is Available(_) ||
      live.baseline.same_text(live.document.text()) ||
      remote.same_present_text(live.document.text())
    ) else {
    raise InvalidOpen
  }
  PersistAndOpen(
    Store(
      {
        ..self,
        state: ReplicaState::Live({
          document: live.document.update(text),
          baseline: match remote {
            Present(revision, remote_text) => Saved(revision, remote_text)
            Missing | Deleted(_) => abort("present remote changed shape")
          },
          phase: LivePhase::Ready,
        }),
      }.advance(),
    ),
  )
}
