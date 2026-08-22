// Canvas context-menu Rabbita island.
//
// This app-private island owns context targets, workflow catalog items, and
// action meaning. Graph/source hosts still own the domain mutations.

///|
const CONTEXT_MENU_ROOT_ID : String = "context-menu"

///|
const CANVAS_ROOT_ID : String = "canvas-root"

///|
const CONTEXT_MENU_PANEL_ID : String = "canvas-context-menu-panel"

///|
priv enum CanvasContextTarget {
  Background(insert_at~ : ScreenPoint)
  Edge(EdgeId)
}

///|
priv struct CanvasContextRequest {
  anchor : @context_menu.Point
  target : CanvasContextTarget
}

///|
priv enum CanvasContextAction {
  AddNode(String)
  Arrange
  Disconnect
}

///|
priv struct CanvasContextMenuItem {
  action : CanvasContextAction
  label : String
  description : String
}

///|
priv struct CanvasContextMenuModel {
  handle : Int
  items : Array[CanvasContextMenuItem]
  target : CanvasContextTarget?
  context_menu : @context_menu.Model
  on_change : () -> Unit
  on_source_result : (String) -> Unit
}

///|
priv enum CanvasContextMenuMsg {
  Request(CanvasContextRequest)
  ContextMenu(@context_menu.Msg)
  DismissAfterExternalMutation
}

///|
#cfg(target="js")
let context_menu_dismissers : Map[Int, () -> Unit] = Map([])

///|
fn canvas_context_pointer_state(handle : Int) -> CanvasPointerState {
  { handle, session: Idle }
}

///|
fn canvas_context_edge_description(handle : Int, edge_id : EdgeId) -> String {
  let state = match canvas_backing(handle) {
    Some(backing) => backing.state()
    None => empty_source_canvas_state()
  }
  match state.edges.search_by(fn(edge) { edge.id == edge_id }) {
    Some(index) => {
      let edge = state.edges[index]
      edge.source.to_string() +
      "." +
      edge.source_port +
      " → " +
      edge.target.to_string() +
      "." +
      edge.target_port
    }
    None => "Disconnect edge"
  }
}

///|
fn canvas_context_menu_items(
  model : CanvasContextMenuModel,
  target : CanvasContextTarget,
) -> Array[CanvasContextMenuItem] {
  match target {
    Background(_) => {
      let items = workflow_node_catalog().map(fn(item) {
        {
          action: AddNode(item.key),
          label: item.label,
          description: item.description,
        }
      })
      let can_arrange = match canvas_backing(model.handle) {
        Some(Runtime(runtime)) =>
          runtime.peek_selection().selected_nodes.length() >= 2
        _ => false
      }
      if can_arrange {
        items.insert(0, {
          action: Arrange,
          label: "Arrange compactly",
          description: "Pack the selection into a compact strip",
        })
      }
      items
    }
    Edge(edge_id) =>
      [
        {
          action: Disconnect,
          label: "Disconnect edge",
          description: canvas_context_edge_description(model.handle, edge_id),
        },
      ]
  }
}

///|
fn context_menu_model(
  handle : Int,
  on_change : () -> Unit,
  on_source_result : (String) -> Unit,
) -> CanvasContextMenuModel {
  {
    handle,
    items: [],
    target: None,
    context_menu: @context_menu.Model::new(id=CONTEXT_MENU_PANEL_ID).with_close_focus_id(
      CANVAS_ROOT_ID,
    ),
    on_change,
    on_source_result,
  }
}

///|
fn CanvasContextMenuModel::open_request(
  self : CanvasContextMenuModel,
  request : CanvasContextRequest,
) -> CanvasContextMenuModel? {
  match request.target {
    Background(insert_at~) => {
      let pointer_state = canvas_context_pointer_state(self.handle)
      match canvas_backing(self.handle) {
        Some(Runtime(_)) if canvas_pointer_world_point(pointer_state, insert_at)
          is None => return None
        _ => ()
      }
      canvas_clear_selected_edge(self.handle)
    }
    Edge(edge_id) => canvas_select_edge(self.handle, edge_id)
  }
  let items = canvas_context_menu_items(self, request.target)
  Some({
    ..self,
    items,
    target: Some(request.target),
    context_menu: self.context_menu.open(
      anchor=request.anchor,
      item_count=items.length(),
    ),
  })
}

///|
fn CanvasContextMenuModel::closed(
  self : CanvasContextMenuModel,
) -> CanvasContextMenuModel {
  { ..self, items: [], target: None, context_menu: self.context_menu.close() }
}

///|
fn CanvasContextMenuModel::with_context_menu_msg(
  self : CanvasContextMenuModel,
  msg : @context_menu.Msg,
) -> CanvasContextMenuModel {
  let context_menu = self.context_menu.update(msg)
  if context_menu.is_open() {
    { ..self, context_menu, }
  } else {
    self.closed()
  }
}

