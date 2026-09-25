///|
enum Mode {
  Text
  Preview
  Split
} derive(Eq)

///|
struct Model {
  text : String
  generation : Int
  mode : Mode
  preview : @preview.State
  mounted : Bool
  replacement : Bool
} derive(Eq)

///|
enum Msg {
  Edit(@text_change.TextChange)
  Race
  Reject
  Accept
  Open
  Unmount
  ReplaceInstance
  ModeSelected(Mode)
  PreviewCompleted(@preview.Event)
}

///|
fn update(
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
  first : @text_area.TextArea,
  second : @text_area.TextArea,
  engine : @preview.PreviewEngine,
) -> (Model, @rabbita.Cmd) {
  match msg {
    Race => (model, @cmd.batch([emit(Reject), emit(Accept)]))
    Reject => (model, first.initialize(model.text))
    Accept => {
      let text = "# Accepted after rejection\n"
      first.accepted(text)
      let (preview, changed) = engine.document_changed(
        model.preview,
        @preview.Input(model.generation, text),
        @text_change.ReplaceAll(text),
        emit.map(event => PreviewCompleted(event)),
      )
      ({ ..model, text, preview, }, changed)
    }
    Open => {
      let obsolete = first.initialize(model.text)
      let text = "# Opened another document\n"
      let current = first.initialize(text)
      let generation = model.generation + 1
      let (preview, activate) = engine.activate(
        @preview.Input(generation, text),
      )
      let (preview, request) = if model.mode == Text {
        (preview, @cmd.none)
      } else {
        engine.request(
          preview,
          @preview.Input(generation, text),
          emit.map(event => PreviewCompleted(event)),
        )
      }
      (
        { ..model, text, generation, preview, },
        @cmd.batch([obsolete, current, activate, request]),
      )
    }
    Unmount => {
      let obsolete = first.initialize(model.text)
      ({ ..model, mounted: false, }, obsolete)
    }
    ReplaceInstance => {
      let obsolete = first.initialize(model.text)
      let text = "# New textarea owner\n"
      let current = second.initialize(text)
      ({ ..model, text, replacement: true, }, @cmd.batch([obsolete, current]))
    }
    Edit(change) => {
      let area = if model.replacement { second } else { first }
      match change.apply(model.text) {
        None => (model, @cmd.none)
        Some(text) if text == model.text => (model, @cmd.none)
        Some(text) => {
          area.accepted(text)
          let (preview, changed) = engine.document_changed(
            model.preview,
            @preview.Input(model.generation, text),
            change,
            emit.map(event => PreviewCompleted(event)),
          )
          ({ ..model, text, preview, }, changed)
        }
      }
    }
    ModeSelected(mode) => {
      let input = @preview.Input(model.generation, model.text)
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
        @preview.Input(model.generation, model.text),
        event,
        emit.map(event => PreviewCompleted(event)),
      )
      ({ ..model, preview, }, command)
    }
  }
}

///|
fn view(
  model : Model,
  emit : @rabbita.Emit[Msg],
  first : @text_area.TextArea,
  second : @text_area.TextArea,
) -> @rabbita.Html {
  let area = if model.replacement { second } else { first }
  @html.div([
    @html.button(on_click=emit(Race), "Reject then accept"),
    @html.button(on_click=emit(Open), "Open document"),
    @html.button(on_click=emit(Unmount), "Unmount"),
    @html.button(on_click=emit(ReplaceInstance), "Replace instance"),
    @html.div([
      @html.button(on_click=emit(ModeSelected(Text)), "Text"),
      @html.button(on_click=emit(ModeSelected(Preview)), "Preview"),
      @html.button(on_click=emit(ModeSelected(Split)), "Split"),
    ]),
    if model.mounted {
      @html.div([
        @html.div(
          attrs=@html.Attrs::build().hidden(model.mode == Preview),
          @html.textarea(
            attrs=area.attach(
              @html.Attrs::build().aria_label("Document text"),
              change => emit(Edit(change)),
              _ => @cmd.none,
            ),
            @html.nothing,
          ),
        ),
        @html.div(
          attrs=@html.Attrs::build().hidden(model.mode == Text),
          model.preview.view(),
        ),
      ])
    } else {
      @html.p("Unmounted")
    },
  ])
}

///|
#cfg(target="js")
fn main {
  fn app() {
    let first = @text_area.TextArea::TextArea("proof-text")
    let second = @text_area.TextArea::TextArea("proof-text")
    let engine = @preview.PreviewEngine::PreviewEngine()
    let (model, emit) = @rabbita.create_state_with_init(
      init=_ => {
        let text = "# First document\n"
        let (preview, activate) = engine.activate(@preview.Input(1, text))
        (
          {
            text,
            generation: 1,
            mode: Text,
            preview,
            mounted: true,
            replacement: false,
          },
          @cmd.batch([first.initialize(text), activate]),
        )
      },
      update=(model, msg, emit) => {
        update(model, msg, emit, first, second, engine)
      },
    )
    model.map(current => view(current, emit, first, second))
  }
  @rabbita.new(app).mount("app")
}
