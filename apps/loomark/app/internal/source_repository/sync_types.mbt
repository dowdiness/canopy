///|
pub(all) suberror InvalidAccountId derive(Eq, Debug)

///|
pub(all) suberror InvalidOperationId derive(Eq, Debug)

///|
pub(all) suberror InvalidRecoveryId derive(Eq, Debug)

///|
pub(all) suberror InvalidRevision derive(Eq, Debug)

///|
pub(all) suberror InvalidReplica derive(Eq, Debug)

///|
pub struct AccountId(String) derive(Eq, Hash, Debug)

///|
pub fn AccountId::parse(value : String) -> AccountId raise InvalidAccountId {
  guard !value.is_empty() else { raise InvalidAccountId }
  AccountId(value)
}

///|
pub fn AccountId::value(self : Self) -> String {
  self.0
}

///|
pub struct OperationId(String) derive(Eq, Debug)

///|
pub fn OperationId::parse(
  value : String,
) -> OperationId raise InvalidOperationId {
  guard valid_uuid(value) else { raise InvalidOperationId }
  OperationId(value)
}

///|
pub fn OperationId::value(self : Self) -> String {
  self.0
}

///|
pub struct SavedRevision(Double) derive(Eq, Debug)

///|
pub fn SavedRevision::parse(
  value : Double,
) -> SavedRevision raise InvalidRevision {
  guard value >= 1.0 &&
    value <= 9007199254740991.0 &&
    @double.floor(value) == value else {
    raise InvalidRevision
  }
  SavedRevision(value)
}

///|
pub fn SavedRevision::value(self : Self) -> Double {
  self.0
}

///|
pub(all) enum RemoteDocument {
  Missing
  Present(SavedRevision, String)
  Deleted(SavedRevision)
} derive(Eq, Debug)

///|
pub fn RemoteDocument::revision(self : Self) -> Double {
  match self {
    Missing => 0.0
    Present(revision, _) | Deleted(revision) => revision.value()
  }
}

///|
pub(all) enum RemoteEntry {
  Present(DocumentId, SavedRevision, String)
  Deleted(DocumentId, SavedRevision)
} derive(Eq, Debug)

///|
pub fn RemoteEntry::document_id(self : Self) -> DocumentId {
  match self {
    Present(id, _, _) | Deleted(id, _) => id
  }
}

///|
pub fn RemoteEntry::revision(self : Self) -> SavedRevision {
  match self {
    Present(_, revision, _) | Deleted(_, revision) => revision
  }
}

///|
fn RemoteDocument::same_content(self : Self, other : Self) -> Bool {
  match (self, other) {
    (Missing, Missing) | (Deleted(_), Deleted(_)) => true
    (Present(_, left), Present(_, right)) => left == right
    _ => false
  }
}

///|
fn RemoteDocument::same_present_text(self : Self, text : String) -> Bool {
  match self {
    Present(_, remote_text) => remote_text == text
    Missing | Deleted(_) => false
  }
}

///|
pub(all) enum PendingContent {
  Save(String)
  Delete
} derive(Eq, Debug)

///|
pub struct PendingOperation {
  operation_id : OperationId
  base_revision : Double
  content : PendingContent
} derive(Eq, Debug)

///|
pub fn PendingOperation::operation_id(self : Self) -> OperationId {
  self.operation_id
}

///|
pub fn PendingOperation::base_revision(self : Self) -> Double {
  self.base_revision
}

///|
pub fn PendingOperation::content(self : Self) -> PendingContent {
  self.content
}

///|
pub struct RecoveryIdentity(Document) derive(Eq, Debug)

///|
fn recovery_identity(
  document_id : DocumentId,
  value : DocumentId,
) -> RecoveryIdentity raise InvalidRecoveryId {
  let identity = Document::create(value, "")
  guard value != document_id else { raise InvalidRecoveryId }
  RecoveryIdentity(identity)
}

///|
fn RecoveryIdentity::id(self : Self) -> DocumentId {
  self.0.id()
}

///|
fn RecoveryIdentity::document(self : Self, text : String) -> Document {
  self.0.update(text)
}

///|
pub enum ReplicaPhase {
  Ready
  Sending(PendingOperation)
  Available(RemoteDocument)
  Diverged(RemoteDocument)
} derive(Eq, Debug)

///|
/// A remote revision parsed from the only Replica phase in which it may be
/// explicitly opened. Callers cannot manufacture one from another phase.
pub struct RemoteUpdate {
  priv replica : DocumentReplica
  priv content : RemoteUpdateContent
} derive(Eq, Debug)

///|
priv enum RemoteUpdateContent {
  PresentUpdate(SavedRevision, String)
  DeletedUpdate(SavedRevision)
} derive(Eq, Debug)