///|
fn canvas_context_failure_result(
  handle : Int,
  detail : String,
) -> SourceGraphOperationResultJson {
  match source_graph_by_handle(handle) {
    Some(graph) =>
      source_graph_result_json_for_graph(graph, false, Some(detail))
    None =>
      source_graph_operation_result_json(false, "", [detail], 0, Some(detail))
  }
}

///|
fn canvas_context_insert_unique(handle : Int, kind : String) -> String {
  source_graph_insert_unique(handle, kind, kind) catch {
    Failure::Failure(detail) =>
      canvas_context_failure_result(handle, detail).to_json().stringify()
  }
}

///|
fn canvas_context_apply(
  model : CanvasContextMenuModel,
  target : CanvasContextTarget,
  action : CanvasContextAction,
) -> Unit raise Failure {
  match (target, action) {
    (Background(insert_at~), AddNode(kind)) =>
      match canvas_backing(model.handle) {
        Some(Source(_)) =>
          (model.on_source_result)(
            canvas_context_insert_unique(model.handle, kind),
          )
        Some(Runtime(runtime)) =>
          runtime.add_node(kind, insert_at.x(), insert_at.y())
        None => ()
      }
    (Background(_), Arrange) =>
      match canvas_backing(model.handle) {
        Some(Runtime(runtime)) => runtime.arrange_selection()
        _ => ()
      }
    (Edge(edge_id), Disconnect) =>
      match canvas_backing(model.handle) {
        Some(Source(graph)) => {
          let result = graph.disconnect_edge(edge_id) catch {
            Failure::Failure(detail) =>
              canvas_context_failure_result(model.handle, detail)
          }
          (model.on_source_result)(result.to_json().stringify())
        }
        Some(Runtime(runtime)) => ignore(runtime.disconnect_edge(edge_id))
        None => ()
      }
    _ => ()
  }
  (model.on_change)()
}

///|
fn context_menu_action_cmd(
  model : CanvasContextMenuModel,
  item : CanvasContextMenuItem,
) -> @rabbita.Cmd {
  match model.target {
    None => @rabbita.none
    Some(target) =>
      @rabbita.attempt(
        _ => @rabbita.none,
        () => canvas_context_apply(model, target, item.action),
      )
  }
}

///|
fn context_menu_update(
  _emit : @rabbita.Emit[CanvasContextMenuMsg],
  msg : CanvasContextMenuMsg,
  model : CanvasContextMenuModel,
) -> (@rabbita.Cmd, CanvasContextMenuModel) {
  match msg {
    Request(request) =>
      match model.open_request(request) {
        None => (@rabbita.none, model)
        Some(model) =>
          (
            @rabbita.batch([
              model.context_menu.position_cmd(),
              model.context_menu.focus_cmd(),
              @rabbita.effect(fn() { (model.on_change)() }),
            ]),
            model,
          )
      }
    DismissAfterExternalMutation =>
      (
        if model.context_menu.is_open() {
          model.context_menu.close_focus_cmd()
        } else {
          @rabbita.none
        },
        model.closed(),
      )
    ContextMenu(context_menu_msg) =>
      match context_menu_msg {
        @context_menu.Activate(index) =>
          match model.items.get(index) {
            Some(item) => {
              let cmd = context_menu_action_cmd(model, item)
              let cmd = if context_menu_msg.requests_close_focus() {
                @rabbita.batch([cmd, model.context_menu.close_focus_cmd()])
              } else {
                cmd
              }
              (cmd, model.with_context_menu_msg(context_menu_msg))
            }
            None => (@rabbita.none, model)
          }
        @context_menu.Close | @context_menu.Dismiss(_) => {
          let cmd = if context_menu_msg.requests_close_focus() {
            model.context_menu.close_focus_cmd()
          } else {
            @rabbita.none
          }
          (cmd, model.with_context_menu_msg(context_menu_msg))
        }
        @context_menu.Key(_) => {
          let model = model.with_context_menu_msg(context_menu_msg)
          (@rabbita.none, model)
        }
        @context_menu.FocusNext
        | @context_menu.FocusPrevious
        | @context_menu.FocusFirst
        | @context_menu.FocusLast
        | @context_menu.FocusItem(_) => {
          let model = model.with_context_menu_msg(context_menu_msg)
          let cmd = if context_menu_msg.requests_focus() {
            model.context_menu.focus_cmd()
          } else {
            @rabbita.none
          }
          (cmd, model)
        }
      }
  }
}

///|
fn context_menu_item_view(
  emit : @rabbita.Emit[CanvasContextMenuMsg],
  context_menu : @context_menu.Model,
  index : Int,
  item : CanvasContextMenuItem,
) -> @rabbita.Html {
  @html.button(
    type_="button",
    title=item.description,
    attrs=context_menu.item_attrs(index, msg => emit(ContextMenu(msg))),
    [@html.text(item.label)],
  )
}

