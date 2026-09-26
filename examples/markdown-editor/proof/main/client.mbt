///|
struct Model {
  text : String
  generation : Int
  mode : @editor.Mode
  editor : @editor.EditorState
  mounted : Bool
  replacement : Bool
  reject_next : Bool
  rejected : Bool
} derive(Eq)

///|
enum Msg {
  Edit(Int, @text_change.TextChange)
  NativeEdit(Int, @editor.InputEdit)
  BeginRejection
  Race
  Reject
  Accept
  Open
  StaleEdit
  Unmount
  ReplaceInstance
  ModeSelected(@editor.Mode)
  EditorCompleted(@editor.EditorEvent)
}

///|
fn update(
  model : Model,
  msg : Msg,
  emit : @rabbita.Emit[Msg],
  first : @editor.MarkdownEditor,
  second : @editor.MarkdownEditor,
) -> (Model, @rabbita.Cmd) {
  let area = if model.replacement { second } else { first }
  match msg {
    BeginRejection => {
      let text = "abc"
      let generation = model.generation + 1
      let (state, command) = area.activate(
        generation,
        text,
        @editor.Text,
        emit.map(event => EditorCompleted(event)),
      )
      (
        {
          ..model,
          text,
          generation,
          mode: @editor.Text,
          editor: state,
          reject_next: true,
          rejected: false,
        },
        command,
      )
    }
    Race => (model, @cmd.batch([emit(Reject), emit(Accept)]))
    Reject => (model, area.restore(model.text))
    Accept => {
      let text = "# Accepted after rejection\n"
      let (state, changed) = area.accepted(
        model.editor,
        model.generation,
        text,
        @text_change.ReplaceAll(text),
        emit.map(event => EditorCompleted(event)),
      )
      ({ ..model, text, editor: state, }, changed)
    }
    Open => {
      let obsolete = area.restore(model.text)
      let text = "# Opened another document\n"
      let generation = model.generation + 1
      let (state, command) = area.activate(
        generation,
        text,
        model.mode,
        emit.map(event => EditorCompleted(event)),
      )
      (
        { ..model, text, generation, editor: state, },
        @cmd.batch([obsolete, command]),
      )
    }
    StaleEdit => (model, emit(Edit(1, @text_change.ReplaceAll("# Obsolete\n"))))
    Unmount => {
      let obsolete = area.restore(model.text)
      ({ ..model, mounted: false, }, obsolete)
    }
    ReplaceInstance => {
      let obsolete = area.restore(model.text)
      let text = "# New textarea owner\n"
      let generation = model.generation + 1
      let (state, current) = second.activate(
        generation,
        text,
        model.mode,
        emit.map(event => EditorCompleted(event)),
      )
      (
        { ..model, text, generation, editor: state, replacement: true, },
        @cmd.batch([obsolete, current]),
      )
    }
    NativeEdit(generation, input) => {
      match area.admit(input) {
        None => (model, @cmd.none)
        Some(change) =>
          update(model, Edit(generation, change), emit, first, second)
      }
    }
    Edit(generation, change) => {
      guard generation == model.generation else { return (model, @cmd.none) }
      if model.reject_next {
        return (
          { ..model, reject_next: false, rejected: true, },
          area.restore(model.text),
        )
      }
      match change.apply(model.text) {
        None => (model, area.restore(model.text))
        Some(text) if text == model.text => (model, @cmd.none)
        Some(text) => {
          let (state, changed) = area.accepted(
            model.editor,
            model.generation,
            text,
            change,
            emit.map(event => EditorCompleted(event)),
          )
          ({ ..model, text, editor: state, }, changed)
        }
      }
    }
    ModeSelected(mode) => {
      let (state, command) = area.mode_changed(
        model.editor,
        model.generation,
        model.text,
        model.mode,
        mode,
        emit.map(event => EditorCompleted(event)),
      )
      ({ ..model, mode, editor: state, }, command)
    }
    EditorCompleted(event) => {
      let (state, command) = area.update(
        model.editor,
        model.generation,
        model.text,
        event,
        emit.map(event => EditorCompleted(event)),
      )
      ({ ..model, editor: state, }, command)
    }
  }
}

///|
fn view(
  model : Model,
  emit : @rabbita.Emit[Msg],
  first : @editor.MarkdownEditor,
  second : @editor.MarkdownEditor,
) -> @rabbita.Html {
  let area = if model.replacement { second } else { first }
  @html.div([
    @html.button(on_click=emit(BeginRejection), "Start rejected native edit"),
    @html.p("Accepted text: \{model.text}"),
    @html.p(if model.rejected { "Rejected first edit" } else { "" }),
    @html.button(on_click=emit(Race), "Reject then accept"),
    @html.button(on_click=emit(Open), "Open document"),
    @html.button(on_click=emit(StaleEdit), "Old document edit"),
    @html.button(on_click=emit(Unmount), "Unmount"),
    @html.button(on_click=emit(ReplaceInstance), "Replace instance"),
    @html.div([
      @html.button(on_click=emit(ModeSelected(@editor.Text)), "Text"),
      @html.button(on_click=emit(ModeSelected(@editor.Preview)), "Preview"),
      @html.button(on_click=emit(ModeSelected(@editor.Split)), "Split"),
    ]),
    if model.mounted {
      area.view(
        model.editor,
        model.mode,
        "Document text",
        input => emit(NativeEdit(model.generation, input)),
        _ => @cmd.none,
      )
    } else {
      @html.p("Unmounted")
    },
  ])
}

///|
#cfg(target="js")
fn main {
  fn app() {
    let first = @editor.MarkdownEditor::MarkdownEditor("proof-text")
    let second = @editor.MarkdownEditor::MarkdownEditor("proof-text")
    let (model, emit) = @rabbita.create_state_with_init(
      init=emit => {
        let text = "# First document\n"
        let (state, command) = first.activate(
          1,
          text,
          @editor.Text,
          emit.map(event => EditorCompleted(event)),
        )
        (
          {
            text,
            generation: 1,
            mode: @editor.Text,
            editor: state,
            mounted: true,
            replacement: false,
            reject_next: false,
            rejected: false,
          },
          command,
        )
      },
      update=(model, msg, emit) => update(model, msg, emit, first, second),
    )
    model.map(current => view(current, emit, first, second))
  }
  @rabbita.new(app).mount("app")
}
