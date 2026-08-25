///|
extern "js" fn input_data(event : @dom.InputEvent) -> @js.Nullable[String] =
  #| (event) => event.data

///|
extern "js" fn input_selection_start(event : @dom.InputEvent) -> Int =
  #| (event) => event.currentTarget?.selectionStart ?? -1

///|
extern "js" fn input_selection_end(event : @dom.InputEvent) -> Int =
  #| (event) => event.currentTarget?.selectionEnd ?? -1

///|
extern "js" fn input_value_length(event : @dom.InputEvent) -> Int =
  #| (event) => event.currentTarget?.textLength ?? -1

///|
extern "js" fn composition_selection_start(
  event : @dom.CompositionEvent,
) -> Int =
  #| (event) => event.currentTarget?.selectionStart ?? -1

///|
extern "js" fn composition_selection_end(event : @dom.CompositionEvent) -> Int =
  #| (event) => event.currentTarget?.selectionEnd ?? -1

///|
extern "js" fn composition_value_length(event : @dom.CompositionEvent) -> Int =
  #| (event) => event.currentTarget?.textLength ?? -1

///|
extern "js" fn install_textarea_value(id : String, text : String) -> Unit =
  #| (id, text) => {
  #|   const textarea = document.getElementById(id);
  #|   if (!(textarea instanceof HTMLTextAreaElement)) {
  #|     throw new Error(`textarea not found: ${id}`);
  #|   }
  #|   textarea.value = text;
  #| }

///|
extern "js" fn read_textarea_value(id : String) -> @js.Nullable[String] =
  #| (id) => {
  #|   const textarea = document.getElementById(id);
  #|   return textarea instanceof HTMLTextAreaElement ? textarea.value : null;
  #| }

///|
let pending_before_input : Ref[@text_edit.InputObservation?] = Ref(None)

///|
let pending_composition_start : Ref[@text_edit.InputObservation?] = Ref(None)

///|
pub fn capture_before_input(
  event : @dom.InputEvent,
) -> @text_edit.InputObservation {
  let observation = @text_edit.before_input(
    input_type=event.input_type(),
    data=input_data(event).to_option(),
    composing=event.is_composing(),
    selection_start=input_selection_start(event),
    selection_end=input_selection_end(event),
    value_length=input_value_length(event),
  )
  pending_before_input.val = Some(observation)
  observation
}

///|
pub fn capture_input(
  event : @dom.InputEvent,
) -> (@text_edit.InputObservation?, @text_edit.InputObservation) {
  let before = pending_before_input.val
  pending_before_input.val = None
  let after = @text_edit.after_input(
    input_type=event.input_type(),
    data=input_data(event).to_option(),
    composing=event.is_composing(),
    selection_start=input_selection_start(event),
    selection_end=input_selection_end(event),
    value_length=input_value_length(event),
  )
  (before, after)
}

///|
pub fn capture_composition_start(
  event : @dom.CompositionEvent,
) -> @text_edit.InputObservation {
  let observation = @text_edit.composition_start(
    selection_start=composition_selection_start(event),
    selection_end=composition_selection_end(event),
    value_length=composition_value_length(event),
  )
  pending_composition_start.val = Some(observation)
  observation
}

///|
pub fn capture_composition_end(
  event : @dom.CompositionEvent,
) -> (@text_edit.InputObservation?, @text_edit.InputObservation) {
  let started = pending_composition_start.val
  pending_composition_start.val = None
  let ended = @text_edit.composition_end(
    data=event.get_data(),
    selection_start=composition_selection_start(event),
    selection_end=composition_selection_end(event),
    value_length=composition_value_length(event),
  )
  (started, ended)
}

///|
/// Install complete Document text only at an explicit surface boundary.
pub fn install(id : String, text : String) -> @cmd.Cmd {
  @cmd.custom_cmd(
    _ => {
      pending_before_input.val = None
      pending_composition_start.val = None
      install_textarea_value(id, text)
    },
    kind=@cmd.after_render,
  )
}

///|
/// Read complete browser text only for an explicitly named recovery.
pub fn read(id : String, result~ : @cmd.Emit[String?]) -> @cmd.Cmd {
  @cmd.custom_cmd(scheduler => {
    scheduler.add(result(read_textarea_value(id).to_option()))
  })
}
