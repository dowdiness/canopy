///|
priv struct EditorInput {
  activation : Activation
  show_new_document_hint : Bool
  disabled : Bool
  read_only : Bool
  mode : EditorMode
  preview : @editor.EditorState
  /// Declares Japanese content so assistive technology and typography use it.
  japanese : Bool
} derive(Eq)

///|
priv enum EditorUiEvent {
  InputChanged(Int, @editor.InputEdit)
  CompositionStarted(Int)
  CompositionEnded(Int)
  ScrollClaimed(ScrollPane)
}

///|
fn build_editor_view(
  input : @rabbita.Val[EditorInput?],
  compact : @rabbita.Val[Bool],
  editor : @editor.MarkdownEditor,
  on_event : @rabbita.Emit[EditorUiEvent],
) -> @rabbita.Val[@rabbita.Html] {
  fn editor_panels(
    orientation : @rui.SeparatorOrientation,
  ) -> @rabbita.Val[@rabbita.Html] {
    @rui.resizable_panel_group_with_input(
      id="loomark-editor-panels",
      input~,
      default_size=50,
      min=25,
      max=75,
      orientation~,
      aria_label="Resize editor and preview",
      class="min-h-0 min-w-0 w-full flex-1",
      (scope, input) => {
        match input {
          Some(input) => {
            let split = input.mode == Split
            let text_visible = input.mode != Preview
            let preview_visible = input.mode != Text
            [
              @rui.resizable_panel(
                scope~,
                side=@rui.FirstPanel,
                class="flex min-h-0 min-w-0 overflow-hidden bg-lm-paper",
                attrs=@html.Attrs::build()
                  .id("loomark-text-pane")
                  .hidden(!text_visible)
                  .on_wheel(_ => on_event(ScrollClaimed(TextPane)))
                  .on_pointerdown(_ => on_event(ScrollClaimed(TextPane)))
                  .on_keydown(_ => on_event(ScrollClaimed(TextPane))),
                style=if split {
                  ["overflow:hidden"]
                } else if text_visible {
                  ["display:block;flex:1 1 100%;overflow:hidden"]
                } else {
                  ["display:none;overflow:hidden"]
                },
                text_area_view(
                  on_event,
                  editor,
                  input.activation,
                  japanese=input.japanese,
                  show_new_document_hint=input.show_new_document_hint,
                  disabled=input.disabled,
                  read_only=input.read_only,
                ),
              ),
              @rui.resizable_handle(
                scope~,
                with_handle=true,
                aria_label="Resize editor and preview",
                class="loomark-divider",
                attrs=@html.Attrs::build().hidden(!split),
                style=if split { [] } else { ["display:none"] },
              ),
              @rui.resizable_panel(
                scope~,
                side=@rui.SecondPanel,
                class="flex min-h-0 min-w-0 overflow-hidden bg-lm-paper",
                attrs=content_language(input.japanese)
                  .hidden(!preview_visible)
                  .on_wheel(_ => on_event(ScrollClaimed(PreviewPane)))
                  .on_pointerdown(_ => on_event(ScrollClaimed(PreviewPane)))
                  .on_keydown(_ => on_event(ScrollClaimed(PreviewPane))),
                style=if split {
                  ["overflow:hidden"]
                } else if preview_visible {
                  ["display:block;flex:1 1 100%;overflow:hidden"]
                } else {
                  ["display:none;overflow:hidden"]
                },
                editor.preview_view(input.preview, id="loomark-preview-scroll"),
              ),
            ]
          }
          None => []
        }
      },
    )
  }

  fn wide_editor_panels() -> @rabbita.Val[@rabbita.Html] {
    editor_panels(@rui.Horizontal)
  }

  fn compact_editor_panels() -> @rabbita.Val[@rabbita.Html] {
    editor_panels(@rui.Vertical)
  }

  compact.switch_by(
    compact => {
      if compact {
        compact_editor_panels()
      } else {
        wide_editor_panels()
      }
    },
    by=compact => if compact { "compact" } else { "wide" },
  )
}

///|
fn mode_name(mode : EditorMode) -> String {
  match mode {
    Text => "Text"
    Preview => "Preview"
    Split => "Split"
  }
}

///|
fn mode_dom_id(mode : EditorMode) -> String {
  "loomark-mode-\{mode_name(mode).to_lower()}"
}

///|
fn mode_tab(
  mode : EditorMode,
  selected_mode : EditorMode,
  on_select : @rabbita.Emit[EditorMode],
) -> @rabbita.Html {
  let name = mode_name(mode)
  let icon_class = "pointer-events-none block size-4"
  let icon = match mode {
    Text => @view.text_mode_icon(icon_class)
    Preview => @view.preview_mode_icon(icon_class)
    Split => @view.split_mode_icon(icon_class)
  }
  @rui.tabs_trigger(
    value=name.to_lower(),
    selected=mode == selected_mode,
    controls="loomark-editor-panel",
    id=mode_dom_id(mode),
    on_value_change=@cmd.Emit(_ => on_select(mode)),
    title=name,
    class="loomark-mode-button",
    attrs=@html.Attrs::build().aria_label(name),
    style=[
      "width:2.25rem;height:2.25rem;min-height:2.25rem;flex:none;padding:0",
    ],
    icon,
  )
}

///|
fn mode_content(mode : EditorMode, content : @rabbita.Html) -> @rabbita.Html {
  @rui.tabs_content(
    value=mode_name(mode).to_lower(),
    selected=true,
    labelledby=mode_dom_id(mode),
    id="loomark-editor-panel",
    class="min-h-0 min-w-0 flex-1 flex-col overflow-hidden",
    style=["display:flex"],
    content,
  )
}

///|
fn text_area_view(
  on_event : @rabbita.Emit[EditorUiEvent],
  editor : @editor.MarkdownEditor,
  activation : Activation,
  show_new_document_hint~ : Bool,
  japanese~ : Bool,
  disabled? : Bool,
  read_only? : Bool,
) -> @rabbita.Html {
  @html.div(
    class="loomark-source-frame h-full min-h-0 w-full min-w-0",
    attrs=content_language(japanese)
      .spellcheck(false)
      .data_set(
        "new-document-hint",
        if show_new_document_hint {
          "true"
        } else {
          "false"
        },
      ),
    Map([
      (
        "activation-\{activation.generation}",
        editor.input_view(
          "Text",
          input => on_event(InputChanged(activation.generation, input)),
          composing => {
            if composing {
              on_event(CompositionStarted(activation.generation))
            } else {
              on_event(CompositionEnded(activation.generation))
            }
          },
          disabled?,
          read_only?,
          rows=24,
          // Changing this attribute splits Chromium's native typing undo group.
          placeholder="Start writing…",
          autofocus=true,
          class="loomark-source m-0 block h-full min-h-0 w-full min-w-0 resize-none rounded-none border-0 bg-transparent font-lm-writing text-lm-ink caret-lm-accent outline-0 [tab-size:2]",
        ),
      ),
      (
        "writing-focus",
        @html.div(
          id=@writing_focus_browser.WRITING_FOCUS_LAYER_ID,
          class="loomark-writing-dimming",
          attrs=@html.Attrs::build().aria_hidden("true").inert(true),
          ([] : Array[@rabbita.Html]),
        ),
      ),
    ]),
  )
}

///|
/// The interface stays English; only document content declares Japanese.
fn content_language(japanese : Bool) -> @html.Attrs {
  let attrs = @html.Attrs::build()
  if japanese {
    attrs.lang("ja")
  } else {
    attrs
  }
}
