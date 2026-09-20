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
  Replica(@source_repository.AccountId)
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
#warnings("-unused_value")
priv enum DocumentsDeletePhase {
  Unavailable
  Available
  Waiting(DeleteOperation)
  Deleting(DeleteOperation)
  Failed(DeleteOperation, @source_repository.DeleteFailure)
} derive(Eq)

///|
pub(all) enum Feedback {
  MaximumElapsed(Int)
  SaveCompleted(SaveOperation, @source_repository.SaveResult)
  ReplicaCommitted(@source_repository.ReplicaWrite)
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
pub(all) enum Effect {
  ArmMaximum(Int)
  PersistSource(SaveOperation)
  PersistReplica(@source_repository.ReplicaWrite)
  ReplicaEligible(@source_repository.AccountId, @source_repository.Document)
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
pub(all) suberror ActionError {
  ExpiredAction
} derive(Eq, Debug)

///|
pub struct State {
  priv saved : @source_repository.SavedDocuments
  priv records : Array[Record]
  priv visible_account : @source_repository.AccountId?
  priv last_autosave_id : Int
  priv last_pending_edit_revision : Int
  priv last_delete_request : Int
} derive(Eq)
