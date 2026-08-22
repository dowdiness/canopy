///|
/// The one pointer owner for the workflow canvas root. This is deliberately
/// app-private: it coordinates the two existing graph hosts without becoming a
/// reusable canvas event algebra.
priv enum CanvasPointerSession {
  Idle
  GraphGesture(pointer_id~ : Int, down_node_id~ : String, additive~ : Bool)
  SourceConnection(
    pointer_id~ : Int,
    source_node_id~ : String,
    source_port_id~ : String,
    cursor~ : @spatial.WorldPoint
  )
} derive(Eq)

///|
priv struct CanvasPointerState {
  handle : Int
  session : CanvasPointerSession
} derive(Eq)

///|
priv enum CanvasPointerHit {
  Background
  Edge(EdgeId)
  Node(String)
  Handle(node_id~ : String, side~ : CanvasHandleSide, port_id~ : String)
}

///|
priv enum CanvasHandleSide {
  Input
  Output
}

///|
priv struct CanvasPointerInput {
  event : @dom.PointerEvent
  root : @dom.Element
  screen : ScreenPoint?
  hit : CanvasPointerHit
}

///|
priv struct CanvasWheelInput {
  delta_y : Double
  delta_mode : Int
  ctrl_key : Bool
  screen : ScreenPoint?
}

///|
priv enum CanvasPointerMsg {
  PointerDown(CanvasPointerInput)
  PointerMove(CanvasPointerInput)
  PointerUp(CanvasPointerInput)
  PointerCancel(CanvasPointerInput)
  PointerLeave
  LostPointerCapture(CanvasPointerInput)
  Wheel(CanvasWheelInput)
  Click(CanvasPointerHit)
}

///|
#cfg(target="js")
priv suberror CanvasPointerSubscription {
  Event(String, @rabbita.Emit[CanvasPointerMsg])
}

///|
#cfg(target="js")
extern "js" fn canvas_pointer_is_mac_like() -> Bool = "() => /Mac|iPhone|iPad|iPod/.test(navigator.platform)"

///|
fn canvas_pointer_root() -> @dom.Element {
  @dom.document().get_element_by_id("canvas-root").unwrap()
}

///|
fn canvas_pointer_input(
  event : @dom.PointerEvent,
  root : @dom.Element,
) -> CanvasPointerInput {
  {
    event,
    root,
    screen: canvas_pointer_screen_point(event),
    hit: canvas_pointer_hit(event),
  }
}

///|
fn canvas_pointer_current_target(event : @dom.PointerEvent) -> @dom.Element? {
  match event.current_target().to_option() {
    Some(target) => target.to_element()
    None => None
  }
}

///|
fn canvas_pointer_screen_point(event : @dom.PointerEvent) -> ScreenPoint? {
  match canvas_pointer_current_target(event) {
    None => None
    Some(root) => {
      let rect = root.get_bounding_client_rect()
      let point = ScreenPoint::from_xy(
        x=event.get_client_x() - rect.get_left(),
        y=event.get_client_y() - rect.get_top(),
      ) catch {
        @spatial.CoordinateError::NonFinite => return None
      }
      Some(point)
    }
  }
}

///|
fn canvas_pointer_hit_from_element(element : @dom.Element?) -> CanvasPointerHit {
  match element {
    None => Background
    Some(element) => {
      match element.closest("[data-edge-id]") {
        Some(edge) =>
          match edge.get_attribute("data-edge-id") {
            Some(id) => return Edge(EdgeId(id))
            None => ()
          }
        None => ()
      }
      match element.closest("[data-handle]") {
        Some(handle) => {
          let node_id = handle.get_attribute("data-node-id")
          let port_id = handle.get_attribute("data-port-id")
          let side = handle.get_attribute("data-handle")
          match (node_id, port_id, side) {
            (Some(node_id), Some(port_id), Some("input")) =>
              return Handle(node_id~, side=Input, port_id~)
            (Some(node_id), Some(port_id), Some("output")) =>
              return Handle(node_id~, side=Output, port_id~)
            _ => ()
          }
        }
        None => ()
      }
      match element.closest(".canvas-node") {
        Some(node) =>
          match node.get_attribute("data-node-id") {
            Some(node_id) => Node(node_id)
            None => Background
          }
        None => Background
      }
    }
  }
}

