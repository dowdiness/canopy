///|
priv enum DocumentOrigin {
  EphemeralNew
  ImportedNew
  Existing
} derive(Eq)

///|
priv enum DocumentsCheckpointEligibility {
  Deferred
  Eligible
} derive(Eq)

///|
priv struct DocumentsCheckpoint {
  maximum_id : Int
  maximum_armed : Bool
  eligibility : DocumentsCheckpointEligibility
} derive(Eq)

///|
priv enum DocumentsSaveStatus {
  Saved
  Waiting(DocumentsCheckpoint)
  Saving(SaveOperation, DocumentsCheckpoint?)
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
priv struct DocumentRecord {
  document : @source_repository.Document
  origin : DocumentOrigin
  edit : EditState
  save : DocumentsSaveStatus
  lead_source : LeadSource
  delete : DocumentsDeletePhase
} derive(Eq)

///|
priv struct SaveOperation {
  document : @source_repository.Document
  origin : DocumentOrigin
} derive(Eq)

///|
priv struct DeleteOperation {
  document_id : String
  request_id : Int
} derive(Eq)

///|
priv enum DocumentsDeletePhase {
  Available
  Waiting(DeleteOperation)
  Deleting(DeleteOperation)
  Failed(DeleteOperation, @source_repository.DeleteFailure)
} derive(Eq)

///|
priv enum DocumentsFeedback {
  MaximumElapsed(String, Int)
  SaveCompleted(SaveOperation, @source_repository.SaveResult)
  DeleteCompleted(DeleteOperation, @source_repository.DeleteResult)
}

///|
priv enum DocumentsEvent {
  DocumentsNew(String)
  DocumentsImported(String, String)
  DocumentsTextChanged(String, String)
  DocumentsCompositionStarted(String)
  DocumentsCompositionEnded(String)
  DocumentsFeedbackReceived(DocumentsFeedback)
  DocumentsRetrySave(String)
  DocumentsVisibilityFlush(String)
  ApplyPendingEdit(String, Int)
  DeleteConfirmed(String)
  RetryDelete(String)
  DismissDeleteFailure(String)
}

///|
priv enum DocumentsDecision {
  DocumentsArmMaximum(String, Int)
  DocumentsPersist(SaveOperation)
  DeleteDocument(DeleteOperation)
}

///|
priv struct Documents {
  saved : @source_repository.SavedDocuments
  records : Array[DocumentRecord]
  last_checkpoint_id : Int
  last_pending_edit_revision : Int
  last_delete_request : Int
} derive(Eq)
