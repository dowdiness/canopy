///|
/// A Markdown editing component. The host owns accepted text and the selected
/// mode; this component owns native input and incremental preview work.
pub struct MarkdownEditor {
  priv area : @text_area.TextArea
  priv engine : @preview.PreviewEngine
}

///|
pub fn MarkdownEditor::MarkdownEditor(id : String) -> MarkdownEditor {
  {
    area: @text_area.TextArea::TextArea(id),
    engine: @preview.PreviewEngine::PreviewEngine(),
  }
}

///|
pub struct EditorState {
  priv preview : @preview.State
} derive(Eq)

///|
pub struct EditorEvent {
  priv preview : @preview.Event
}

///|
/// A native input awaiting admission against this editor's current document.
pub struct InputEdit {
  priv input : @text_area.InputEdit
}

///|
pub(all) enum Mode {
  Text
  Preview
  Split
} derive(Eq)

///|
pub fn MarkdownEditor::activate(
  self : MarkdownEditor,
  generation : Int,
  text : String,
  mode : Mode,
  emit : @rabbita.Emit[EditorEvent],
) -> (EditorState, @rabbita.Cmd) {
  let (preview, command) = activate(
    self.area,
    self.engine,
    generation,
    text,
    mode != Text,
    emit.map(event => { preview: event, }),
  )
  ({ preview, }, command)
}

///|
pub fn MarkdownEditor::accepted(
  self : MarkdownEditor,
  state : EditorState,
  generation : Int,
  text : String,
  change : @text_change.TextChange,
  emit : @rabbita.Emit[EditorEvent],
) -> (EditorState, @rabbita.Cmd) {
  let (preview, command) = accepted(
    self.area,
    self.engine,
    state.preview,
    generation,
    text,
    change,
    emit.map(event => { preview: event, }),
  )
  ({ preview, }, command)
}

///|
pub fn MarkdownEditor::mode_changed(
  self : MarkdownEditor,
  state : EditorState,
  generation : Int,
  text : String,
  previous : Mode,
  current : Mode,
  emit : @rabbita.Emit[EditorEvent],
) -> (EditorState, @rabbita.Cmd) {
  let (preview, command) = visibility_changed(
    self.engine,
    state.preview,
    generation,
    text,
    previous != Text,
    current != Text,
    emit.map(event => { preview: event, }),
  )
  ({ preview, }, command)
}

///|
pub fn MarkdownEditor::update(
  self : MarkdownEditor,
  state : EditorState,
  generation : Int,
  text : String,
  event : EditorEvent,
  emit : @rabbita.Emit[EditorEvent],
) -> (EditorState, @rabbita.Cmd) {
  let (preview, command) = self.engine.update(
    state.preview,
    @preview.Input(generation, text),
    event.preview,
    emit.map(event => { preview: event, }),
  )
  ({ preview, }, command)
}

///|
pub fn MarkdownEditor::view(
  self : MarkdownEditor,
  state : EditorState,
  mode : Mode,
  label : String,
  on_change : (InputEdit) -> @rabbita.Cmd,
  on_composing : (Bool) -> @rabbita.Cmd,
  disabled? : Bool,
  read_only? : Bool,
) -> @rabbita.Html {
  @html.div(class="rmd-editor", [
    @html.section(
      class=if mode == Split {
        "rmd-editor-pane rmd-editor-source rmd-editor-split"
      } else {
        "rmd-editor-pane rmd-editor-source"
      },
      attrs=@html.Attrs::build()
        .hidden(mode == Preview)
        .aria_label("Markdown source"),
      self.input_view(label, on_change, on_composing, disabled?, read_only?),
    ),
    @html.section(
      class="rmd-editor-pane rmd-editor-result",
      attrs=@html.Attrs::build()
        .hidden(mode == Text)
        .aria_label("Rendered Markdown"),
      self.preview_view(state),
    ),
  ])
}

///|
/// Render the input inside a host-provided pane. Keep this node mounted across
/// mode changes; a host may key its parent by document generation.
pub fn MarkdownEditor::input_view(
  self : MarkdownEditor,
  label : String,
  on_change : (InputEdit) -> @rabbita.Cmd,
  on_composing : (Bool) -> @rabbita.Cmd,
  disabled? : Bool,
  read_only? : Bool,
  rows? : Int = 20,
  autofocus? : Bool = false,
  class? : String = "rmd-editor-input",
) -> @rabbita.Html {
  @html.textarea(
    rows~,
    autofocus~,
    disabled?,
    read_only?,
    class~,
    attrs=self.area.attach(
      @html.Attrs::build().aria_label(label),
      input => on_change({ input, }),
      on_composing,
    ),
    @html.nothing,
  )
}

///|
/// Render the derived preview inside a host-provided pane.
pub fn MarkdownEditor::preview_view(
  _self : MarkdownEditor,
  state : EditorState,
  id? : String,
) -> @rabbita.Html {
  state.preview.view(id?)
}

///|
pub fn MarkdownEditor::restore(
  self : MarkdownEditor,
  text : String,
) -> @rabbita.Cmd {
  self.area.restore(text)
}

///|
/// Admit a native input once before the host applies it to accepted text.
pub fn MarkdownEditor::admit(
  self : MarkdownEditor,
  edit : InputEdit,
) -> @text_change.TextChange? {
  self.area.admit(edit.input)
}

///|
pub fn MarkdownEditor::value(
  self : MarkdownEditor,
  on_value : (String) -> @rabbita.Cmd,
) -> @rabbita.Cmd {
  self.area.value(on_value)
}
