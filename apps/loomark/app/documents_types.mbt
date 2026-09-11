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
  quiet_revision : Int
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
priv struct DocumentRecord {
  document : @source_repository.Document
  origin : DocumentOrigin
  composing : Bool
  save : DocumentsSaveStatus
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
  Observing(DeleteOperation)
  Unknown(DeleteOperation)
  Failed(DeleteOperation, @source_repository.DeleteFailure)
} derive(Eq)

///|
priv enum DocumentsFeedback {
  QuietElapsed(String, Int)
  MaximumElapsed(String, Int)
  SaveCompleted(SaveOperation, @source_repository.SaveResult)
  DeleteCompleted(DeleteOperation, @source_repository.DeleteResult)
  DeleteWatchdogElapsed(DeleteOperation)
  DeletionObservationCompleted(
    DeleteOperation,
    @source_repository.DeletionObservationResult
  )
  DeletionObservationElapsed(DeleteOperation)
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
  DeleteConfirmed(String)
  RetryDelete(String)
  DismissDeleteFailure(String)
}

///|
priv enum DocumentsDecision {
  DocumentsArmQuiet(String, Int)
  DocumentsArmMaximum(String, Int)
  DocumentsPersist(SaveOperation)
  DeleteDocument(DeleteOperation)
  ArmDeleteWatchdog(DeleteOperation)
  ObserveDeletion(DeleteOperation)
  ArmDeletionWatchdog(DeleteOperation)
}

///|
priv struct Documents {
  saved : @source_repository.SavedDocuments
  records : Array[DocumentRecord]
  last_checkpoint_id : Int
  last_quiet_revision : Int
  last_delete_request : Int
} derive(Eq)
