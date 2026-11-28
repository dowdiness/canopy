///|
#derive(Eq)
priv enum Page {
  /// Compact viewport, and what to open when nothing is stored yet.
  Loading(Bool, CreationIntent)
  OpeningNew(OpeningNewContext, Creation)
  Editing(EditingDocument)
  Recovery(@source_repository.OpenFailure, Bool)
}

///|
#derive(Eq)
priv struct Model {
  page : Page
  /// Whether the Document index or the Editor is in front.
  screen : Screen
  /// The Document index, kept while the Editor is in front so Back returns
  /// to the same search, scroll position, and card. An embedded Loomark
  /// never draws it.
  index : @document_index.DocumentIndex[@documents.Key]
  replication : @replication.State
  sign_in : @sign_in.SignIn
  focus_mode : Bool
}

///|
/// Which screen is in front. The Editor always holds a document, so the
/// Document index can show over it, and choosing a card is a Document switch.
#derive(Eq)
priv enum Screen {
  Browsing(Browsing)
  /// The Editor is in front.
  Writing(Writing)
  /// Back was asked during IME composition; the index returns once it ends,
  /// with Resume in front when `resuming`.
  Leaving(resuming~ : Bool)
  /// The startup URL named this document; it opens once the repository has
  /// loaded, or the index shows when it does not exist.
  Requested(@documents.Key)
  /// Loomark is embedded in another page: the Editor alone, with no index.
  Embedded
}

///|
#derive(Eq)
priv struct Writing {
  /// What `Notes` does to browser history to bring the index back.
  notes : NotesReturn
  /// The document the URL names. Whenever the Editor holds another one, as
  /// after a Document switch, the URL is replaced to name it.
  named : @documents.Key
  /// The Resume entry this was opened from, focused again on return.
  chosen : String?
}

///|
#derive(Eq)
priv enum NotesReturn {
  /// The Editor was opened from the index, whose history entry is behind it.
  HistoryBack
  /// The Editor opened at startup, with no index entry behind it.
  IndexEntry
}

///|
#derive(Eq)
priv struct Browsing {
  /// A document chosen while browsing that has not opened yet.
  opening : Opening?
  /// The document whose deletion was asked for from its card, so focus
  /// returns to the card rather than to Recent documents.
  card_deletion : @documents.Key?
  /// Resume is in front of the cards.
  resuming : Bool
}

///|
/// A choice made while browsing: the Editor comes to the front once it
/// activates a document newer than `generation`.
#derive(Eq)
priv struct Opening {
  generation : Int32
  /// The card chosen, shown Loading until it opens. A New document, an
  /// Example, or an import has none.
  card : @documents.Key?
  /// How the opened document's history entry comes to exist.
  entry : Entry
  /// The Resume entry to select once its document opens.
  choice : @resume_view.Choice[@documents.Key]?
}

///|
#derive(Eq)
priv enum Entry {
  /// A link, Back, or Forward already reached a URL over the index's entry.
  Pushed
  /// Chosen without a link: opening adds the entry over the index's.
  ToPush
  /// The startup URL named it, with no index entry behind.
  Startup
}

///|
#derive(Eq)
priv enum ScrollPane {
  TextPane
  PreviewPane
}

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
#derive(Eq)
priv struct OpeningNewContext {
  documents : @documents.Model
  mode : EditorMode
  compact : Bool
  next_activation_generation : Int32
}

///|
#derive(Eq)
priv struct Activation {
  key : @documents.Key
  generation : Int32
}

///|
priv struct ActivationTarget {
  key : @documents.Key
  document : @source_repository.Document
  resume_hint : @source_repository.EditingDocumentHint?
}

///|
#derive(Eq)
priv struct EditingDocument {
  activation : Activation
  documents : @documents.Model
  creation : Creation?
  deletion : DocumentDeletion
  mode : EditorMode
  menu_open : Bool
  compact : Bool
  preview : @editor.EditorState
  imports_pending : Int32
  next_creation_request_id : Int32
  /// The reading position held in the pane being read since the latest
  /// Editor-mode change, until the user engages a pane or the text changes.
  reading_anchor : @viewport.ReadingAnchor?
}

///|
/// The active document's text as Recent documents last settled it, which
/// lags typing by a short pause.
fn EditingDocument::settled_text(self : Self) -> String? {
  self.documents
  .recent()
  .iter()
  .find_first(listed => listed.key == self.activation.key)
  .map(listed => listed.source)
}

///|
#derive(Eq)
priv enum EditorMode {
  Text
  Preview
  /// `reading` is the pane the user last engaged; the other pane follows it.
  Split(reading~ : ScrollPane)
}

