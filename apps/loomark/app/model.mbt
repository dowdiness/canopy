///|
priv enum Model {
  Loading(Bool)
  Editing(EditingState)
  Recovery(@source_repository.OpenFailure, Bool)
} derive(Eq)

///|
priv struct Activation {
  document_id : String
  generation : Int
} derive(Eq)

///|
priv struct EditingState {
  activation : Activation
  text : String
  composing : Bool
  save : SaveState
  last_checkpoint_epoch : Int
  creation : DocumentCreation
  deletion : DocumentDeletion
  last_delete_request : Int
  mode : EditorMode
  compact : Bool
  preview : @preview.State
  repository : @source_repository.RepositorySnapshot
} derive(Eq)

///|
priv enum EditorMode {
  Text
  Preview
  Split
} derive(Eq)

///|
priv enum CheckpointEligibility {
  Deferred
  Eligible
} derive(Eq)

///|
priv struct Checkpoint {
  epoch : Int
  quiet_revision : Int
  eligibility : CheckpointEligibility
} derive(Eq)

///|
priv enum SaveState {
  Saved
  Waiting(Checkpoint)
  Saving(String, Checkpoint?)
  Failed(@source_repository.SaveFailure, Bool)
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
  DeleteConfirmation(String)
  Deleting(Int, String)
  DeleteFailed(String, @source_repository.DeleteFailure)
} derive(Eq)

///|
priv enum Msg {
  Opened(@source_repository.OpenResult)
  ExampleSelected(Activation, String)
  TextChanged(Activation, @text_change.TextChange)
  CompositionStarted(Activation)
  CompositionEnded(Activation)
  ModeSelected(EditorMode)
  PreviewEvent(@preview.Event)
  ViewportChanged(Int)
  QuietElapsed(Activation, Int, Int)
  MaximumElapsed(Activation, Int)
  VisibilityChanged(Bool)
  SaveCompleted(Activation, String, @source_repository.SaveResult)
  RetrySave
  DocumentSelected(String)
  CreateRequested
  CreateCompleted(Activation, @source_repository.CreateResult)
  DeleteRequested(String)
  DeleteCancelled
  DeleteConfirmed(String)
  DeleteCompleted(Int, @source_repository.DeleteResult)
  DismissDeleteFailure
}
