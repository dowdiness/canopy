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
let initial_text = "# Markdown playground\n\nEdit this document and switch between **Text**, **Preview**, and **Split**.\n\n- Your text lives in this example app.\n- Preview is derived from accepted edits.\n"

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
          let (preview, command) = engine.document_changed(
            model.preview,
            @preview.Input(0, text),
            change,
            emit.map(event => PreviewCompleted(event)),
          )
          ({ ..model, text, preview, }, command)
        }
      }
    CompositionChanged(composing) => ({ ..model, composing, }, @cmd.none)
    ModeSelected(mode) => {
      let input = @preview.Input(0, model.text)
      let (preview, command) = if model.mode == Text && mode != Text {
        engine.request(
          model.preview,
          input,
          emit.map(event => PreviewCompleted(event)),
        )
      } else if model.mode != Text && mode == Text {
        engine.suspend(model.preview, input)
      } else {
        (model.preview, @cmd.none)
      }
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
) -> @rabbita.Html {
  @html.div(class="page", [
    @html.header([
      @html.p(class="eyebrow", "RABBITA MARKDOWN / PROTOTYPE"),
      @html.h1("A document, without an app around it."),
      @html.p(
        class="intro",
        "A small consumer of the extracted input and preview packages. No account, storage, or sync.",
      ),
    ]),
    @html.div(class="workspace", [
      @html.div(class="toolbar", [
        @html.span(class="document-name", "Untitled.md"),
        @html.div(
          class="modes",
          attrs=@html.Attrs::build().aria_label("View mode").role("group"),
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
              @html.Attrs::build().aria_label("Markdown text"),
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
          model.preview.view(),
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
    ]),
  ])
}

///|
#cfg(target="js")
fn main {
  fn app() {
    let area = @text_area.TextArea::TextArea("markdown-demo-text")
    let engine = @preview.PreviewEngine::PreviewEngine()
    let (model, emit) = @rabbita.create_state_with_init(
      init=_emit => {
        let (preview, command) = engine.activate(
          @preview.Input(0, initial_text),
        )
        (
          { text: initial_text, mode: Text, preview, composing: false, },
          @cmd.batch([area.initialize(initial_text), command]),
        )
      },
      update=(model, msg, emit) => update(model, msg, emit, area, engine),
    )
    model.map(current => view(emit, current, area))
  }
  @rabbita.new(app).mount("app")
}
