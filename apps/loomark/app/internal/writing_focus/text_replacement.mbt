///|
pub struct LineReplacement {
  text_lines : TextLines
  first : Int
  removed : Int
  inserted : ArrayView[String]
}

///|
// Native string equality compares chunks without a JS loop over each UTF-16 unit.
fn common_prefix_length(before : String, after : String, limit : Int) -> Int {
  for matched = 0, upper_bound = limit; matched < upper_bound; {
    let candidate = matched + (upper_bound - matched + 1) / 2
    if before.unsafe_substring(start=matched, end=candidate) ==
      after.unsafe_substring(start=matched, end=candidate) {
      continue candidate, upper_bound
    }
    continue matched, candidate - 1
  } nobreak {
    matched
  }
}

///|
fn common_suffix_length(before : String, after : String, limit : Int) -> Int {
  for matched = 0, upper_bound = limit; matched < upper_bound; {
    let candidate = matched + (upper_bound - matched + 1) / 2
    if before.unsafe_substring(
        start=before.length() - candidate,
        end=before.length() - matched,
      ) ==
      after.unsafe_substring(
        start=after.length() - candidate,
        end=after.length() - matched,
      ) {
      continue candidate, upper_bound
    }
    continue matched, candidate - 1
  } nobreak {
    matched
  }
}

///|
fn replacement_bounds(before : String, after : String) -> (Int, Int, Int) {
  let shared_length = if before.length() < after.length() {
    before.length()
  } else {
    after.length()
  }
  let start = common_prefix_length(before, after, shared_length)
  let suffix = common_suffix_length(before, after, shared_length - start)
  (start, before.length() - suffix, after.length() - suffix)
}

///|
/// Returns a new index without changing `self`; unchanged text returns `None`.
pub fn TextLines::replace_text(
  self : TextLines,
  text : String,
) -> LineReplacement? {
  if text == self.text {
    return None
  }
  let (start, old_end, new_end) = replacement_bounds(self.text, text)
  let first = self.line_at(start)
  let last = self.line_at(old_end)
  // Native selection and edit offsets may split UTF-16 surrogate pairs.
  let replacement = self.lines[first].unsafe_substring(
      start=0,
      end=start - self.starts[first],
    ) +
    text.unsafe_substring(start~, end=new_end) +
    self.lines[last].unsafe_substring(
      start=old_end - self.starts[last],
      end=self.lines[last].length(),
    )
  let inserted = replacement.split("\n").map(line => line.to_owned()).to_array()
  let removed = last - first + 1
  let line_count = self.lines.length() - removed + inserted.length()
  let lines = Array::makei(line_count, index => {
    if index < first {
      self.lines[index]
    } else if index < first + inserted.length() {
      inserted[index - first]
    } else {
      self.lines[index - inserted.length() + removed]
    }
  })
  Some({
    text_lines: index_lines(text, lines[:]),
    first,
    removed,
    inserted: lines[first:first + inserted.length()],
  })
}
