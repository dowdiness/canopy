///|
/// Split owns the listener and pending write together so changing documents,
/// modes, or scroll direction invalidates both before the next render.
priv suberror SplitScrollSubscription {
  Follow(String, String, @editor.EditorState)
}

///|
fn split_scroll_subscription(
  source : String,
  target : String,
  activation : Int,
  preview : @editor.EditorState,
) -> @sub.Sub {
  @sub.custom_sub(
    "loomark.split-scroll(\{source},\{target},\{activation})",
    @sub.Scope::Local,
    Follow(source, target, preview),
    (payload, scheduler) => {
      guard payload is SplitScrollSubscription::Follow(source, target, preview) else {
        return None
      }
      let mut active = true
      let mut previous_preview = preview
      let document = @dom.document().as_event_target()
      fn sync_after_render() {
        scheduler.add(
          @cmd.custom_cmd(kind=@cmd.after_render, _ => {
            guard active else { return }
            guard @dom.document().get_element_by_id(source).to_option()
              is Some(from) &&
              @dom.document().get_element_by_id(target).to_option() is Some(to) else {
              return
            }
            let source_distance = from.get_scroll_height() -
              from.get_client_height()
            let target_distance = to.get_scroll_height() -
              to.get_client_height()
            if source_distance > 0 && target_distance > 0 {
              let next = from.get_scroll_top() /
                source_distance *
                target_distance
              if (to.get_scroll_top() - next).abs() >= 1.0 {
                to.set_scroll_top(next)
              }
            }
          }),
        )
      }
      let listener : @dom.Listener = event => {
        guard event.target().to_element() is Some(element) &&
          element.get_attribute("id") == Some(source) else {
          return
        }
        sync_after_render()
      }
      document.add_event_listener_with_options(
        "scroll",
        listener,
        capture=true,
        passive=true,
      )
      Some({
        unload: _ => {
          active = false
          document.remove_event_listener_with_options(
            "scroll",
            listener,
            capture=true,
          )
        },
        update_tagger: payload => {
          guard payload is SplitScrollSubscription::Follow(_, _, next) else {
            return
          }
          if previous_preview != next {
            previous_preview = next
            sync_after_render()
          }
        },
      })
    },
  )
}