///|
fn canvas_pointer_hit(event : @dom.PointerEvent) -> CanvasPointerHit {
  canvas_pointer_hit_from_element(event.target().to_element())
}

///|
fn canvas_pointer_release_hit(
  root : @dom.Element,
  event : @dom.PointerEvent,
) -> CanvasPointerHit {
  match
    @dom.document().element_from_point(
      event.get_client_x(),
      event.get_client_y(),
    ) {
    Some(element) if root.contains(element.as_node()) =>
      canvas_pointer_hit_from_element(Some(element))
    _ => Background
  }
}

///|
fn canvas_pointer_canvas_state(model : CanvasPointerState) -> CanvasState {
  match canvas_backing(model.handle) {
    Some(backing) => backing.state()
    None => empty_source_canvas_state()
  }
}

///|
fn canvas_pointer_world_point(
  model : CanvasPointerState,
  screen : ScreenPoint,
) -> @spatial.WorldPoint? {
  let world = canvas_pointer_canvas_state(model).viewport.screen_to_world(
    screen,
  ) catch {
    @spatial.CoordinateError::NonFinite => return None
  }
  Some(world)
}

///|
fn canvas_pointer_hit_is_admissible(
  model : CanvasPointerState,
  hit : CanvasPointerHit,
  screen : ScreenPoint,
) -> Bool {
  match hit {
    Node(_) | Handle(side=Output, ..) =>
      canvas_pointer_world_point(model, screen) is Some(_)
    _ => true
  }
}

///|
fn canvas_pointer_set_panning(root : @dom.Element, active : Bool) -> Unit {
  root.set_attribute("class", if active { "panning" } else { "" })
}

///|
fn canvas_pointer_release_capture(root : @dom.Element, pointer_id : Int) -> Unit {
  root.release_pointer_capture(pointer_id) catch {
    @dom.DOMExceptionError(..) => ()
  }
}

///|
fn canvas_pointer_node_id(hit : CanvasPointerHit, fallback : String) -> String {
  match hit {
    Node(node_id) | Handle(node_id~, ..) => node_id
    Background | Edge(_) => fallback
  }
}

///|
fn canvas_pointer_target_port(hit : CanvasPointerHit) -> String {
  match hit {
    Handle(side=Input, port_id~, ..) => port_id
    _ => ""
  }
}

///|
fn canvas_pointer_source_target(
  hit : CanvasPointerHit,
) -> (NodeId, String)? {
  match hit {
    Handle(node_id~, side=Input, port_id~) =>
      Some((NodeId(node_id), port_id))
    _ => None
  }
}

///|
fn canvas_select_edge(handle : Int, edge_id : EdgeId) -> Unit {
  match canvas_backing(handle) {
    Some(backing) => backing.select_edge(edge_id)
    None => ()
  }
}

///|
fn canvas_clear_selected_edge(handle : Int) -> Unit {
  match canvas_backing(handle) {
    Some(backing) => backing.clear_selected_edge()
    None => ()
  }
}

///|
fn canvas_pointer_complete_source_connection(
  model : CanvasPointerState,
  source_node_id : String,
  source_port_id : String,
  hit : CanvasPointerHit,
) -> Unit {
  match canvas_backing(model.handle) {
    Some(Source(graph)) =>
      graph.complete_connection(
        NodeId(source_node_id),
        source_port_id,
        canvas_pointer_source_target(hit),
      )
    _ => ()
  }
}

