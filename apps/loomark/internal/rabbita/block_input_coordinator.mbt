///|
/// One browser Block input captured against the document state that rendered
/// its text control. This package-private value is replaced, not accumulated,
/// while input from the same JavaScript turn is waiting to be delivered.
priv struct PendingBlockInput {
  document_id : @archive.LoomarkDocumentId
  expected_version : @markdown.MarkdownDocumentVersion
  node_id : @markdown.MarkdownNodeId
  input_id : String
  text : String
  selection : @dom_boundary.TextSelection
}

///|
fn PendingBlockInput::PendingBlockInput(
  document_id~ : @archive.LoomarkDocumentId,
  expected_version~ : @markdown.MarkdownDocumentVersion,
  node_id~ : @markdown.MarkdownNodeId,
  input_id~ : String,
  text~ : String,
  selection~ : @dom_boundary.TextSelection,
) -> PendingBlockInput {
  { document_id, expected_version, node_id, input_id, text, selection }
}

///|
priv enum BlockEditCheck {
  Current
  WrongDocument
  StaleVersion
}

///|
fn check_block_edit(
  current_document_id : @archive.LoomarkDocumentId,
  current_version : @markdown.MarkdownDocumentVersion,
  input : PendingBlockInput,
) -> BlockEditCheck {
  if input.document_id != current_document_id {
    WrongDocument
  } else if input.expected_version != current_version {
    StaleVersion
  } else {
    Current
  }
}

///|
priv enum BlockSelectionCheck {
  ValidBlockSelection
  NonCollapsedBlockSelection
  InvalidBlockSelection
  MissingBlockSelectionTarget
}

///|
fn check_block_selection(
  document : @markdown.MarkdownDocumentSnapshot,
  input : PendingBlockInput,
) -> BlockSelectionCheck {
  let target_exists = document
    .blocks()
    .fold(init=false, (found, block) => {
      found || block.node_id() == input.node_id
    })
  if !target_exists {
    MissingBlockSelectionTarget
  } else if input.selection.start() != input.selection.end() {
    NonCollapsedBlockSelection
  } else {
    let offset = input.selection.start()
    if offset < 0 ||
      offset > input.text.length() ||
      !@moji.is_grapheme_boundary(input.text, offset) {
      InvalidBlockSelection
    } else {
      ValidBlockSelection
    }
  }
}

///|
/// Identifies one deferred delivery attempt. A newer enqueue makes every older
/// schedule inapplicable without requiring timer cancellation.
priv struct BlockInputSchedule {
  generation : Int
}

///|
/// One latest input released for the existing Block commit path.
priv struct BlockInputDelivery {
  token : Int
  input : PendingBlockInput
}

///|
/// Deterministic state for replacing rapid Block input with its latest value.
/// Scheduling and message delivery remain in the Rabbita command shell.
priv struct BlockInputState {
  pending : PendingBlockInput?
  generation : Int
  next_token : Int
  in_flight : BlockInputDelivery?
  composition : PendingBlockInput?
  composition_final : PendingBlockInput?
}

///|
fn BlockInputState::BlockInputState() -> BlockInputState {
  {
    pending: None,
    generation: 0,
    next_token: 0,
    in_flight: None,
    composition: None,
    composition_final: None,
  }
}

///|
fn BlockInputState::enqueue(
  self : BlockInputState,
  input : PendingBlockInput,
) -> (BlockInputState, BlockInputSchedule) {
  let generation = self.generation + 1
  ({ ..self, pending: Some(input), generation }, { generation, })
}

///|
fn BlockInputState::flush(
  self : BlockInputState,
  schedule : BlockInputSchedule,
) -> (BlockInputState, BlockInputDelivery?) {
  guard schedule.generation == self.generation && self.in_flight is None else {
    return (self, None)
  }
  match self.pending {
    None => (self, None)
    Some(input) => {
      let delivery = { token: self.next_token, input }
      (
        {
          ..self,
          pending: None,
          next_token: self.next_token + 1,
          in_flight: Some(delivery),
        },
        Some(delivery),
      )
    }
  }
}

///|
fn BlockInputState::begin_composition(
  self : BlockInputState,
  input : PendingBlockInput,
) -> (BlockInputState, Bool) {
  guard self.in_flight is None else { return (self, false) }
  let input = match self.pending {
    Some(pending) if pending.matches(
        input.document_id,
        input.expected_version,
        input.node_id,
        input.input_id,
      ) => { ..pending, selection: input.selection }
    _ => input
  }
  (
    {
      ..self,
      pending: None,
      generation: self.generation + 1,
      composition: Some(input),
      composition_final: None,
    },
    true,
  )
}

///|
fn BlockInputState::has_composition(
  self : BlockInputState,
  input_id : String,
) -> Bool {
  match self.composition {
    Some(input) => input.input_id == input_id
    None => false
  }
}

///|
fn BlockInputState::update_composition(
  self : BlockInputState,
  input_id : String,
  text : String,
  selection : @dom_boundary.TextSelection,
) -> (BlockInputState, Bool) {
  match self.composition {
    Some(input) if input.input_id == input_id =>
      ({ ..self, composition: Some({ ..input, text, selection }) }, true)
    _ => (self, false)
  }
}

///|
fn PendingBlockInput::matches(
  self : PendingBlockInput,
  document_id : @archive.LoomarkDocumentId,
  version : @markdown.MarkdownDocumentVersion,
  node_id : @markdown.MarkdownNodeId,
  input_id : String,
) -> Bool {
  self.document_id == document_id &&
  self.expected_version == version &&
  self.node_id == node_id &&
  self.input_id == input_id
}

