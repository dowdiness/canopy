///|
priv struct InputFacts {
  input_type : String
  data : String?
  selection_start : Int
  selection_end : Int
  text_length : Int
}

///|
priv struct CompositionFacts {
  selection_start : Int
  selection_end : Int
  text_length : Int
}

///|
priv enum InputState {
  Idle
  WaitingForInput(InputFacts)
  Composing(CompositionFacts)
  CompositionEnded
}

///|
priv enum InputDecision {
  Ignore
  Emit(@text_change.TextChange)
  ReadValue
}

///|
priv enum InputOperation {
  Insert(String)
  DeleteBackward
  DeleteForward
}

///|
/// One browser-owned textarea used by Loomark.
pub struct TextArea {
  priv id : String
  priv mut state : InputState
}

///|
pub fn TextArea::TextArea(id : String) -> TextArea {
  { id, state: Idle }
}

///|
fn input_target(event : @dom.InputEvent) -> @dom.HTMLTextAreaElement {
  guard @dom.IsEvent::current_target(event).to_option() is Some(target) else {
    abort("TextArea input event has no current target")
  }
  guard @dom.IsEventTarget::to_html_text_area_element(target) is Some(text_area) else {
    abort("TextArea input event target is not an HTMLTextAreaElement")
  }
  text_area
}

///|
fn composition_target(
  event : @dom.CompositionEvent,
) -> @dom.HTMLTextAreaElement {
  guard @dom.IsEvent::current_target(event).to_option() is Some(target) else {
    abort("TextArea composition event has no current target")
  }
  guard @dom.IsEventTarget::to_html_text_area_element(target) is Some(text_area) else {
    abort("TextArea composition event target is not an HTMLTextAreaElement")
  }
  text_area
}

///|
fn text_area_by_id(id : String) -> @dom.HTMLTextAreaElement {
  guard @dom.document().get_element_by_id(id).to_option() is Some(element) else {
    abort("TextArea element not found: " + id)
  }
  guard @dom.IsEventTarget::to_html_text_area_element(element)
    is Some(text_area) else {
    abort("TextArea ID does not identify an HTMLTextAreaElement: " + id)
  }
  text_area
}

///|
fn input_facts(
  event : @dom.InputEvent,
  text_area : @dom.HTMLTextAreaElement,
) -> InputFacts {
  {
    input_type: event.input_type(),
    data: event.get_data().to_option(),
    selection_start: text_area.get_selection_start(),
    selection_end: text_area.get_selection_end(),
    text_length: text_area.get_text_length(),
  }
}

///|
fn composition_facts(text_area : @dom.HTMLTextAreaElement) -> CompositionFacts {
  {
    selection_start: text_area.get_selection_start(),
    selection_end: text_area.get_selection_end(),
    text_length: text_area.get_text_length(),
  }
}

///|
fn valid_input(facts : InputFacts) -> Bool {
  facts.selection_start >= 0 &&
  facts.selection_start <= facts.selection_end &&
  facts.selection_end <= facts.text_length
}

///|
fn valid_composition(facts : CompositionFacts) -> Bool {
  facts.selection_start >= 0 &&
  facts.selection_start <= facts.selection_end &&
  facts.selection_end <= facts.text_length
}

///|
fn is_composition_input_type(input_type : String) -> Bool {
  input_type == "insertCompositionText" || input_type == "insertFromComposition"
}

///|
fn input_operation(facts : InputFacts) -> InputOperation? {
  match facts.input_type {
    "insertText"
    | "insertReplacementText"
    | "insertFromPaste"
    | "insertFromPasteAsQuotation"
    | "insertFromDrop"
    | "insertTranspose" => facts.data.map(data => Insert(data))
    "insertLineBreak" | "insertParagraph" => Some(Insert("\n"))
    "deleteContentBackward"
    | "deleteWordBackward"
    | "deleteSoftLineBackward"
    | "deleteHardLineBackward" => Some(DeleteBackward)
    "deleteContentForward"
    | "deleteWordForward"
    | "deleteSoftLineForward"
    | "deleteHardLineForward"
    | "deleteByCut"
    | "deleteByDrag" => Some(DeleteForward)
    _ => None
  }
}