///|
fn canvas_pointer_start(
  model : CanvasPointerState,
  input : CanvasPointerInput,
  on_change : () -> Unit,
) -> CanvasPointerState {
  let event = input.event
  guard model.session is Idle else { return model }
  guard event.get_button() == 0 else { return model }
  guard !(canvas_pointer_is_mac_like() && event.get_ctrl_key()) else {
    return model
  }
  let screen = match input.screen {
    Some(screen) => screen
    None => return model
  }
  let hit = input.hit
  match hit {
    Edge(_) => {
      on_change()
      return model
    }
    Handle(side=Input, ..) => {
      canvas_clear_selected_edge(model.handle)
      on_change()
      return model
    }
    _ => ()
  }
  guard canvas_pointer_hit_is_admissible(model, hit, screen) else {
    return model
  }
  let root = input.root
  let pointer_id = event.get_pointer_id()
  let additive = event.get_shift_key() ||
    event.get_meta_key() ||
    event.get_ctrl_key()
  let next_session = match (canvas_backing(model.handle), hit) {
    (Some(Source(_)), Handle(node_id~, side=Output, port_id~)) =>
      SourceConnection(
        pointer_id~,
        source_node_id=node_id,
        source_port_id=port_id,
        cursor=match canvas_pointer_world_point(model, screen) {
          Some(point) => point
          None => return model
        },
      )
    (Some(Source(_)), Node(node_id)) =>
      GraphGesture(pointer_id~, down_node_id=node_id, additive~)
    (Some(Source(_)), Background) =>
      GraphGesture(pointer_id~, down_node_id="", additive~)
    (Some(_), Handle(side=Output, ..)) =>
      GraphGesture(pointer_id~, down_node_id="", additive~)
    (Some(_), Node(node_id)) =>
      GraphGesture(pointer_id~, down_node_id=node_id, additive~)
    (Some(_), Background) =>
      GraphGesture(pointer_id~, down_node_id="", additive~)
    (_, Edge(_) | Handle(side=Input, ..)) => return model
    (None, _) => return model
  }
  root.set_pointer_capture(pointer_id) catch {
    @dom.DOMExceptionError(..) => return model
  }
  let admitted = match (canvas_backing(model.handle), hit) {
    (Some(backing), Handle(node_id~, side=Output, port_id~)) =>
      backing.pointer_down_handle(
        NodeId(node_id),
        port_id,
        screen.x(),
        screen.y(),
      )
    (Some(backing), Node(node_id)) =>
      backing.pointer_down(Some(NodeId(node_id)), screen.x(), screen.y())
    (Some(backing), Background) =>
      backing.pointer_down(None, screen.x(), screen.y())
    _ => false
  }
  guard admitted else {
    canvas_pointer_release_capture(root, pointer_id)
    return model
  }
  let next = { ..model, session: next_session }
  canvas_clear_selected_edge(model.handle)
  match hit {
    Background => canvas_pointer_set_panning(root, true)
    _ => ()
  }
  on_change()
  next
}

///|
fn canvas_pointer_move(
  model : CanvasPointerState,
  input : CanvasPointerInput,
  on_change : () -> Unit,
) -> CanvasPointerState {
  let event = input.event
  match model.session {
    Idle => {
      let node_id = match input.hit {
        Node(node_id) | Handle(node_id~, ..) => node_id
        Background | Edge(_) => ""
      }
      match canvas_backing(model.handle) {
        Some(backing) => if backing.hover_node(node_id) { on_change() }
        None => ()
      }
      model
    }
    GraphGesture(pointer_id~, ..) if pointer_id == event.get_pointer_id() =>
      match input.screen {
        None => model
        Some(screen) =>
          match canvas_backing(model.handle) {
            Some(backing) => {
              ignore(backing.hover_node(""))
              backing.pointer_move(screen.x(), screen.y())
              on_change()
              model
            }
            None => model
          }
      }
    SourceConnection(pointer_id~, source_node_id~, source_port_id~, ..) if pointer_id ==
      event.get_pointer_id() =>
      match input.screen {
        None => model
        Some(screen) =>
          match canvas_pointer_world_point(model, screen) {
            None => model
            Some(next_cursor) => {
              match canvas_backing(model.handle) {
                Some(backing) => {
                  backing.pointer_move(screen.x(), screen.y())
                  on_change()
                }
                None => ()
              }
              {
                ..model,
                session: SourceConnection(
                  pointer_id~,
                  source_node_id~,
                  source_port_id~,
                  cursor=next_cursor,
                ),
              }
            }
          }
      }
    _ => model
  }
}

