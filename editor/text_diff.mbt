// Text diffing utilities for computing Edit objects from text changes.
// Keep this file as a parser-facing adapter only; shared diff logic belongs in
// dowdiness/crdt/text_change rather than another local implementation.

///|
pub struct TextSplice {
  start : Int
  delete_len : Int
  inserted : String
} derive(Eq, Show)

///|
/// Compute the minimal single-span splice between two strings.
pub fn compute_text_splice(old_text : String, new_text : String) -> TextSplice {
  let change = @text_change.compute_text_change(old_text, new_text)
  {
    start: change.start,
    delete_len: change.delete_len,
    inserted: change.inserted,
  }
}

///|
/// Compute an Edit from the difference between old and new text
/// using the shared text_change adapter.
pub fn compute_edit(old_text : String, new_text : String) -> @parser.Edit {
  @text_change.compute_text_change(old_text, new_text).to_parser_edit()
}
