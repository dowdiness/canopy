///|
#cfg(target="js")
extern "js" fn focus_element(element : @dom.Element) -> Unit =
  #| element => {
  #|   if (typeof element.focus === "function") element.focus();
  #| }

///|
/// Focus the configured close-focus origin after the current render flush.
#cfg(target="js")
pub fn[T] Model::close_focus_cmd(self : Model[T]) -> @rabbita.Cmd {
  match self.close_focus_id {
    Some(id) =>
      @cmd.custom_cmd(
        _ => {
          match @dom.document().get_element_by_id(id).to_option() {
            Some(element) if element.get_is_connected() =>
              focus_element(element)
            _ => ()
          }
        },
        kind=@cmd.after_render,
      )
    None => @rabbita.none
  }
}

///|
#cfg(not(target="js"))
pub fn[T] Model::close_focus_cmd(self : Model[T]) -> @rabbita.Cmd {
  ignore(self.close_focus_id)
  @rabbita.none
}
