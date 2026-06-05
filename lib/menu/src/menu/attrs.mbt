///|
fn Model::item_id(self : Model, index : Int) -> String {
  self.id + "-item-" + index.to_string()
}

///|
fn Model::is_focused(self : Model, index : Int) -> Bool {
  match self.focused {
    Some(focused) => focused == index
    None => false
  }
}

///|
fn bool_attr(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}

///|
pub fn Model::keydown_msg(self : Model, key : String) -> Msg? {
  match key {
    "ArrowDown" => Some(FocusNext)
    "ArrowUp" => Some(FocusPrevious)
    "Home" => Some(FocusFirst)
    "End" => Some(FocusLast)
    "Escape" => Some(Close)
    "Enter" | " " | "Spacebar" =>
      match self.focused {
        Some(index) => Some(Activate(index))
        None => None
      }
    _ =>
      if self.item_count > 0 && key.length() == 1 {
        Some(Key(key))
      } else {
        None
      }
  }
}

///|
fn Model::base_panel_attrs(self : Model) -> @html.Attrs {
  @html.Attrs::build().id(self.id).role("menu").tabindex(-1)
}

///|
#cfg(target="js")
pub fn Model::panel_attrs(
  self : Model,
  dispatch : (Msg) -> @rabbita.Cmd,
) -> @html.Attrs {
  self
  .base_panel_attrs()
  .on_keydown(event => {
    match self.keydown_msg(event.key()) {
      Some(msg) => {
        event.prevent_default()
        dispatch(msg)
      }
      None => @rabbita.none
    }
  })
}

///|
#cfg(not(target="js"))
pub fn Model::panel_attrs(
  self : Model,
  dispatch : (Msg) -> @rabbita.Cmd,
) -> @html.Attrs {
  ignore(dispatch)
  self.base_panel_attrs()
}

///|
fn Model::base_item_attrs(self : Model, index : Int) -> @html.Attrs {
  let focused = self.is_focused(index)
  @html.Attrs::build()
  .id(self.item_id(index))
  .role("menuitem")
  .tabindex(if focused { 0 } else { -1 })
  .data_set("active", bool_attr(focused))
  .aria_posinset((index + 1).to_string())
  .aria_setsize(self.item_count.to_string())
}

///|
#cfg(target="js")
pub fn Model::item_attrs(
  self : Model,
  index : Int,
  dispatch : (Msg) -> @rabbita.Cmd,
) -> @html.Attrs {
  self
  .base_item_attrs(index)
  .on_click(_ => dispatch(Activate(index)))
  .on_focus(_ => dispatch(FocusItem(index)))
}

///|
#cfg(not(target="js"))
pub fn Model::item_attrs(
  self : Model,
  index : Int,
  dispatch : (Msg) -> @rabbita.Cmd,
) -> @html.Attrs {
  ignore(dispatch)
  self.base_item_attrs(index)
}

///|
pub fn scrim_attrs(on_close : @rabbita.Cmd) -> @html.Attrs {
  @html.Attrs::build().aria_hidden("true").tabindex(-1).on_click(_ => on_close)
}

///|
#cfg(target="js")
extern "js" fn focus_element_by_id(id : String) -> Unit =
  #| (id) => {
  #|   const el = document.getElementById(id);
  #|   if (el && typeof el.focus === "function") {
  #|     el.focus();
  #|   }
  #| }

///|
#cfg(target="js")
pub fn Model::focus_cmd(self : Model) -> @rabbita.Cmd {
  match self.focused {
    Some(index) => {
      let id = self.item_id(index)
      @cmd.custom_cmd(_ => focus_element_by_id(id), kind=@cmd.after_render)
    }
    None => @rabbita.none
  }
}

///|
#cfg(not(target="js"))
pub fn Model::focus_cmd(self : Model) -> @rabbita.Cmd {
  ignore(self)
  @rabbita.none
}
