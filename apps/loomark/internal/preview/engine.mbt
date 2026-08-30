///|
#warnings("-unused_value")
priv enum PreviewFailure {
  InitializationFailed
  TransitionFailed
  OutOfSync
  Unusable
} derive(Eq, Debug)

///|
priv struct AcceptedMarkdownRender {
  previous : @markdown.MarkdownPreviousUpdate
  lazy_keys : Array[Int]
}

///|
priv struct PreviewAcceptance {
  domain : Ref[Unit]
  sequence : Int
}

///|
impl Eq for PreviewAcceptance with fn equal(self, other) {
  physical_equal(self.domain, other.domain) && self.sequence == other.sequence
}

///|
priv struct PendingMarkdownRender {
  acceptance : PreviewAcceptance
  owner_generation : Int?
  render : AcceptedMarkdownRender
}

///|
#warnings("-unused_value")
priv struct PreviewOutput {
  html : @rabbita.Html
  empty : Bool
  acceptance : PreviewAcceptance
} derive(Eq)

///|
priv enum EngineState {
  NoPair
  Healthy(
    parser~ : @loom.SyntaxParser,
    updates~ : @markdown.MarkdownDocumentUpdates,
    source~ : String
  )
  Broken
}

///|
/// Imperative owner of at most one live syntax Parser.
pub struct PreviewEngine {
  priv mut state : EngineState
  priv mut accepted_render : AcceptedMarkdownRender?
  priv mut pending_render : PendingMarkdownRender?
  priv acceptance_domain : Ref[Unit]
  priv mut next_acceptance_sequence : Int
  priv mut next_lazy_key : Int
  priv mut owner_generation : Int?
}

///|
pub fn PreviewEngine::PreviewEngine() -> PreviewEngine {
  {
    state: NoPair,
    accepted_render: None,
    pending_render: None,
    acceptance_domain: Ref::Ref(()),
    next_acceptance_sequence: 0,
    next_lazy_key: 0,
    owner_generation: None,
  }
}

///|
fn PreviewEngine::activate_generation(
  self : PreviewEngine,
  generation : Int,
) -> Bool {
  match self.owner_generation {
    Some(current) if generation <= current => false
    None | Some(_) => {
      self.owner_generation = Some(generation)
      self.state = NoPair
      self.accepted_render = None
      self.pending_render = None
      true
    }
  }
}

///|
fn PreviewEngine::owns(self : PreviewEngine, generation : Int) -> Bool {
  self.owner_generation == Some(generation)
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
    parser => {
      let updates = @markdown.MarkdownDocumentUpdates(
        parser,
        extensions=@markdown.MarkdownExtensions::task_list(),
      )
      Ok(Healthy(parser~, updates~, source~))
    }
  }
}

///|
fn PreviewEngine::fresh_lazy_key(self : PreviewEngine) -> Int {
  let key = self.next_lazy_key
  self.next_lazy_key += 1
  key
}

///|
fn previous_block_indexes_are_valid(
  indexes : ArrayView[Int?],
  previous_key_count : Int,
) -> Bool {
  let seen : Set[Int] = Set([])
  indexes.all(match_index => {
    match match_index {
      Some(index) =>
        index >= 0 && index < previous_key_count && seen.add_and_check(index)
      None => true
    }
  })
}

///|
fn markdown_matches_are_valid(
  blocks : ArrayView[@markdown.MarkdownTopLevelBlock],
  previous_key_count : Int,
) -> Bool {
  previous_block_indexes_are_valid(
    blocks.map(block => block.matched_previous_block_index())[:],
    previous_key_count,
  )
}

///|
fn PreviewEngine::output(
  self : PreviewEngine,
  updates : @markdown.MarkdownDocumentUpdates,
) -> PreviewOutput {
  let update = updates.document_update()
  let previous = self.accepted_render.map(state => state.previous)
  let previous_keys = self.accepted_render.map_or([], state => state.lazy_keys)
  let blocks = update.top_level_blocks(previous~)
  let matches_valid = markdown_matches_are_valid(blocks, previous_keys.length())
  let keys = blocks.map(block => {
    match (matches_valid, block.matched_previous_block_index()) {
      (true, Some(index)) => previous_keys[index]
      _ => self.fresh_lazy_key()
    }
  })
  let acceptance = {
    domain: self.acceptance_domain,
    sequence: self.next_acceptance_sequence,
  }
  self.next_acceptance_sequence += 1
  let render = { previous: update.as_previous(), lazy_keys: keys }
  let output = {
    html: render_top_level_blocks(blocks, keys),
    empty: blocks.is_empty(),
    acceptance,
  }
  self.pending_render = Some({
    acceptance,
    owner_generation: self.owner_generation,
    render,
  })
  output
}

///|
/// Accept renderer state only after the Preview lifecycle admits this output.
fn PreviewEngine::accept(self : PreviewEngine, output : PreviewOutput) -> Bool {
  guard self.pending_render is Some(pending) else { return false }
  guard physical_equal(output.acceptance.domain, self.acceptance_domain) &&
    output.acceptance.sequence == pending.acceptance.sequence &&
    pending.owner_generation == self.owner_generation else {
    return false
  }
  self.accepted_render = Some(pending.render)
  self.pending_render = None
  true
}

///|
fn PreviewEngine::break_parser(self : PreviewEngine) -> Unit {
  self.state = Broken
  self.accepted_render = None
  self.pending_render = None
}

///|
/// Create the first Parser, or replace an unusable Parser, from current text.
fn PreviewEngine::prepare(
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
    Healthy(source=known_source, updates~, ..) =>
      if known_source == source {
        Ok(self.output(updates))
      } else {
        self.break_parser()
        Err(OutOfSync)
      }
  }
}

///|
/// Advance a healthy Parser once for one committed Document change.
fn PreviewEngine::apply(
  self : PreviewEngine,
  change : @text_change.TextChange,
  new_source : String,
) -> Result[Unit, PreviewFailure] {
  match self.state {
    NoPair => Ok(())
    Broken => Err(Unusable)
    Healthy(parser~, updates~, source=old_source) => {
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
          self.state = Healthy(parser~, updates~, source=new_source)
          self.pending_render = None
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
fn PreviewEngine::refresh(
  self : PreviewEngine,
  source : String,
) -> Result[PreviewOutput, PreviewFailure] {
  match self.state {
    NoPair | Broken => self.prepare(source)
    Healthy(source=known_source, updates~, ..) =>
      if known_source == source {
        Ok(self.output(updates))
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
fn PreviewEngine::prepare_owned(
  self : PreviewEngine,
  generation : Int,
  source : String,
) -> Result[PreviewOutput, PreviewFailure]? {
  guard self.owns(generation) else { return None }
  Some(self.prepare(source))
}

///|
fn PreviewEngine::apply_owned(
  self : PreviewEngine,
  generation : Int,
  change : @text_change.TextChange,
  source : String,
) -> Result[Unit, PreviewFailure]? {
  guard self.owns(generation) else { return None }
  Some(self.apply(change, source))
}

///|
fn PreviewEngine::refresh_owned(
  self : PreviewEngine,
  generation : Int,
  source : String,
) -> Result[PreviewOutput, PreviewFailure]? {
  guard self.owns(generation) else { return None }
  Some(self.refresh(source))
}

///|
fn PreviewEngine::discard_owned(self : PreviewEngine, generation : Int) -> Bool {
  guard self.owns(generation) else { return false }
  self.discard()
  true
}
