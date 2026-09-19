///|
pub(all) suberror InvalidAccountId derive(Eq, Debug)

///|
pub(all) suberror InvalidOperationId derive(Eq, Debug)

///|
pub(all) suberror InvalidRecoveryId derive(Eq, Debug)

///|
pub(all) suberror InvalidRevision derive(Eq, Debug)

///|
pub(all) suberror InvalidCheckpoint derive(Eq, Debug)

///|
pub struct AccountId(String) derive(Eq, Debug)

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
  guard value.length() == 36 else { raise InvalidOperationId }
  for i in 0..<36 {
    if i == 8 || i == 13 || i == 18 || i == 23 {
      guard value[i] == '-' else { raise InvalidOperationId }
    } else {
      guard value[i] is ('0'..='9' | 'a'..='f' | 'A'..='F') else {
        raise InvalidOperationId
      }
    }
  }
  guard value[14] is ('1'..='8') &&
    value[19] is ('8' | '9' | 'a' | 'b' | 'A' | 'B') else {
    raise InvalidOperationId
  }
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
  document_id : String,
  value : String,
) -> RecoveryIdentity raise InvalidRecoveryId {
  let identity = Document::create(value, "") catch {
    _ => raise InvalidRecoveryId
  }
  guard identity.id() != document_id else { raise InvalidRecoveryId }
  RecoveryIdentity(identity)
}

///|
fn RecoveryIdentity::id(self : Self) -> String {
  self.0.id()
}

///|
fn RecoveryIdentity::document(self : Self, text : String) -> Document {
  self.0.update(text)
}

///|
pub enum SyncPhase {
  Ready
  Sending(PendingOperation)
  RemoteUpdate(RemoteDocument)
  Conflict(RecoveryIdentity)
} derive(Eq, Debug)

///|
pub struct SyncCheckpoint {
  account : AccountId
  generation : Double
  document : Document
  baseline : RemoteDocument
  phase : SyncPhase
} derive(Eq, Debug)

///|
pub fn SyncCheckpoint::enroll(
  account : AccountId,
  document : Document,
) -> SyncCheckpoint {
  {
    account,
    generation: 0.0,
    document,
    baseline: RemoteDocument::Missing,
    phase: SyncPhase::Ready,
  }
}

///|
pub fn SyncCheckpoint::account(self : Self) -> AccountId {
  self.account
}

///|
pub fn SyncCheckpoint::document(self : Self) -> Document {
  self.document
}

///|
pub fn SyncCheckpoint::generation(self : Self) -> Double {
  self.generation
}

///|
fn SyncCheckpoint::advance(self : Self) -> SyncCheckpoint {
  { ..self, generation: self.generation + 1.0, }
}

///|
fn checkpoint_from_storage(
  account : AccountId,
  document : Document,
  generation : Double,
  baseline : RemoteDocument,
  phase : SyncPhase,
) -> SyncCheckpoint raise InvalidCheckpoint {
  guard generation >= 0.0 &&
    generation <= 9007199254740991.0 &&
    @double.floor(generation) == generation else {
    raise InvalidCheckpoint
  }
  match phase {
    Sending(operation) => {
      guard operation.base_revision == baseline.revision() else {
        raise InvalidCheckpoint
      }
    }
    Ready | RemoteUpdate(_) | Conflict(_) => ()
  }
  { account, generation, document, baseline, phase, }
}

///|
/// A write intent produced by a sync transition. Callers cannot accidentally
/// detach conflict recovery from its checkpoint.
pub enum CheckpointWrite {
  CheckpointOnly(SyncCheckpoint)
  CheckpointAndRecovery(SyncCheckpoint, Document)
} derive(Eq, Debug)

///|
pub fn CheckpointWrite::checkpoint(self : Self) -> SyncCheckpoint {
  match self {
    CheckpointOnly(checkpoint) | CheckpointAndRecovery(checkpoint, _) =>
      checkpoint
  }
}
