///|
/// The private harness has exactly one mount per page/process. This is a
/// bounded test seam, not a reusable handle registry or lifecycle API.
let mounted : @ref.Ref[Bool] = { val: false }

///|
/// Build the shell model shared by private and standalone mounts.
fn initial_model(
  host_id : String,
  editor : @markdown.MarkdownEditor,
  document_id : @archive.LoomarkDocumentId,
  replica_id : String,
  archive_persistence_enabled~ : Bool,
  bootstrap_pending~ : Bool,
) -> DriverModel raise {
  let host_width = @dom_boundary.measure_element_id(host_id)
    .offset_width()
    .to_int() catch {
      _ => SPLIT_STACK_BREAKPOINT
    }
  let current_version = editor.version()
  let durable_version = if bootstrap_pending {
    None
  } else {
    Some(current_version)
  }
  {
    state: @core.ApplicationState::ApplicationState(@core.Raw),
    runtime_state: EditorRuntimeState::Healthy,
    document: editor.snapshot(),
    document_version: current_version,
    document_id,
    raw_selection: None,
    archive_persistence_enabled,
    bootstrap_pending,
    semantic_document: None,
    preview_artifact: None,
    raw_preview: RawPreviewModel::enabled(),
    semantic_read_count: 0,
    split_preview_open: false,
    compact_split: compact_split_for_width(host_width),
    active_block_key: None,
    replica_id,
    source_revision: 0,
    text_input_generation: 0,
    fatal: false,
    error: None,
    error_code: None,
    error_operation: None,
    error_count: 0,
    committed_change_count: 0,
    fail_next_editor_commit: false,
    force_parser_failure: false,
    force_reconstruction_failure: false,
    reconstruction_attempt_count: 0,
    resize_count: 0,
    selection: None,
    measurement: None,
    event_detail: None,
    event_count: 0,
    control_ready: false,
    event_install_count: 0,
    event_unload_count: 0,
    listening: true,
    rejection: None,
    archive_queue: @repository.LocalArchivePersistenceQueue::LocalArchivePersistenceQueue(
      document_id~,
      queue_epoch=replica_id,
      current=current_version,
      durable=durable_version,
    ),
  }
}

///|
/// Build and mount the one shared application with an explicit host shell.
#warnings("-alert_unstable")
fn mount_private_dev_host_shell(
  host_id : String,
  source : String,
) -> String raise {
  if mounted.val {
    return "{\"ok\":false,\"error\":\"host-already-mounted\"}"
  }
  let replica_id = @archive_storage.fresh_id("loomark-dev-host-")
  let document_id = @archive.LoomarkDocumentId::from_string(
    @archive_storage.fresh_id("loomark-document-"),
  ) catch {
    _ => return "{\"ok\":false,\"error\":\"document-id-allocation-failed\"}"
  }
  let (editor, attachment) = @markdown.MarkdownEditor::with_semantic_attachment(
    agent_id=replica_id,
    source~,
  ) catch {
    _ => return "{\"ok\":false,\"error\":\"editor-initialization-failed\"}"
  }
  let initial = initial_model(
    host_id,
    editor,
    document_id,
    replica_id,
    archive_persistence_enabled=false,
    bootstrap_pending=false,
  )
  detached_focus_token.val = ""
  publish(initial, None, None)
  let app = application(
    ApplicationProfile::private_dev_host(),
    editor,
    attachment,
    initial,
    None,
  )
  app.mount(host_id)
  mounted.val = true
  "{\"ok\":true}"
}

///|
/// Mount the standalone shell immediately; its initial archive load is a
/// Rabbita Cmd and the editor session is adopted when that Cmd completes.
fn mount_standalone_with_mode(
  host_id : String,
  source : String,
  bootstrap_mode : StandaloneBootstrapMode,
) -> String {
  if mounted.val {
    return "{\"ok\":false,\"error\":\"host-already-mounted\"}"
  }
  mounted.val = true
  let replica_id = @archive_storage.fresh_id("loomark-standalone-writer-")
  let document_id = @archive.LoomarkDocumentId::from_string(
    @archive_storage.fresh_id("loomark-document-"),
  ) catch {
    _ => {
      recovery_application(RecoveryCategory::EditorInitializationFailed).mount(
        host_id,
      )
      return "{\"ok\":true}"
    }
  }
  // The production caller supplies an empty source. This session preserves the
  // shared shell shape; persisted LocalText is never inserted into it.
  let (editor, attachment) = @markdown.MarkdownEditor::with_semantic_attachment(
    agent_id=replica_id,
    source~,
  ) catch {
    _ => {
      recovery_application(RecoveryCategory::EditorInitializationFailed).mount(
        host_id,
      )
      return "{\"ok\":true}"
    }
  }
  let initial = initial_model(
    host_id,
    editor,
    document_id,
    replica_id,
    archive_persistence_enabled=false,
    bootstrap_pending=true,
  ) catch {
    _ => {
      attachment.dispose()
      recovery_application(RecoveryCategory::EditorInitializationFailed).mount(
        host_id,
      )
      return "{\"ok\":true}"
    }
  }
  detached_focus_token.val = ""
  publish(initial, None, None)
  let app = application(
    ApplicationProfile::standalone(bootstrap_mode),
    editor,
    attachment,
    initial,
    None,
  )
  app.mount(host_id)
  "{\"ok\":true}"
}

///|
/// Mount production standalone in its source-only LocalText lane.
pub fn mount_standalone(host_id : String, source : String) -> String {
  mount_standalone_with_mode(host_id, source, LocalTextBootstrap)
}

///|
/// Mount the fixed full-history baseline used only by Gate R0's browser oracle.
pub fn mount_full_history_oracle(host_id : String, source : String) -> String {
  mount_standalone_with_mode(host_id, source, FullHistoryOracleBootstrap)
}

///|
/// Mount the private application exactly once into a fresh connected element.
pub fn mount_private_dev_host(host_id : String, source : String) -> String {
  mount_private_dev_host_shell(host_id, source) catch {
    _ => "{\"ok\":false,\"error\":\"editor-initialization-failed\"}"
  }
}
