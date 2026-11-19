///|
fn after_render(connect : () -> Unit) -> @cmd.Cmd {
  @cmd.custom_cmd(kind=@cmd.after_render, _ => connect())
}

///|
/// Move focus to `#element_id`. The app asks only for elements it renders,
/// so a missing one is a programming error.
fn focus_element(element_id : String) -> Unit {
  guard @dom.document().get_element_by_id(element_id).to_option()
    is Some(element) &&
    element.to_html_element() is Some(target) else {
    abort("#\{element_id} must be rendered before it is focused")
  }
  target.focus()
}

///|
/// Focus `#element_id` once the next render has drawn it.
pub fn focus_after_render(element_id : String) -> @cmd.Cmd {
  after_render(() => focus_element(element_id))
}

///|
/// A connection waits for the render that draws its elements, and is
/// released first when its subscription ends.
priv enum RenderWait {
  Scheduled
  Released
}

///|
priv suberror FocusWhenDrawn {
  FocusWhenDrawn(String, @cmd.Cmd)
}

///|
/// Focus `#element_id` after the next render, then send `focused`. Start it
/// only once the view draws that element, such as a card that waited for a
/// measurement; ending it first cancels the focus.
pub fn focus_when_drawn(element_id : String, focused : @cmd.Cmd) -> @sub.Sub {
  @sub.custom_sub(
    "browser.focus_when_drawn(\{element_id})",
    Local,
    FocusWhenDrawn(element_id, focused),
    (payload, scheduler) => {
      guard payload is FocusWhenDrawn(element_id, tagger) else { return None }
      let mut tagger = tagger
      let mut wait = Scheduled
      scheduler.queue_command(
        after_render(() => {
          guard wait is Scheduled else { return }
          focus_element(element_id)
          scheduler.queue_command(tagger)
        }),
      )
      Some({
        unload: _ => wait = Released,
        update_tagger: payload => {
          if payload is FocusWhenDrawn(_, next) {
            tagger = next
          }
        },
      })
    },
  )
}
