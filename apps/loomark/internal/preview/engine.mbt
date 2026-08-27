///|
pub(all) enum PreviewFailure {
  InitializationFailed
  TransitionFailed
  OutOfSync
  Unusable
} derive(Eq, Debug)

///|
pub(all) struct PreviewOutput {
  html : @rabbita.Html
  empty : Bool
} derive(Eq)

///|
priv enum EngineState {
  NoPair
  Healthy(parser~ : @loom.SyntaxParser, source~ : String)
  Broken
}

///|
/// Imperative owner of at most one live syntax Parser.
pub struct PreviewEngine {
  priv mut state : EngineState
}

///|
pub fn PreviewEngine::PreviewEngine() -> PreviewEngine {
  { state: NoPair }
}

///|
fn create_parser_state(source : String) -> Result[EngineState, PreviewFailure] {
  try
    @loom.new_syntax_parser(
      @loom.SourceId("loomark-preview"),
      source,
      @markdown.markdown_grammar.to_syntax_grammar(),
    )
  catch {
    _ => Err(InitializationFailed)
  } noraise {
    parser => Ok(Healthy(parser~, source~))
  }
}

///|
fn output(parser : @loom.SyntaxParser) -> PreviewOutput {
  let snapshot = parser.snapshot().read_or_abort()
  let document = @markdown.experimental_markdown_ir_from_syntax_with_diagnostics(
    parser.source_id(),
    snapshot.syntax,
    snapshot.diagnostics,
  )
  { html: render(document), empty: is_empty(document) }
}

///|
fn PreviewEngine::break_parser(self : PreviewEngine) -> Unit {
  self.state = Broken
}

///|
/// Create the first Parser, or replace an unusable Parser, from current text.
pub fn PreviewEngine::prepare(
  self : PreviewEngine,
  source : String,
) -> Result[PreviewOutput, PreviewFailure] {
  match self.state {
    NoPair | Broken =>
      match create_parser_state(source) {
        Ok(state) => {
          self.state = state
          self.refresh(source)
        }
        Err(failure) => {
          self.state = Broken
          Err(failure)
        }
      }
    Healthy(source=known_source, parser~) =>
      if known_source == source {
        Ok(output(parser))
      } else {
        self.break_parser()
        Err(OutOfSync)
      }
  }
}

///|
/// Advance a healthy Parser once for one committed Document change.
pub fn PreviewEngine::apply(
  self : PreviewEngine,
  change : @text_change.TextChange,
  new_source : String,
) -> Result[Unit, PreviewFailure] {
  match self.state {
    NoPair => Ok(())
    Broken => Err(Unusable)
    Healthy(parser~, source=old_source) => {
      guard change.apply(old_source) == Some(new_source) else {
        self.break_parser()
        return Err(OutOfSync)
      }
      let result : Result[Unit, PreviewFailure] = try {
        match change {
          @text_change.ReplaceRange(start~, delete_len~, inserted~) =>
            parser.apply_edit(
              @loom.Edit::new(start, delete_len, inserted.length()),
              new_source,
            )
          @text_change.ReplaceAll(_) => parser.set_source(new_source)
        }
      } catch {
        _ => Err(TransitionFailed)
      } noraise {
        _ => Ok(())
      }
      match result {
        Ok(_) => {
          self.state = Healthy(parser~, source=new_source)
          Ok(())
        }
        Err(failure) => {
          self.break_parser()
          Err(failure)
        }
      }
    }
  }
}

///|
/// Read and materialize the current semantic result. Broken Parsers are
/// replaced here because callers invoke refresh only at an allowed retry
/// boundary.
pub fn PreviewEngine::refresh(
  self : PreviewEngine,
  source : String,
) -> Result[PreviewOutput, PreviewFailure] {
  match self.state {
    NoPair | Broken => self.prepare(source)
    Healthy(source=known_source, parser~) =>
      if known_source == source {
        Ok(output(parser))
      } else {
        self.break_parser()
        Err(OutOfSync)
      }
  }
}

///|
fn PreviewEngine::discard(self : PreviewEngine) -> Unit {
  self.break_parser()
}

///|
/// Emit a command after DOM patching and one animation-frame boundary. The
/// zero-delay task after the frame gives the patched Preparing state a paint
/// opportunity before synchronous Parser construction starts.
pub fn after_paint(command : @cmd.Cmd) -> @cmd.Cmd {
  @cmd.custom_cmd(kind=@cmd.after_render, scheduler => {
    ignore(
      @dom.window().request_animation_frame(_ => {
        ignore(@dom.window().set_timeout(() => scheduler.add(command), 0))
      }),
    )
  })
}

///|
pub fn prepare_cmd(
  engine : PreviewEngine,
  source : String,
  result~ : @cmd.Emit[Result[PreviewOutput, PreviewFailure]],
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => scheduler.add(result(engine.prepare(source))))
}

///|
pub fn apply_cmd(
  engine : PreviewEngine,
  change : @text_change.TextChange,
  source : String,
  result~ : @cmd.Emit[Result[Unit, PreviewFailure]],
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    scheduler.add(result(engine.apply(change, source)))
  })
}

///|
pub fn refresh_cmd(
  engine : PreviewEngine,
  source : String,
  result~ : @cmd.Emit[Result[PreviewOutput, PreviewFailure]],
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => scheduler.add(result(engine.refresh(source))))
}

///|
pub fn discard_cmd(engine : PreviewEngine) -> @cmd.Cmd {
  @cmd.custom_cmd(_ => engine.discard())
}
