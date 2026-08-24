///|
priv struct ApplicationProfile {
  bootstrap_mode : StandaloneBootstrapMode?
  subscriptions : (DriverModel, @cmd.Emit[DriverEvent]) -> @sub.Sub
  preview_view : (DriverModel, @cmd.Emit[DriverEvent], @rabbita_runtime.Html) -> @rabbita_runtime.Html
}

///|
fn ApplicationProfile::standalone(
  bootstrap_mode : StandaloneBootstrapMode,
) -> ApplicationProfile {
  {
    bootstrap_mode: Some(bootstrap_mode),
    subscriptions: standalone_subscriptions,
    preview_view: standalone_preview_view,
  }
}

///|
fn ApplicationProfile::private_dev_host() -> ApplicationProfile {
  {
    bootstrap_mode: None,
    subscriptions: private_dev_host_subscriptions,
    preview_view: private_dev_host_preview_view,
  }
}

///|
fn application(
  profile : ApplicationProfile,
  editor : @markdown.MarkdownEditor,
  attachment : @md_markdown.MarkdownSemanticAttachment,
  initial : DriverModel,
  baseline : @repository.LocalArchivePendingWrite?,
) -> @rabbita_runtime.App {
  projection_benchmark_trace_enable()
  let bootstrap_mode = profile.bootstrap_mode
  let initial = match bootstrap_mode {
    Some(LocalTextBootstrap) =>
      { ..initial, raw_preview: RawPreviewModel::disabled() }
    _ => initial
  }
  let current_session : @ref.Ref[EditorSession] = {
    val: { editor, attachment },
  }
  let projection_session : @ref.Ref[ProjectionSession?]? = None
  let latest_model : @ref.Ref[DriverModel?] = { val: None }
  let raw_input_coordinator = RawInputCoordinator::RawInputCoordinator()
  raw_input_coordinator.set_fast_source(initial.document.source())
  let block_input_coordinator = BlockInputCoordinator::BlockInputCoordinator()
  let projection_worker = match selected_projection_placement {
    ProjectionWorker =>
      Some(ProjectionWorkerRuntime::new("loomark-production-projection"))
    ProjectionInProcess =>
      Some(
        ProjectionWorkerRuntime::new_in_process("loomark-comparison-projection"),
      )
    ProjectionSynchronous => None
  }
  // Raw Preview is a development/full-history capability. Production
  // LocalText is Raw-only and must not allocate an idle Worker.
  let raw_preview_runtime = match bootstrap_mode {
    Some(LocalTextBootstrap) => None
    _ => Some(RawPreviewRuntime::new("loomark-raw-preview"))
  }
  let application_subscriptions = (model, emit) => {
    let base = (profile.subscriptions)(model, emit)
    match (projection_worker, raw_preview_runtime) {
      (Some(projection), Some(raw_preview)) =>
        @sub.batch([
          base,
          projection_worker_subscription(projection),
          raw_preview_subscriptions(raw_preview),
        ])
      (Some(projection), None) =>
        @sub.batch([base, projection_worker_subscription(projection)])
      (None, Some(raw_preview)) =>
        @sub.batch([base, raw_preview_subscriptions(raw_preview)])
      (None, None) => base
    }
  }
  let update = (model, event, emit) => {
    let session = current_session.val
    let (next, command) = update_model_with_raw_preview_runtime(
      session.editor,
      session.attachment,
      raw_input_coordinator,
      block_input_coordinator,
      model,
      latest_model,
      event,
      emit,
      projection_session?,
      projection_worker?,
      bootstrap_mode?,
      session_ref=current_session,
      raw_preview_runtime?,
    ) catch {
      Failure::Failure(_) as failure => {
        raw_input_coordinator.cancel_pending()
        block_input_coordinator.cancel_pending()
        let (next, command) = recover_after_parser_failure(
          current_session,
          model,
          failure,
          emit,
          projection_session?,
        )
        raw_input_coordinator.set_fast_source(next.document.source())
        publish(next, Some(raw_input_coordinator), None)
        (next, command)
      }
      @markdown.MarkdownEditorError::Committed(..) as committed => {
        raw_input_coordinator.cancel_pending()
        block_input_coordinator.cancel_pending()
        let (next, command) = recover_after_parser_failure(
          current_session,
          model,
          committed,
          emit,
          projection_session?,
        )
        raw_input_coordinator.set_fast_source(next.document.source())
        publish(next, Some(raw_input_coordinator), None)
        (next, command)
      }
      error => {
        raw_input_coordinator.cancel_pending()
        block_input_coordinator.cancel_pending()
        let (next, command) = quarantine_outer_error(
          current_session,
          model,
          error,
          projection_session?,
        )
        raw_input_coordinator.set_fast_source(next.document.source())
        publish(next, Some(raw_input_coordinator), None)
        (next, command)
      }
    }
    let projection_command = match projection_worker {
      Some(runtime) => runtime.sync(next, emit)
      None => @rabbita_runtime.none
    }
    let raw_preview_command = match
      (raw_preview_runtime, raw_input_coordinator.fast_source_value()) {
      (Some(runtime), Some(source)) =>
        if !next.fatal &&
          !next.bootstrap_pending &&
          preview_requested(next) &&
          source != next.document.source() {
          runtime.request(source, emit)
        } else {
          @rabbita_runtime.none
        }
      _ => @rabbita_runtime.none
    }
    (next, @cmd.batch([command, projection_command, raw_preview_command]))
  }
  @rabbita_runtime.new(() => {
    let (model, emit) = @rabbita_runtime.create_state_with_init(
      init=fn(emit) {
        let bootstrap_command = match bootstrap_mode {
          Some(LocalTextBootstrap) =>
            @archive_storage.load(result=loaded => emit(Bootstrap(loaded)))
          Some(FullHistoryOracleBootstrap) =>
            @archive_storage.load_legacy_archive(result=loaded => {
              emit(Bootstrap(loaded))
            })
          None => @rabbita_runtime.none
        }
        let persistence_command = local_archive_write_command(baseline, emit)
        let projection_command = match projection_worker {
          Some(runtime) => runtime.sync(initial, emit)
          None => @rabbita_runtime.none
        }
        (
          initial,
          @cmd.batch([
            bootstrap_command, persistence_command, projection_command,
          ]),
        )
      },
      update~,
      subscriptions=application_subscriptions,
    )
    let active_view = application_view(
      model, emit, raw_input_coordinator, block_input_coordinator,
    )
    model.view2(active_view, (model, active_view) => {
      latest_model.val = Some(model)
      (profile.preview_view)(model, emit, active_view)
    })
  })
}
