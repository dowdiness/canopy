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
/// Focus the configured close-focus origin after the current render flush.
#cfg(target="js")
pub fn Model::close_focus_cmd(self : Model) -> @rabbita.Cmd {
  match self.close_focus_id {
    Some(id) =>
      @cmd.custom_cmd(_ => focus_element_by_id(id), kind=@cmd.after_render)
    None => @rabbita.none
  }
}

///|
#cfg(not(target="js"))
pub fn Model::close_focus_cmd(self : Model) -> @rabbita.Cmd {
  ignore(self.close_focus_id)
  @rabbita.none
}
