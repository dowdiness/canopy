///|
priv enum Model {
  Loading
  Editing(EditingState)
  Recovery(@browser_storage.OpenFailure)
} derive(Eq)

///|
priv enum DisplayLayout {
  Text
  Preview
  Split
} derive(Eq)

///|
priv struct PreviewState {
  last_completed : @preview.PreviewResult?
  preparing_input : String?
  failed_input : String?
  failure : @preview.PreviewFailure?
} derive(Eq)

///|
fn PreviewState::initial() -> PreviewState {
  {
    last_completed: None,
    preparing_input: None,
    failed_input: None,
    failure: None,
  }
}

///|
priv struct EditingState {
  document_id : String
  text : String
  composing : Bool
  save : SaveState
  display : DisplayLayout
  preview : PreviewState
  initial_text_focus : Bool
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
  TextChanged(String)
  CompositionStarted
  CompositionEnded
  SaveRequested(String)
  SaveCompleted(String, @browser_storage.SaveResult)
  RetrySave
  DisplaySelected(DisplayLayout)
  PreviewIntent
  PreviewPrepared(
    String,
    Result[@preview.PreviewResult, @preview.PreviewFailure]
  )
}
