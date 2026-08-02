///|
/// Private pre-`MountedApp` application and test-driver seam.
priv enum DriverEvent {
  ReplaceSource(String)
  SelectRaw
  SelectPreview
  RawInput(String)
  EditorFailure
  RestoreSnapshot(
    version~ : Int,
    source~ : String,
    mode~ : @core.ApplicationMode
  )
  FocusPreview
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
}

///|
/// Versioned errors owned by the private focus-token codec.
priv enum FocusTokenError {
  Malformed
  UnsupportedVersion(Int)
  Ambiguous
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
  source_revision : Int
  fatal : Bool
  error : String?
  error_code : String?
  error_operation : String?
  error_count : Int
  committed_change_count : Int
  fail_next_editor_commit : Bool
  /// Rendering epoch used only to remount Raw after a rejected commit.
  raw_surface_revision : Int
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
} derive(Eq)

///|
/// The private harness has exactly one mount per page/process. This is a
/// bounded test seam, not a reusable handle registry or lifecycle API.
let mounted : @ref.Ref[Bool] = { val: false }

///|
let detached_snapshot : @ref.Ref[String] = { val: "{}" }

///|
/// Latest committed model for deferred browser effects in this private shell.
let detached_model : @ref.Ref[DriverModel?] = { val: None }

///|
/// Detached logical focus state for the private driver only.
let detached_focus_token : @ref.Ref[String] = { val: "" }

///|
/// Focus tokens have a private wire version independent from snapshots.
const FOCUS_TOKEN_VERSION : Int = 1

///|
fn mode_name(mode : @core.ApplicationMode) -> String {
  match mode {
    @core.Raw => "raw"
    @core.Block => "block"
    @core.Preview => "preview"
  }
}

///|
/// The private driver maps a pure focus target to one mounted control.
fn focus_target_id(target : @core.FocusTarget) -> String {
  match target {
    @core.RawEditor => "loomark-input"
    @core.PreviewControl => "loomark-focus-target"
  }
}

///|
fn focus_target_name(target : @core.FocusTarget) -> String {
  match target {
    @core.RawEditor => "raw"
    @core.PreviewControl => "preview"
  }
}

///|
/// Serialize a known focus target and revision at the private shell boundary.
fn encode_focus_token(
  target : @core.FocusTarget,
  source_revision : Int,
) -> String {
  "v" +
  FOCUS_TOKEN_VERSION.to_string() +
  "|" +
  focus_target_name(target) +
  "|" +
  source_revision.to_string()
}

///|
/// Decode a token exactly once before handing its typed locator to the core.
fn decode_focus_token(
  token : String,
) -> Result[@core.FocusLocator, FocusTokenError] {
  let parts = token.split("|").to_array()
  guard parts.length() == 3 else { return Err(FocusTokenError::Malformed) }
  guard parts[0].has_prefix("v") else { return Err(FocusTokenError::Malformed) }
  let version = @string.parse_int(parts[0][1:], base=10) catch {
    _ => return Err(FocusTokenError::Malformed)
  }
  if version != FOCUS_TOKEN_VERSION {
    return Err(FocusTokenError::UnsupportedVersion(version))
  }
  let target = match parts[1] {
    "raw" => @core.RawEditor
    "preview" => @core.PreviewControl
    _ => return Err(FocusTokenError::Ambiguous)
  }
  let source_revision = @string.parse_int(parts[2], base=10) catch {
    _ => return Err(FocusTokenError::Malformed)
  }
  Ok(@core.FocusLocator(target~, source_revision~))
}

///|
/// Map codec failures to one private-driver error category.
fn focus_token_error(error : FocusTokenError) -> (String, String) {
  match error {
    FocusTokenError::Malformed => ("malformed-focus", "malformed focus token")
    FocusTokenError::UnsupportedVersion(version) =>
      (
        "unsupported-focus-version",
        "unsupported focus token version: " + version.to_string(),
      )
    FocusTokenError::Ambiguous => ("ambiguous-focus", "ambiguous focus target")
  }
}

