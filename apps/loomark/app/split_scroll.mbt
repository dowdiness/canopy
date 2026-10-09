///|
/// Connect already-resolved nodes. The caller schedules sync after rendering
/// and invalidates queued work before invoking the returned disconnect action.
fn connect_split_scroll(
  from : @dom.Element,
  to : @dom.Element,
  schedule_sync : () -> Unit,
) -> (() -> Unit, () -> Unit) {
  let listener : @dom.Listener = _ => schedule_sync()
  from.add_event_listener_with_options("scroll", listener, passive=true)
  (
    () => {
      let next = split_scroll_top(
        from.get_scroll_top(),
        from.get_scroll_height(),
        from.get_client_height(),
        to.get_scroll_top(),
        to.get_scroll_height(),
        to.get_client_height(),
      )
      if next is Some(top) {
        to.set_scroll_top(top)
      }
    },
    () => from.remove_event_listener("scroll", listener),
  )
}
