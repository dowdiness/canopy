///|
priv enum EventTarget {
  EditorHost
  TextEditor
}

///|
extern "js" fn js_listen_structure_tree_edits(
  callback : (String) -> Unit,
) -> () -> Unit =
  #| (callback) => {
  #|   let active = true;
  #|   let current = null;
  #|   const install = () => {
  #|     if (!active) return;
  #|     const next = document.querySelector('#canopy-editor');
  #|     if (next === current) return;
  #|     if (current) current.setStructureTreeEditCallback(null);
  #|     current = next;
  #|     if (current) {
  #|       const installed = current;
  #|       current.setStructureTreeEditCallback(edit => {
  #|         if (!active || current !== installed) return;
  #|         callback(JSON.stringify(edit));
  #|       });
  #|     }
  #|   };
  #|   install();
  #|   const observer = new MutationObserver(install);
  #|   observer.observe(document.body, { childList: true, subtree: true });
  #|   return () => {
  #|     active = false;
  #|     observer.disconnect();
  #|     if (current) current.setStructureTreeEditCallback(null);
  #|     current = null;
  #|   };
  #| }

///|
priv enum EventName {
  ActionOverlayOpen
  ActionKey
  ExternalCrdtChange
  FileOpened
  LongPress
  NodeSelected
  SyncStatus
}

///|
fn EventTarget::selector(self : EventTarget) -> String {
  match self {
    EditorHost => "#canopy-editor"
    TextEditor => "#canopy-text-editor"
  }
}

///|
fn EventTarget::key(self : EventTarget) -> String {
  match self {
    EditorHost => "editor-host"
    TextEditor => "text-editor"
  }
}

///|
fn EventName::event_type(self : EventName) -> String {
  match self {
    ActionOverlayOpen => "action-overlay-open"
    ActionKey => "action-key"
    ExternalCrdtChange => "external-crdt-changed"
    FileOpened => "file-loaded"
    LongPress => "long-press"
    NodeSelected => "node-selected"
    SyncStatus => "sync-status"
  }
}

///|
fn EventName::key(self : EventName) -> String {
  match self {
    ActionOverlayOpen => "action-overlay-open"
    ActionKey => "action-key"
    ExternalCrdtChange => "external-crdt-changed"
    FileOpened => "file-loaded"
    LongPress => "long-press"
    NodeSelected => "node-selected"
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
      try {
        let subscription = @dom_boundary.listen_custom_event_selector(
          target.selector(),
          event_name.event_type(),
          detail => scheduler.add(current_tagger(detail)),
        )
        Some({
          unload: fn(_) { subscription.dispose() catch { _ => () } },
          update_tagger: fn(payload) {
            guard payload is CustomEvent(_, _, new_tagger) else { return }
            current_tagger = new_tagger
          },
        })
      } catch {
        error => {
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
priv suberror StructureTreeEditSub {
  Listen(Int, @rabbita.Emit[Msg])
}

///|
fn structure_tree_edit_sub_loader(
  payload : Error,
  scheduler : &@rabbita_cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    Listen(generation, tagger) => {
      let mut current_tagger = tagger
      let dispose = js_listen_structure_tree_edits(json => {
        let op = @lambda.parse_tree_edit_op(@json.parse(json)) catch {
          _ => return
        }
        scheduler.add(current_tagger(StructureTreeEdit(generation~, op)))
      })
      Some({
        unload: _ => dispose(),
        update_tagger: payload => {
          guard payload is Listen(_, new_tagger) else { return }
          current_tagger = new_tagger
        },
      })
    }
    _ => None
  }
}

///|
fn structure_tree_edit_subscription(
  generation : Int,
  emit : @rabbita.Emit[Msg],
) -> @sub.Sub {
  @sub.custom_sub(
    "ideal.structure_tree_edit(generation=\{generation})",
    @sub.Scope::Local,
    Listen(generation, emit),
    @sub.SubLoader(structure_tree_edit_sub_loader),
  )
}

///|
fn editor_dom_event_subscriptions(
  emit : @rabbita.Emit[Msg],
  model : Model,
) -> @sub.Sub {
  let structure_events = if model.mode == Structure {
    structure_tree_edit_subscription(model.structure_generation, emit)
  } else {
    @sub.none
  }
  @sub.batch([
    structure_events,
    custom_event_sub(
      EditorHost,
      ActionOverlayOpen,
      emit.map(detail => OpenActionOverlayForNode(event_detail_node_id(detail))),
    ),
    custom_event_sub(
      EditorHost,
      ActionKey,
      emit.map(key => ActionOverlay(OverlayKeyPressed(key))),
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
      NodeSelected,
      emit.map(detail => StructureNodeSelected(event_detail_node_id(detail))),
    ),
    // The host dispatches "file-loaded" on #canopy-text-editor with the chosen
    // file's text as the (plain-string) event detail; deliver it as FileLoaded.
    custom_event_sub(
      TextEditor,
      FileOpened,
      emit.map(content => FileLoaded(content)),
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
