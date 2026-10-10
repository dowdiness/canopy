///|
const WRITING_FOCUS_LAYER_ID : String = "loomark-writing-focus"

///|
priv suberror WritingFocusSubscription {
  Refresh(@editor.EditorState)
}

///|
priv enum WritingFocusConnection {
  AwaitingRender
  Connected(WritingFocus)
  Removed
}

///|
fn resolve_writing_focus() -> WritingFocus raise {
  let document = @dom.document()
  guard document.get_element_by_id(EDITOR_TEXT_ID).to_option() is Some(element) &&
    element.to_html_text_area_element() is Some(text_area) else {
    raise MissingFocusElement(EDITOR_TEXT_ID)
  }
  guard document.get_element_by_id(WRITING_FOCUS_LAYER_ID).to_option()
    is Some(element) &&
    element.to_html_element() is Some(dimming_layer) else {
    raise MissingFocusElement(WRITING_FOCUS_LAYER_ID)
  }
  add_writing_focus(text_area, dimming_layer)
}

///|
fn writing_focus_subscription(
  activation : Int,
  preview : @editor.EditorState,
) -> @sub.Sub {
  @sub.custom_sub(
    "loomark.writing-focus(\{activation})",
    @sub.Scope::Local,
    WritingFocusSubscription::Refresh(preview),
    (_, scheduler) => {
      let mut connection : WritingFocusConnection = AwaitingRender
      let mut previous_preview = preview
      scheduler.add(
        @cmd.custom_cmd(kind=@cmd.after_render, _ => {
          match connection {
            AwaitingRender => {
              let focus = resolve_writing_focus() catch {
                error => {
                  connection = Removed
                  report_writing_focus_error(@js.any(error))
                  return
                }
              }
              connection = Connected(focus)
            }
            Connected(_) | Removed => ()
          }
        }),
      )
      Some({
        unload: _ => {
          let previous = connection
          connection = Removed
          match previous {
            Connected(focus) => remove_writing_focus(focus)
            AwaitingRender | Removed => ()
          }
        },
        update_tagger: payload => {
          let next = match payload {
            WritingFocusSubscription::Refresh(next) => next
            _ => abort("Unexpected writing-focus subscription payload")
          }
          if next != previous_preview {
            previous_preview = next
            scheduler.add(
              @cmd.custom_cmd(kind=@cmd.after_render, _ => {
                match connection {
                  Connected(focus) => refresh_writing_focus(focus)
                  AwaitingRender | Removed => ()
                }
              }),
            )
          }
        },
      })
    },
  )
}
