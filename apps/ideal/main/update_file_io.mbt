///|
fn handle_file_io(
  emit : Emit[Msg],
  msg : Msg,
  model : Model,
) -> (Cmd, Model)? raise {
  let _ = emit
  match msg {
    LoadExample(example_text) => Some(load_text(model, example_text))
    OpenFile =>
      Some((@rabbita.effect(fn() { @ffi.load_file(model.handle) }), model))
    SaveFile => {
      let source = model.editor.get_text()
      Some(
        (
          @rabbita.effect(fn() { @file_io.save_text(source, "canopy.lambda") }),
          model,
        ),
      )
    }
    FileLoaded(content) => Some(load_text(model, content))
    _ => None
  }
}
