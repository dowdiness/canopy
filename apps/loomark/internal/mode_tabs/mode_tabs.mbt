///|
extern "js" fn focus_element_by_id(id : String) -> Unit =
  #| (id) => {
  #|   const element = document.getElementById(id);
  #|   if (element && typeof element.focus === "function") element.focus();
  #| }

///|
/// Focus one mode tab after Rabbita patches its roving tabindex.
pub fn focus(id : String) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => focus_element_by_id(id), kind=@cmd.after_render)
}