///|
/// Map pure focus compatibility rejections to one private-driver category.
fn focus_rejection(error : @core.FocusDecisionError) -> (String, String) {
  match error {
    @core.Stale => ("stale-focus", "stale focus token")
    @core.ModeInapplicable =>
      (
        "focus-mode-inapplicable", "focus target is inapplicable in current mode",
      )
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
fn reject_focus(
  model : DriverModel,
  error : @core.FocusDecisionError,
) -> (DriverModel, @cmd.Cmd) {
  let (code, message) = focus_rejection(error)
  let next = record_error(model, code, "browser-effect", message)
  publish(next)
  (next, @rabbita_runtime.none)
}

///|
fn reject_focus_token(
  model : DriverModel,
  error : FocusTokenError,
) -> (DriverModel, @cmd.Cmd) {
  let (code, message) = focus_token_error(error)
  let next = record_error(model, code, "browser-effect", message)
  publish(next)
  (next, @rabbita_runtime.none)
}

///|
/// Keep editor failures categorized without exposing the editor error value.
fn editor_error_detail(error : @markdown.MarkdownEditorError) -> String {
  match error {
    @markdown.InvalidAgentId => "invalid-agent-id"
    @markdown.InitializationFailed(detail~) => detail
    @markdown.ProjectionUnavailable => "projection-unavailable"
    @markdown.InvalidTextRange(..) => "invalid text range"
    @markdown.EditFailed(detail~) => detail
  }
}

///|
/// Commit one canonical source request and install state only after success.
fn commit_source(
  editor : @markdown.MarkdownEditor,
  model : DriverModel,
  state : @core.ApplicationState,
  source : String,
  operation : String,
) -> (DriverModel, Bool) {
  let fail_commit = model.fail_next_editor_commit
  let next = { ..model, fail_next_editor_commit: false }
  let request = if fail_commit {
    @markdown.MarkdownEditRequest::ReplaceText(
      start=-1,
      delete_len=0,
      inserted="",
    )
  } else {
    @markdown.MarkdownEditRequest::ReplaceSource(source)
  }
  match editor.commit(request) {
    Ok(@markdown.Applied(document)) =>
      (
        {
          ..next,
          state,
          document,
          source_revision: model.source_revision + 1,
          committed_change_count: model.committed_change_count + 1,
        },
        true,
      )
    Ok(@markdown.Unchanged(document)) => ({ ..next, state, document }, true)
    Err(error) => {
      let failed = record_error(
        next,
        "editor-commit-failed",
        operation,
        "editor commit failed: " + editor_error_detail(error),
      )
      (
        { ..failed, raw_surface_revision: model.raw_surface_revision + 1 },
        false,
      )
    }
  }
}

///|
fn publish(model : DriverModel) -> Unit {
  let fields : Map[String, Json] = {
    "source": model.document.source().to_json(),
    "version": @core.SNAPSHOT_VERSION.to_json(),
    "mode": mode_name(model.state.mode()).to_json(),
    "source_revision": model.source_revision.to_json(),
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
    "resize_count": model.resize_count.to_json(),
    "selection": match model.selection {
      Some(selection) => selection.to_json()
      None => Json::null()
    },
    "measurement": match model.measurement {
      Some(measurement) => measurement.to_json()
      None => Json::null()
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
  detached_model.val = Some(model)
}

///|
fn editor_surface(
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> Map[String, @rabbita_runtime.Html] {
  let source = model.document.source()
  match model.state.mode() {
    @core.Raw =>
      Map([
        (
          "raw|" + model.raw_surface_revision.to_string(),
          @html.textarea(
            id="loomark-input",
            value=source,
            rows=4,
            on_input=emit.map(source => RawInput(source)),
            "",
          ),
        ),
      ])
    @core.Preview =>
      {
        "preview": @html.pre(
          id="loomark-preview",
          attrs=@html.Attrs::build().data_set("loomark-source", source),
          source,
        ),
      }
    @core.Block =>
      {
        "block": @html.pre(
          id="loomark-block",
          attrs=@html.Attrs::build().data_set("loomark-source", source),
          source,
        ),
      }
  }
}

///|
fn preview_view(
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> @rabbita_runtime.Html {
  let raw_button = @html.button(
    id="loomark-mode-raw",
    type_="button",
    on_click=emit(SelectRaw),
    "Raw",
  )
  let preview_button = @html.button(
    id="loomark-mode-preview",
    type_="button",
    on_click=emit(SelectPreview),
    "Preview",
  )
  let focus_button = @html.button(
    id="loomark-focus-target",
    type_="button",
    on_click=emit(FocusPreview),
    "Focus preview",
  )
  let mode = @html.p(
    id="loomark-mode",
    "mode: " + mode_name(model.state.mode()),
  )
  let event_button = @html.button(
    id="loomark-event-target",
    type_="button",
    "Dispatch event",
  )
  let driver_button = @html.button(
    id="loomark-driver-target",
    type_="button",
    hidden=true,
    "Driver",
  )
  let error_text = match model.error {
    Some(error) => "error: " + error
    None => "ready"
  }
  @html.div(id="loomark-root", [
    @html.h1("Loomark"),
    @html.nav(id="loomark-toolbar", [raw_button, preview_button]),
    mode,
    @html.div(id="loomark-surface", editor_surface(model, emit)),
    event_button,
    driver_button,
    focus_button,
    @html.p(id="loomark-error", error_text),
  ])
}

///|
fn after_render(
  action : (&@cmd.Scheduler) -> Unit raise @dom_boundary.DomBoundaryError,
  failed : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  @cmd.custom_cmd(
    scheduler => {
      action(scheduler) catch {
        error => scheduler.add(failed(EffectFailed(error.message())))
      }
    },
    kind=@cmd.AfterRender,
  )
}

///|
/// Revalidate the latest model after rendering, then perform the final DOM
/// write without queuing a state update after it.
fn focus_latest_after_render(
  locator : @core.FocusLocator,
  token : String,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  after_render(
    scheduler => {
      match detached_model.val {
        Some(model) =>
          match
            @core.decide_focus(model.state, model.source_revision, locator) {
            @core.Compatible(target) => {
              let previous_token = detached_focus_token.val
              detached_focus_token.val = token
              @dom_boundary.focus_id(focus_target_id(target)) catch {
                error => {
                  detached_focus_token.val = previous_token
                  scheduler.add(emit(EffectFailed(error.message())))
                }
              }
            }
            @core.Rejected(error) => scheduler.add(emit(FocusRejected(error)))
          }
        None => scheduler.add(emit(EffectFailed("focus model unavailable")))
      }
    },
    emit,
  )
}

///|
fn driver_event_name(event : DriverEvent) -> String {
  match event {
    ReplaceSource(_) => "source"
    SelectRaw => "select-raw"
    SelectPreview => "select-preview"
    RawInput(_) => "raw-input"
    EditorFailure => "editor-failure"
    RestoreSnapshot(..) => "restore-snapshot"
    FocusPreview => "focus-preview"
    FocusRaw => "focus-raw"
    RestoreFocus(_) => "restore-focus"
    FocusRejected(_) => "focus-rejected"
    WriteSelection(..) => "write-selection"
    WriteSelectionFailure => "write-selection-failure"
    MeasurePreview => "measure-preview"
    MeasureFailure => "measure-failure"
    SelectionRead(..) => "selection-read"
    Measured(..) => "measured"
    EffectFailed(_) => "effect-failed"
    CustomEvent(_) => "custom-event"
    ControlInstalled => "control-installed"
    SubscriptionInstalled => "subscription-installed"
    SubscriptionUnloaded => "subscription-unloaded"
    InvalidRequest(_) => "invalid-request"
    StopListening => "stop-listening"
    Fatal(_) => "fatal"
    Resize(_) => "resize"
  }
}

///|
/// Decode the private DOM transport without exposing a mutable application
/// handle to the generated JavaScript boundary.
fn parse_driver_event(detail : String) -> DriverEvent {
  if detail == "select-raw" {
    SelectRaw
  } else if detail == "select-preview" {
    SelectPreview
  } else if detail == "focus-preview" {
    FocusPreview
  } else if detail == "focus-raw" {
    FocusRaw
  } else if detail == "write-selection-failure" {
    WriteSelectionFailure
  } else if detail == "measure-preview" {
    MeasurePreview
  } else if detail == "measure-failure" {
    MeasureFailure
  } else if detail == "stop-listening" {
    StopListening
  } else if detail.has_prefix("source|") {
    ReplaceSource(detail["source|".length():].to_owned())
  } else if detail.has_prefix("raw-input|") {
    RawInput(detail["raw-input|".length():].to_owned())
  } else if detail == "editor-failure" {
    EditorFailure
  } else if detail.has_prefix("restore-focus|") {
    RestoreFocus(detail["restore-focus|".length():].to_owned())
  } else if detail.has_prefix("restore-snapshot|") {
    let payload = detail["restore-snapshot|".length():].to_owned()
    let parsed = @json.parse(payload) catch {
      _ => return InvalidRequest("restore-snapshot")
    }
    match parsed {
      Json::Object(fields) => {
        let version = match fields.get("version") {
          Some(Json::Number(value, ..)) => value.to_int()
          _ => return InvalidRequest("restore-snapshot")
        }
        let source = match fields.get("source") {
          Some(Json::String(value)) => value
          _ => return InvalidRequest("restore-snapshot")
        }
        let mode = match fields.get("mode") {
          Some(Json::String(value)) =>
            match value {
              "raw" => @core.Raw
              "preview" => @core.Preview
              _ => return InvalidRequest("restore-snapshot")
            }
          _ => return InvalidRequest("restore-snapshot")
        }
        RestoreSnapshot(version~, source~, mode~)
      }
      _ => InvalidRequest("restore-snapshot")
    }
  } else if detail.has_prefix("write-selection|") {
    let parts = detail["write-selection|".length():].split("|").to_array()
    guard parts.length() == 2 else { return InvalidRequest("write-selection") }
    let start = @string.parse_int(parts[0], base=10) catch {
      _ => return InvalidRequest("write-selection")
    }
    let end = @string.parse_int(parts[1], base=10) catch {
      _ => return InvalidRequest("write-selection")
    }
    WriteSelection(start~, end~)
  } else if detail.has_prefix("fatal|") {
    Fatal(detail["fatal|".length():].to_owned())
  } else {
    InvalidRequest("unknown")
  }
}

///|
/// Dispatch one request through the mount-owned DOM event target.
fn dispatch_driver(detail : String) -> Unit {
  @dom_boundary.dispatch_custom_event_id(
    "loomark-driver-target",
    "loomark-driver",
    detail~,
  ) catch {
    _ => ()
  }
}

///|
fn update_model(
  editor : @markdown.MarkdownEditor,
  model : DriverModel,
  event : DriverEvent,
  emit : @cmd.Emit[DriverEvent],
) -> (DriverModel, @cmd.Cmd) {
  if model.fatal {
    let next = {
      ..model,
      rejection: Some(
        "operation=" + driver_event_name(event) + ";reason=fatal-state",
      ),
    }
    publish(next)
    return (next, @rabbita_runtime.none)
  }
  if model.state.mode() != @core.Raw && event is RawInput(_) {
    let next = record_error(
      model, "mode-inapplicable", "editor-dispatch", "Raw input is unavailable outside Raw mode",
    )
    publish(next)
    return (next, @rabbita_runtime.none)
  }
  match event {
    ReplaceSource(source) | RawInput(source) => {
      let transition = @core.reduce(
        model.state,
        @core.ApplicationEvent::RequestCanonicalSource(source~),
      )
      let mut next = model
      for decision in transition.decisions() {
        match decision {
          @core.ReplaceCanonicalSource(source) => {
            let (committed, _) = commit_source(
              editor,
              next,
              transition.state(),
              source,
              "editor-dispatch",
            )
            next = committed
          }
          @core.SnapshotRejected(_) =>
            next = record_error(
              next, "invalid-snapshot", "editor-dispatch", "snapshot rejected",
            )
        }
      }
      publish(next)
      (next, @rabbita_runtime.none)
    }
    EditorFailure => {
      let next = { ..model, fail_next_editor_commit: true }
      publish(next)
      (next, @rabbita_runtime.none)
    }
    RestoreSnapshot(version~, source~, mode~) => {
      let snapshot = @core.ApplicationStateSnapshot::ApplicationStateSnapshot(
        version~,
        source~,
        mode~,
      )
      let transition = @core.reduce(
        model.state,
        @core.ApplicationEvent::RestoreSnapshot(
          snapshot~,
          canonical_source=model.document.source(),
        ),
      )
      let mut next = model
      let mut accepted = true
      for decision in transition.decisions() {
        match decision {
          @core.ReplaceCanonicalSource(source) => {
            let (committed, commit_accepted) = commit_source(
              editor,
              next,
              transition.state(),
              source,
              "restore-snapshot",
            )
            next = committed
            accepted = accepted && commit_accepted
          }
          @core.SnapshotRejected(error) => {
            accepted = false
            let message = match error {
              @core.UnsupportedSnapshotVersion(version) =>
                "unsupported snapshot version: " + version.to_string()
            }
            next = record_error(
              next, "unsupported-snapshot-version", "restore-snapshot", message,
            )
          }
        }
      }
      if accepted {
        next = { ..next, state: transition.state() }
      }
      publish(next)
      (next, @rabbita_runtime.none)
    }
    SelectRaw | SelectPreview => {
      let mode = match event {
        SelectRaw => @core.Raw
        SelectPreview => @core.Preview
        _ => @core.Raw
      }
      let transition = @core.reduce(
        model.state,
        @core.ApplicationEvent::SelectMode(mode~),
      )
      let next = { ..model, state: transition.state() }
      publish(next)
      (next, @rabbita_runtime.none)
    }
    FocusRaw | FocusPreview => {
      let target = match event {
        FocusRaw => @core.RawEditor
        FocusPreview => @core.PreviewControl
        _ => @core.PreviewControl
      }
      let locator = @core.FocusLocator(
        target~,
        source_revision=model.source_revision,
      )
      let token = encode_focus_token(target, model.source_revision)
      match @core.decide_focus(model.state, model.source_revision, locator) {
        @core.Compatible(_) => {
          publish(model)
          (model, focus_latest_after_render(locator, token, emit))
        }
        @core.Rejected(error) => reject_focus(model, error)
      }
    }
    FocusRejected(error) => reject_focus(model, error)
    RestoreFocus(token) =>
      match decode_focus_token(token) {
        Ok(locator) =>
          match
            @core.decide_focus(model.state, model.source_revision, locator) {
            @core.Compatible(_) => {
              publish(model)
              (model, focus_latest_after_render(locator, token, emit))
            }
            @core.Rejected(error) => reject_focus(model, error)
          }
        Err(error) => reject_focus_token(model, error)
      }
    WriteSelection(start~, end~) => {
      publish(model)
      (
        model,
        after_render(
          scheduler => {
            let selection = @dom_boundary.TextSelection(
              start,
              end,
              @dom_boundary.NoDirection,
            )
            @dom_boundary.write_text_selection_id("loomark-input", selection)
            let read = @dom_boundary.read_text_selection_id("loomark-input")
            scheduler.add(
              emit(SelectionRead(start=read.start(), end=read.end())),
            )
          },
          emit,
        ),
      )
    }
    WriteSelectionFailure => {
      publish(model)
      (
        model,
        after_render(
          scheduler => {
            ignore(scheduler)
            let selection = @dom_boundary.TextSelection(
              0,
              1,
              @dom_boundary.NoDirection,
            )
            @dom_boundary.write_text_selection_id(
              "loomark-missing-input", selection,
            )
          },
          emit,
        ),
      )
    }
    MeasurePreview => {
      publish(model)
      (
        model,
        after_render(
          scheduler => {
            let measurement = @dom_boundary.measure_element_id(
              "loomark-preview",
            )
            scheduler.add(
              emit(
                Measured(
                  width=measurement.offset_width(),
                  height=measurement.offset_height(),
                ),
              ),
            )
          },
          emit,
        ),
      )
    }
    MeasureFailure => {
      publish(model)
      (
        model,
        after_render(
          scheduler => {
            ignore(scheduler)
            ignore(@dom_boundary.measure_element_id("loomark-missing-preview"))
          },
          emit,
        ),
      )
    }
    SelectionRead(start~, end~) => {
      let next = {
        ..model,
        selection: Some(start.to_string() + ":" + end.to_string()),
      }
      publish(next)
      (next, @rabbita_runtime.none)
    }
    Measured(width~, height~) => {
      let next = {
        ..model,
        measurement: Some(width.to_string() + ":" + height.to_string()),
      }
      publish(next)
      (next, @rabbita_runtime.none)
    }
    EffectFailed(message) => {
      let next = record_error(
        model, "browser-effect-failed", "browser-effect", message,
      )
      publish(next)
      (next, @rabbita_runtime.none)
    }
    CustomEvent(detail) => {
      let next = {
        ..model,
        event_detail: Some(detail),
        event_count: model.event_count + 1,
      }
      publish(next)
      (next, @rabbita_runtime.none)
    }
    ControlInstalled => {
      let next = { ..model, control_ready: true }
      publish(next)
      (next, @rabbita_runtime.none)
    }
    SubscriptionInstalled => {
      let next = { ..model, event_install_count: model.event_install_count + 1 }
      publish(next)
      (next, @rabbita_runtime.none)
    }
    SubscriptionUnloaded => {
      let next = { ..model, event_unload_count: model.event_unload_count + 1 }
      publish(next)
      (next, @rabbita_runtime.none)
    }
    InvalidRequest(message) => {
      let code = if message == "restore-snapshot" {
        "invalid-snapshot"
      } else {
        "invalid-request"
      }
      let next = record_error(
        model,
        code,
        "editor-dispatch",
        "invalid driver request: " + message,
      )
      publish(next)
      (next, @rabbita_runtime.none)
    }
    StopListening => {
      let next = { ..model, listening: false }
      publish(next)
      (next, @rabbita_runtime.none)
    }
    Fatal(message) => {
      let next = { ..model, fatal: true, error: Some(message), rejection: None }
      publish(next)
      (next, @rabbita_runtime.none)
    }
    Resize(viewport) => {
      ignore(viewport)
      let next = { ..model, resize_count: model.resize_count + 1 }
      publish(next)
      (next, @rabbita_runtime.none)
    }
  }
}

///|
fn driver_control_subscription_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    DriverSubscription::Control(emit) => {
      let mut tagger = emit
      let mut disposed = false
      let mut subscription : @dom_boundary.CustomEventSubscription? = None
      let install = _ => {
        guard !disposed && subscription is None else { return }
        subscription = Some(
          @dom_boundary.listen_custom_event_id(
            "loomark-driver-target",
            "loomark-driver",
            detail => {
              guard !disposed else { return }
              scheduler.add(tagger(parse_driver_event(detail)))
            },
          ),
        ) catch {
          _ => None
        }
        match subscription {
          Some(_) => scheduler.add(tagger(ControlInstalled))
          None => ()
        }
      }
      scheduler.run_effect(@cmd.AfterRender, install)
      Some({
        unload: _ => {
          if !disposed {
            disposed = true
            match subscription {
              Some(running) => running.dispose() catch { _ => () }
              None => ()
            }
          }
        },
        update_tagger: payload => {
          guard payload is DriverSubscription::Control(new_emit) else { return }
          guard !disposed else { return }
          tagger = new_emit
        },
      })
    }
    _ => None
  }
}

///|
fn driver_test_subscription_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    DriverSubscription::Test(emit, lifecycle) => {
      let mut tagger = emit
      let mut lifecycle_tagger = lifecycle
      let mut disposed = false
      let mut installed = false
      let mut subscription : @dom_boundary.CustomEventSubscription? = None
      let install = _ => {
        guard !disposed && subscription is None else { return }
        subscription = Some(
          @dom_boundary.listen_custom_event_id(
            "loomark-event-target",
            "loomark-test",
            detail => {
              guard !disposed else { return }
              scheduler.add(tagger(detail))
            },
          ),
        ) catch {
          _ => None
        }
        match subscription {
          Some(_) => {
            installed = true
            scheduler.add(lifecycle_tagger(SubscriptionInstalled))
          }
          None => ()
        }
      }
      scheduler.run_effect(@cmd.AfterRender, install)
      Some({
        unload: scheduler => {
          if !disposed {
            disposed = true
            match subscription {
              Some(running) => {
                running.dispose() catch {
                  _ => ()
                }
                subscription = None
              }
              None => ()
            }
            if installed {
              installed = false
              scheduler.add(lifecycle_tagger(SubscriptionUnloaded))
            }
          }
        },
        update_tagger: payload => {
          guard payload is DriverSubscription::Test(new_emit, new_lifecycle) else {
            return
          }
          guard !disposed else { return }
          tagger = new_emit
          lifecycle_tagger = new_lifecycle
        },
      })
    }
    _ => None
  }
}

///|
fn driver_control_subscription(emit : @cmd.Emit[DriverEvent]) -> @sub.Sub {
  @sub.custom_sub(
    "loomark.driver-control",
    @sub.Local,
    DriverSubscription::Control(emit),
    driver_control_subscription_loader,
  )
}

///|
fn driver_test_subscription(
  emit : @cmd.Emit[DriverEvent],
  source : String,
) -> @sub.Sub {
  @sub.custom_sub(
    "loomark.driver-event",
    @sub.Local,
    DriverSubscription::Test(
      emit.map(detail => CustomEvent(detail + "|" + source)),
      emit,
    ),
    driver_test_subscription_loader,
  )
}

///|
fn subscriptions(
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> @sub.Sub {
  let control = driver_control_subscription(emit)
  if !model.listening || model.fatal {
    control
  } else {
    @sub.batch([
      @sub.on_resize(emit.map(_ => Resize({ width: 0, height: 0 }))),
      driver_test_subscription(emit, model.document.source()),
      control,
    ])
  }
}

///|
/// Mount the private application exactly once into a fresh connected element.
#warnings("-alert_unstable")
pub fn mount(host_id : String, source : String) -> String {
  if mounted.val {
    return "{\"ok\":false,\"error\":\"host-already-mounted\"}"
  }
  let editor = @markdown.MarkdownEditor(agent_id="loomark-dev-host", source~) catch {
    _ => return "{\"ok\":false,\"error\":\"editor-initialization-failed\"}"
  }
  let initial : DriverModel = {
    state: @core.ApplicationState::ApplicationState(@core.Raw),
    document: editor.snapshot(),
    source_revision: 0,
    fatal: false,
    error: None,
    error_code: None,
    error_operation: None,
    error_count: 0,
    committed_change_count: 0,
    fail_next_editor_commit: false,
    raw_surface_revision: 0,
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
  }
  detached_model.val = None
  detached_focus_token.val = ""
  publish(initial)
  let update = (model, event, emit) => update_model(editor, model, event, emit)
  let app = @rabbita_runtime.new(() => {
    let (model, emit) = @rabbita_runtime.create_state(
      initial,
      update~,
      subscriptions~,
    )
    model.map(model => preview_view(model, emit))
  })
  app.mount(host_id)
  mounted.val = true
  "{\"ok\":true}"
}

///|
/// Return an immutable detached snapshot for private browser assertions.
pub fn snapshot() -> String {
  detached_snapshot.val
}

///|
/// Queue a typed source transaction through the Rabbita update loop.
pub fn request_source(source : String) -> Unit {
  dispatch_driver("source|" + source)
}

///|
/// Queue the Raw mode transition through the typed application event.
pub fn select_raw() -> Unit {
  dispatch_driver("select-raw")
}

///|
/// Queue the Preview mode transition through the typed application event.
pub fn select_preview() -> Unit {
  dispatch_driver("select-preview")
}

///|
/// Queue a versioned source/mode snapshot restore through one transaction.
pub fn restore_snapshot(version : Int, source : String, mode : String) -> Unit {
  let payload : Map[String, Json] = {
    "version": version.to_json(),
    "source": source.to_json(),
    "mode": mode.to_json(),
  }
  dispatch_driver("restore-snapshot|" + Json::object(payload).stringify())
}

///|
/// Arm the next real editor transaction to use a failing editor request.
pub fn force_editor_failure() -> Unit {
  dispatch_driver("editor-failure")
}

///|
/// Queue the Preview focus operation; the DOM write is AfterRender.
pub fn focus_preview() -> Unit {
  dispatch_driver("focus-preview")
}

///|
/// Queue the Raw editor focus operation; the DOM write is AfterRender.
pub fn focus_raw() -> Unit {
  dispatch_driver("focus-raw")
}

///|
/// Return the last committed logical focus token, detached from the DOM.
pub fn capture_focus() -> String {
  detached_focus_token.val
}

///|
/// Queue a logical focus restoration through the private driver.
pub fn restore_focus(token : String) -> Unit {
  dispatch_driver("restore-focus|" + token)
}

///|
/// Queue a selection write followed by a read through the DOM boundary.
pub fn write_selection(start : Int, end : Int) -> Unit {
  dispatch_driver(
    "write-selection|" + start.to_string() + "|" + end.to_string(),
  )
}

///|
/// Queue a selection write against a missing element.
pub fn write_selection_failure() -> Unit {
  dispatch_driver("write-selection-failure")
}

///|
/// Queue a detached preview measurement.
pub fn measure_preview() -> Unit {
  dispatch_driver("measure-preview")
}

///|
/// Queue a measurement against a missing element.
pub fn measure_failure() -> Unit {
  dispatch_driver("measure-failure")
}

///|
/// Dispose the custom event subscription through the update loop.
pub fn stop_listening() -> Unit {
  dispatch_driver("stop-listening")
}

///|
/// Queue a fatal driver state for negative-path assertions.
pub fn fail(message : String) -> Unit {
  dispatch_driver("fatal|" + message)
}
