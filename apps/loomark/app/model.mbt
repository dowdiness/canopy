///|
priv enum Page {
  Loading(Bool)
  PreparingNew(PreparingNewState)
  Editing(EditingState)
  Recovery(@source_repository.OpenFailure, Bool)
} derive(Eq)

///|
priv struct Model {
  page : Page
  sync : @sync.State
} derive(Eq)

///|
priv struct PreparingNewState {
  documents : @documents.State
  mode : EditorMode
  compact : Bool
  request_id : Int
  next_activation_generation : Int
} derive(Eq)

///|
priv struct Activation {
  key : @documents.Key
  generation : Int
} derive(Eq)

///|
priv struct ActivationTarget {
  key : @documents.Key
  document : @source_repository.Document
  resume_hint : @source_repository.EditingDocumentHint?
}

///|
priv struct EditingState {
  activation : Activation
  documents : @documents.State
  creation : DocumentCreation
  deletion : DocumentDeletion
  mode : EditorMode
  compact : Bool
  preview : @preview.State
  import_failed : Bool
  new_preparation_request_id : Int
} derive(Eq)

///|
priv enum EditorMode {
  Text
  Preview
  Split
} derive(Eq)

///|
priv enum DocumentCreation {
  Idle
  Creating
  CreationFailed(@source_repository.CreateFailure)
} derive(Eq)

///|
priv enum DocumentDeletion {
  NoDeletion
  DeleteConfirmation(@documents.Key)
} derive(Eq)

///|
priv enum Msg {
  Opened(@source_repository.OpenResult)
  EmptyCreateCompleted(Int, @source_repository.CreateResult)
  ExampleSelected(Activation, String)
  TextChanged(Activation, @text_change.TextChange)
  CompositionStarted(Activation)
  CompositionEnded(Activation)
  ModeSelected(EditorMode)
  ImportFilesSelected(FixedArray[@dom.File])
  ImportReadCompleted(Result[Bytes, Error])
  ImportCreateCompleted(String, @source_repository.CreateResult)
  DismissImportFailure
  ExportRequested
  PreviewEvent(@preview.Event)
  ViewportChanged(Double)
  DocumentsLifecycle(@documents.Feedback)
  ApplyPendingEdit(@documents.Key, Int)
  VisibilityChanged(Bool)
  RetrySave
  DocumentSelected(@documents.Key)
  CreateRequested
  CreateCompleted(@documents.Key, @source_repository.CreateResult)
  DeleteRequested(@documents.Key)
  DeleteCancelled
  DeleteConfirmed(@documents.Key)
  RetryDelete(@documents.Key)
  DismissDeleteFailure(@documents.Key)
  PersistCheckpoint(@source_repository.CheckpointWrite)
  Sync(SyncMsg)
}

///|
priv enum SyncMsg {
  AccountResolved(Int, @sync.AccountResult)
  CheckpointCompleted(@sync.RequestId, @source_repository.CheckpointResult)
}
