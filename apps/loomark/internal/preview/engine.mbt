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
    parser~ : @loom.Parser[@markdown.Block],
    attachment~ : @markdown.MarkdownSemanticAttachment,
    source~ : String
  )
  Broken
}

///|
/// Imperative owner of at most one live Parser/Markdown attachment pair.
pub struct PreviewEngine {
  priv mut state : EngineState
}

///|
pub fn PreviewEngine::PreviewEngine() -> PreviewEngine {
  { state: NoPair }
}

///|
fn create_pair(source : String) -> Result[EngineState, PreviewFailure] {
  try
    @loom.new_parser(
      @loom.SourceId("loomark-preview"),
      source,
      @markdown.markdown_grammar,
    )
  catch {
    _ => Err(InitializationFailed)
  } noraise {
    parser => {
      let attachment = @markdown.MarkdownSemanticAttachment::MarkdownSemanticAttachment(
        parser,
      )
      Ok(Healthy(parser~, attachment~, source~))
    }
  }
}

///|
fn output(attachment : @markdown.MarkdownSemanticAttachment) -> PreviewOutput {
  let document = attachment.document()
  { html: render(document), empty: is_empty(document) }
}

///|
fn PreviewEngine::break_pair(self : PreviewEngine) -> Unit {
  match self.state {
    Healthy(attachment~, ..) => attachment.dispose()
    NoPair | Broken => ()
  }
  self.state = Broken
}

///|
/// Create the first pair, or replace an unusable pair, from current text.
pub fn PreviewEngine::prepare(
  self : PreviewEngine,
  source : String,
) -> Result[PreviewOutput, PreviewFailure] {
  match self.state {
    NoPair | Broken =>
      match create_pair(source) {
        Ok(state) => {
          self.state = state
          self.refresh(source)
        }
        Err(failure) => {
          self.state = Broken
          Err(failure)
        }
      }
    Healthy(source=known_source, attachment~, ..) =>
      if known_source == source {
        Ok(output(attachment))
      } else {
        self.break_pair()
        Err(OutOfSync)
      }
  }
}

///|
/// Advance a healthy pair once for one committed Document change.
pub fn PreviewEngine::apply(
  self : PreviewEngine,
  change : @text_change.TextChange,
  new_source : String,
) -> Result[Unit, PreviewFailure] {
  match self.state {
    NoPair => Ok(())
    Broken => Err(Unusable)
    Healthy(parser~, attachment~, source=old_source) => {
      guard change.apply(old_source) == Some(new_source) else {
        self.break_pair()
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
          self.state = Healthy(parser~, attachment~, source=new_source)
          Ok(())
        }
        Err(failure) => {
          self.break_pair()
          Err(failure)
        }
      }
    }
  }
}

///|
/// Read and materialize the current semantic result. Broken pairs are replaced
/// here because callers invoke refresh only at an allowed retry boundary.
pub fn PreviewEngine::refresh(
  self : PreviewEngine,
  source : String,
) -> Result[PreviewOutput, PreviewFailure] {
  match self.state {
    NoPair | Broken => self.prepare(source)
    Healthy(source=known_source, attachment~, ..) =>
      if known_source == source {
        Ok(output(attachment))
      } else {
        self.break_pair()
        Err(OutOfSync)
      }
  }
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