///|
fn BlockInputState::display_text(
  self : BlockInputState,
  document_id~ : @archive.LoomarkDocumentId,
  version~ : @markdown.MarkdownDocumentVersion,
  node_id~ : @markdown.MarkdownNodeId,
  input_id~ : String,
  committed_text~ : String,
) -> String {
  let input = match self.composition {
    Some(input) => Some(input)
    None =>
      match self.pending {
        Some(input) => Some(input)
        None => self.in_flight.map(delivery => delivery.input)
      }
  }
  match input {
    Some(input) if input.matches(document_id, version, node_id, input_id) =>
      input.text
    _ => committed_text
  }
}

///|
fn BlockInputState::is_active(self : BlockInputState, token : Int) -> Bool {
  self.pending is None &&
  (match self.in_flight {
    Some(delivery) => delivery.token == token
    None => false
  })
}

///|
fn BlockInputState::cancel(self : BlockInputState) -> BlockInputState {
  {
    pending: None,
    generation: self.generation + 1,
    next_token: self.next_token,
    in_flight: None,
    composition: None,
    composition_final: None,
  }
}

///|
fn BlockInputState::finish(
  self : BlockInputState,
  token : Int,
) -> (BlockInputState, BlockInputSchedule?) {
  match self.in_flight {
    Some(delivery) if delivery.token == token => {
      let state = { ..self, in_flight: None }
      let schedule = state.pending.map(_ => { generation: state.generation })
      (state, schedule)
    }
    _ => (self, None)
  }
}

///|
/// Mutable Rabbita shell around the deterministic Block input state.
priv struct BlockInputCoordinator {
  state : @ref.Ref[BlockInputState]
}

///|
fn BlockInputCoordinator::BlockInputCoordinator() -> BlockInputCoordinator {
  { state: @ref.Ref(BlockInputState::BlockInputState()) }
}

///|
fn BlockInputCoordinator::schedule(
  self : BlockInputCoordinator,
  schedule : BlockInputSchedule,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  @cmd.delay(
    @cmd.custom_cmd(scheduler => {
      let (state, delivery) = self.state.val.flush(schedule)
      self.state.val = state
      match delivery {
        Some(delivery) =>
          scheduler.add(
            emit(
              Editing(BlockInput(token=delivery.token, input=delivery.input)),
            ),
          )
        None => ()
      }
    }),
    0,
  )
}

///|
fn BlockInputCoordinator::enqueue(
  self : BlockInputCoordinator,
  input : PendingBlockInput,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  let duplicate_final = match self.state.val.composition_final {
    Some(final_input) =>
      final_input.matches(
        input.document_id,
        input.expected_version,
        input.node_id,
        input.input_id,
      ) &&
      final_input.text == input.text
    None => false
  }
  self.state.val = { ..self.state.val, composition_final: None }
  if duplicate_final {
    return @rabbita_runtime.none
  }
  let (state, schedule) = self.state.val.enqueue(input)
  self.state.val = state
  self.schedule(schedule, emit)
}

///|
fn BlockInputCoordinator::begin_composition(
  self : BlockInputCoordinator,
  input : PendingBlockInput,
) -> Bool {
  let (state, accepted) = self.state.val.begin_composition(input)
  self.state.val = state
  accepted
}

///|
fn BlockInputCoordinator::has_composition(
  self : BlockInputCoordinator,
  input_id : String,
) -> Bool {
  self.state.val.has_composition(input_id)
}

///|
fn BlockInputCoordinator::update_composition(
  self : BlockInputCoordinator,
  input_id : String,
  text : String,
  selection : @dom_boundary.TextSelection,
) -> Bool {
  let (state, updated) = self.state.val.update_composition(
    input_id, text, selection,
  )
  self.state.val = state
  updated
}

///|
fn BlockInputCoordinator::finish_composition(
  self : BlockInputCoordinator,
  input_id : String,
  committed_text : String,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  let input = match self.state.val.composition {
    Some(input) if input.input_id == input_id => input
    _ => return @rabbita_runtime.none
  }
  self.state.val = { ..self.state.val, composition: None }
  guard input.text != committed_text else { return @rabbita_runtime.none }
  let (state, schedule) = self.state.val.enqueue(input)
  let (state, delivery) = state.flush(schedule)
  self.state.val = state
  match delivery {
    Some(delivery) => {
      self.state.val = {
        ..self.state.val,
        composition_final: Some(delivery.input),
      }
      emit(Editing(BlockInput(token=delivery.token, input=delivery.input)))
    }
    None => @rabbita_runtime.none
  }
}

///|
fn BlockInputCoordinator::is_active(
  self : BlockInputCoordinator,
  token : Int,
) -> Bool {
  self.state.val.is_active(token)
}

///|
fn BlockInputCoordinator::finish(
  self : BlockInputCoordinator,
  token : Int,
  emit : @cmd.Emit[DriverEvent],
) -> @cmd.Cmd {
  let (state, schedule) = self.state.val.finish(token)
  self.state.val = state
  match schedule {
    Some(schedule) => self.schedule(schedule, emit)
    None => @rabbita_runtime.none
  }
}

///|
fn BlockInputCoordinator::display_text(
  self : BlockInputCoordinator,
  document_id~ : @archive.LoomarkDocumentId,
  version~ : @markdown.MarkdownDocumentVersion,
  node_id~ : @markdown.MarkdownNodeId,
  input_id~ : String,
  committed_text~ : String,
) -> String {
  self.state.val.display_text(
    document_id~,
    version~,
    node_id~,
    input_id~,
    committed_text~,
  )
}

///|
fn BlockInputCoordinator::cancel_pending(self : BlockInputCoordinator) -> Unit {
  self.state.val = self.state.val.cancel()
}
