///|
enum Mode {
  Text
  Preview
  Split
} derive(Eq)

///|
struct Model {
  text : String
  mode : Mode
  preview : @preview.State
  composing : Bool
} derive(Eq)

///|
enum Msg {
  Edit(@text_change.TextChange)
  CompositionChanged(Bool)
  ModeSelected(Mode)
  PreviewCompleted(@preview.Event)
}

///|
fn update(
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
  area : @text_area.TextArea,
  engine : @preview.PreviewEngine,
) -> (Model, @rabbita.Cmd) {
  match msg {
    Edit(change) =>
      match change.apply(model.text) {
        None =>
          (model, area.value(text => emit(Edit(@text_change.ReplaceAll(text)))))
        Some(text) if text == model.text => (model, @cmd.none)
        Some(text) => {
          let (preview, command) = @editor.accepted(
            area,
            engine,
            model.preview,
            0,
            text,
            change,
            emit.map(event => PreviewCompleted(event)),
          )
          ({ ..model, text, preview, }, command)
        }
      }
    CompositionChanged(composing) => ({ ..model, composing, }, @cmd.none)
    ModeSelected(mode) => {
      let (preview, command) = @editor.visibility_changed(
        engine,
        model.preview,
        0,
        model.text,
        model.mode != Text,
        mode != Text,
        emit.map(event => PreviewCompleted(event)),
      )
      ({ ..model, mode, preview, }, command)
    }
    PreviewCompleted(event) => {
      let (preview, command) = engine.update(
        model.preview,
        @preview.Input(0, model.text),
        event,
        emit.map(event => PreviewCompleted(event)),
      )
      ({ ..model, preview, }, command)
    }
  }
}

///|
fn mode_button(
  mode : Mode,
  selected : Mode,
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
  area : @text_area.TextArea,
  id : String,
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
            mode_button(Text, model.mode, "Text", emit),
            mode_button(Preview, model.mode, "Preview", emit),
            mode_button(Split, model.mode, "Split", emit),
          ],
        ),
      ]),
      @html.div(class="panes", [
        @html.section(
          class=if model.mode == Split {
            "pane source split"
          } else {
            "pane source"
          },
          attrs=@html.Attrs::build()
            .hidden(model.mode == Preview)
            .aria_label("Markdown source"),
          @html.textarea(
            rows=20,
            class="editor-input",
            attrs=area.attach(
              @html.Attrs::build().aria_label("\{name} Markdown text"),
              change => emit(Edit(change)),
              composing => emit(CompositionChanged(composing)),
            ),
            @html.nothing,
          ),
        ),
        @html.section(
          class="pane result",
          attrs=@html.Attrs::build()
            .hidden(model.mode == Text)
            .aria_label("Rendered Markdown"),
          model.preview.view(id="\{id}-preview"),
        ),
      ]),
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
  initial_mode : Mode,
) -> @rabbita.Val[@rabbita.Html] {
  let area = @text_area.TextArea::TextArea("\{id}-text")
  let engine = @preview.PreviewEngine::PreviewEngine()
  let (model, emit) = @rabbita.create_state_with_init(
    init=emit => {
      let (preview, command) = @editor.activate(
        area,
        engine,
        0,
        initial_text,
        initial_mode != Text,
        emit.map(event => PreviewCompleted(event)),
      )
      (
        { text: initial_text, mode: initial_mode, preview, composing: false, },
        command,
      )
    },
    update=(model, msg, emit) => update(model, msg, emit, area, engine),
  )
  model.map(current => view(emit, current, area, id, name))
}

///|
#cfg(target="js")
fn main {
  fn app() {
    let left = editor(
      "draft-a",
      "Draft A",
      "# First draft\n\nAn **independent** Markdown document.\n\n- Alpha\n- Beta\n",
      Text,
    )
    let right = editor(
      "draft-b",
      "Draft B",
      "# Second draft\n\nEdit here without changing Draft A.\n\n- One\n- Two\n",
      Split,
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
