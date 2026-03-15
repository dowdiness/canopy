// Pure contiguous text-change logic shared across crdt, loom, and valtio.
// Keep this module leaf-only: no parser, CRDT, or UI dependencies.

///|
pub(all) struct TextChange {
  start : Int
  delete_len : Int
  inserted : String
} derive(Eq, Show)

///|
/// Compute the minimal contiguous text change between two strings.
pub fn compute_text_change(old_text : String, new_text : String) -> TextChange {
  let old_len = old_text.length()
  let new_len = new_text.length()

  let mut prefix = 0
  while prefix < old_len &&
        prefix < new_len &&
        old_text[prefix] == new_text[prefix] {
    prefix += 1
  }

  let mut suffix = 0
  while suffix < old_len - prefix &&
        suffix < new_len - prefix &&
        old_text[old_len - 1 - suffix] == new_text[new_len - 1 - suffix] {
    suffix += 1
  }

  let delete_len = old_len - prefix - suffix
  let inserted = new_text[prefix:new_len - suffix].to_string()
  { start: prefix, delete_len, inserted }
}

///|
pub fn TextChange::is_noop(self : TextChange) -> Bool {
  self.delete_len == 0 && self.inserted.length() == 0
}