///|
fn canvas_pointer_finish(
  model : CanvasPointerState,
  input : CanvasPointerInput,
  on_change : () -> Unit,
) -> CanvasPointerState {
  let event = input.event
  match model.session {
    Idle => model
    GraphGesture(pointer_id~, down_node_id~, additive~) => {
      if pointer_id != event.get_pointer_id() {
        return model
      }
      let hit = canvas_pointer_release_hit(input.root, event)
      canvas_pointer_set_panning(input.root, false)
      let next = { ..model, session: Idle }
      let node_id = canvas_pointer_node_id(hit, down_node_id)
      let target_port_id = canvas_pointer_target_port(hit)
      match canvas_backing(model.handle) {
        Some(backing) => backing.pointer_up(node_id, target_port_id, additive)
        None => ()
      }
      canvas_pointer_release_capture(input.root, pointer_id)
      on_change()
      next
    }
    SourceConnection(pointer_id~, source_node_id~, source_port_id~, ..) => {
      if pointer_id != event.get_pointer_id() {
        return model
      }
      let hit = canvas_pointer_release_hit(input.root, event)
      canvas_pointer_set_panning(input.root, false)
      let next = { ..model, session: Idle }
      canvas_pointer_complete_source_connection(
        next, source_node_id, source_port_id, hit,
      )
      canvas_pointer_release_capture(input.root, pointer_id)
      on_change()
      next
    }
  }
}

///|
fn canvas_pointer_interrupt(
  model : CanvasPointerState,
  input : CanvasPointerInput,
  on_change : () -> Unit,
) -> CanvasPointerState {
  let event = input.event
  match model.session {
    Idle => model
    GraphGesture(pointer_id~, ..) => {
      if pointer_id != event.get_pointer_id() {
        return model
      }
      canvas_pointer_set_panning(input.root, false)
      let next = { ..model, session: Idle }
      match canvas_backing(model.handle) {
        Some(backing) => backing.pointer_interrupt()
        None => ()
      }
      canvas_pointer_release_capture(input.root, pointer_id)
      on_change()
      next
    }
    SourceConnection(pointer_id~, ..) => {
      if pointer_id != event.get_pointer_id() {
        return model
      }
      canvas_pointer_set_panning(input.root, false)
      let next = { ..model, session: Idle }
      match canvas_backing(model.handle) {
        Some(backing) => backing.pointer_interrupt()
        None => ()
      }
      canvas_pointer_release_capture(input.root, pointer_id)
      on_change()
      next
    }
  }
}

///|
fn canvas_pointer_message(
  event_name : String,
  event : @dom.Event,
  root : @dom.Element,
) -> CanvasPointerMsg? {
  match event_name {
    "wheel" =>
      match event.to_wheel_event() {
        None => None
        Some(wheel) => {
          // Consume synchronously before scheduling the message. Keep this
          // access order for Firefox/macOS wheel-unit compatibility.
          wheel.prevent_default()
          let delta_y = wheel.get_delta_y()
          let delta_mode = wheel.get_delta_mode()
          let ctrl_key = wheel.get_ctrl_key()
          let screen : ScreenPoint? = match wheel.current_target().to_option() {
            None => None
            Some(target) =>
              match target.to_element() {
                None => None
                Some(root) => {
                  let rect = root.get_bounding_client_rect()
                  let point = ScreenPoint::from_xy(
                    x=wheel.get_client_x() - rect.get_left(),
                    y=wheel.get_client_y() - rect.get_top(),
                  ) catch {
                    @spatial.CoordinateError::NonFinite => return None
                  }
                  Some(point)
                }
              }
          }
          Some(Wheel({ delta_y, delta_mode, ctrl_key, screen }))
        }
      }
    "click" =>
      Some(Click(canvas_pointer_hit_from_element(event.target().to_element())))
    "keydown" =>
      match event.to_keyboard_event() {
        None => None
        Some(keyboard) =>
          match keyboard.key() {
            "Enter" | " " | "Spacebar" =>
              match
                canvas_pointer_hit_from_element(keyboard.target().to_element()) {
                Edge(edge_id) => {
                  keyboard.prevent_default()
                  Some(Click(Edge(edge_id)))
                }
                _ => None
              }
            _ => None
          }
      }
    _ =>
      match event.to_pointer_event() {
        None => None
        Some(pointer) => {
          let input = canvas_pointer_input(pointer, root)
          match event_name {
            "pointerdown" => Some(PointerDown(input))
            "pointermove" => Some(PointerMove(input))
            "pointerup" => Some(PointerUp(input))
            "pointercancel" => Some(PointerCancel(input))
            "pointerleave" => Some(PointerLeave)
            "lostpointercapture" => Some(LostPointerCapture(input))
            _ => None
          }
        }
      }
  }
}

