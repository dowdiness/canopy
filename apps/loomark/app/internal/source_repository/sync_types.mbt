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
/// The bounded remote fact relevant to one already-identified document.
pub(all) enum RemoteHead {
  Present(SavedRevision)
  Deleted(SavedRevision)
} derive(Eq, Debug)

///|
/// The newest remote fact known from both durable Replica state and transient
/// discovery. Construction remains in this package so callers cannot forget
/// either source of knowledge.
pub struct RemoteKnowledge(RemoteHead?) derive(Eq, Debug)

///|
pub fn RemoteEntry::head(self : Self) -> RemoteHead {
  match self {
    Present(_, revision, _) => RemoteHead::Present(revision)
    Deleted(_, revision) => RemoteHead::Deleted(revision)
  }
}

///|
fn RemoteHead::revision(self : Self) -> SavedRevision {
  match self {
    Present(revision) | Deleted(revision) => revision
  }
}

///|
fn RemoteHead::newest(self : Self, other : Self) -> Self {
  let left = self.revision().value()
  let right = other.revision().value()
  if right > left ||
    (right == left && other is RemoteHead::Deleted(_) && self is Present(_)) {
    other
  } else {
    self
  }
}

///|
pub fn RemoteKnowledge::head(self : Self) -> RemoteHead? {
  self.0
}

