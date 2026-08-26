///|
fn mode_name(mode : EditorMode) -> String {
  match mode {
    Text => "Text"
    Preview => "Preview"
    Split => "Split"
  }
}

///|
fn mode_tab(
  mode : EditorMode,
  selected_mode : EditorMode,
  focused_mode : EditorMode,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  let name = mode_name(mode)
  let selected = mode == selected_mode
  @html.button(
    id=mode_dom_id(mode),
    class=if selected {
      "loomark-mode-tab is-selected"
    } else {
      "loomark-mode-tab"
    },
    title=name,
    type_="button",
    attrs=@html.Attrs::build()
      .role("tab")
      .aria_label(name)
      .aria_selected(if selected { "true" } else { "false" })
      .aria_controls("loomark-editor-panel")
      .tabindex(if mode == focused_mode { 0 } else { -1 }),
    on_click=emit(ModeSelected(mode)),
    @html.span(
      class="loomark-mode-icon loomark-mode-icon--\{name.to_lower()}",
      attrs=@html.Attrs::build().aria_hidden("true"),
      @html.nothing,
    ),
  )
}

///|
fn mode_keydown(
  event : @dom.KeyboardEvent,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Cmd {
  let key = event.key()
  match key {
    "ArrowLeft" | "ArrowRight" | "Enter" | " " => {
      event.prevent_default()
      emit(ModeKeyPressed(key))
    }
    _ => @cmd.none
  }
}

///|
fn mode_bar(
  selected : EditorMode,
  focused : EditorMode,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  @html.header(class="loomark-mode-bar", [
    @html.div(
      class="loomark-mode-tabs",
      attrs=@html.Attrs::build()
        .role("tablist")
        .aria_label("Editor mode")
        .aria_orientation("horizontal")
        .on_keydown(event => mode_keydown(event, emit)),
      [
        mode_tab(Text, selected, focused, emit),
        mode_tab(Preview, selected, focused, emit),
        mode_tab(Split, selected, focused, emit),
      ],
    ),
  ])
}

///|
fn text_area_view(
  emit : @rabbita.Emit[Msg],
  text_area : @text_area.TextArea,
) -> @rabbita.Html {
  @html.textarea(
    rows=24,
    autofocus=true,
    class="loomark-text",
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
    @html.nothing,
  )
}

///|
fn preview_view() -> @rabbita.Html {
  @html.div(
    id="loomark-preview-scroll",
    class="loomark-preview-scroll",
    attrs=@html.Attrs::build()
      .role("region")
      .aria_label("Markdown preview")
      .tabindex(0),
    @html.div(class="loomark-reading-frame", [
      @html.p(
        class="loomark-preview-empty",
        attrs=@html.Attrs::build().role("status"),
        "Nothing to preview",
      ),
    ]),
  )
}

///|
fn save_failure_view(
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
  @html.div(
    class="loomark-save-alert",
    attrs=@html.Attrs::build().role("alert"),
    [
      @html.p("Changes are not saved in this browser." + reason),
      @html.button(on_click=emit(RetrySave), "Retry saving"),
    ],
  )
}

///|
fn view(
  model : Model,
  emit : @rabbita.Emit[Msg],
  editor_panels : @rabbita.Html,
) -> @rabbita.Html {
  @html.div(
    id="loomark-root",
    class="loomark-root",
    attrs=@html.Attrs::build()
      .role("region")
      .aria_label("Loomark Markdown Editor"),
    match model {
      Loading(_) =>
        @html.div(class="loomark-loading", [@html.p("Loading document")])
      Recovery(failure, _) => {
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
        @html.div(class="loomark-recovery", [
          @html.h1("Document recovery"),
          @html.p(message),
        ])
      }
      Editing(editing) =>
        @html.div(class="loomark-editor", [
          mode_bar(editing.mode, editing.focused_mode, emit),
          @html.main_(
            id="loomark-editor-panel",
            class="loomark-editor-panel",
            attrs=@html.Attrs::build()
              .role("tabpanel")
              .aria_label("\{mode_name(editing.mode)} mode"),
            editor_panels,
          ),
          match editing.save {
            Failed(failure) => save_failure_view(failure, emit)
            Saved | Waiting | Saving(_) => @html.nothing
          },
        ])
    },
  )
}
