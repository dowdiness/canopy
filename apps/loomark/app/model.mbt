///|
priv enum Page {
  Loading(Bool)
  OpeningNew(OpeningNewContext, Creation)
  Editing(EditingDocument)
  Recovery(@source_repository.OpenFailure, Bool)
} derive(Eq)

///|
priv struct Model {
  page : Page
  replication : @replication.State
  sign_in : @sign_in.SignIn
  scroll_owner : ScrollPane
} derive(Eq)

///|
priv enum ScrollPane {
  TextPane
  PreviewPane
} derive(Eq)

///|
fn Model::sync(self : Self) -> @sync.State {
  self.replication.protocol()
}

///|
fn Model::with_sync(self : Self, sync : @sync.State) -> Self {
  { ..self, replication: self.replication.with_protocol(sync), }
}

///|
fn Model::with_page(self : Self, page : Page) -> Self {
  { ..self, page, }
}

///|
priv struct OpeningNewContext {
  documents : @documents.Model
  mode : EditorMode
  compact : Bool
  next_activation_generation : Int
  lifecycle_error : String?
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
priv struct EditingDocument {
  activation : Activation
  documents : @documents.Model
  creation : Creation?
  lifecycle_error : String?
  deletion : DocumentDeletion
  mode : EditorMode
  menu_open : Bool
  compact : Bool
  preview : @editor.EditorState
  import_failed : Bool
  imports_pending : Int
  next_creation_request_id : Int
} derive(Eq)

///|
priv enum EditorMode {
  Text
  Preview
  Split
} derive(Eq)

///|
priv struct Creation {
  request_id : Int
  intent : CreationIntent
  status : CreationStatus
} derive(Eq)

///|
priv enum CreationIntent {
  NewDocument
  Example(String)
} derive(Eq)

///|
priv enum CreationStatus {
  InProgress
  Failed(@source_repository.CreateFailure)
  Fault(String)
} derive(Eq)

///|
priv enum DocumentUpdate {
  Updated(@documents.Transition)
  Unchanged
  Obsolete
  Fault
}

///|
priv enum DocumentDeletion {
  NoDeletion
  DeleteConfirmation(@documents.Key)
} derive(Eq)

///|
priv struct AccountControlsInput {
  session : @sync.Session
  sign_in : @sign_in.View
} derive(Eq)

///|
priv enum Msg {
  AuthenticationReturned(Bool)
  Opened(@source_repository.OpenResult)
  EmptyCreateCompleted(Int, @source_repository.CreateResult)
  ExampleSelected(Activation, String)
  ExampleCreateCompleted(Int, String, @source_repository.CreateResult)
  InputChanged(Int, @editor.InputEdit)
  TextChanged(Int, @text_change.TextChange)
  CompositionStarted(Int)
  CompositionEnded(Int)
  ModeSelected(EditorMode)
  MenuToggled
  EscapePressed
  ImportFilesSelected(FixedArray[@browser.File])
  ImportReadCompleted(Result[Bytes, Error])
  ImportCreateCompleted(String, @source_repository.CreateResult)
  DismissImportFailure
  ExportRequested
  PreviewEvent(@editor.EditorEvent)
  ScrollClaimed(ScrollPane)
  ViewportChanged(Double)
  DocumentMaximumElapsed(Int)
  DocumentSaved(@documents.SaveOperation, @source_repository.Document)
  DocumentSaveFailed(@documents.SaveOperation, @source_repository.SaveFailure)
  DocumentDeleted(@documents.DeleteOperation, @source_repository.DocumentId)
  DocumentDeleteFailed(
    @documents.DeleteOperation,
    @source_repository.DeleteFailure
  )
  ApplyPendingEdit(@documents.Key, Int)
  VisibilityChanged(Bool)
  PageRestored
  RetrySave
  RetryAccount
  StartSync(@documents.StartSync)
  AcceptRemote(@documents.AcceptRemote)
  RetrySaving(@replica_persistence.Retry)
  RetrySync(@sync.Retry)
  RetrySelection(@sync.SelectionRetry)
  DocumentSelected(@documents.Key)
  CreateRequested
  RetryOpeningNewCreation
  DismissDocumentFault
  CreateCompleted(Int, @source_repository.CreateResult)
  DeleteRequested(@documents.Key)
  DeleteCancelled
  DeleteConfirmed(@documents.Key)
  RetryDelete(@documents.Key)
  DismissDeleteFailure(@documents.Key)
  SignIn(@sign_in.Event)
  LogoutRequested
  LogoutCompleted(@sync.LogoutAttempt, @account_http.LogoutResult)
  Sync(SyncMsg)
}

///|
priv enum SyncMsg {
  AccountResolved(Int, @sync.AccountResult)
  DiscoveryCompleted(
    @source_repository.AccountId,
    @sync.DiscoveryId,
    @document_http.DiscoveryResult
  )
  ReplicaWriteCompleted(
    @replica_persistence.Attempt,
    Result[Unit, @source_repository.ReplicaFailure]
  )
  OperationPrepared(@sync.OperationAttempt, @source_repository.OperationId?)
  DeliveryCompleted(@sync.DeliveryAttempt, @replication.DeliveryResult)
  RemoteCompleted(@sync.ReadAttempt, @document_http.RemoteResult)
  OpenCompleted(@sync.OpenAttempt, @document_http.RemoteResult)
  RecoveryCreated(@sync.RecoveryAttempt, @source_repository.CreateResult)
}
