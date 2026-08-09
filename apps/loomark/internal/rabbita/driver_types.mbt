///|
/// Editing-surface events: mode-gated input and structural requests that
/// cross the atomic editor façade. ReplaceSource is deliberately exempt
/// from the mode gate (driver source replacement works in any mode).
priv enum EditingEvent {
  ReplaceSource(String)
  RawInput(String, @dom_boundary.TextSelection?, Int?)
  RawSelectionEdit(RawSelectionEditRequest)
  CommitCapturedRawSelection(String)
  BlockFocused(String)
  BlockHeading(Int, BlockSelection?)
  BlockToggleList(BlockSelection?)
  BlockDelete
  BlockInput(token~ : Int, input~ : PendingBlockInput)
  BlockSplit(node_id~ : @markdown.MarkdownNodeId, offset~ : Int)
  BlockMerge(node_id~ : @markdown.MarkdownNodeId, selection~ : BlockSelection)
  BlockNavigate(key~ : String, direction~ : Int)
  ProbeBlockSelection(String)
}

///|
/// View-surface events: mode selection, split, focus commands, and the
/// effect reports that accompany them. Not mode-gated.
priv enum NavigationEvent {
  SelectRaw
  SelectBlock
  SelectPreview
  ToggleSplitPreview
  FocusPreview
  FocusBlock
  FocusRaw
  RestoreFocus(String)
  FocusRejected(@core.FocusDecisionError)
  EffectFailed(String)
  BlockSelectionRejected(String, BlockSelection?)
}

///|
/// Driver/test instrumentation events: probes, measurements, and their
/// outbound results.
priv enum ProbeEvent {
  WriteSelection(start~ : Int, end~ : Int)
  WriteSelectionFailure
  CaptureRawSelection
  RawSelectionCaptured(@dom_boundary.TextSelection)
  InstallRawSelection
  MeasurePreview
  MeasureFailure
  SelectionRead(start~ : Int, end~ : Int)
  Measured(width~ : Double, height~ : Double)
}

///|
/// The editor/semantic resources currently owned by the application shell.
/// The holder is swapped only after a complete archive reopen succeeds.
priv struct EditorSession {
  editor : @markdown.MarkdownEditor
  attachment : @md_markdown.MarkdownSemanticAttachment
}

///|
/// Application-control events: failures, restore, subscriptions, fatal,
/// resize, and driver protocol errors.
priv enum LifecycleEvent {
  EditorFailure
  ForceParserFailure
  ForceReconstructionFailure
  RecoveryCopy
  RecoveryDownload
  RecoveryReload
  RecoveryEffectFailed(String)
  RestoreSnapshot(
    version~ : Int,
    source~ : String,
    mode~ : @core.ApplicationMode
  )
  CustomEvent(String)
  ControlInstalled
  SubscriptionInstalled
  SubscriptionUnloaded
  InvalidRequest(String)
  StopListening
  Fatal(String)
  Resize(@common.Viewport)
}

///|
/// Dispatch envelope: the concern of an event is encoded by the
/// constructor, so update_model's routing is total and misrouting is
/// unrepresentable. Archive completions are processed even in fatal state.
priv enum DriverEvent {
  Editing(EditingEvent)
  Navigation(NavigationEvent)
  Probe(ProbeEvent)
  Lifecycle(LifecycleEvent)
  Archive(@archive_storage.LocalArchiveWriteCompletion)
}

///|
priv suberror DriverSubscription {
  Control(@cmd.Emit[DriverEvent])
  Test(@cmd.Emit[String], @cmd.Emit[DriverEvent])
}

///|
priv struct DriverModel {
  state : @core.ApplicationState
  runtime_state : EditorRuntimeState
  document : @markdown.MarkdownDocumentSnapshot
  document_version : @markdown.MarkdownDocumentVersion
  document_id : @archive.LoomarkDocumentId
  raw_selection : VersionedRawSelection?
  archive_persistence_enabled : Bool
  semantic_document : @md_markdown.MarkdownIR?
  semantic_read_count : Int
  split_preview_open : Bool
  compact_split : Bool
  active_block_key : String?
  replica_id : String
  source_revision : Int
  text_input_generation : Int
  fatal : Bool
  error : String?
  error_code : String?
  error_operation : String?
  error_count : Int
  committed_change_count : Int
  fail_next_editor_commit : Bool
  force_parser_failure : Bool
  force_reconstruction_failure : Bool
  reconstruction_attempt_count : Int
  resize_count : Int
  selection : String?
  measurement : String?
  event_detail : String?
  event_count : Int
  control_ready : Bool
  event_install_count : Int
  event_unload_count : Int
  listening : Bool
  rejection : String?
  archive_tracker : @repository.LocalArchiveRequestTracker
  local_storage_warning : Bool
} derive(Eq)
