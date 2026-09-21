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
} derive(Eq)

///|
priv enum DocumentDeletion {
  NoDeletion
  DeleteConfirmation(@documents.Key)
} derive(Eq)

///|
priv enum SyncRetry {
  RetryPersistence(@replica_persistence.Retry)
  RetryNetwork(@sync.Retry)
} derive(Eq)

///|
priv enum Msg {
  Opened(@source_repository.OpenResult)
  EmptyCreateCompleted(Int, @source_repository.CreateResult)
  ExampleSelected(Activation, String)
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
  RetrySave
  RetryAccount
  StartSync(@documents.StartSync)
  AcceptRemote(@documents.AcceptRemote)
  RetrySync(SyncRetry)
  DocumentSelected(@documents.Key)
  CreateRequested
  CreateCompleted(Int, @source_repository.CreateResult)
  DeleteRequested(@documents.Key)
  DeleteCancelled
  DeleteConfirmed(@documents.Key)
  RetryDelete(@documents.Key)
  DismissDeleteFailure(@documents.Key)
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
  OperationPrepared(
    @sync.PlanId,
    @source_repository.AccountId,
    @source_repository.DocumentId,
    @source_repository.OperationId?
  )
  DeliveryCompleted(
    @sync.EffectId,
    @source_repository.AccountId,
    @source_repository.DocumentId,
    @source_repository.OperationId,
    @document_http.DeliveryResult
  )
  RemoteCompleted(
    @sync.EffectId,
    @source_repository.AccountId,
    @source_repository.DocumentId,
    @sync.RemoteRead,
    @document_http.RemoteResult
  )
  RecoveryCreated(
    @sync.EffectId,
    @source_repository.AccountId,
    @source_repository.DocumentId,
    @source_repository.CreateResult
  )
}
