///|
pub enum Key {
  Source(@source_repository.DocumentId)
  Replica(@source_repository.AccountId, @source_repository.DocumentId)
} derive(Eq, Hash, Debug)

///|
priv enum LocalDocumentOrigin {
  EphemeralNew
  ImportedNew
  Existing
} derive(Eq)

///|
priv enum DocumentPersistence {
  Source(LocalDocumentOrigin, SourceLifecycle)
  StartingSync(
    @source_repository.AccountId,
    @source_repository.Document,
    Autosave
  )
  Replica(@source_repository.AccountId, ReplicaDeletePhase, Autosave)
  Forking(ForkOwnership, Autosave)
} derive(Eq)

///|
priv enum ReplicaDeletePhase {
  ReplicaAvailable
  ReplicaPending
  ReplicaFailed(@source_repository.ReplicaFailure)
} derive(Eq)

///|
priv struct ForkOwnership {
  account : @source_repository.AccountId
  original : @source_repository.DocumentId
  recovery : @source_repository.Document
} derive(Eq)

///|
priv struct DeletionFailure {
  operation : DeleteOperation
  cause : @source_repository.DeleteFailure
} derive(Eq)

///|
priv enum SourceLifecycle {
  Writable(SourceSave, DeletionFailure?)
  WaitingToDelete(SaveOperation, DeleteOperation, AutosaveWindow?)
  Deleting(DeleteOperation, Autosave)
} derive(Eq)

///|
/// Only a writable Source can start a write. WaitingToDelete owns an already
/// running write; Deleting can retain autosave work but never a running write.
priv enum SourceSave {
  Idle
  Waiting(AutosaveWindow)
  Saving(SaveOperation, AutosaveWindow?)
  Failed(@source_repository.SaveFailure)
} derive(Eq)

///|
/// Autosave scheduling without a Source write. Idle means no scheduled work,
/// not a durability acknowledgment; Replica durability belongs to its lane.
priv enum Autosave {
  Idle
  Waiting(AutosaveWindow)
  Failed(@source_repository.SaveFailure)
} derive(Eq)

///|
priv enum AutosaveEligibility {
  Deferred
  Eligible
} derive(Eq)

///|
priv struct AutosaveWindow {
  maximum_id : Int
  maximum_armed : Bool
  eligibility : AutosaveEligibility
} derive(Eq)

///|
priv enum LeadSource {
  Unlisted
  Available(String)
} derive(Eq)

///|
priv enum Editing {
  Idle
  Waiting(Int)
  ComposingIdle
  ComposingWaiting(Int)
  ComposingReady
} derive(Eq)

///|
priv struct Record {
  persistence : DocumentPersistence
  document : @source_repository.Document
  version : Int
  edit : Editing
  lead_source : LeadSource
} derive(Eq)

///|
pub struct SaveOperation {
  key : Key
  document : @source_repository.Document
  priv request_id : Int
} derive(Eq)

///|
pub struct DeleteOperation {
  key : Key
  document_id : @source_repository.DocumentId
  request_id : Int
} derive(Eq)

///|
pub struct ReplicaEdit {
  priv durable : @source_repository.DocumentReplica
  priv document : @source_repository.Document
} derive(Eq)

///|
pub enum Edit {
  Changed(Transition)
  SameText
}

///|
pub enum Delete {
  Accepted(Transition)
  AlreadyPending
}

///|
pub enum Update {
  Applied(Transition)
  // The current input is already satisfied; no transition is needed.
  Unchanged
  Superseded
}

///|
pub struct Transition {
  model : Model
  effects : ReadOnlyArray[Action]
}

///|
pub(all) enum Msg {
  Imported(@source_repository.DocumentId, String)
  CompositionStarted(Key)
  CompositionEnded(Key)
  RetrySave(Key)
  VisibilityFlush(Key)
  VisibilityFlushAll
  ApplyPendingEdit(Key, Int)
  DismissDeleteFailure(Key)
  MaximumElapsed(Int)
  Saved(SaveOperation, @source_repository.Document)
  SaveFailed(SaveOperation, @source_repository.SaveFailure)
  Deleted(DeleteOperation, @source_repository.DocumentId)
  DeleteFailed(DeleteOperation, @source_repository.DeleteFailure)
  ReplicaAdvanced(@source_repository.ReplicaWrite)
  ReplicaSettled(@source_repository.ReplicaWrite, Key?)
  ReplicaDeletionFailed(
    @source_repository.ReplicaWrite,
    @source_repository.ReplicaFailure
  )
  Promoted(@source_repository.ReplicaWrite)
  PromotionFailed(
    @source_repository.ReplicaWrite,
    @source_repository.ReplicaFailure
  )
}