///|
#derive(Eq)
priv struct Creation {
  request_id : Int32
  intent : CreationIntent
  status : CreationStatus
}

///|
#derive(Eq)
priv enum CreationIntent {
  NewDocument
  Example(String)
}

///|
#derive(Eq)
priv enum CreationStatus {
  InProgress
  Failed(@source_repository.CreateFailure)
  Fault(String)
}

///|
priv enum DocumentUpdate {
  Updated(@documents.Transition)
  Unchanged
  Obsolete
  Fault(String)
}

///|
#derive(Eq)
priv enum DocumentDeletion {
  NoDeletion
  DeleteConfirmation(@documents.Key)
}

///|
#derive(Eq)
priv struct AccountControlsInput {
  session : @sync.Session
  sign_in : @sign_in.View
}

///|
priv enum Msg {
  Notify(String)
  NotificationFocusReturn
  AuthenticationReturned(Bool)
  Opened(@source_repository.OpenResult)
  EmptyCreateCompleted(Int32, @source_repository.CreateResult)
  ExampleSelected(Activation, String)
  ExampleCreateCompleted(Int32, String, @source_repository.CreateResult)
  /// Editor input, stamped with the device clock when it happened.
  InputChanged(Int32, @editor.InputEdit, @source_repository.ChangeTime)
  TextChanged(Int32, @text_change.TextChange, @source_repository.ChangeTime)
  CompositionStarted(Int32)
  CompositionEnded(Int32)
  ModeSelected(@editor.Mode)
  FocusModeToggled
  ReadingAnchored(Int32, @viewport.ReadingAnchor)
  MenuToggled
  EscapePressed
  ImportFilesSelected(FixedArray[@browser.File])
  ImportReadCompleted(Result[Bytes, Error])
  ImportCreateCompleted(String, @source_repository.CreateResult)
  ExportRequested
  PreviewEvent(@editor.EditorEvent)
  PaneEngaged(ScrollPane)
  ViewportChanged(Double)
  DocumentMaximumElapsed(Int32)
  DocumentSaved(@documents.SaveOperation, @source_repository.Document)
  DocumentSaveFailed(@documents.SaveOperation, @source_repository.SaveFailure)
  DocumentDeleted(@documents.DeleteOperation, @source_repository.DocumentId)
  DocumentDeleteFailed(
    @documents.DeleteOperation,
    @source_repository.DeleteFailure,
  )
  ApplyPendingEdit(@documents.Key, Int32)
  VisibilityChanged(Bool)
  PageRestored
  RetryAccount
  StartSync(@documents.StartSync)
  AcceptRemote(@documents.AcceptRemote)
  RetrySync(@sync.Retry)
  RetrySelection(@sync.SelectionRetry)
  DocumentSelected(@documents.Key)
  CreateRequested
  RetryOpeningNewCreation
  CreateCompleted(Int32, @source_repository.CreateResult)
  DeleteRequested(@documents.Key)
  DeleteCancelled
  DeleteConfirmed(@documents.Key)
  SignIn(@sign_in.Event)
  LogoutRequested
  LogoutCompleted(@sync.LogoutAttempt, @account_http.LogoutResult)
  Sync(SyncMsg)
  IndexMsg(@document_index.Msg[@documents.Key])
  /// A card or New was followed in the Document index.
  UrlRequested(@url.UrlRequest)
  UrlChanged(@url.Url)
  /// `Notes` was chosen in the Editor toolbar.
  NotesRequested
  /// Delete document was chosen on this document's card.
  IndexDeleteRequested(@documents.Key)
  /// Today was followed in the Document index on this local date.
  TodayDated(String)
  /// A Resume entry was chosen.
  EntryChosen(@resume_view.Choice[@documents.Key])
}

///|
priv enum SyncMsg {
  AccountResolved(Int32, @sync.AccountResult)
  DiscoveryCompleted(
    @source_repository.AccountId,
    @sync.DiscoveryId,
    @document_http.DiscoveryResult,
  )
  ReplicaWriteCompleted(
    @replica_persistence.Attempt,
    Result[Unit, @source_repository.ReplicaFailure],
  )
  OperationPrepared(@sync.OperationAttempt, @source_repository.OperationId?)
  DeliveryCompleted(@sync.DeliveryAttempt, @replication.DeliveryResult)
  RemoteCompleted(@sync.ReadAttempt, @document_http.RemoteResult)
  OpenCompleted(@sync.OpenAttempt, @document_http.RemoteResult)
  RecoveryCreated(@sync.RecoveryAttempt, @source_repository.CreateResult)
}
