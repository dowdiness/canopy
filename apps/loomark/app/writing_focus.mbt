///|
const WRITING_FOCUS_LAYER_ID : String = "loomark-writing-focus"

///|
fn report_browser_error(message : String, error : @js.Any) -> Unit {
  @js.global().get("console").call("error", [@js.any(message), error]) |> ignore
}

///|
priv suberror WritingFocusSubscription {
  Refresh(@editor.EditorState)
}

///|
/// The activation key replaces the text area and its dimming layer. Resolve
/// both after rendering and release the old connection. The session draws the
/// caret in Text and Split, and dims surrounding paragraphs only in Focus Mode.
fn writing_focus_subscription(
  activation : Int,
  focus_mode : Bool,
  preview : @editor.EditorState,
) -> @sub.Sub {
  @sub.custom_sub(
    "loomark.writing-focus(\{activation},\{focus_mode})",
    @sub.Scope::Local,
    WritingFocusSubscription::Refresh(preview),
    (_, scheduler) => {
      let mut previous_preview = preview
      let connection = AfterRender(
        scheduler,
        connection => {
          guard editor_text_area() is Some(text_area) &&
            @dom.document()
            .get_element_by_id(WRITING_FOCUS_LAYER_ID)
            .to_option()
            is Some(layer) &&
            layer.to_html_element() is Some(dimming_layer) else {
            report_browser_error(
              "Loomark rendered no text area and writing-focus layer:",
              @js.any(activation),
            )
            return None
          }
          Some(
            @writing_focus_browser.connect(
              text_area,
              dimming_layer,
              dims=focus_mode,
              on_failure=error => {
                report_browser_error(
                  "Loomark could not update writing focus:", error,
                )
                connection.detach()
              },
            ) catch {
              @js.JsError(error) => {
                report_browser_error(
                  "Loomark could not connect writing focus:", error,
                )
                return None
              }
            },
          )
        },
        release=focus => focus.disconnect(),
      )
      Some({
        unload: _ => connection.detach(),
        update_tagger: payload => {
          guard payload is WritingFocusSubscription::Refresh(next) else {
            abort("Unexpected writing-focus subscription payload")
          }
          if previous_preview != next {
            previous_preview = next
            connection.after_render(scheduler, focus => focus.refresh())
          }
        },
      })
    },
  )
}
