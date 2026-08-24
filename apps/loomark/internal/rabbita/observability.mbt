///|
let detached_snapshot : @ref.Ref[String] = { val: "{}" }

///|
fn mode_name(mode : @core.ApplicationMode) -> String {
  match mode {
    @core.Raw => "raw"
    @core.Block => "block"
    @core.Preview => "preview"
  }
}

///|
fn runtime_state_name(state : EditorRuntimeState) -> String {
  match state {
    EditorRuntimeState::Healthy => "healthy"
    EditorRuntimeState::LocalText(_) => "local-text"
    EditorRuntimeState::Restarting => "restarting"
    EditorRuntimeState::RawRecovery(_) => "raw-recovery"
  }
}

///|
fn runtime_source(model : DriverModel) -> String {
  match model.runtime_state {
    EditorRuntimeState::LocalText(source)
    | EditorRuntimeState::RawRecovery(source) => source
    _ => model.document.source()
  }
}

///|
fn record_error(
  model : DriverModel,
  code : String,
  operation : String,
  message : String,
) -> DriverModel {
  {
    ..model,
    error: Some(message),
    error_code: Some(code),
    error_operation: Some(operation),
    error_count: model.error_count + 1,
  }
}

///|
fn local_persistence_failure_name(
  error : @repository.LocalArchivePersistenceFailure,
) -> String {
  match error {
    @repository.LocalArchivePersistenceFailure::Storage(error) =>
      match error {
        @repository.LocalArchiveStorageWriteFailure::Unavailable =>
          "unavailable"
        @repository.LocalArchiveStorageWriteFailure::QuotaExceeded =>
          "quota-exceeded"
        @repository.LocalArchiveStorageWriteFailure::Failed => "failed"
      }
    @repository.LocalArchivePersistenceFailure::PreparationFailed =>
      "archive-preparation-failed"
  }
}

///|
fn local_persistence_snapshot(
  status : @repository.LocalArchivePersistenceStatus,
) -> Json {
  match status {
    @repository.LocalArchivePersistenceStatus::DurableLocal(version) =>
      Json::object({
        "status": "durable-local".to_json(),
        "current_version": version.to_json_string().to_json(),
        "durable_version": version.to_json_string().to_json(),
        "error": Json::null(),
      })
    @repository.LocalArchivePersistenceStatus::Applied(current~, durable~) =>
      Json::object({
        "status": "applied".to_json(),
        "current_version": current.to_json_string().to_json(),
        "durable_version": match durable {
          Some(version) => version.to_json_string().to_json()
          None => Json::null()
        },
        "error": Json::null(),
      })
    @repository.LocalArchivePersistenceStatus::StorageFailed(
      current~,
      durable~,
      error~
    ) =>
      Json::object({
        "status": "storage-failed".to_json(),
        "current_version": current.to_json_string().to_json(),
        "durable_version": match durable {
          Some(version) => version.to_json_string().to_json()
          None => Json::null()
        },
        "error": local_persistence_failure_name(error).to_json(),
      })
  }
}

///|
/// Whether the currently presented surface owns the browser Raw draft.
fn raw_draft_surface_live(
  mode : @core.ApplicationMode,
  split_preview_open : Bool,
) -> Bool {
  mode == @core.Raw || (mode == @core.Preview && split_preview_open)
}

///|
fn publish(
  model : DriverModel,
  raw_input_coordinator : RawInputCoordinator?,
  raw_input_token : Int?,
) -> Unit {
  match (raw_input_coordinator, raw_input_token) {
    (Some(coordinator), Some(token)) => coordinator.mark_publish_started(token)
    _ => ()
  }
  let fields : Map[String, Json] = {
    "source": match raw_input_coordinator {
      Some(coordinator) if raw_draft_surface_live(
          model.state.mode(),
          model.split_preview_open,
        ) &&
        (
          model.runtime_state is EditorRuntimeState::Healthy ||
          model.runtime_state is EditorRuntimeState::LocalText(_)
        ) =>
        match coordinator.fast_source_value() {
          Some(source) => source.to_json()
          None => runtime_source(model).to_json()
        }
      _ => runtime_source(model).to_json()
    },
    "replica_id": model.replica_id.to_json(),
    "version": @core.SNAPSHOT_VERSION.to_json(),
    "mode": mode_name(model.state.mode()).to_json(),
    "runtime_state": runtime_state_name(model.runtime_state).to_json(),
    "local_persistence": local_persistence_snapshot(
      model.archive_queue.status(),
    ),
    "split_preview_open": model.split_preview_open.to_json(),
    "source_revision": model.source_revision.to_json(),
    "semantic_read_count": model.semantic_read_count.to_json(),
    "fatal": model.fatal.to_json(),
    "error_code": match model.error_code {
      Some(code) => code.to_json()
      None => Json::null()
    },
    "error_operation": match model.error_operation {
      Some(operation) => operation.to_json()
      None => Json::null()
    },
    "error_count": model.error_count.to_json(),
    "committed_change_count": model.committed_change_count.to_json(),
    "editor_failure_armed": model.fail_next_editor_commit.to_json(),
    "parser_failure_armed": model.force_parser_failure.to_json(),
    "reconstruction_attempt_count": model.reconstruction_attempt_count.to_json(),
    "resize_count": model.resize_count.to_json(),
    "selection": match model.selection {
      Some(selection) => selection.to_json()
      None => Json::null()
    },
    "measurement": match model.measurement {
      Some(measurement) => measurement.to_json()
      None => Json::null()
    },
    "raw_input_phase": match raw_input_coordinator {
      Some(coordinator) => {
        match raw_input_token {
          Some(token) => coordinator.mark_publish_finished(token)
          None => ()
        }
        match coordinator.phase_json() {
          Some(phase) => phase
          None => Json::null()
        }
      }
      None => Json::null()
    },
    "raw_render_barrier_armed": match raw_input_coordinator {
      Some(coordinator) => coordinator.render_barrier_armed().to_json()
      None => false.to_json()
    },
    "raw_render_barrier_waiting": match raw_input_coordinator {
      Some(coordinator) => coordinator.render_barrier_waiting().to_json()
      None => false.to_json()
    },
    "event_detail": match model.event_detail {
      Some(detail) => detail.to_json()
      None => Json::null()
    },
    "event_count": model.event_count.to_json(),
    "control_ready": model.control_ready.to_json(),
    "event_install_count": model.event_install_count.to_json(),
    "event_unload_count": model.event_unload_count.to_json(),
    "listening": model.listening.to_json(),
    "rejection": match model.rejection {
      Some(rejection) => rejection.to_json()
      None => Json::null()
    },
    "error": match model.error {
      Some(error) => error.to_json()
      None => Json::null()
    },
  }
  detached_snapshot.val = Json::object(fields).stringify()
  projection_trace_adopted_not_presented()
}

