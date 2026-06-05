// Canvas context-menu Rabbita island.
//
// TypeScript still owns graph hit-testing and source-backed action execution;
// this cell owns the menu surface, roving focus, keyboard handling, and ARIA
// attrs through `dowdiness/rabbita-menu/menu`.

///|
let context_menu_root_id : String = "context-menu"

///|
let context_menu_panel_id : String = "canvas-context-menu-panel"

///|
let context_menu_show_event : String = "canopy-canvas-context-menu-show"

///|
let context_menu_hide_event : String = "canopy-canvas-context-menu-hide"

///|
priv struct CanvasContextMenuItem {
  key : String
  label : String
  description : String
} derive(@json.FromJson)

///|
priv struct CanvasContextMenuPayload {
  items : Array[CanvasContextMenuItem]
} derive(@json.FromJson)

///|
priv struct CanvasContextMenuModel {
  visible : Bool
  items : Array[CanvasContextMenuItem]
  menu : @menu.Model
  on_select : (String) -> Unit
  on_close : () -> Unit
}

///|
priv enum CanvasContextMenuMsg {
  Show(String)
  Hide
  Menu(@menu.Msg)
}

///|
fn decode_context_menu_payload(json_text : String) -> CanvasContextMenuPayload? {
  let json = @json.parse(json_text) catch { _ => return None }
  let payload : CanvasContextMenuPayload = @json.from_json(json) catch {
    _ => return None
  }
  Some(payload)
}

///|
fn context_menu_model(
  on_select : (String) -> Unit,
  on_close : () -> Unit,
) -> CanvasContextMenuModel {
  {
    visible: false,
    items: [],
    menu: @menu.Model::new(id=context_menu_panel_id, item_count=0),
    on_select,
    on_close,
  }
}

///|
fn CanvasContextMenuModel::with_items(
  self : CanvasContextMenuModel,
  items : Array[CanvasContextMenuItem],
) -> CanvasContextMenuModel {
  {
    ..self,
    visible: true,
    items,
    menu: self.menu.reset(item_count=items.length()),
  }
}

///|
fn CanvasContextMenuModel::closed(
  self : CanvasContextMenuModel,
) -> CanvasContextMenuModel {
  { ..self, visible: false, items: [], menu: self.menu.reset(item_count=0) }
}

///|
fn context_menu_close_cmd(model : CanvasContextMenuModel) -> @rabbita.Cmd {
  @rabbita.effect(fn() { (model.on_close)() })
}

///|
fn context_menu_select_cmd(
  model : CanvasContextMenuModel,
  key : String,
) -> @rabbita.Cmd {
  @rabbita.effect(fn() {
    (model.on_select)(key)
    (model.on_close)()
  })
}

///|
fn context_menu_update(
  _emit : @rabbita.Emit[CanvasContextMenuMsg],
  msg : CanvasContextMenuMsg,
  model : CanvasContextMenuModel,
) -> (@rabbita.Cmd, CanvasContextMenuModel) {
  match msg {
    Show(json_text) =>
      match decode_context_menu_payload(json_text) {
        Some(payload) => {
          let model = model.with_items(payload.items)
          (model.menu.focus_cmd(), model)
        }
        None => (@rabbita.none, model.closed())
      }
    Hide => (@rabbita.none, model.closed())
    Menu(menu_msg) =>
      match menu_msg {
        @menu.Activate(index) =>
          match model.items.get(index) {
            Some(item) => {
              let cmd = context_menu_select_cmd(model, item.key)
              (cmd, model.closed())
            }
            None => (@rabbita.none, model)
          }
        @menu.Close => (context_menu_close_cmd(model), model.closed())
        @menu.Key(_) => (@rabbita.none, model)
        @menu.FocusNext
        | @menu.FocusPrevious
        | @menu.FocusFirst
        | @menu.FocusLast
        | @menu.FocusItem(_) => {
          let model = { ..model, menu: model.menu.update(menu_msg) }
          let cmd = if menu_msg.requests_focus() {
            model.menu.focus_cmd()
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
  menu : @menu.Model,
  index : Int,
  item : CanvasContextMenuItem,
) -> @rabbita.Html {
  @html.button(
    type_="button",
    title=item.description,
    attrs=menu.item_attrs(index, msg => emit(Menu(msg))),
    [@html.text(item.label)],
  )
}

///|
fn context_menu_view(
  emit : @rabbita.Emit[CanvasContextMenuMsg],
  model : CanvasContextMenuModel,
) -> @rabbita.Html {
  if !model.visible {
    return @html.nothing
  }
  let items : Array[@rabbita.Html] = []
  for index, item in model.items {
    items.push(context_menu_item_view(emit, model.menu, index, item))
  }
  @html.div(
    attrs=model.menu
      .panel_attrs(msg => emit(Menu(msg)))
      .aria_label("Canvas context menu"),
    items,
  )
}

///|
#cfg(target="js")
extern "js" fn context_menu_event_detail(event : @dom.Event) -> String =
  #| (event) => {
  #|   const detail = event && "detail" in event ? event.detail : "";
  #|   return typeof detail === "string" ? detail : "";
  #| }

///|
#cfg(target="js")
priv suberror CanvasContextMenuSub {
  ShowEvent(@rabbita.Emit[CanvasContextMenuMsg])
  HideEvent(@rabbita.Emit[CanvasContextMenuMsg])
}

///|
#cfg(target="js")
fn context_menu_event_target() -> @dom.EventTarget {
  @dom.document()
  .get_element_by_id(context_menu_root_id)
  .unwrap()
  .as_event_target()
}

///|
#cfg(target="js")
fn context_menu_sub_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    CanvasContextMenuSub::ShowEvent(emit) => {
      let tagger = @ref.Ref(emit)
      let target = context_menu_event_target()
      let listener : @dom.Listener = event => {
        scheduler.add((tagger.val)(Show(context_menu_event_detail(event))))
      }
      target.add_event_listener(context_menu_show_event, listener)
      Some({
        unload: _ => {
          target.remove_event_listener(context_menu_show_event, listener)
        },
        update_tagger: next => {
          guard next is CanvasContextMenuSub::ShowEvent(new_emit) else {
            return
          }
          tagger.val = new_emit
        },
      })
    }
    CanvasContextMenuSub::HideEvent(emit) => {
      let tagger = @ref.Ref(emit)
      let target = context_menu_event_target()
      let listener : @dom.Listener = _ => scheduler.add((tagger.val)(Hide))
      target.add_event_listener(context_menu_hide_event, listener)
      Some({
        unload: _ => {
          target.remove_event_listener(context_menu_hide_event, listener)
        },
        update_tagger: next => {
          guard next is CanvasContextMenuSub::HideEvent(new_emit) else {
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
  _model : CanvasContextMenuModel,
) -> @sub.Sub {
  @sub.batch([
    @sub.custom_sub(
      context_menu_show_event,
      @sub.Scope::Local,
      CanvasContextMenuSub::ShowEvent(emit),
      context_menu_sub_loader,
    ),
    @sub.custom_sub(
      context_menu_hide_event,
      @sub.Scope::Local,
      CanvasContextMenuSub::HideEvent(emit),
      context_menu_sub_loader,
    ),
  ])
}

///|
#cfg(target="js")
pub fn mount_canvas_context_menu(
  on_select : (String) -> Unit,
  on_close : () -> Unit,
) -> Unit {
  @rabbita.new(
    @rabbita.cell(
      model=context_menu_model(on_select, on_close),
      update=context_menu_update,
      view=context_menu_view,
      subscriptions=context_menu_subscriptions,
    ),
  ).mount(context_menu_root_id)
}
