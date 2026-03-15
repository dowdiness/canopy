// Shared text-change adapter for contiguous edits.
// Debt rule: if another root package needs old/new text diffing, extend this
// package instead of re-implementing prefix/suffix scans locally.

///|
pub struct TextChange {
  start : Int
  delete_len : Int
  inserted : String
} derive(Eq, Show)

///|
fn text_change_from_deltas(deltas : Array[@loom_core.TextDelta]) -> TextChange {
  let mut start = 0
  let mut delete_len = 0
  let mut inserted = ""
  let mut seen_change = false
  for delta in deltas {
    match delta {
      @loom_core.TextDelta::Retain(n) => if not(seen_change) { start += n }
      @loom_core.TextDelta::Delete(n) => {
        delete_len += n
        seen_change = true
      }
      @loom_core.TextDelta::Insert(text) => {
        inserted = inserted + text
        seen_change = true
      }
    }
  }
  { start, delete_len, inserted }
}

///|
/// Compute the minimal contiguous text change between two strings.
pub fn compute_text_change(old_text : String, new_text : String) -> TextChange {
  text_change_from_deltas(@loom_core.text_to_delta(old_text, new_text))
}

///|
pub fn TextChange::is_noop(self : TextChange) -> Bool {
  self.delete_len == 0 && self.inserted == ""
}

///|
pub fn TextChange::to_parser_edit(self : TextChange) -> @loom_core.Edit {
  @loom_core.Edit::new(self.start, self.delete_len, self.inserted.length())
}
