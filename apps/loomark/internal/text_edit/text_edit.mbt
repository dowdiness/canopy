///|
pub struct InputObservation {
  priv input_type : String
  priv data : String?
  priv composing : Bool
  priv selection_start : Int
  priv selection_end : Int
  priv value_length : Int
} derive(Eq, Debug)

///|
pub enum RecoveryReason {
  MissingBeforeInput
  UnsupportedInputType(String)
  InconsistentInput
  InvalidUtf16Range
} derive(Eq, Debug)

///|
pub enum Resolution {
  Accepted(@text_change.TextChange, String)
  IgnoreComposition
  Recover(RecoveryReason)
} derive(Eq, Debug)

///|
priv enum InputOperation {
  Insert(String)
  DeleteBackward
  DeleteForward
}

///|
pub fn before_input(
  input_type~ : String,
  data~ : String?,
  composing~ : Bool,
  selection_start~ : Int,
  selection_end~ : Int,
  value_length~ : Int,
) -> InputObservation {
  { input_type, data, composing, selection_start, selection_end, value_length }
}

///|
pub fn after_input(
  input_type~ : String,
  data~ : String?,
  composing~ : Bool,
  selection_start~ : Int,
  selection_end~ : Int,
  value_length~ : Int,
) -> InputObservation {
  { input_type, data, composing, selection_start, selection_end, value_length }
}

///|
pub fn composition_start(
  selection_start~ : Int,
  selection_end~ : Int,
  value_length~ : Int,
) -> InputObservation {
  before_input(
    input_type="compositionstart",
    data=None,
    composing=true,
    selection_start~,
    selection_end~,
    value_length~,
  )
}

///|
pub fn composition_end(
  data~ : String,
  selection_start~ : Int,
  selection_end~ : Int,
  value_length~ : Int,
) -> InputObservation {
  after_input(
    input_type="compositionend",
    data=Some(data),
    composing=false,
    selection_start~,
    selection_end~,
    value_length~,
  )
}

///|
pub fn InputObservation::input_type(self : InputObservation) -> String {
  self.input_type
}

///|
pub fn missing_before_input() -> RecoveryReason {
  MissingBeforeInput
}

///|
pub fn RecoveryReason::label(self : RecoveryReason) -> String {
  match self {
    MissingBeforeInput => "missing-beforeinput"
    UnsupportedInputType(input_type) => "unsupported-input-type:" + input_type
    InconsistentInput => "inconsistent-input-facts"
    InvalidUtf16Range => "invalid-utf16-range"
  }
}

///|
fn apply_change(source : String, change : @text_change.TextChange) -> String? {
  let removed_end = change.start + change.delete_len
  guard source.get_view(end=change.start) is Some(prefix) else { return None }
  guard source.get_view(start=removed_end) is Some(suffix) else { return None }
  let builder = StringBuilder(
    size_hint=source.length() - change.delete_len + change.inserted.length(),
  )
  builder
  ..write_stringview(prefix)
  ..write_string(change.inserted)
  .write_stringview(suffix)
  Some(builder.to_string())
}

///|
fn input_operation(observation : InputObservation) -> InputOperation? {
  match observation.input_type {
    "insertText"
    | "insertReplacementText"
    | "insertFromPaste"
    | "insertFromPasteAsQuotation"
    | "insertFromDrop"
    | "insertTranspose" => observation.data.map(data => Insert(data))
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
fn valid_observation(observation : InputObservation) -> Bool {
  observation.selection_start >= 0 &&
  observation.selection_start <= observation.selection_end &&
  observation.selection_end <= observation.value_length
}

///|
pub fn resolve(
  source : String,
  before : InputObservation,
  after : InputObservation,
) -> Resolution {
  guard !before.composing && !after.composing else { return IgnoreComposition }
  guard before.input_type == after.input_type &&
    before.value_length == source.length() &&
    valid_observation(before) &&
    valid_observation(after) else {
    return Recover(InconsistentInput)
  }
  guard input_operation(before) is Some(operation) else {
    return Recover(UnsupportedInputType(before.input_type))
  }
  let (start, inserted) = match operation {
    Insert(inserted) => (before.selection_start, inserted)
    DeleteBackward =>
      (
        if before.selection_start < before.selection_end {
          before.selection_start
        } else {
          after.selection_start
        },
        "",
      )
    DeleteForward => (before.selection_start, "")
  }
  let delete_len = source.length() + inserted.length() - after.value_length
  guard delete_len >= 0 else { return Recover(InconsistentInput) }
  let expected_delete_len = before.selection_end - before.selection_start
  guard expected_delete_len == 0 || expected_delete_len == delete_len else {
    return Recover(InconsistentInput)
  }
  let change : @text_change.TextChange = { start, delete_len, inserted }
  guard apply_change(source, change) is Some(next) else {
    return Recover(InvalidUtf16Range)
  }
  guard next.length() == after.value_length else {
    return Recover(InconsistentInput)
  }
  Accepted(change, next)
}

///|
pub fn resolve_composition(
  source : String,
  started : InputObservation,
  ended : InputObservation,
) -> Resolution {
  guard started.input_type == "compositionstart" &&
    ended.input_type == "compositionend" &&
    started.value_length == source.length() &&
    valid_observation(started) &&
    valid_observation(ended) &&
    ended.data is Some(inserted) else {
    return Recover(InconsistentInput)
  }
  guard inserted != "" || ended.value_length != source.length() else {
    return IgnoreComposition
  }
  let change : @text_change.TextChange = {
    start: started.selection_start,
    delete_len: started.selection_end - started.selection_start,
    inserted,
  }
  guard apply_change(source, change) is Some(next) else {
    return Recover(InvalidUtf16Range)
  }
  guard next.length() == ended.value_length else {
    return Recover(InconsistentInput)
  }
  Accepted(change, next)
}