///|
pub struct DocumentReplica {
  account : AccountId
  generation : Double
  document : Document
  baseline : RemoteDocument
  phase : ReplicaPhase
  recovery : RecoveryIdentity?
} derive(Eq, Debug)

///|
pub fn DocumentReplica::DocumentReplica(
  account : AccountId,
  document : Document,
) -> DocumentReplica {
  {
    account,
    generation: 0.0,
    document,
    baseline: RemoteDocument::Missing,
    phase: ReplicaPhase::Ready,
    recovery: None,
  }
}

///|
pub fn DocumentReplica::receive(
  account : AccountId,
  document : Document,
  revision : SavedRevision,
) -> DocumentReplica {
  {
    account,
    generation: 0.0,
    document,
    baseline: RemoteDocument::Present(revision, document.text()),
    phase: ReplicaPhase::Ready,
    recovery: None,
  }
}

///|
pub fn DocumentReplica::account(self : Self) -> AccountId {
  self.account
}

///|
pub fn DocumentReplica::document(self : Self) -> Document {
  self.document
}

///|
pub fn DocumentReplica::generation(self : Self) -> Double {
  self.generation
}

///|
pub fn DocumentReplica::baseline_revision(self : Self) -> Double {
  self.baseline.revision()
}

///|
pub fn DocumentReplica::observed_revision(self : Self) -> Double {
  match self.phase {
    Available(remote) | Diverged(remote) => remote.revision()
    Ready | Sending(_) => self.baseline.revision()
  }
}

///|
pub fn DocumentReplica::remote_update(self : Self) -> RemoteUpdate? {
  match self.phase {
    Available(RemoteDocument::Present(revision, text)) =>
      Some({ replica: self, content: PresentUpdate(revision, text), })
    Available(Deleted(revision)) =>
      Some({ replica: self, content: DeletedUpdate(revision), })
    Available(Missing) => None
    Ready | Sending(_) | Diverged(_) => None
  }
}

///|
pub fn RemoteUpdate::remote(self : Self) -> RemoteDocument {
  match self.content {
    PresentUpdate(revision, text) => RemoteDocument::Present(revision, text)
    DeletedUpdate(revision) => RemoteDocument::Deleted(revision)
  }
}

///|
fn DocumentReplica::advance(self : Self) -> DocumentReplica {
  { ..self, generation: self.generation + 1.0, }
}

///|
fn replica_from_storage(
  account : AccountId,
  document : Document,
  generation : Double,
  baseline : RemoteDocument,
  phase : ReplicaPhase,
  recovery : RecoveryIdentity?,
) -> DocumentReplica raise InvalidReplica {
  guard generation >= 0.0 &&
    generation <= 9007199254740991.0 &&
    @double.floor(generation) == generation else {
    raise InvalidReplica
  }
  match phase {
    Sending(operation) => {
      guard operation.base_revision == baseline.revision() else {
        raise InvalidReplica
      }
    }
    Available(remote) => {
      guard remote.revision() > baseline.revision() &&
        baseline.same_present_text(document.text()) else {
        raise InvalidReplica
      }
    }
    Diverged(remote) => {
      guard remote.revision() > baseline.revision() &&
        !baseline.same_present_text(document.text()) &&
        !remote.same_present_text(document.text()) else {
        raise InvalidReplica
      }
    }
    Ready => ()
  }
  { account, generation, document, baseline, phase, recovery, }
}

///|
pub fn DocumentReplica::recovery_document_id(self : Self) -> DocumentId? {
  self.recovery.map(recovery => recovery.id())
}

///|
pub fn DocumentReplica::is_deleted(self : Self) -> Bool {
  self.baseline is RemoteDocument::Deleted(_)
}

///|
/// A write intent produced by a sync transition. Callers cannot accidentally
/// detach conflict recovery from its replica.
pub enum ReplicaWrite {
  Store(DocumentReplica)
  Fork(DocumentReplica, Document)
  PromoteSource(DocumentReplica)
} derive(Eq, Debug)

///|
pub fn ReplicaWrite::replica(self : Self) -> DocumentReplica {
  match self {
    Store(replica) | Fork(replica, _) | PromoteSource(replica) =>
      replica
  }
}

///|
pub fn ReplicaWrite::recovery(self : Self) -> Document? {
  match self {
    Fork(_, recovery) => Some(recovery)
    Store(_) | PromoteSource(_) => None
  }
}

///|
pub fn DocumentReplica::store(self : Self) -> ReplicaWrite {
  Store(self)
}

///|
pub fn DocumentReplica::promote_source(self : Self) -> ReplicaWrite {
  PromoteSource(self)
}