///|
fn driver_event_name(event : DriverEvent) -> String {
  match event {
    Editing(edit_event) =>
      match edit_event {
        ReplaceSource(_) => "source"
        LocalTextInput(_) => "local-text-input"
        RawInput(_, _) => "raw-input"
        RawFastPreview(_) => "raw-fast-preview"
        RawFastFlush(_, _) => "raw-fast-flush"
        RawSelectionEdit(_) => "raw-selection-edit"
        CommitCapturedRawSelection(_) => "commit-captured-raw-selection"
        BlockFocused(_) => "block-focused"
        BlockHeading(_, _) => "block-heading"
        BlockToggleList(_) => "block-toggle-list"
        BlockDelete => "block-delete"
        BlockInput(..) => "block-input"
        BlockSplit(..) => "block-split"
        BlockMerge(..) => "block-merge"
        BlockNavigate(..) => "block-navigate"
        ProbeBlockSelection(_) => "probe-block-selection"
      }
    Navigation(nav_event) =>
      match nav_event {
        SelectRaw => "select-raw"
        SelectBlock => "select-block"
        SelectPreview => "select-preview"
        ToggleSplitPreview => "toggle-split"
        FocusPreview => "focus-preview"
        FocusBlock => "focus-block"
        FocusRaw => "focus-raw"
        RestoreFocus(_) => "restore-focus"
        FocusRejected(_) => "focus-rejected"
        EffectFailed(_) => "effect-failed"
        BlockSelectionRejected(_, _) => "block-selection-rejected"
      }
    Probe(probe_event) =>
      match probe_event {
        WriteSelection(..) => "write-selection"
        WriteSelectionFailure => "write-selection-failure"
        CaptureRawSelection => "capture-raw-selection"
        RawSelectionCaptured(_) => "raw-selection-captured"
        InstallRawSelection => "install-raw-selection"
        MeasurePreview => "measure-preview"
        MeasureFailure => "measure-failure"
        SelectionRead(..) => "selection-read"
        Measured(..) => "measured"
      }
    GotRawPreviewMsg(_) => "raw-preview"
    Lifecycle(life_event) =>
      match life_event {
        EditorFailure => "editor-failure"
        RetryLocalPersistence(_) => "retry-local-persistence"
        ForceParserFailure => "force-parser-failure"
        ForceReconstructionFailure => "force-reconstruction-failure"
        ArmRawRenderBarrier => "arm-raw-render-barrier"
        ReleaseRawRenderBarrier => "release-raw-render-barrier"
        RecoveryCopy => "recovery-copy"
        RecoveryDownload => "recovery-download"
        RecoveryReload => "recovery-reload"
        RecoveryEffectFailed(_) => "recovery-effect-failed"
        RestoreSnapshot(..) => "restore-snapshot"
        CustomEvent(_) => "custom-event"
        ControlInstalled => "control-installed"
        SubscriptionInstalled => "subscription-installed"
        SubscriptionUnloaded => "subscription-unloaded"
        InvalidRequest(_) => "invalid-request"
        StopListening => "stop-listening"
        Fatal(_) => "fatal"
        ProjectionWorkerResolved(_, _, _) => "projection-worker-resolved"
        Resize(_) => "resize"
      }
    Bootstrap(_) => "standalone-bootstrap-completed"
    Archive(_) => "archive-write-completed"
  }
}
