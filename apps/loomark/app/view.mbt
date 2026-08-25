///|
fn layout_button(
  layout : DisplayLayout,
  label : String,
  selected : Bool,
  prepare_on_intent : Bool,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let attrs = if prepare_on_intent {
    @html.Attrs::build()
    .aria_pressed(selected.to_string())
    .on_mouseenter(_ => emit(PreviewIntent))
    .on_focus(_ => emit(PreviewIntent))
    .on_pointerdown(_ => emit(PreviewIntent))
  } else {
    @html.Attrs::build().aria_pressed(selected.to_string())
  }
  @html.button(
    class="loomark-layout-button",
    type_="button",
    on_click=emit(DisplaySelected(layout)),
    attrs~,
    label,
  )
}

///|
fn layout_controls(
  selected : DisplayLayout,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  @html.div(
    class="loomark-layout-controls",
    attrs=@html.Attrs::build().role("group").aria_label("Display layout"),
    [
      layout_button(Text, "Text", selected == Text, false, emit),
      layout_button(Preview, "Preview", selected == Preview, true, emit),
      layout_button(Split, "Split", selected == Split, true, emit),
    ],
  )
}

///|
fn document_textarea(
  editing : EditingState,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  @html.textarea(
    id=TEXT_SURFACE_ID,
    class="loomark-text",
    rows=24,
    autofocus=editing.initial_text_focus,
    attrs=@html.Attrs::build()
      .aria_label("Text")
      .on_beforeinput(event => {
        emit(BeforeInputCaptured(@text_surface.capture_before_input(event)))
      })
      .on_input(event => {
        let (before, after) = @text_surface.capture_input(event)
        emit(InputCaptured(before, after))
      })
      .on_compositionstart(event => {
        ignore(@text_surface.capture_composition_start(event))
        emit(CompositionStarted)
      })
      .on_compositionend(event => {
        let (started, ended) = @text_surface.capture_composition_end(event)
        emit(CompositionEnded(started, ended))
      }),
    @html.nothing,
  )
}

///|
fn input_metrics(metrics : InputMetrics) -> @rabbita.Html {
  @html.p(
    class="loomark-input-metrics",
    attrs=@html.Attrs::build().aria_live("polite"),
    "Accepted edits: \{metrics.accepted_edits} · Complete value reads: \{metrics.complete_value_reads} · Value-length reads: \{metrics.value_length_reads} · Recoveries: \{metrics.recovery_count} · Complete-source diffs: 0 · Last input: \{metrics.last_input_type} · Last recovery: \{metrics.last_recovery}",
  )
}

///|
fn preview_pane(preview : PreviewState) -> @rabbita.Html {
  let content = match preview.last_completed {
    Some(result) => result.content()
    None if preview.failure is Some(_) => @html.nothing
    None => @html.p(class="loomark-preview-preparing", "Preparing preview…")
  }
  @html.div(
    class="loomark-preview",
    attrs=@html.Attrs::build().role("region").aria_label("Preview result"),
    content,
  )
}

///|
fn editing_surface(
  editing : EditingState,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  match editing.display {
    Text =>
      @html.div(class="loomark-text-layout", document_textarea(editing, emit))
    Preview =>
      @html.div(class="loomark-preview-layout", preview_pane(editing.preview))
    Split =>
      @html.div(class="loomark-split-layout", [
        @html.div(class="loomark-split-pane", document_textarea(editing, emit)),
        @html.div(class="loomark-split-pane", preview_pane(editing.preview)),
      ])
  }
}

///|
fn save_failure(
  failure : @browser_storage.SaveFailure,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let reason = match failure {
    @browser_storage.SaveFailure::StorageUnavailable =>
      " Browser storage is unavailable."
    @browser_storage.SaveFailure::QuotaExceeded => " Browser storage is full."
    @browser_storage.SaveFailure::WriteFailed =>
      " Browser storage failed while writing the document."
  }
  @html.div(attrs=@html.Attrs::build().role("alert"), [
    @html.p("Changes are not saved in this browser." + reason),
    @html.button(on_click=emit(RetrySave), "Retry saving"),
  ])
}

///|
fn view(model : Model, emit : @rabbita.Emit[Msg]) -> @rabbita.Html {
  @html.div(
    id="loomark-root",
    attrs=@html.Attrs::build()
      .role("region")
      .aria_label("Loomark Markdown Editor"),
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
        @html.div(class="loomark-editor", [
          match editing.save {
            Failed(failure) => save_failure(failure, emit)
            Saved | Waiting | Saving(_) => @html.nothing
          },
          match editing.preview.failure {
            Some(failure) =>
              @html.p(
                class="loomark-preview-failure",
                attrs=@html.Attrs::build().role("alert"),
                failure.message(),
              )
            None => @html.nothing
          },
          layout_controls(editing.display, emit),
          input_metrics(editing.metrics),
          editing_surface(editing, emit),
        ])
    },
  )
}
