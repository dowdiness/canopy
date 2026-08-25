///|
fn observation(
  input_type : String,
  data : String?,
  start : Int,
  end : Int,
  length : Int,
) -> InputObservation {
  before_input(
    input_type~,
    data~,
    composing=false,
    selection_start=start,
    selection_end=end,
    value_length=length,
  )
}

///|
fn after_observation(
  input_type : String,
  data : String?,
  start : Int,
  end : Int,
  length : Int,
) -> InputObservation {
  after_input(
    input_type~,
    data~,
    composing=false,
    selection_start=start,
    selection_end=end,
    value_length=length,
  )
}

///|
test "insertText resolves the pre-edit UTF-16 selection without complete text" {
  debug_inspect(
    resolve(
      "ab",
      observation("insertText", Some("X"), 1, 1, 2),
      after_observation("insertText", Some("X"), 2, 2, 3),
    ),
    content="Accepted({ start: 1, delete_len: 0, inserted: \"X\" }, \"aXb\")",
  )
}

///|
test "selection replacement uses the exact pre-edit range" {
  debug_inspect(
    resolve(
      "aBCd",
      observation("insertText", Some("x"), 1, 3, 4),
      after_observation("insertText", Some("x"), 2, 2, 3),
    ),
    content="Accepted({ start: 1, delete_len: 2, inserted: \"x\" }, \"axd\")",
  )
}

///|
test "collapsed backward deletion derives its range from post-edit selection" {
  debug_inspect(
    resolve(
      "abc",
      observation("deleteContentBackward", None, 2, 2, 3),
      after_observation("deleteContentBackward", None, 1, 1, 2),
    ),
    content="Accepted({ start: 1, delete_len: 1, inserted: \"\" }, \"ac\")",
  )
}

///|
test "collapsed forward deletion uses pre-edit start and the length delta" {
  debug_inspect(
    resolve(
      "abc",
      observation("deleteContentForward", None, 1, 1, 3),
      after_observation("deleteContentForward", None, 1, 1, 2),
    ),
    content="Accepted({ start: 1, delete_len: 1, inserted: \"\" }, \"ac\")",
  )
}

///|
test "line break supplies normalized LF when InputEvent data is null" {
  debug_inspect(
    resolve(
      "ab",
      observation("insertLineBreak", None, 1, 1, 2),
      after_observation("insertLineBreak", None, 2, 2, 3),
    ),
    content="Accepted({ start: 1, delete_len: 0, inserted: \"\\n\" }, \"a\\nb\")",
  )
}

///|
test "composition commits once from its initial selection" {
  let started = composition_start(
    selection_start=1,
    selection_end=2,
    value_length=3,
  )
  let ended = composition_end(
    data="日本",
    selection_start=3,
    selection_end=3,
    value_length=4,
  )
  debug_inspect(
    resolve_composition("abc", started, ended),
    content="Accepted({ start: 1, delete_len: 1, inserted: \"日本\" }, \"a日本c\")",
  )
}

///|
test "cancelled composition preserves the accepted Document text" {
  let started = composition_start(
    selection_start=1,
    selection_end=2,
    value_length=3,
  )
  let ended = composition_end(
    data="",
    selection_start=1,
    selection_end=2,
    value_length=3,
  )
  debug_inspect(
    resolve_composition("abc", started, ended),
    content="IgnoreComposition",
  )
}

///|
test "surrogate-splitting browser ranges require explicit recovery" {
  debug_inspect(
    resolve(
      "A🤣B",
      observation("insertText", Some("x"), 2, 2, 4),
      after_observation("insertText", Some("x"), 3, 3, 5),
    ),
    content="Recover(InvalidUtf16Range)",
  )
}

///|
test "history operations require explicit whole-value recovery" {
  debug_inspect(
    resolve(
      "abc",
      observation("historyUndo", None, 3, 3, 3),
      after_observation("historyUndo", None, 0, 0, 0),
    ),
    content="Recover(UnsupportedInputType(\"historyUndo\"))",
  )
}
