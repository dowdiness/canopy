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
priv struct InputMetrics {
  accepted_edits : Int
  complete_value_reads : Int
  value_length_reads : Int
  recovery_count : Int
  last_input_type : String
  last_recovery : String
} derive(Eq)

///|
fn InputMetrics::initial() -> InputMetrics {
  {
    accepted_edits: 0,
    complete_value_reads: 0,
    value_length_reads: 0,
    recovery_count: 0,
    last_input_type: "-",
    last_recovery: "-",
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
  metrics : InputMetrics
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
  BeforeInputCaptured(@text_edit.InputObservation)
  InputCaptured(@text_edit.InputObservation?, @text_edit.InputObservation)
  CompositionStarted
  CompositionEnded(@text_edit.InputObservation?, @text_edit.InputObservation)
  WholeValueRead(@text_edit.RecoveryReason, String?)
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
