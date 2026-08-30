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
  creation : DocumentCreation
  mode : EditorMode
  compact : Bool
  preview : PreviewState
  repository : @source_repository.RepositorySnapshot
} derive(Eq)

///|
priv enum EditorMode {
  Text
  Preview
  Split
} derive(Eq)

///|
priv struct PreviewResult {
  text : String
  html : @rabbita.Html
  empty : Bool
} derive(Eq)

///|
priv enum PreviewState {
  Unrequested
  Preparing
  Ready(PreviewResult)
  Failed(PreviewResult?)
} derive(Eq)

///|
priv enum SaveState {
  Saved
  Waiting
  Saving(String)
  Failed(@source_repository.SaveFailure)
} derive(Eq)

///|
priv enum DocumentCreation {
  Idle
  Creating
  CreationFailed(@source_repository.CreateFailure)
} derive(Eq)

///|
priv enum Msg {
  Opened(@source_repository.OpenResult)
  ExampleSelected(Activation, String)
  TextChanged(Activation, @text_change.TextChange)
  CompositionStarted(Activation)
  CompositionEnded(Activation)
  ModeSelected(EditorMode)
  BeginPreviewPreparation(Activation)
  PreviewPrepared(
    Activation,
    String,
    Result[@preview.PreviewOutput, @preview.PreviewFailure]
  )
  ParserAdvanced(
    Activation,
    String,
    Bool,
    Result[Unit, @preview.PreviewFailure]
  )
  PreviewRefreshRequested(Activation, String)
  PreviewRefreshed(
    Activation,
    String,
    Result[@preview.PreviewOutput, @preview.PreviewFailure]
  )
  ViewportChanged(Int)
  SaveRequested(Activation, String)
  SaveCompleted(Activation, String, @source_repository.SaveResult)
  RetrySave
  DocumentSelected(String)
  CreateRequested
  CreateCompleted(Activation, @source_repository.CreateResult)
}
