///|
struct Model {
  text : String
  mode : @editor.Mode
  editor : @editor.EditorState
  composing : Bool
} derive(Eq)

///|
enum Msg {
  Edit(@editor.InputEdit)
  CompositionChanged(Bool)
  ModeSelected(@editor.Mode)
  EditorCompleted(@editor.EditorEvent)
}

///|
fn update(
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
  editor : @editor.MarkdownEditor,
) -> (Model, @rabbita.Cmd) {
  match msg {
    Edit(input) =>
      match editor.admit(input) {
        None => (model, @cmd.none)
        Some(change) =>
          match change.apply(model.text) {
            None => (model, editor.restore(model.text))
            Some(text) if text == model.text => (model, @cmd.none)
            Some(text) => {
              let (state, command) = editor.accepted(
                model.editor,
                0,
                text,
                change,
                emit.map(event => EditorCompleted(event)),
              )
              ({ ..model, text, editor: state, }, command)
            }
          }
      }
    CompositionChanged(composing) => ({ ..model, composing, }, @cmd.none)
    ModeSelected(mode) => {
      let (state, command) = editor.mode_changed(
        model.editor,
        0,
        model.text,
        model.mode,
        mode,
        emit.map(event => EditorCompleted(event)),
      )
      ({ ..model, mode, editor: state, }, command)
    }
    EditorCompleted(event) => {
      let (state, command) = editor.update(
        model.editor,
        0,
        model.text,
        event,
        emit.map(event => EditorCompleted(event)),
      )
      ({ ..model, editor: state, }, command)
    }
  }
}

///|
fn mode_button(
  mode : @editor.Mode,
  selected : @editor.Mode,
  label : String,
  emit : @rabbita.Emit[Msg],
) -> @rabbita.Html {
  @html.button(
    type_="button",
    class=if mode == selected { "selected" } else { "" },
    attrs=@html.Attrs::build().aria_pressed(
      if mode == selected {
        "true"
      } else {
        "false"
      },
    ),
    on_click=emit(ModeSelected(mode)),
    label,
  )
}

///|
fn view(
  emit : @rabbita.Emit[Msg],
  model : Model,
  editor : @editor.MarkdownEditor,
  name : String,
) -> @rabbita.Html {
  @html.section(
    class="workspace",
    attrs=@html.Attrs::build().aria_label(name),
    [
      @html.div(class="toolbar", [
        @html.span(class="document-name", name),
        @html.div(
          class="modes",
          attrs=@html.Attrs::build()
            .aria_label("\{name} view mode")
            .role("group"),
          [
            mode_button(@editor.Text, model.mode, "Text", emit),
            mode_button(@editor.Preview, model.mode, "Preview", emit),
            mode_button(@editor.Split, model.mode, "Split", emit),
          ],
        ),
      ]),
      editor.view(
        model.editor,
        model.mode,
        "\{name} Markdown text",
        change => emit(Edit(change)),
        composing => emit(CompositionChanged(composing)),
      ),
      @html.div(class="footer", [
        @html.span(
          if model.composing {
            "Composing…"
          } else {
            "Edits stay in this page"
          },
        ),
        @html.span("Not saved"),
      ]),
    ],
  )
}

///|
fn editor(
  id : String,
  name : String,
  initial_text : String,
  initial_mode : @editor.Mode,
) -> @rabbita.Val[@rabbita.Html] {
  let editor = @editor.MarkdownEditor::MarkdownEditor("\{id}-text")
  let (model, emit) = @rabbita.create_state_with_init(
    init=emit => {
      let (state, command) = editor.activate(
        0,
        initial_text,
        initial_mode,
        emit.map(event => EditorCompleted(event)),
      )
      (
        {
          text: initial_text,
          mode: initial_mode,
          editor: state,
          composing: false,
        },
        command,
      )
    },
    update=(model, msg, emit) => update(model, msg, emit, editor),
  )
  model.map(current => view(emit, current, editor, name))
}

///|
#cfg(target="js")
fn main {
  fn app() {
    let left = editor(
      "draft-a",
      "Draft A",
      "# First draft\n\nAn **independent** Markdown document.\n\n- Alpha\n- Beta\n",
      @editor.Text,
    )
    let right = editor(
      "draft-b",
      "Draft B",
      "# Second draft\n\nEdit here without changing Draft A.\n\n- One\n- Two\n",
      @editor.Split,
    )
    left.map2(right, (left, right) => {
      @html.div(class="page", [
        @html.header([
          @html.p(class="eyebrow", "RABBITA MARKDOWN / PROTOTYPE"),
          @html.h1("Two documents, no application around them."),
          @html.p(
            class="intro",
            "Independent input and preview. No account, storage, or sync.",
          ),
        ]),
        @html.div(class="editor-grid", [left, right]),
      ])
    })
  }
  @rabbita.new(app).mount("app")
}