///|
fn decide_input(
  state : InputState,
  after : InputFacts,
  is_composing : Bool,
) -> (InputState, InputDecision) {
  match state {
    Composing(start) => (Composing(start), Ignore)
    CompositionEnded => (Idle, Ignore)
    Idle => (Idle, ReadValue)
    WaitingForInput(before) => {
      guard !is_composing &&
        before.input_type == after.input_type &&
        before.data == after.data &&
        valid_input(before) &&
        valid_input(after) else {
        return (Idle, ReadValue)
      }
      guard input_operation(before) is Some(operation) else {
        return (Idle, ReadValue)
      }
      let (start, inserted) = match operation {
        Insert(inserted) => (before.selection_start, inserted)
        DeleteBackward =>
          if before.selection_start < before.selection_end {
            (before.selection_start, "")
          } else {
            (after.selection_start, "")
          }
        DeleteForward => (before.selection_start, "")
      }
      let delete_len = before.text_length +
        inserted.length() -
        after.text_length
      guard delete_len >= 0 &&
        start >= 0 &&
        start + delete_len <= before.text_length else {
        return (Idle, ReadValue)
      }
      let selected_len = before.selection_end - before.selection_start
      guard selected_len == 0 || selected_len == delete_len else {
        return (Idle, ReadValue)
      }
      (
        Idle,
        Emit(
          @text_change.TextChange::ReplaceRange(start~, delete_len~, inserted~),
        ),
      )
    }
  }
}

///|
fn decide_composition_end(
  state : InputState,
  ended : CompositionFacts,
  inserted : String,
) -> InputDecision {
  guard state is Composing(start) &&
    valid_composition(start) &&
    valid_composition(ended) else {
    return ReadValue
  }
  if inserted == "" && ended.text_length == start.text_length {
    return Ignore
  }
  let delete_len = start.selection_end - start.selection_start
  guard start.text_length - delete_len + inserted.length() == ended.text_length else {
    return ReadValue
  }
  Emit(
    @text_change.TextChange::ReplaceRange(
      start=start.selection_start,
      delete_len~,
      inserted~,
    ),
  )
}

///|
fn emit_decision(
  decision : InputDecision,
  text_area : @dom.HTMLTextAreaElement,
  on_change : (@text_change.TextChange) -> @cmd.Cmd,
) -> @cmd.Cmd {
  match decision {
    Ignore => @cmd.none
    Emit(change) => on_change(change)
    ReadValue =>
      on_change(@text_change.TextChange::ReplaceAll(text_area.get_value()))
  }
}

///|
/// Add native textarea edit handling to Rabbita attributes.
pub fn TextArea::attach(
  self : TextArea,
  attrs : @html.Attrs,
  on_change : (@text_change.TextChange) -> @cmd.Cmd,
  on_composing : (Bool) -> @cmd.Cmd,
) -> @html.Attrs {
  attrs
  .id(self.id)
  .on_beforeinput(event => {
    let text_area = input_target(event)
    if self.state is Composing(_) || event.is_composing() {
      @cmd.none
    } else if self.state is CompositionEnded &&
      is_composition_input_type(event.input_type()) {
      @cmd.none
    } else {
      self.state = WaitingForInput(input_facts(event, text_area))
      @cmd.none
    }
  })
  .on_input(event => {
    let text_area = input_target(event)
    let (next_state, decision) = decide_input(
      self.state,
      input_facts(event, text_area),
      event.is_composing(),
    )
    self.state = next_state
    emit_decision(decision, text_area, on_change)
  })
  .on_compositionstart(event => {
    let text_area = composition_target(event)
    self.state = Composing(composition_facts(text_area))
    on_composing(true)
  })
  .on_compositionend(event => {
    let text_area = composition_target(event)
    let decision = decide_composition_end(
      self.state,
      composition_facts(text_area),
      event.get_data(),
    )
    self.state = CompositionEnded
    @cmd.batch([
      emit_decision(decision, text_area, on_change),
      on_composing(false),
    ])
  })
}

///|
/// Initialize a newly rendered textarea with Document text.
pub fn TextArea::initialize(
  self : TextArea,
  document_text : String,
) -> @cmd.Cmd {
  self.state = Idle
  @cmd.custom_cmd(
    _ => text_area_by_id(self.id).set_value(document_text),
    kind=@cmd.after_render,
  )
}

///|
/// Read the complete current textarea value.
pub fn TextArea::value(
  self : TextArea,
  on_value : (String) -> @cmd.Cmd,
) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    scheduler.add(on_value(text_area_by_id(self.id).get_value()))
  })
}
