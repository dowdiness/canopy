///|
fn view(
  model : Model,
  emit : @rabbita.Emit[Msg],
  text_area : @text_area.TextArea,
) -> @rabbita.Html {
  @html.div(
    id="loomark-root",
    attrs=@html.Attrs::build()
      .role("region")
      .aria_label("Loomark Markdown Editor"),
    style=[
      "box-sizing:border-box;min-height:100vh;min-height:100dvh;padding:1rem",
    ],
    match model {
      Loading => @html.p("Loading document")
      Recovery(failure) => {
        let message = match failure {
          @browser_storage.OpenFailure::InvalidRecord =>
            "The stored document is invalid and was not overwritten."
          @browser_storage.OpenFailure::StorageUnavailable =>
            "Browser storage is unavailable."
          @browser_storage.OpenFailure::ReadFailed =>
            "Browser storage failed while reading the document."
          @browser_storage.OpenFailure::DocumentIdentityUnavailable =>
            "This browser cannot create a document identity."
        }
        @html.div([@html.h1("Document recovery"), @html.p(message)])
      }
      Editing(editing) =>
        @html.div([
          match editing.save {
            Failed(failure) => {
              let reason = match failure {
                @browser_storage.SaveFailure::StorageUnavailable =>
                  " Browser storage is unavailable."
                @browser_storage.SaveFailure::QuotaExceeded =>
                  " Browser storage is full."
                @browser_storage.SaveFailure::WriteFailed =>
                  " Browser storage failed while writing the document."
              }
              @html.div(attrs=@html.Attrs::build().role("alert"), [
                @html.p("Changes are not saved in this browser." + reason),
                @html.button(on_click=emit(RetrySave), "Retry saving"),
              ])
            }
            Saved | Waiting | Saving(_) => @html.nothing
          },
          @html.textarea(
            rows=24,
            autofocus=true,
            attrs=text_area.attach(
              @html.Attrs::build().aria_label("Text"),
              change => emit(TextChanged(change)),
              composing => {
                if composing {
                  emit(CompositionStarted)
                } else {
                  emit(CompositionEnded)
                }
              },
            ),
            style=[
              "box-sizing:border-box;width:100%;min-height:calc(100dvh - 2rem)",
            ],
            @html.nothing,
          ),
        ])
    },
  )
}
