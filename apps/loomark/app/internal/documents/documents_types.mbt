///|
pub enum Key {
  Source(@source_repository.DocumentId)
  Replica(@source_repository.AccountId, @source_repository.DocumentId)
} derive(Eq, Hash)

///|
priv enum LocalDocumentOrigin {
  EphemeralNew
  ImportedNew
  Existing
} derive(Eq)

///|
priv enum DocumentPersistence {
  Source(LocalDocumentOrigin, SourceDeletePhase)
  StartingSync(@source_repository.AccountId, @source_repository.Document)
  Replica(@source_repository.AccountId, ReplicaDeletePhase)
  Forking(ForkOwnership)
} derive(Eq)

///|
/// Page-local projection of synchronized deletion. The durable Replica and its
/// persistence lane remain authoritative; this state only controls visibility
/// and failure feedback.
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
priv enum SourceDeletePhase {
  Available
  Waiting(DeleteOperation)
  Deleting(DeleteOperation)
  Failed(DeleteOperation, @source_repository.DeleteFailure)
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
priv enum DocumentsSaveStatus {
  Saved
  Waiting(AutosaveWindow)
  Saving(SaveOperation, AutosaveWindow?)
  Failed(@source_repository.SaveFailure)
} derive(Eq)

///|
priv enum LeadSource {
  Unlisted
  Available(String)
} derive(Eq)

///|
priv enum EditState {
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
  edit : EditState
  save : DocumentsSaveStatus
  lead_source : LeadSource
} derive(Eq)

///|
pub struct SaveOperation {
  key : Key
  document : @source_repository.Document
} derive(Eq)

///|
pub struct DeleteOperation {
  key : Key
  document_id : @source_repository.DocumentId
  request_id : Int
} derive(Eq)

///|
/// One Replica edit admitted by Documents. The durable base and optimistic
/// working copy are consumed together by the parent in the same update.
pub struct ReplicaEdit {
  priv durable : @source_repository.DocumentReplica
  priv document : @source_repository.Document
} derive(Eq)

///|
#warnings("-unused_value")
priv enum DocumentsDeletePhase {
  Unavailable
  Available
  Waiting(DeleteOperation)
  Deleting(DeleteOperation)
  Failed(DeleteOperation, @source_repository.DeleteFailure)
  ReplicaPending
  ReplicaFailed(@source_repository.ReplicaFailure)
} derive(Eq)

///|
pub(all) enum Feedback {
  MaximumElapsed(Int)
  SaveCompleted(SaveOperation, @source_repository.SaveResult)
  ReplicaAdvanced(@source_repository.ReplicaWrite)
  ReplicaSettled(@source_repository.ReplicaWrite, Key?)
  ReplicaDeletionFailed(
    @source_repository.ReplicaWrite,
    @source_repository.ReplicaFailure
  )
  PromotionCompleted(
    @source_repository.ReplicaWrite,
    Result[Unit, @source_repository.ReplicaFailure]
  )
  DeleteCompleted(DeleteOperation, @source_repository.DeleteResult)
}

///|
pub(all) enum Msg {
  New(@source_repository.DocumentId)
  Imported(@source_repository.DocumentId, String)
  TextChanged(Key, String)
  CompositionStarted(Key)
  CompositionEnded(Key)
  FeedbackReceived(Feedback)
  RetrySave(Key)
  VisibilityFlush(Key)
  ApplyPendingEdit(Key, Int)
  DeleteConfirmed(Key)
  RetryDelete(Key)
  DismissDeleteFailure(Key)
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
pub(all) enum RemoteChange {
  UpdateAvailable(AcceptRemote)
  DeletedRemotely(AcceptRemote)
} derive(Eq)

///|
pub(all) enum RemoteAcceptance {
  Opened(State, @source_repository.Document, @source_repository.ReplicaWrite)
  Removed(State, @source_repository.ReplicaWrite)
}

///|
/// A canonical durable Replica materialized as one exact working copy.
pub struct OpenedDocument {
  priv documents : State
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
pub struct State {
  priv saved : @source_repository.SavedDocuments
  priv records : Array[Record]
  priv visible_account : @source_repository.AccountId?
  priv last_autosave_id : Int
  priv last_working_copy_version : Int
  priv last_delete_request : Int
} derive(Eq)