///|
#cfg(target="js")
fn canvas_pointer_subscription_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    CanvasPointerSubscription::Event(event_name, emit) => {
      let tagger = @ref.Ref(emit)
      let root = canvas_pointer_root()
      let target = root.as_event_target()
      let listener : @dom.Listener = event => {
        match canvas_pointer_message(event_name, event, root) {
          Some(message) => scheduler.add((tagger.val)(message))
          None => ()
        }
      }
      if event_name == "wheel" {
        target.add_event_listener_with_options(
          event_name,
          listener,
          passive=false,
        )
      } else {
        target.add_event_listener(event_name, listener)
      }
      Some({
        unload: _ => target.remove_event_listener(event_name, listener),
        update_tagger: next => {
          guard next is CanvasPointerSubscription::Event(next_name, new_emit) else {
            return
          }
          guard next_name == event_name else { return }
          tagger.val = new_emit
        },
      })
    }
    _ => None
  }
}

///|
#cfg(target="js")
fn canvas_pointer_subscription(
  event_name : String,
  emit : @rabbita.Emit[CanvasPointerMsg],
) -> @sub.Sub {
  @sub.custom_sub(
    "canvas.pointer." + event_name,
    @sub.Scope::Local,
    CanvasPointerSubscription::Event(event_name, emit),
    @sub.SubLoader(canvas_pointer_subscription_loader),
  )
}

///|
#cfg(target="js")
fn canvas_pointer_subscriptions(
  emit : @rabbita.Emit[CanvasPointerMsg],
) -> @sub.Sub {
  @sub.batch([
    canvas_pointer_subscription("click", emit),
    canvas_pointer_subscription("keydown", emit),
    canvas_pointer_subscription("pointerdown", emit),
    canvas_pointer_subscription("pointermove", emit),
    canvas_pointer_subscription("pointerup", emit),
    canvas_pointer_subscription("pointercancel", emit),
    canvas_pointer_subscription("pointerleave", emit),
    canvas_pointer_subscription("lostpointercapture", emit),
    canvas_pointer_subscription("wheel", emit),
  ])
}

///|
fn canvas_pointer_update(
  model : CanvasPointerState,
  message : CanvasPointerMsg,
  on_change : () -> Unit,
) -> CanvasPointerState {
  match message {
    Click(hit) => {
      match hit {
        Edge(edge_id) => {
          canvas_select_edge(model.handle, edge_id)
          on_change()
        }
        _ => ()
      }
      model
    }
    PointerDown(input) => canvas_pointer_start(model, input, on_change)
    PointerMove(input) => canvas_pointer_move(model, input, on_change)
    PointerUp(input) => canvas_pointer_finish(model, input, on_change)
    PointerCancel(input) => canvas_pointer_interrupt(model, input, on_change)
    LostPointerCapture(input) =>
      canvas_pointer_interrupt(model, input, on_change)
    Wheel(input) => {
      guard model.session is Idle else { return model }
      guard input.screen is Some(screen) else { return model }
      match canvas_backing(model.handle) {
        Some(backing) => {
          backing.zoom(
            input.delta_y,
            input.delta_mode,
            input.ctrl_key,
            screen.x(),
            screen.y(),
          )
          on_change()
          model
        }
        None => model
      }
    }
    PointerLeave => {
      match canvas_backing(model.handle) {
        Some(backing) => if backing.hover_node("") { on_change() }
        None => ()
      }
      model
    }
  }
}

///|
fn canvas_pointer_view(_model : CanvasPointerState) -> @rabbita.Html {
  @html.nothing
}

///|
#cfg(target="js")
pub fn mount_canvas_pointer_session(
  handle : Int,
  on_change : () -> Unit,
) -> Unit {
  @rabbita.new(fn() {
    let (model, _emit) = @rabbita.create_state(
      { handle, session: Idle },
      update=fn(model, message, _emit) {
        (canvas_pointer_update(model, message, on_change), @rabbita.none)
      },
      subscriptions=fn(_model, emit) { canvas_pointer_subscriptions(emit) },
    )
    model.map(canvas_pointer_view)
  }).mount("canvas-pointer-session-root")
}
