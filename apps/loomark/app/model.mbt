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
  replication : @replication.State
  departure : Departure
  // A canceled departure does not cancel or release its physical HTTP request.
  login_prepare : LoginAttempt?
  next_login_id : Int
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
  imports_pending : Int
  new_preparation_request_id : Int
} derive(Eq)

///|
priv enum EditorMode {
  Text
  Preview
  Split
} derive(Eq)

///|
priv struct EditorPanelsInput {
  activation : Activation
  disabled : Bool
  read_only : Bool
  mode : EditorMode
  preview : @preview.State
} derive(Eq)

///|
priv enum DocumentCreation {
  Idle
  Creating(Int)
  CreationFailed(@source_repository.CreateFailure)
  ExampleCreationFailed(String, @source_repository.CreateFailure)
} derive(Eq)

///|
priv enum DocumentDeletion {
  NoDeletion
  DeleteConfirmation(@documents.Key)
} derive(Eq)

///|
priv struct LoginAttempt(Int) derive(Eq)

///|
priv enum LoginFailure {
  SaveFailed(@documents.DepartureFailure)
  AuthenticationFailed
} derive(Eq)

///|
priv enum Departure {
  Stable
  SavingBeforeLogin(LoginAttempt)
  PreparingLogin(LoginAttempt)
  PreparedLogin(LoginAttempt, @account_http.GoogleAuthorizationUrl)
  Redirecting(LoginAttempt)
  LoginFailed(LoginFailure)
} derive(Eq)

///|
fn Departure::editor_disabled(self : Self) -> Bool {
  match self {
    SavingBeforeLogin(_)
    | PreparingLogin(_)
    | PreparedLogin(_, _)
    | Redirecting(_) => true
    Stable | LoginFailed(_) => false
  }
}

///|
fn Departure::cancel(self : Self, attempt : LoginAttempt) -> Self {
  match self {
    SavingBeforeLogin(current)
    | PreparingLogin(current)
    | PreparedLogin(current, _) =>
      if current == attempt {
        Stable
      } else {
        self
      }
    Stable | Redirecting(_) | LoginFailed(_) => self
  }
}

///|
priv struct AccountControlsInput {
  session : @sync.Session
  departure : Departure
  can_login : Bool
} derive(Eq)

///|
priv enum Msg {
  AuthenticationReturned(Bool)
  Opened(@source_repository.OpenResult)
  EmptyCreateCompleted(Int, @source_repository.CreateResult)
  ExampleSelected(Activation, String)
  ExampleCreateCompleted(Int, String, @source_repository.CreateResult)
  TextChanged(Int, @text_change.TextChange)
  CompositionStarted(Int)
  CompositionEnded(Int)
  ModeSelected(EditorMode)
  ImportFilesSelected(FixedArray[@browser.File])
  ImportReadCompleted(Result[Bytes, Error])
  ImportCreateCompleted(String, @source_repository.CreateResult)
  DismissImportFailure
  ExportRequested
  PreviewEvent(@preview.Event)
  ViewportChanged(Double)
  DocumentsLifecycle(@documents.Feedback)
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
  CreateCompleted(Int, @source_repository.CreateResult)
  DeleteRequested(@documents.Key)
  DeleteCancelled
  DeleteConfirmed(@documents.Key)
  RetryDelete(@documents.Key)
  DismissDeleteFailure(@documents.Key)
  LoginRequested
  LoginCancelled(LoginAttempt)
  LoginPrepared(LoginAttempt, @account_http.LoginResult)
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
  DeliveryCompleted(@sync.DeliveryAttempt, @document_http.DeliveryResult)
  RemoteCompleted(@sync.ReadAttempt, @document_http.RemoteResult)
  OpenCompleted(@sync.OpenAttempt, @document_http.RemoteResult)
  RecoveryCreated(@sync.RecoveryAttempt, @source_repository.CreateResult)
}
