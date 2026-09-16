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
priv struct CanvasContextMenuModel {
  context_menu : @context_menu.Model[CanvasContextMenuItem]
  // Identifies an opening, not an item index. Closing consumes that opening.
  generation : Int
  problem : CanvasContextProblem?
} derive(Eq)

///|
priv struct CanvasContextMenuBinding {
  handle : Int
  on_change : () -> Unit
  on_source_result : (String) -> Unit
}

///|
priv enum CanvasContextNavigation {
  Next
  Previous
  First
  Last
  Item(Int)
}

///|
fn CanvasContextNavigation::message(
  self : CanvasContextNavigation,
) -> @context_menu.Msg {
  match self {
    Next => @context_menu.FocusNext
    Previous => @context_menu.FocusPrevious
    First => @context_menu.FocusFirst
    Last => @context_menu.FocusLast
    Item(index) => @context_menu.FocusItem(index)
  }
}

///|
priv enum CanvasContextMenuIntent {
  Select(CanvasContextOperation)
  Navigate(CanvasContextNavigation)
  UnhandledKey
  Close(restore_focus~ : Bool)
  Reject(CanvasContextProblem)
}

///|
priv enum CanvasContextMenuMsg {
  Request(Result[CanvasContextRequest, CanvasContextProblem])
  Prepared(Int, Result[CanvasContextPreparedMenu, CanvasContextProblem])
  Menu(Int, CanvasContextMenuIntent)
  Completed(Int, CanvasContextOutcome)
  DismissAfterExternalMutation
}

///|
#cfg(target="js")
let context_menu_dismissers : Map[Int, () -> Unit] = Map([])

///|
fn context_menu_model() -> CanvasContextMenuModel {
  {
    context_menu: @context_menu.Model::new(id=CONTEXT_MENU_PANEL_ID).with_close_focus_id(
      CANVAS_ROOT_ID,
    ),
    generation: 0,
    problem: None,
  }
}

///|
fn CanvasContextMenuModel::closed(
  self : CanvasContextMenuModel,
) -> CanvasContextMenuModel {
  {
    context_menu: self.context_menu.close(),
    generation: self.generation + 1,
    problem: None,
  }
}

///|
// Resolve the headless widget's raw index against the emitting render, once.
// The reducer receives the operation itself, never an index into a newer menu.
fn context_menu_message(
  model : CanvasContextMenuModel,
  msg : @context_menu.Msg,
) -> CanvasContextMenuMsg {
  let intent = match msg {
    @context_menu.Activate(index) =>
      match model.context_menu.item(index) {
        Some(item) => Select(item.operation)
        None =>
          Reject(Rejected("This menu item is unavailable. Reopen the menu."))
      }
    @context_menu.Close | @context_menu.Dismiss(_) =>
      Close(restore_focus=msg.requests_close_focus())
    @context_menu.FocusNext => Navigate(Next)
    @context_menu.FocusPrevious => Navigate(Previous)
    @context_menu.FocusFirst => Navigate(First)
    @context_menu.FocusLast => Navigate(Last)
    @context_menu.FocusItem(index) =>
      match model.context_menu.item(index) {
        Some(_) => Navigate(Item(index))
        None =>
          Reject(Rejected("This menu item is unavailable. Reopen the menu."))
      }
    @context_menu.Key(_) => UnhandledKey
  }
  Menu(model.generation, intent)
}

///|
fn context_menu_update(
  binding : CanvasContextMenuBinding,
  model : CanvasContextMenuModel,
  msg : CanvasContextMenuMsg,
  emit : @rabbita.Emit[CanvasContextMenuMsg],
) -> (CanvasContextMenuModel, @rabbita.Cmd) {
  match msg {
    Request(request) =>
      match request {
        Err(problem) => ({ ..model, problem: Some(problem), }, @rabbita.none)
        Ok(request) => {
          let next = model.closed()
          (
            next,
            @rabbita.perform(
              result => emit(Prepared(next.generation, result)),
              () => canvas_context_prepare(binding.handle, request),
            ),
          )
        }
      }
    Prepared(generation, result) => {
      // Preparation may change ephemeral selection, even when another request
      // supersedes its menu before this completion is delivered.
      let notify = match result {
        Ok(_) => @rabbita.effect(() => (binding.on_change)())
        Err(_) => @rabbita.none
      }
      if generation != model.generation {
        return (model, notify)
      }
      match result {
        Err(problem) => ({ ..model, problem: Some(problem), }, notify)
        Ok(prepared) => {
          let context_menu = model.context_menu.open(
            anchor=prepared.anchor,
            items=prepared.items[:],
          )
          (
            { ..model, context_menu, },
            @rabbita.batch([
              notify,
              context_menu.position_cmd(),
              context_menu.focus_cmd(),
            ]),
          )
        }
      }
    }
    Menu(generation, intent) => {
      // A dismissed/superseded render is a cancelled interaction. In particular,
      // a second activation cannot apply the same opening's operation twice.
      if generation != model.generation || !model.context_menu.is_open() {
        return (model, @rabbita.none)
      }
      match intent {
        Select(operation) => {
          let next = model.closed()
          (
            next,
            @rabbita.batch([
              @rabbita.perform(
                result => emit(Completed(next.generation, result)),
                () => canvas_context_execute(operation),
              ),
              model.context_menu.close_focus_cmd(),
            ]),
          )
        }
        Navigate(navigation) => {
          let msg = navigation.message()
          let context_menu = model.context_menu.update(msg)
          (
            { ..model, context_menu, },
            if msg.requests_focus() {
              context_menu.focus_cmd()
            } else {
              @rabbita.none
            },
          )
        }
        UnhandledKey => (model, @rabbita.none)
        Close(restore_focus~) =>
          (
            model.closed(),
            if restore_focus {
              model.context_menu.close_focus_cmd()
            } else {
              @rabbita.none
            },
          )
        Reject(problem) =>
          ({ ..model.closed(), problem: Some(problem), }, @rabbita.none)
      }
    }
    Completed(generation, outcome) => {
      // A committed change must reach the host even if a newer menu is open.
      // Only feedback belongs to the opening that launched the operation.
      let (problem, notify) = match outcome {
        RuntimeApplied => (None, @rabbita.effect(() => (binding.on_change)()))
        SourceApplied(result) =>
          (
            None,
            @rabbita.effect(() => {
              (binding.on_source_result)(ToJson::to_json(result).stringify())
              (binding.on_change)()
            }),
          )
        SourceRejected(result, selection_changed~) =>
          (
            Some(
              Rejected(
                result.message.unwrap_or("The source rejected this operation."),
              ),
            ),
            @rabbita.effect(() => {
              (binding.on_source_result)(ToJson::to_json(result).stringify())
              // on_change invalidates rendering; this is an ephemeral selection
              // change, not a successful source edit (result.applied is false).
              if selection_changed {
                (binding.on_change)()
              }
            }),
          )
        Failed(problem) => (Some(problem), @rabbita.none)
      }
      (
        if generation == model.generation {
          { ..model, problem, }
        } else {
          model
        },
        notify,
      )
    }
    DismissAfterExternalMutation =>
      (
        model.closed(),
        if model.context_menu.is_open() {
          model.context_menu.close_focus_cmd()
        } else {
          @rabbita.none
        },
      )
  }
}

