///|
fn dom_after_render_result(
  action : () -> Unit raise @dom_boundary.DomBoundaryError,
  on_error? : (@dom_boundary.DomBoundaryError) -> @rabbita.Cmd = fn(_) {
    @rabbita.none
  },
) -> @rabbita.Cmd {
  @rabbita_cmd.custom_cmd(
    fn(scheduler) {
      try {
        action()
      } catch {
        error => scheduler.add(on_error(error))
      }
    },
    kind=@rabbita_cmd.after_render,
  )
}

///|
fn focus_id_after_render(
  id : String,
  on_error? : (@dom_boundary.DomBoundaryError) -> @rabbita.Cmd = fn(_) {
    @rabbita.none
  },
) -> @rabbita.Cmd {
  dom_after_render_result(() => @dom_boundary.focus_id(id), on_error~)
}

///|
fn focus_selector_after_render(
  selector : String,
  on_error? : (@dom_boundary.DomBoundaryError) -> @rabbita.Cmd = fn(_) {
    @rabbita.none
  },
) -> @rabbita.Cmd {
  dom_after_render_result(
    () => @dom_boundary.focus_selector(selector),
    on_error~,
  )
}

///|
fn scroll_selector_after_render(
  selector : String,
  on_error? : (@dom_boundary.DomBoundaryError) -> @rabbita.Cmd = fn(_) {
    @rabbita.none
  },
) -> @rabbita.Cmd {
  dom_after_render_result(
    () => @dom_boundary.scroll_selector(selector),
    on_error~,
  )
}
