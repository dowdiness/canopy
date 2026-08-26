///|
priv enum Model {
  Loading(Bool)
  Editing(EditingState)
  Recovery(@browser_storage.OpenFailure, Bool)
} derive(Eq)

///|
priv struct EditingState {
  document_id : String
  text : String
  composing : Bool
  save : SaveState
  mode : EditorMode
  focused_mode : EditorMode
  compact : Bool
  preview : PreviewState
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
  Failed(@browser_storage.SaveFailure)
} derive(Eq)

///|
priv enum Msg {
  Opened(@browser_storage.OpenResult)
  TextChanged(@text_change.TextChange)
  CompositionStarted
  CompositionEnded
  ModeSelected(EditorMode)
  ModeKeyPressed(String)
  BeginPreviewPreparation
  PreviewPrepared(
    String,
    Result[@preview.PreviewOutput, @preview.PreviewFailure]
  )
  ParserAdvanced(String, Bool, Result[Unit, @preview.PreviewFailure])
  PreviewRefreshRequested(String)
  PreviewRefreshed(
    String,
    Result[@preview.PreviewOutput, @preview.PreviewFailure]
  )
  ViewportChanged(Int)
  SaveRequested(String)
  SaveCompleted(String, @browser_storage.SaveResult)
  RetrySave
}
