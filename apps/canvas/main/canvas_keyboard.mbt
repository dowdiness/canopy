///|
priv enum CanvasDeleteTarget {
  Disconnect(EdgeId)
  DeleteNodes(Array[NodeId])
}

///|
priv struct CanvasKeyboardBinding {
  handle : Int
  on_change : () -> Unit
  send_source : (CanvasSourceMessage) -> Unit
  can_mutate : () -> Bool
}

///|
priv enum CanvasKeyboardMsg {
  Delete(CanvasDeleteTarget)
}

///|
fn canvas_delete_target(backing : CanvasBacking) -> CanvasDeleteTarget? {
  let selected_edge = match backing {
    Runtime(runtime) => runtime.selected_edge()
    Source(graph) => graph.selected_edge
  }
  match selected_edge {
    Some(edge) => Some(Disconnect(edge))
    None => {
      let nodes = match backing {
        Runtime(runtime) => runtime.peek_selection().selected_nodes
        Source(graph) => graph.interaction.selected_nodes
      }
      if nodes.length() == 0 {
        None
      } else {
        Some(DeleteNodes(nodes.copy()))
      }
    }
  }
}

///|
fn canvas_delete_key_admitted(
  key : String,
  meta_key : Bool,
  ctrl_key : Bool,
  alt_key : Bool,
  editable_target : Bool,
) -> Bool {
  (key == "Delete" || key == "Backspace") &&
  !meta_key &&
  !ctrl_key &&
  !alt_key &&
  !editable_target
}

///|
fn canvas_keyboard_update(
  binding : CanvasKeyboardBinding,
  target : CanvasDeleteTarget,
) -> Unit {
  if !(binding.can_mutate)() {
    return
  }
  match canvas_backing(binding.handle) {
    Some(Runtime(runtime)) => {
      let changed = match target {
        Disconnect(edge) => runtime.disconnect_edge(edge)
        DeleteNodes(nodes) => {
          runtime.delete_nodes(nodes)
          true
        }
      }
      if changed {
        (binding.on_change)()
      }
    }
    Some(Source(_)) => {
      let request : CanvasSourceMessage = match target {
        Disconnect(edge) => Request(Disconnect(edge), None)
        DeleteNodes(nodes) => Request(DeleteNodes(nodes), None)
      }
      (binding.send_source)(request)
    }
    None => ()
  }
}

///|
#cfg(target="js")
priv suberror CanvasKeyboardSub {
  Keydown(@dom.EventTarget, Int, @rabbita.Emit[CanvasKeyboardMsg], () -> Bool)
}

///|
#cfg(target="js")
fn canvas_keyboard_target_is_editable(target : @dom.EventTarget) -> Bool {
  match target.to_element().bind(element => element.to_html_element()) {
    Some(element) =>
      element.get_is_content_editable() ||
      element.closest("input, textarea, select, [contenteditable='true']")
      is Some(_)
    None => false
  }
}

///|
#cfg(target="js")
fn canvas_keyboard_sub_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    CanvasKeyboardSub::Keydown(target, handle, emit, can_mutate) => {
      let tagger = @ref.Ref(emit)
      let listener : @dom.Listener = event => {
        match event.to_keyboard_event() {
          None => ()
          Some(keyboard) =>
            if can_mutate() &&
              canvas_delete_key_admitted(
                keyboard.key(),
                keyboard.meta_key(),
                keyboard.ctrl_key(),
                keyboard.alt_key(),
                canvas_keyboard_target_is_editable(keyboard.target()),
              ) {
              match canvas_backing(handle).bind(canvas_delete_target) {
                None => ()
                Some(captured) => {
                  keyboard.prevent_default()
                  dismiss_canvas_context_menu(handle)
                  scheduler.add((tagger.val)(Delete(captured)))
                }
              }
            }
        }
      }
      target.add_event_listener("keydown", listener)
      Some({
        unload: _ => target.remove_event_listener("keydown", listener),
        update_tagger: next => {
          guard next is CanvasKeyboardSub::Keydown(_, _, new_emit, _) else {  }
          tagger.val = new_emit
        },
      })
    }
    _ => None
  }
}

///|
#cfg(target="js")
fn canvas_keyboard_subscriptions(
  target : @dom.EventTarget,
  handle : Int,
  emit : @rabbita.Emit[CanvasKeyboardMsg],
  can_mutate : () -> Bool,
) -> @sub.Sub {
  @sub.custom_sub(
    "canvas.keyboard.delete",
    @sub.Scope::Local,
    CanvasKeyboardSub::Keydown(target, handle, emit, can_mutate),
    canvas_keyboard_sub_loader,
  )
}

///|
#cfg(target="js")
fn mount_canvas_keyboard(
  target : @dom.EventTarget,
  handle : Int,
  on_change : () -> Unit,
  send_source : (CanvasSourceMessage) -> Unit,
  can_mutate : () -> Bool,
) -> Unit {
  let binding : CanvasKeyboardBinding = {
    handle,
    on_change,
    send_source,
    can_mutate,
  }
  @rabbita.new(() => {
    let (model, _emit) = @rabbita.create_state(
      (),
      update=(_, msg, _) => {
        match msg {
          Delete(target) =>
            ((), @rabbita.effect(() => canvas_keyboard_update(binding, target)))
        }
      },
      subscriptions=(_, emit) => {
        canvas_keyboard_subscriptions(target, handle, emit, can_mutate)
      },
    )
    model.map(_ => @html.nothing)
  }).mount("canvas-keyboard-root")
}
