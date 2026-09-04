///|
/// Pure per-document save lanes. Commands are represented only as decisions;
/// the application shell is responsible for executing them.
priv enum DocumentOrigin {
  Existing
  New
} derive(Eq)

///|
priv enum DocumentsCheckpointEligibility {
  Deferred
  Eligible
} derive(Eq)

///|
priv struct DocumentsCheckpoint {
  id : Int
  order : @source_repository.ChangeOrder
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
  source : @source_repository.SourceRecord
  origin : DocumentOrigin
  composing : Bool
  save : DocumentsSaveStatus
  delete : DocumentsDeletePhase
} derive(Eq)

///|
priv struct SaveOperation {
  source : @source_repository.SourceRecord
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
  Probing(DeleteOperation)
  Unknown(DeleteOperation)
  Failed(DeleteOperation, @source_repository.DeleteFailure)
} derive(Eq)

///|
priv enum DocumentsFeedback {
  QuietElapsed(String, @source_repository.ChangeOrder)
  MaximumElapsed(String, Int)
  SaveCompleted(SaveOperation, @source_repository.SaveResult)
  DeleteCompleted(DeleteOperation, @source_repository.DeleteResult)
  DeleteWatchdogElapsed(DeleteOperation)
  DeleteProbeCompleted(DeleteOperation, @source_repository.ProbeResult)
  DeleteProbeElapsed(DeleteOperation)
}

///|
priv enum DocumentsEvent {
  DocumentsNew(String)
  DocumentsImported(String, String, @source_repository.ChangeOrder)
  DocumentsTextChanged(String, String, @source_repository.ChangeOrder)
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
  DocumentsArmQuiet(String, @source_repository.ChangeOrder)
  DocumentsArmMaximum(String, Int)
  DocumentsPersist(SaveOperation)
  DeleteSource(DeleteOperation)
  ArmDeleteWatchdog(DeleteOperation)
  ProbeDelete(DeleteOperation)
  ArmProbeWatchdog(DeleteOperation)
}

///|
priv struct Documents {
  snapshot : @source_repository.RepositorySnapshot
  records : Array[DocumentRecord]
  last_checkpoint_id : Int
  last_delete_request : Int
  change_order_floor : @source_repository.ChangeOrder
} derive(Eq)
