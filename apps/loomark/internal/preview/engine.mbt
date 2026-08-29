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
  Healthy(
    parser~ : @loom.SyntaxParser,
    semantics~ : @markdown.MarkdownSemanticSession,
    source~ : String
  )
  Broken
}

///|
/// Imperative owner of at most one live syntax Parser.
pub struct PreviewEngine {
  priv mut state : EngineState
  priv mut next_revision_key : Int
}

///|
pub fn PreviewEngine::PreviewEngine() -> PreviewEngine {
  { state: NoPair, next_revision_key: 0 }
}

///|
fn create_parser_state(
  source : String,
  first_revision_key : Int,
) -> Result[EngineState, PreviewFailure] {
  try
    @loom.new_syntax_parser(
      @loom.SourceId("loomark-preview"),
      source,
      @markdown.markdown_grammar.to_syntax_grammar(),
    )
  catch {
    _ => Err(InitializationFailed)
  } noraise {
    parser => {
      let semantics = @markdown.MarkdownSemanticSession(
        parser,
        extensions=@markdown.MarkdownExtensions::task_list(),
        first_revision_key~,
      )
      Ok(Healthy(parser~, semantics~, source~))
    }
  }
}

///|
fn PreviewEngine::output(
  self : PreviewEngine,
  semantics : @markdown.MarkdownSemanticSession,
) -> PreviewOutput {
  let publication = semantics.publish()
  self.next_revision_key = semantics.next_revision_key()
  let document = publication.document()
  { html: render_publication(publication), empty: is_empty(document) }
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
      match create_parser_state(source, self.next_revision_key) {
        Ok(state) => {
          self.state = state
          self.refresh(source)
        }
        Err(failure) => {
          self.state = Broken
          Err(failure)
        }
      }
    Healthy(source=known_source, semantics~, ..) =>
      if known_source == source {
        Ok(self.output(semantics))
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
    Healthy(parser~, semantics~, source=old_source) => {
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
          self.state = Healthy(parser~, semantics~, source=new_source)
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
    Healthy(source=known_source, semantics~, ..) =>
      if known_source == source {
        Ok(self.output(semantics))
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
