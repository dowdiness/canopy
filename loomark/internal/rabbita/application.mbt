///|
/// Private pre-`MountedApp` application and test-driver seam.
priv enum DriverEvent {
  ReplaceSource(String)
  SelectPreview
  FocusPreview
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
priv suberror DriverSubscription {
  Control(@cmd.Emit[DriverEvent])
  Test(@cmd.Emit[String], @cmd.Emit[DriverEvent])
}

///|
priv struct DriverModel {
  state : @core.ApplicationState
  document : @markdown.MarkdownDocumentSnapshot
  fatal : Bool
  error : String?
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
fn mode_name(mode : @core.ApplicationMode) -> String {
  match mode {
    @core.Raw => "raw"
    @core.Block => "block"
    @core.Preview => "preview"
  }
}

///|
fn publish(model : DriverModel) -> Unit {
  let fields : Map[String, Json] = {
    "source": model.document.source().to_json(),
    "mode": mode_name(model.state.mode()).to_json(),
    "fatal": model.fatal.to_json(),
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
}

///|
fn preview_view(
  model : DriverModel,
  emit : @cmd.Emit[DriverEvent],
) -> @rabbita_runtime.Html {
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
  let preview = @html.pre(
    id="loomark-preview",
    attrs=@html.Attrs::build().data_set(
      "loomark-source",
      model.document.source(),
    ),
    model.document.source(),
  )
  let input = @html.textarea(
    id="loomark-input",
    value=model.document.source(),
    rows=4,
    read_only=true,
    "",
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
    mode,
    preview,
    input,
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
fn driver_event_name(event : DriverEvent) -> String {
  match event {
    ReplaceSource(_) => "source"
    SelectPreview => "select-preview"
    FocusPreview => "focus-preview"
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
  if detail == "select-preview" {
    SelectPreview
  } else if detail == "focus-preview" {
    FocusPreview
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
  match event {
    ReplaceSource(source) => {
      let transition = @core.reduce(
        model.state,
        @core.ApplicationEvent::RequestCanonicalSource(source~),
      )
      let mut next = model
      let mut command = @rabbita_runtime.none
      for decision in transition.decisions() {
        match decision {
          @core.ReplaceCanonicalSource(source) =>
            match
              editor.commit(
                @markdown.MarkdownEditRequest::ReplaceSource(source),
              ) {
              Ok(result) => {
                let snapshot = match result {
                  @markdown.Applied(snapshot) | @markdown.Unchanged(snapshot) =>
                    snapshot
                }
                next = { ..next, state: transition.state(), document: snapshot }
              }
              Err(_) => {
                next = { ..next, error: Some("editor commit failed") }
                command = @rabbita_runtime.none
              }
            }
          @core.SnapshotRejected(_) =>
            next = { ..next, error: Some("snapshot rejected") }
        }
      }
      publish(next)
      (next, command)
    }
    SelectPreview => {
      let transition = @core.reduce(
        model.state,
        @core.ApplicationEvent::SelectMode(mode=@core.Preview),
      )
      let next = { ..model, state: transition.state() }
      publish(next)
      (next, @rabbita_runtime.none)
    }
    FocusPreview => {
      publish(model)
      (
        model,
        after_render(
          scheduler => {
            ignore(scheduler)
            @dom_boundary.focus_id("loomark-focus-target")
          },
          emit,
        ),
      )
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
      let next = { ..model, error: Some(message) }
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
      let next = { ..model, error: Some("invalid driver request: " + message) }
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
    fatal: false,
    error: None,
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
/// Queue the read-only Preview mode transition.
pub fn select_preview() -> Unit {
  dispatch_driver("select-preview")
}

///|
/// Queue the focus operation; the DOM write is AfterRender.
pub fn focus_preview() -> Unit {
  dispatch_driver("focus-preview")
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