///|
fn context_menu_view(
  emit : @rabbita.Emit[CanvasContextMenuMsg],
  model : CanvasContextMenuModel,
) -> @rabbita.Html {
  let content : Array[@rabbita.Html] = []
  if model.context_menu.is_open() {
    let dispatch = msg => emit(context_menu_message(model, msg))
    let items : Array[@rabbita.Html] = []
    for index, item in model.context_menu.items() {
      items.push(
        @html.button(
          type_="button",
          title=item.description,
          attrs=model.context_menu.item_attrs(index, dispatch),
          [@html.text(item.label)],
        ),
      )
    }
    content.push(
      @html.div(
        attrs=model.context_menu
          .panel_attrs(dispatch)
          .aria_label("Canvas context menu"),
        items,
      ),
    )
  }
  if model.problem is Some(problem) {
    content.push(
      @html.div(
        id="canvas-context-menu-status",
        class="context-menu-status",
        attrs=@status.Error.attrs(),
        @html.text(problem.message()),
      ),
    )
  }
  @html.div(content)
}

///|
#cfg(target="js")
fn canvas_context_request(
  event : @dom.Event,
  root : @dom.Element,
) -> Result[CanvasContextRequest, CanvasContextProblem] {
  let mouse = match event.to_mouse_event() {
    Some(mouse) => mouse
    None => return Err(Rejected("A context menu requires a pointer position."))
  }
  let client_x = mouse.get_client_x()
  let client_y = mouse.get_client_y()
  let anchor_x = Float::from_double(client_x)
  let anchor_y = Float::from_double(client_y)
  guard !anchor_x.is_nan() &&
    !anchor_x.is_inf() &&
    !anchor_y.is_nan() &&
    !anchor_y.is_inf() else {
    return Err(Rejected("The menu position is outside the supported range."))
  }
  let target = match
    canvas_pointer_hit_from_element(event.target().to_element()) {
    CanvasPointerHit::Edge(edge_id) => CanvasContextTarget::Edge(edge_id)
    _ => {
      let rect = root.get_bounding_client_rect()
      let insert_at = ScreenPoint::from_xy(
        x=client_x - rect.get_left(),
        y=client_y - rect.get_top(),
      ) catch {
        @spatial.CoordinateError::NonFinite =>
          return Err(
            Rejected("The canvas position is outside the supported range."),
          )
      }
      CanvasContextTarget::Background(insert_at~)
    }
  }
  Ok({ anchor: @context_menu.Point(x=anchor_x, y=anchor_y), target, })
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
        scheduler.add(
          (tagger.val)(Request(canvas_context_request(event, root))),
        )
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
  handle : Int,
  model : CanvasContextMenuModel,
  emit : @rabbita.Emit[CanvasContextMenuMsg],
) -> @sub.Sub {
  @sub.batch([
    @sub.custom_sub(
      "canvas.context-menu",
      @sub.Scope::Local,
      CanvasContextMenuSub::ContextMenuEvent(handle, emit),
      context_menu_sub_loader,
    ),
    model.context_menu.subscriptions(
      emit.map(msg => context_menu_message(model, msg)),
    ),
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
  let binding : CanvasContextMenuBinding = {
    handle,
    on_change,
    on_source_result,
  }
  @rabbita.new(() => {
    let (model, emit) = @rabbita.create_state(
      context_menu_model(),
      update=(model, msg, emit) => {
        context_menu_update(binding, model, msg, emit)
      },
      subscriptions=(model, emit) => {
        context_menu_subscriptions(handle, model, emit)
      },
    )
    model.map(model => context_menu_view(emit, model))
  }).mount(CONTEXT_MENU_ROOT_ID)
}
