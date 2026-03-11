// Text diffing utilities for computing Edit objects from text changes
// Used to convert CRDT text updates into incremental parser Edit operations

///|
pub struct TextSplice {
  start : Int
  delete_len : Int
  inserted : String
} derive(Eq, Show)

///|
/// Compute the minimal single-span splice between two strings.
pub fn compute_text_splice(old_text : String, new_text : String) -> TextSplice {
  let prefix_len = find_common_prefix(old_text, new_text)
  let old_suffix_start = prefix_len
  let new_suffix_start = prefix_len
  let old_len = old_text.length()
  let new_len = new_text.length()
  let suffix_len = find_common_suffix_after_prefix(
    old_text, new_text, old_suffix_start, new_suffix_start, old_len, new_len,
  )
  let old_end = old_len - suffix_len
  let inserted_end = new_len - suffix_len
  {
    start: prefix_len,
    delete_len: old_end - prefix_len,
    inserted: new_text[prefix_len:inserted_end].to_string(),
  }
}

///|
/// Compute an Edit from the difference between old and new text
/// Uses longest common prefix/suffix algorithm for efficient diff
pub fn compute_edit(old_text : String, new_text : String) -> @parser.Edit {
  let splice = compute_text_splice(old_text, new_text)
  @parser.Edit::new(splice.start, splice.delete_len, splice.inserted.length())
}

///|
/// Find the length of the longest common prefix between two strings
fn find_common_prefix(s1 : String, s2 : String) -> Int {
  let mut i = 0
  let min_len = if s1.length() < s2.length() {
    s1.length()
  } else {
    s2.length()
  }
  while i < min_len && s1[i] == s2[i] {
    i = i + 1
  }
  i
}

///|
/// Find the length of the longest common suffix after a given prefix position
/// This avoids double-counting characters in both prefix and suffix
fn find_common_suffix_after_prefix(
  s1 : String,
  s2 : String,
  s1_start : Int,
  s2_start : Int,
  s1_len : Int,
  s2_len : Int,
) -> Int {
  let mut i = 0
  let s1_remaining = s1_len - s1_start
  let s2_remaining = s2_len - s2_start
  let min_remaining = if s1_remaining < s2_remaining {
    s1_remaining
  } else {
    s2_remaining
  }
  while i < min_remaining && s1[s1_len - 1 - i] == s2[s2_len - 1 - i] {
    i = i + 1
  }
  i
}
