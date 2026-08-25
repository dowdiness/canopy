///|
priv enum Model {
  Loading
  Editing(EditingState)
  Recovery(@browser_storage.OpenFailure)
} derive(Eq)

///|
priv struct EditingState {
  document_id : String
  text : String
  composing : Bool
  save : SaveState
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
}
