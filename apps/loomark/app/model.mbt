///|
priv enum Model {
  Loading(Bool)
  PreparingNew(PreparingNewState)
  Editing(EditingState)
  Recovery(@source_repository.OpenFailure, Bool)
} derive(Eq)

///|
priv struct PreparingNewState {
  documents : Documents
  mode : EditorMode
  compact : Bool
  request_id : Int
  next_activation_generation : Int
} derive(Eq)

///|
priv struct Activation {
  document_id : String
  generation : Int
} derive(Eq)

///|
priv struct EditingState {
  activation : Activation
  documents : Documents
  creation : DocumentCreation
  deletion : DocumentDeletion
  mode : EditorMode
  compact : Bool
  preview : @preview.State
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
  DeleteDeferred(String)
  DeleteConfirmation(String)
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
  ExportRequested
  PreviewEvent(@preview.Event)
  ViewportChanged(Int)
  DocumentsLifecycle(DocumentsFeedback)
  VisibilityChanged(Bool)
  RetrySave
  DocumentSelected(String)
  CreateRequested
  CreateCompleted(String, @source_repository.CreateResult)
  DeleteRequested(String)
  DeleteCancelled
  DeleteConfirmed(String)
  RetryDelete(String)
  DismissDeleteFailure(String)
}
