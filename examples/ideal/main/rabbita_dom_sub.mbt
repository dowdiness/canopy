///|
priv enum EventTarget {
  EditorHost
}

///|
priv enum EventName {
  ActionOverlayOpen
  ActionKey
  ExternalCrdtChange
  LongPress
  SyncStatus
}

///|
fn EventTarget::selector(self : EventTarget) -> String {
  match self {
    EditorHost => "#canopy-editor"
  }
}

///|
fn EventTarget::key(self : EventTarget) -> String {
  match self {
    EditorHost => "editor-host"
  }
}

///|
fn EventName::event_type(self : EventName) -> String {
  match self {
    ActionOverlayOpen => "action-overlay-open"
    ActionKey => "action-key"
    ExternalCrdtChange => "external-crdt-changed"
    LongPress => "long-press"
    SyncStatus => "sync-status"
  }
}

///|
fn EventName::key(self : EventName) -> String {
  match self {
    ActionOverlayOpen => "action-overlay-open"
    ActionKey => "action-key"
    ExternalCrdtChange => "external-crdt-changed"
    LongPress => "long-press"
    SyncStatus => "sync-status"
  }
}

///|
priv suberror DomEventSub {
  CustomEvent(EventTarget, EventName, @rabbita.Emit[String])
}

///|
fn custom_event_sub(
  target : EventTarget,
  event_name : EventName,
  tagger : @rabbita.Emit[String],
) -> @sub.Sub {
  @sub.custom_sub(
    "dom.custom_event(target=\{target.key()},event=\{event_name.key()})",
    @sub.Scope::Local,
    CustomEvent(target, event_name, tagger),
    @sub.SubLoader(dom_event_sub_loader),
  )
}

///|
fn dom_event_sub_loader(
  payload : Error,
  scheduler : &@rabbita_cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    CustomEvent(target, event_name, tagger) => {
      let mut current_tagger = tagger
      let subscription = try? @dom_boundary.listen_custom_event_selector(
        target.selector(),
        event_name.event_type(),
        detail => scheduler.add(current_tagger(detail)),
      )
      match subscription {
        Ok(subscription) =>
          Some({
            unload: fn(_) {
              let _ : Result[Unit, @dom_boundary.DomBoundaryError] = try? subscription.dispose()
            },
            update_tagger: fn(payload) {
              guard payload is CustomEvent(_, _, new_tagger) else { return }
              current_tagger = new_tagger
            },
          })
        Err(error) => {
          js_warn_dom_event_subscription_error(
            dom_event_subscription_error_message(
              target,
              event_name,
              error.message(),
            ),
          )
          None
        }
      }
    }
    _ => None
  }
}

///|
fn dom_event_subscription_error_message(
  target : EventTarget,
  event_name : EventName,
  detail : String,
) -> String {
  "[canopy] failed to install DOM event subscription target=\{target.key()} event=\{event_name.key()}: \{detail}"
}

///|
extern "js" fn js_warn_dom_event_subscription_error(message : String) -> Unit =
  #| (message) => {
  #|   if (typeof console !== "undefined" && typeof console.warn === "function") {
  #|     console.warn(message);
  #|   }
  #| }

///|
fn editor_dom_event_subscriptions(emit : @rabbita.Emit[Msg]) -> @sub.Sub {
  @sub.batch([
    custom_event_sub(
      EditorHost,
      ActionOverlayOpen,
      emit.map(detail => OpenActionOverlayForNode(event_detail_node_id(detail))),
    ),
    custom_event_sub(
      EditorHost,
      ActionKey,
      emit.map(key => ActionKeyPressed(key)),
    ),
    custom_event_sub(
      EditorHost,
      ExternalCrdtChange,
      emit.map(_ => ExternalCrdtChanged),
    ),
    custom_event_sub(
      EditorHost,
      LongPress,
      emit.map(detail => LongPressTriggeredForNode(event_detail_node_id(detail))),
    ),
    custom_event_sub(
      EditorHost,
      SyncStatus,
      emit.map(detail => SyncStatusChanged(event_detail_status(detail))),
    ),
  ])
}

///|
fn event_detail_node_id(detail : String) -> String {
  if detail == "" {
    return ""
  }
  let json = @json.parse(detail) catch { _ => return detail }
  match json {
    Json::Object(m) =>
      match m.get("nodeId") {
        Some(Json::String(node_id)) => node_id
        _ => ""
      }
    Json::String(node_id) => node_id
    _ => detail
  }
}

///|
fn event_detail_status(detail : String) -> String {
  if detail == "" {
    return ""
  }
  let json = @json.parse(detail) catch { _ => return detail }
  match json {
    Json::Object(m) =>
      match m.get("status") {
        Some(Json::String(status)) => status
        _ => ""
      }
    Json::String(status) => status
    _ => detail
  }
}
