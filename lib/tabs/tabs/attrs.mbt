///|
fn bool_attr(value : Bool) -> String {
  if value {
    "true"
  } else {
    "false"
  }
}

///|
/// Attrs for the tablist container element.
pub fn tablist_attrs(label~ : String) -> @html.Attrs {
  @html.Attrs::build().role("tablist").aria_label(label)
}

///|
/// Roving-tabindex and ARIA attrs for the tab button at `index`. `aria-controls`
/// is set only on the selected tab — the other panels are not mounted, so
/// cross-referencing missing ids would mislead assistive tech. The selected
/// panel's `aria-labelledby` still ties it back to its tab button.
fn Model::base_tab_attrs(
  self : Model,
  index : Int,
  panel_id : String,
) -> @html.Attrs {
  let selected = self.is_selected(index)
  let attrs = @html.Attrs::build()
    .id(self.tab_button_id(index))
    .role("tab")
    .aria_selected(bool_attr(selected))
    .tabindex(if selected { 0 } else { -1 })
  if selected {
    attrs.aria_controls(panel_id)
  } else {
    attrs
  }
}

///|
#cfg(target="js")
pub fn Model::tab_attrs(
  self : Model,
  index : Int,
  panel_id~ : String,
  dispatch~ : (Int) -> @rabbita.Cmd,
) -> @html.Attrs {
  self
  .base_tab_attrs(index, panel_id)
  .on_click(_ => dispatch(index))
  .on_keydown(event => {
    match self.nav_target(event.key()) {
      Some(target) => {
        event.prevent_default()
        dispatch(target)
      }
      None => @rabbita.none
    }
  })
}

///|
#cfg(not(target="js"))
pub fn Model::tab_attrs(
  self : Model,
  index : Int,
  panel_id~ : String,
  dispatch~ : (Int) -> @rabbita.Cmd,
) -> @html.Attrs {
  ignore(dispatch)
  self.base_tab_attrs(index, panel_id)
}

///|
/// ARIA attrs for the tabpanel at `index`. The panel id is consumer-owned so
/// existing/legacy container ids survive the migration; `aria-labelledby` points
/// back at the behavior-owned tab button id.
pub fn Model::panel_attrs(
  self : Model,
  index : Int,
  panel_id~ : String,
) -> @html.Attrs {
  @html.Attrs::build()
  .id(panel_id)
  .role("tabpanel")
  .aria_labelledby(self.tab_button_id(index))
  .tabindex(0)
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
/// Focus the selected tab button after the next render. Roving tabindex makes
/// inactive tabs unreachable via Tab, so keyboard navigation would otherwise
/// leave focus stranded on the previous (now `tabindex="-1"`) button.
#cfg(target="js")
pub fn Model::focus_cmd(self : Model) -> @rabbita.Cmd {
  if self.tab_count <= 0 {
    @rabbita.none
  } else {
    let id = self.tab_button_id(self.selected)
    @cmd.custom_cmd(_ => focus_element_by_id(id), kind=@cmd.after_render)
  }
}

///|
#cfg(not(target="js"))
pub fn Model::focus_cmd(self : Model) -> @rabbita.Cmd {
  ignore(self)
  @rabbita.none
}
