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
  problem : CanvasContextProblem?
} derive(Eq)

///|
priv struct CanvasContextMenuBinding {
  handle : Int
  on_change : () -> Unit
  on_source_result : (SourceGraphOperationResultJson) -> Unit
  can_mutate : () -> Bool
}

///|
priv enum CanvasContextMenuMsg {
  Request(Result[CanvasContextRequest, CanvasContextProblem])
  Prepared(Result[CanvasContextPreparedMenu, CanvasContextProblem])
  Select(CanvasContextOperation)
  Menu(@context_menu.Msg)
  Completed(CanvasContextOutcome)
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
    problem: None,
  }
}

///|
fn CanvasContextMenuModel::close(
  self : CanvasContextMenuModel,
) -> CanvasContextMenuModel {
  { context_menu: self.context_menu.close(), problem: None, }
}

///|
// Resolve the headless widget's raw index against the emitting render, once.
// The reducer receives the operation itself, never an index into a newer menu.
fn menu_intent(
  model : CanvasContextMenuModel,
  input : @context_menu.Msg,
) -> CanvasContextMenuMsg {
  match input {
    @context_menu.Activate(index) =>
      match model.context_menu.item(index) {
        Some(item) => Select(item.operation)
        None => Menu(input)
      }
    _ => Menu(input)
  }
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
          let next = model.close()
          (
            next,
            @rabbita.perform(result => emit(Prepared(result)), () => {
              guard (binding.can_mutate)() else {
                return Err(
                  Rejected("The graph parser stopped. Reload to recover."),
                )
              }
              build_context_menu(binding.handle, request)
            }),
          )
        }
      }
    Prepared(result) => {
      let notify = match result {
        Ok(_) => @rabbita.effect(() => (binding.on_change)())
        Err(_) => @rabbita.none
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
    Select(operation) => {
      if !model.context_menu.is_open() {
        return (model, @rabbita.none)
      }
      (
        model.close(),
        @rabbita.batch([
          @rabbita.perform(result => emit(Completed(result)), () => {
            guard (binding.can_mutate)() else {
              return Failed(
                Rejected("The graph parser stopped. Reload to recover."),
              )
            }
            apply_menu_operation(operation)
          }),
          model.context_menu.close_focus_cmd(),
        ]),
      )
    }
    Menu(input) => {
      let context_menu = model.context_menu.update(input)
      (
        { ..model, context_menu, },
        if input.requests_close_focus() {
          model.context_menu.close_focus_cmd()
        } else if input.requests_focus() {
          context_menu.focus_cmd()
        } else {
          @rabbita.none
        },
      )
    }
    Completed(outcome) => {
      let (problem, notify) : (CanvasContextProblem?, @rabbita.Cmd) = match
        outcome {
        RuntimeApplied => (None, @rabbita.effect(() => (binding.on_change)()))
        SourceApplied(result) =>
          (
            None,
            @rabbita.effect(() => {
              (binding.on_source_result)(result)
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
              (binding.on_source_result)(result)
              // on_change invalidates rendering; this is an ephemeral selection
              // change, not a successful source edit (result.applied is false).
              if selection_changed {
                (binding.on_change)()
              }
            }),
          )
        Failed(problem) => (Some(problem), @rabbita.none)
      }
      ({ ..model, problem, }, notify)
    }
    DismissAfterExternalMutation =>
      (
        model.close(),
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
    let dispatch = msg => emit(menu_intent(model, msg))
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
fn parse_menu_request(
  event : @dom.Event,
  canvas_root : @dom.Element,
) -> Result[CanvasContextRequest, CanvasContextProblem] {
  let mouse = match event.to_mouse_event() {
    Some(mouse) => mouse
    None => return Err(Rejected("A context menu requires a pointer position."))
  }
  let client_x = mouse.get_client_x()
  let client_y = mouse.get_client_y()
  let anchor = match context_menu_anchor(client_x, client_y) {
    Some(anchor) => anchor
    None =>
      return Err(Rejected("The menu position is outside the supported range."))
  }
  let target = match
    canvas_pointer_hit_from_element(event.target().to_element()) {
    CanvasPointerHit::Edge(edge_id) => CanvasContextTarget::Edge(edge_id)
    _ => {
      let rect = canvas_root.get_bounding_client_rect()
      let insert_at = match
        canvas_relative_screen_point(
          client_x,
          client_y,
          rect.get_left(),
          rect.get_top(),
        ) {
        Some(point) => point
        None =>
          return Err(
            Rejected("The canvas position is outside the supported range."),
          )
      }
      CanvasContextTarget::Background(insert_at~)
    }
  }
  Ok({ anchor, target, })
}

///|
#cfg(target="js")
priv suberror CanvasContextMenuSub {
  ContextMenuEvent(@dom.Element, Int, @rabbita.Emit[CanvasContextMenuMsg])
}

///|
#cfg(target="js")
fn context_menu_sub_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    CanvasContextMenuSub::ContextMenuEvent(root, handle, emit) => {
      let tagger = @ref.Ref(emit)
      let target = root.as_event_target()
      let dismiss = () => {
        scheduler.add((tagger.val)(DismissAfterExternalMutation))
      }
      context_menu_dismissers[handle] = dismiss
      let listener : @dom.Listener = event => {
        // Prevent the browser menu synchronously; admission itself is
        // scheduled only after typed coordinates and hit classification exist.
        event.prevent_default()
        scheduler.add((tagger.val)(Request(parse_menu_request(event, root))))
      }
      target.add_event_listener("contextmenu", listener)
      Some({
        unload: _ => {
          target.remove_event_listener("contextmenu", listener)
          context_menu_dismissers.remove(handle)
        },
        update_tagger: next => {
          guard next is CanvasContextMenuSub::ContextMenuEvent(_, _, new_emit) else {
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
  root : @dom.Element,
  handle : Int,
  model : CanvasContextMenuModel,
  emit : @rabbita.Emit[CanvasContextMenuMsg],
) -> @sub.Sub {
  @sub.batch([
    @sub.custom_sub(
      "canvas.context-menu",
      @sub.Scope::Local,
      CanvasContextMenuSub::ContextMenuEvent(root, handle, emit),
      context_menu_sub_loader,
    ),
    model.context_menu.subscriptions(emit.map(msg => menu_intent(model, msg))),
  ])
}

///|
#cfg(target="js")
fn dismiss_canvas_context_menu(handle : Int) -> Unit {
  match context_menu_dismissers.get(handle) {
    Some(dismiss) => dismiss()
    None => ()
  }
}

///|
#cfg(target="js")
fn mount_canvas_context_menu(
  root : @dom.Element,
  handle : Int,
  on_change : () -> Unit,
  on_source_result : (SourceGraphOperationResultJson) -> Unit,
  can_mutate : () -> Bool,
) -> Unit {
  let binding : CanvasContextMenuBinding = {
    handle,
    on_change,
    on_source_result,
    can_mutate,
  }
  @rabbita.new(() => {
    let (model, emit) = @rabbita.create_state(
      context_menu_model(),
      update=(model, msg, emit) => {
        context_menu_update(binding, model, msg, emit)
      },
      subscriptions=(model, emit) => {
        context_menu_subscriptions(root, handle, model, emit)
      },
    )
    model.map(model => context_menu_view(emit, model))
  }).mount(CONTEXT_MENU_ROOT_ID)
}
