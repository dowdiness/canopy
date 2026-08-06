///|
/// Private pre-`MountedApp` application and test-driver seam.
priv enum DriverEvent {
  ReplaceSource(String)
  SelectRaw
  SelectBlock
  SelectPreview
  ToggleSplitPreview
  BlockFocused(String)
  BlockHeading(Int, BlockSelection?)
  BlockToggleList(BlockSelection?)
  BlockDelete
  RawInput(String, @dom_boundary.TextSelection?)
  BlockInput(
    node_id~ : @markdown.MarkdownNodeId,
    input_id~ : String,
    text~ : String,
    selection_offset~ : Int
  )
  BlockSplit(node_id~ : @markdown.MarkdownNodeId, offset~ : Int)
  BlockMerge(node_id~ : @markdown.MarkdownNodeId, selection~ : BlockSelection)
  BlockNavigate(key~ : String, direction~ : Int)
  BlockSelectionRejected(String, BlockSelection?)
  ProbeBlockSelection(String)
  EditorFailure
  RestoreSnapshot(
    version~ : Int,
    source~ : String,
    mode~ : @core.ApplicationMode
  )
  FocusPreview
  FocusBlock
  FocusRaw
  RestoreFocus(String)
  FocusRejected(@core.FocusDecisionError)
  WriteSelection(start~ : Int, end~ : Int)
  WriteSelectionFailure
  MeasurePreview
  MeasureFailure
  SelectionRead(start~ : Int, end~ : Int)
  Measured(width~ : Double, height~ : Double)
  EffectFailed(String)
  CustomEvent(String)
  ControlInstalled
  SubscriptionInstalled
  SubscriptionUnloaded
  InvalidRequest(String)
  StopListening
  Fatal(String)
  Resize(@common.Viewport)
  ArchiveWriteCompleted(@archive_storage.LocalArchiveWriteCompletion)
}

///|
priv suberror DriverSubscription {
  Control(@cmd.Emit[DriverEvent])
  Test(@cmd.Emit[String], @cmd.Emit[DriverEvent])
}

///|
priv struct DriverModel {
  state : @core.ApplicationState
  document : @markdown.MarkdownDocumentSnapshot
  document_id : @archive.LoomarkDocumentId
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