///|
fn context_menu_view(
  emit : @rabbita.Emit[CanvasContextMenuMsg],
  model : CanvasContextMenuModel,
) -> @rabbita.Html {
  if !model.context_menu.is_open() {
    return @html.nothing
  }
  let items : Array[@rabbita.Html] = []
  for index, item in model.items {
    items.push(context_menu_item_view(emit, model.context_menu, index, item))
  }
  @html.div(
    attrs=model.context_menu
      .panel_attrs(msg => emit(ContextMenu(msg)))
      .aria_label("Canvas context menu"),
    items,
  )
}

///|
#cfg(target="js")
fn canvas_context_request(
  event : @dom.Event,
  root : @dom.Element,
) -> CanvasContextRequest? {
  let mouse = match event.to_mouse_event() {
    Some(mouse) => mouse
    None => return None
  }
  let client_x = mouse.get_client_x()
  let client_y = mouse.get_client_y()
  guard !client_x.is_nan() && !client_x.is_inf() else { return None }
  guard !client_y.is_nan() && !client_y.is_inf() else { return None }
  let event_root = match event.current_target().to_option() {
    Some(target) =>
      match target.to_element() {
        Some(element) => element
        None => root
      }
    None => root
  }
  let rect = event_root.get_bounding_client_rect()
  let insert_at = ScreenPoint::from_xy(
    x=client_x - rect.get_left(),
    y=client_y - rect.get_top(),
  ) catch {
    @spatial.CoordinateError::NonFinite => return None
  }
  let target = match
    canvas_pointer_hit_from_element(event.target().to_element()) {
    CanvasPointerHit::Edge(edge_id) => CanvasContextTarget::Edge(edge_id)
    _ => CanvasContextTarget::Background(insert_at~)
  }
  let anchor_x = Float::from_double(client_x)
  let anchor_y = Float::from_double(client_y)
  guard !anchor_x.is_nan() && !anchor_x.is_inf() else { return None }
  guard !anchor_y.is_nan() && !anchor_y.is_inf() else { return None }
  Some({ anchor: @context_menu.Point(x=anchor_x, y=anchor_y), target })
}

///|
#cfg(target="js")
priv suberror CanvasContextMenuSub {
  ContextMenuEvent(Int, @rabbita.Emit[CanvasContextMenuMsg])
}

///|
#cfg(target="js")
fn context_menu_event_target() -> @dom.EventTarget {
  @dom.document().get_element_by_id(CANVAS_ROOT_ID).unwrap().as_event_target()
}

///|
#cfg(target="js")
fn context_menu_sub_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    CanvasContextMenuSub::ContextMenuEvent(handle, emit) => {
      let tagger = @ref.Ref(emit)
      let root = @dom.document().get_element_by_id(CANVAS_ROOT_ID).unwrap()
      let target = context_menu_event_target()
      let dismiss = () => {
        scheduler.add((tagger.val)(DismissAfterExternalMutation))
      }
      context_menu_dismissers[handle] = dismiss
      let listener : @dom.Listener = event => {
        // Prevent the browser menu synchronously; admission itself is
        // scheduled only after typed coordinates and hit classification exist.
        event.prevent_default()
        match canvas_context_request(event, root) {
          Some(request) => scheduler.add((tagger.val)(Request(request)))
          None => ()
        }
      }
      target.add_event_listener("contextmenu", listener)
      Some({
        unload: _ => {
          target.remove_event_listener("contextmenu", listener)
          context_menu_dismissers.remove(handle)
        },
        update_tagger: next => {
          guard next is CanvasContextMenuSub::ContextMenuEvent(_, new_emit) else {
            return
          }
          tagger.val = new_emit
        },
      })
    }
    _ => None
  }
}

///|
#cfg(target="js")
fn context_menu_subscriptions(
  emit : @rabbita.Emit[CanvasContextMenuMsg],
  model : CanvasContextMenuModel,
) -> @sub.Sub {
  @sub.batch([
    @sub.custom_sub(
      "canvas.context-menu",
      @sub.Scope::Local,
      CanvasContextMenuSub::ContextMenuEvent(model.handle, emit),
      context_menu_sub_loader,
    ),
    model.context_menu.subscriptions(emit.map(msg => ContextMenu(msg))),
  ])
}

///|
#cfg(target="js")
pub fn dismiss_canvas_context_menu(handle : Int) -> Unit {
  match context_menu_dismissers.get(handle) {
    Some(dismiss) => dismiss()
    None => ()
  }
}

///|
#cfg(target="js")
pub fn mount_canvas_context_menu(
  handle : Int,
  on_change : () -> Unit,
  on_source_result : (String) -> Unit,
) -> Unit {
  @rabbita.new(
    @rabbita.cell(
      model=context_menu_model(handle, on_change, on_source_result),
      update=context_menu_update,
      view=context_menu_view,
      subscriptions=context_menu_subscriptions,
    ),
  ).mount(CONTEXT_MENU_ROOT_ID)
}
