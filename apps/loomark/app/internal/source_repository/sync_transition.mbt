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
fn LiveReplica::with_text(self : Self, text : String) -> LiveReplica {
  guard text != self.document.text() else { return self }
  let edited = { ..self, document: self.document.update(text), }
  match self.phase {
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
    Available(remote) | Diverged(remote) if self.baseline.same_text(text) =>
      { ..edited, phase: LivePhase::Available(remote), }
    Available(remote) | Diverged(remote) =>
      { ..edited, phase: LivePhase::Diverged(remote), }
    Ready | Sending(_) => edited
  }
}

///|
fn LiveReplica::observed_revision(self : Self) -> Double {
  match self.phase {
    Available(remote) | Diverged(remote) => remote.revision()
    Ready | Sending(_) => self.baseline.revision()
  }
}

///|
fn LiveReplica::remote_head_advances(self : Self, head : RemoteHead) -> Bool {
  let revision = head.revision().value()
  revision > self.observed_revision() ||
  (revision == self.observed_revision() && head is RemoteHead::Deleted(_))
}

///|
/// Compare the visible text, rather than only the latest Replica candidate, so
/// IME and autosave-delay edits are represented without consulting durability.
/// This method exists only on a parsed live Replica; deletion states therefore
/// cannot be mistaken for synchronized visible text.
pub fn LiveReplica::relation(
  self : Self,
  working_text : String,
  knowledge : RemoteKnowledge,
) -> Relation {
  let live = self.with_text(working_text)
  let known_remote = knowledge.head()
  let remote_ahead = known_remote
    .map(head => live.remote_head_advances(head))
    .unwrap_or(false)
  match live.phase {
    LivePhase::Ready if live.baseline.same_text(live.document.text()) =>
      match known_remote {
        Some(RemoteHead::Deleted(_)) if remote_ahead =>
          Relation::DeletedRemotely
        Some(Present(_)) if remote_ahead => Relation::RemoteAhead
        Some(_) | None => Relation::Current
      }
    Ready | Sending(_) =>
      if remote_ahead {
        Relation::Concurrent
      } else {
        Relation::LocalAhead
      }
    Diverged(_) => Relation::Diverged
    Available(remote) =>
      match (known_remote, remote_ahead) {
        (Some(RemoteHead::Deleted(_)), true) => Relation::DeletedRemotely
        (Some(Present(_)), true) => Relation::RemoteAhead
        _ =>
          match remote {
            RemoteDocument::Present(_, _) => Relation::RemoteAhead
            Deleted(_) => Relation::DeletedRemotely
            Missing => Relation::Unavailable
          }
      }
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
  let replica = { ..self, state: ReplicaState::Live(live.with_text(text)), }
  Persist(Store(replica.advance()))
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
/// The next domain step for opening an unmounted Replica at a required remote
/// revision. Network activity and persistence remain outside this transition.
pub(all) enum OpenStep {
  Ready
  Persist(ReplicaWrite)
  AwaitSync
  Unavailable
} derive(Eq, Debug)

///|
/// Open an unmounted Replica only from remote content already retained by the
/// Replica. The required revision comes from the current remote catalog.
pub fn DocumentReplica::open(self : Self, required : SavedRevision) -> OpenStep {
  let live = match self.state {
    ReplicaState::Live(value) => value
    Deleting(_) | Tombstone(_) => return Unavailable
  }
  if live.baseline.revision() >= required.value() {
    return Ready
  }
  match live.phase {
    Ready | Sending(_) | Diverged(_) => AwaitSync
    Available(remote) if remote.revision() < required.value() => AwaitSync
    Available(RemoteDocument::Missing | Deleted(_)) => Unavailable
    Available(Present(revision, text)) =>
      Persist(
        Store(
          {
            ..self,
            state: ReplicaState::Live({
              document: live.document.update(text),
              baseline: LiveBaseline::Saved(revision, text),
              phase: LivePhase::Ready,
            }),
          }.advance(),
        ),
      )
  }
}