///|
pub fn Msg::from_replica_completion(
  active : @source_repository.ReplicaWrite,
  completion : @replica_persistence.Completion,
  mounted : Key?,
) -> Msg? {
  match completion {
    Current(write) =>
      Some(
        if active is @source_repository.ReplicaWrite::PromoteSource(_) {
          Promoted(write)
        } else {
          ReplicaSettled(write, mounted)
        },
      )
    Superseded(write, _) =>
      Some(
        if active is @source_repository.ReplicaWrite::PromoteSource(_) {
          Promoted(write)
        } else {
          ReplicaAdvanced(write)
        },
      )
    Retryable(write, _, failure) | Failed(write, failure) =>
      if active is @source_repository.ReplicaWrite::PromoteSource(_) {
        Some(PromotionFailed(write, failure))
      } else if write is @source_repository.ReplicaWrite::Remove(_) ||
        write.replica().is_deleting() ||
        write.replica().is_deleted() {
        Some(ReplicaDeletionFailed(write, failure))
      } else {
        None
      }
  }
}

///|
pub(all) enum Action {
  ArmMaximum(Int)
  PersistSource(SaveOperation)
  StoreReplica(@source_repository.ReplicaWrite)
  SaveReplica(ReplicaEdit)
  DeleteReplica(ReplicaEdit)
  RetryReplica(@source_repository.AccountId, @source_repository.DocumentId)
  DeleteSource(DeleteOperation)
}

///|
pub(all) suberror CreateError {
  DocumentAlreadyExists(Key)
} derive(Eq, Debug)

///|
pub(all) suberror EditError {
  DocumentMissing(Key)
  PendingDeletion(Key)
} derive(Eq, Debug)

///|
pub(all) suberror DeleteError {
  DocumentMissing(Key)
  OwnershipTransferInProgress(Key)
  ReplicaMissing(Key)
} derive(Eq, Debug)

///|
pub(all) suberror UpdateError {
  DocumentMissing(Key)
  PendingDeletion(Key)
  CompositionInProgress(Key)
  DocumentMismatch(Key)
  DocumentAlreadyExists(Key)
  InvalidAcknowledgment(Key)
} derive(Eq, Debug)

///|
pub(all) enum SaveStatus {
  Clean
  Unsaved
  SaveFailed(@source_repository.SaveFailure)
} derive(Eq)

///|
pub(all) enum DeleteStatus {
  NotDeletable
  Deletable
  DeletePending
  DeleteFailed(@source_repository.DeleteFailure)
  DeletePersistenceFailed(@source_repository.ReplicaFailure)
} derive(Eq)

///|
pub(all) enum SyncStart {
  Unavailable
  Ready(StartSync)
  Starting
} derive(Eq)

///|
pub struct StartSync {
  priv key : Key
  priv account : @source_repository.AccountId
  priv document : @source_repository.Document
} derive(Eq)

///|
pub struct AcceptRemote {
  priv key : Key
  priv version : Int
  priv update : @source_repository.RemoteUpdate
} derive(Eq)

///|
pub(all) enum RemoteState {
  Current
  LocalAhead
  RemoteAhead
  Concurrent
  Diverged
  DeletedRemotely
  UpdateAvailable(AcceptRemote)
  DeletionAvailable(AcceptRemote)
  Unavailable
} derive(Eq)

///|
pub(all) enum RemoteAcceptance {
  Opened(Model, @source_repository.Document, @source_repository.ReplicaWrite)
  Removed(Model, @source_repository.ReplicaWrite)
}

///|
pub struct OpenedDocument {
  priv documents : Model
  priv key : Key
  priv document : @source_repository.Document
}

///|
pub(all) enum RemoteOpen {
  Opened(OpenedDocument)
  Superseded
}

///|
pub(all) suberror ActionError {
  ExpiredAction
} derive(Eq, Debug)

///|
pub struct Model {
  priv saved : @source_repository.SavedDocuments
  priv records : Array[Record]
  priv visible_account : @source_repository.AccountId?
  priv last_autosave_id : Int
  priv last_working_copy_version : Int
  priv last_delete_request : Int
} derive(Eq)

///|
pub extend AcceptRemote with Eq::{equal, not_equal}

///|
pub extend ActionError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ActionError with Eq::{equal, not_equal}

///|
pub extend DeleteOperation with Eq::{equal, not_equal}

///|
pub extend DeleteStatus with Eq::{equal, not_equal}

///|
pub extend Key with Eq::{equal, not_equal}

///|
pub extend Key with Hash::{hash, hash_combine}

///|
pub extend RemoteState with Eq::{equal, not_equal}

///|
pub extend ReplicaEdit with Eq::{equal, not_equal}

///|
pub extend SaveOperation with Eq::{equal, not_equal}

///|
pub extend SaveStatus with Eq::{equal, not_equal}

///|
pub extend StartSync with Eq::{equal, not_equal}

///|
pub extend Model with Eq::{equal, not_equal}

///|
pub extend SyncStart with Eq::{equal, not_equal}

///|
pub extend Key with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CreateError with Eq::{equal, not_equal}

///|
pub extend CreateError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend EditError with Eq::{equal, not_equal}

///|
pub extend EditError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend DeleteError with Eq::{equal, not_equal}

///|
pub extend DeleteError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend UpdateError with Eq::{equal, not_equal}

///|
pub extend UpdateError with @moonbitlang/core/debug.Debug::{to_repr}
