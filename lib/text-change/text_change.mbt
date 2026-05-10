// Pure contiguous text-change logic shared across crdt, loom, and valtio.
// Keep this module leaf-only: no parser, CRDT, or UI dependencies.

///|
pub(all) struct TextChange {
  start : Int
  delete_len : Int
  inserted : String
} derive(Eq, Debug)

///|
fn cluster_equal(
  old_text : String,
  old_start : Int,
  old_end : Int,
  new_text : String,
  new_start : Int,
  new_end : Int,
) -> Bool {
  old_text[old_start:old_end].to_owned() ==
  new_text[new_start:new_end].to_owned()
}

///|
fn common_prefix_len(old_text : String, new_text : String) -> Int {
  let old_boundaries = @moji.grapheme_boundaries(old_text)
  let new_boundaries = @moji.grapheme_boundaries(new_text)
  let mut idx = 0
  let mut prefix = 0
  while idx + 1 < old_boundaries.length() && idx + 1 < new_boundaries.length() {
    let old_start = old_boundaries[idx]
    let old_end = old_boundaries[idx + 1]
    let new_start = new_boundaries[idx]
    let new_end = new_boundaries[idx + 1]
    if cluster_equal(old_text, old_start, old_end, new_text, new_start, new_end) {
      prefix = old_end
      idx += 1
    } else {
      break
    }
  }
  prefix
}

///|
fn common_suffix_lens(
  old_text : String,
  new_text : String,
  prefix_len : Int,
) -> (Int, Int) {
  let old_boundaries = @moji.grapheme_boundaries(old_text)
  let new_boundaries = @moji.grapheme_boundaries(new_text)
  let mut old_idx = old_boundaries.length() - 1
  let mut new_idx = new_boundaries.length() - 1
  let mut old_suffix_len = 0
  let mut new_suffix_len = 0
  while old_idx > 0 && new_idx > 0 {
    let old_start = old_boundaries[old_idx - 1]
    let old_end = old_boundaries[old_idx]
    let new_start = new_boundaries[new_idx - 1]
    let new_end = new_boundaries[new_idx]
    if old_start < prefix_len || new_start < prefix_len {
      break
    }
    if cluster_equal(old_text, old_start, old_end, new_text, new_start, new_end) {
      old_suffix_len += old_end - old_start
      new_suffix_len += new_end - new_start
      old_idx -= 1
      new_idx -= 1
    } else {
      break
    }
  }
  (old_suffix_len, new_suffix_len)
}

///|
/// Compute the minimal contiguous text change between two strings.
pub fn compute_text_change(old_text : String, new_text : String) -> TextChange {
  let old_len = old_text.length()
  let new_len = new_text.length()

  let prefix = common_prefix_len(old_text, new_text)
  let (old_suffix_len, new_suffix_len) = common_suffix_lens(
    old_text, new_text, prefix,
  )

  let delete_len = old_len - prefix - old_suffix_len
  let inserted = new_text[prefix:new_len - new_suffix_len].to_owned()
  { start: prefix, delete_len, inserted }
}

///|
pub fn TextChange::is_noop(self : TextChange) -> Bool {
  self.delete_len == 0 && self.inserted.length() == 0
}