///|
/// Project a full remote response into the bounded metadata retained by the
/// transient account catalog.
pub fn RemoteDocument::entry(
  self : Self,
  document_id : DocumentId,
) -> RemoteEntry? {
  match self {
    Missing => None
    Present(revision, text) =>
      Some(
        RemoteEntry::Present(
          document_id,
          revision,
          @document_lead.extract(text).primary(),
        ),
      )
    Deleted(revision) => Some(RemoteEntry::Deleted(document_id, revision))
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
fn RemoteDocument::head(self : Self) -> RemoteHead? {
  match self {
    Missing => None
    Present(revision, _) => Some(RemoteHead::Present(revision))
    Deleted(revision) => Some(RemoteHead::Deleted(revision))
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
pub enum LivePhase {
  Ready
  Sending(PendingOperation)
  Available(RemoteDocument)
  Diverged(RemoteDocument)
} derive(Eq, Debug)

///|
pub enum LiveBaseline {
  Unpublished
  Saved(SavedRevision, String)
} derive(Eq, Debug)

///|
pub enum DeletionPhase {
  Ready
  ResolvingSave(PendingOperation)
  Sending(PendingOperation)
} derive(Eq, Debug)

///|
pub struct LiveReplica {
  document : Document
  baseline : LiveBaseline
  phase : LivePhase
} derive(Eq, Debug)

///|
pub struct DeletingReplica {
  document : Document
  baseline : LiveBaseline
  phase : DeletionPhase
} derive(Eq, Debug)

///|
pub(all) enum ReplicaState {
  Live(LiveReplica)
  Deleting(DeletingReplica)
  Tombstone(SavedRevision)
} derive(Eq, Debug)

///|
/// The visible working copy's relation to the newest remote head observed by
/// this client. Persistence and effect activity are deliberately absent.
pub(all) enum Relation {
  Current
  LocalAhead
  RemoteAhead
  Concurrent
  Diverged
  DeletedRemotely
  Unavailable
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
  document_id : DocumentId
  state : ReplicaState
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
    document_id: document.id(),
    state: ReplicaState::Live({
      document,
      baseline: LiveBaseline::Unpublished,
      phase: LivePhase::Ready,
    }),
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
    document_id: document.id(),
    state: ReplicaState::Live({
      document,
      baseline: LiveBaseline::Saved(revision, document.text()),
      phase: LivePhase::Ready,
    }),
    recovery: None,
  }
}

///|
pub fn DocumentReplica::account(self : Self) -> AccountId {
  self.account
}

///|
pub fn DocumentReplica::document_id(self : Self) -> DocumentId {
  self.document_id
}

///|
pub fn DocumentReplica::document(self : Self) -> Document? {
  match self.state {
    Live(value) => Some(value.document)
    Deleting(_) | Tombstone(_) => None
  }
}

///|
/// Parse the only Replica state that may be compared with a visible working
/// copy. Deleting replicas and tombstones cannot manufacture a text relation.
pub fn DocumentReplica::live(self : Self) -> LiveReplica? {
  match self.state {
    Live(value) => Some(value)
    Deleting(_) | Tombstone(_) => None
  }
}

///|
pub fn DocumentReplica::generation(self : Self) -> Double {
  self.generation
}

///|
pub fn DocumentReplica::baseline_revision(self : Self) -> Double {
  match self.state {
    Live(value) => value.baseline.revision()
    Deleting(value) => value.baseline.revision()
    Tombstone(revision) => revision.value()
  }
}

///|
pub fn DocumentReplica::observed_revision(self : Self) -> Double {
  match self.state {
    Live({ phase: Available(remote) | Diverged(remote), .. }) =>
      remote.revision()
    Live(value) => value.baseline.revision()
    Deleting(value) => value.baseline.revision()
    Tombstone(revision) => revision.value()
  }
}

///|
fn LiveBaseline::head(self : Self) -> RemoteHead? {
  match self {
    Unpublished => None
    Saved(revision, _) => Some(RemoteHead::Present(revision))
  }
}

///|
fn DocumentReplica::observed_head(self : Self) -> RemoteHead? {
  match self.state {
    Live({ baseline, phase: Available(remote) | Diverged(remote), .. }) =>
      match remote.head() {
        Some(head) => Some(head)
        None => baseline.head()
      }
    Live({ baseline, .. }) | Deleting({ baseline, .. }) => baseline.head()
    Tombstone(revision) => Some(RemoteHead::Deleted(revision))
  }
}

///|
/// Join durable remote knowledge with the latest transient catalog head. A
/// missing or older catalog cannot erase a fact already stored in the Replica.
pub fn DocumentReplica::remote_knowledge(
  self : Self,
  catalog : RemoteHead?,
) -> RemoteKnowledge {
  let head = match (self.observed_head(), catalog) {
    (Some(durable), Some(discovered)) => Some(durable.newest(discovered))
    (Some(durable), None) => Some(durable)
    (None, Some(discovered)) => Some(discovered)
    (None, None) => None
  }
  RemoteKnowledge(head)
}

///|
pub fn DocumentReplica::remote_update(self : Self) -> RemoteUpdate? {
  match self.state {
    Live({ phase: Available(RemoteDocument::Present(revision, text)), .. }) =>
      Some({ replica: self, content: PresentUpdate(revision, text), })
    Live({ phase: Available(Deleted(revision)), .. }) =>
      Some({ replica: self, content: DeletedUpdate(revision), })
    Live(_) | Deleting(_) | Tombstone(_) => None
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
pub fn RemoteUpdate::head(self : Self) -> RemoteHead {
  match self.content {
    PresentUpdate(revision, _) => RemoteHead::Present(revision)
    DeletedUpdate(revision) => RemoteHead::Deleted(revision)
  }
}

///|
fn DocumentReplica::advance(self : Self) -> DocumentReplica {
  { ..self, generation: self.generation + 1.0, }
}

///|
fn LiveBaseline::revision(self : Self) -> Double {
  match self {
    Unpublished => 0.0
    Saved(revision, _) => revision.value()
  }
}

///|
fn LiveBaseline::remote(self : Self) -> RemoteDocument {
  match self {
    Unpublished => RemoteDocument::Missing
    Saved(revision, text) => RemoteDocument::Present(revision, text)
  }
}

///|
fn LiveBaseline::same_text(self : Self, text : String) -> Bool {
  match self {
    Saved(_, baseline) => baseline == text
    Unpublished => false
  }
}

///|
fn replica_from_storage(
  account : AccountId,
  document_id : DocumentId,
  generation : Double,
  state : ReplicaState,
  recovery : RecoveryIdentity?,
) -> DocumentReplica raise InvalidReplica {
  guard generation >= 0.0 &&
    generation <= 9007199254740991.0 &&
    @double.floor(generation) == generation else {
    raise InvalidReplica
  }
  guard (match state {
    Live(value) => value.document.id() == document_id
    Deleting(value) => value.document.id() == document_id
    Tombstone(_) => recovery is None
  }) else {
    raise InvalidReplica
  }
  { account, generation, document_id, state, recovery, }
}

///|
pub fn DocumentReplica::recovery_document_id(self : Self) -> DocumentId? {
  self.recovery.map(recovery => recovery.id())
}

///|
pub fn DocumentReplica::is_deleted(self : Self) -> Bool {
  self.state is ReplicaState::Tombstone(_)
}

///|
pub fn DocumentReplica::is_deleting(self : Self) -> Bool {
  self.state is ReplicaState::Deleting(_)
}

///|
/// A write intent produced by a sync transition. Callers cannot accidentally
/// detach conflict recovery from its replica.
pub enum ReplicaWrite {
  Store(DocumentReplica)
  // Removal commits identity, not the candidate's transient text. The Replica
  // payload carries routing identity through the persistence lane.
  Remove(DocumentReplica)
  Fork(DocumentReplica, Document)
  PromoteSource(DocumentReplica)
} derive(Eq, Debug)

///|
pub fn ReplicaWrite::replica(self : Self) -> DocumentReplica {
  match self {
    Store(replica)
    | Remove(replica)
    | Fork(replica, _)
    | PromoteSource(replica) => replica
  }
}

///|
pub fn ReplicaWrite::recovery(self : Self) -> Document? {
  match self {
    Fork(_, recovery) => Some(recovery)
    Store(_) | Remove(_) | PromoteSource(_) => None
  }
}

///|
pub fn DocumentReplica::store(self : Self) -> ReplicaWrite {
  Store(self)
}

///|
/// Reassert committed contents after superseding a failed candidate. The new
/// generation lets the write acknowledgment advance the canonical repository.
pub fn DocumentReplica::rewrite(self : Self) -> ReplicaWrite {
  Store(self.advance())
}

///|
pub fn DocumentReplica::promote_source(self : Self) -> ReplicaWrite {
  PromoteSource(self)
}
