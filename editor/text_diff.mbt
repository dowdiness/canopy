// Text diffing utility for computing parser Edits from the shared
// dowdiness/text_change leaf module.

///|
/// Compute a parser Edit from the difference between old and new text.
pub fn compute_edit(old_text : String, new_text : String) -> @parser.Edit {
  let change = @text_change.compute_text_change(old_text, new_text)
  @parser.Edit::new(change.start, change.delete_len, change.inserted.length())
}

///|
priv enum DiffStep {
  Equal
  Insert
  Delete
}

///|
fn compute_text_edits(
  old_text : String,
  new_text : String,
) -> Array[@loom_core.Edit] {
  if old_text == new_text {
    return []
  }
  let old_chars = old_text.to_array()
  let new_chars = new_text.to_array()
  let prefix_len = find_common_prefix(old_text, new_text)
  let old_suffix_start = prefix_len
  let new_suffix_start = prefix_len
  let old_len = old_chars.length()
  let new_len = new_chars.length()
  let suffix_len = find_common_suffix_after_prefix(
    old_text, new_text, old_suffix_start, new_suffix_start, old_len, new_len,
  )
  let old_mid_len = old_len - prefix_len - suffix_len
  let new_mid_len = new_len - prefix_len - suffix_len
  if old_mid_len == 0 && new_mid_len == 0 {
    return []
  }
  let old_mid = old_chars[prefix_len:old_len - suffix_len].to_array()
  let new_mid = new_chars[prefix_len:new_len - suffix_len].to_array()
  let steps = compute_diff_steps(old_mid, new_mid)
  diff_steps_to_edits(steps, prefix_len)
}

///|
fn compute_diff_steps(
  old_chars : Array[Char],
  new_chars : Array[Char],
) -> Array[DiffStep] {
  let old_len = old_chars.length()
  let new_len = new_chars.length()
  let dp : Array[Array[Int]] = []
  for i = 0; i <= old_len; i = i + 1 {
    let row : Array[Int] = []
    for j = 0; j <= new_len; j = j + 1 {
      row.push(0)
    }
    dp.push(row)
  }
  for i = 1; i <= old_len; i = i + 1 {
    for j = 1; j <= new_len; j = j + 1 {
      if old_chars[i - 1] == new_chars[j - 1] {
        dp[i][j] = dp[i - 1][j - 1] + 1
      } else if dp[i][j - 1] >= dp[i - 1][j] {
        dp[i][j] = dp[i][j - 1]
      } else {
        dp[i][j] = dp[i - 1][j]
      }
    }
  }
  let reversed : Array[DiffStep] = []
  let mut i = old_len
  let mut j = new_len
  while i > 0 || j > 0 {
    if i > 0 && j > 0 && old_chars[i - 1] == new_chars[j - 1] {
      reversed.push(Equal)
      i = i - 1
      j = j - 1
    } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
      reversed.push(Insert)
      j = j - 1
    } else {
      reversed.push(Delete)
      i = i - 1
    }
  }
  let steps : Array[DiffStep] = []
  for idx = reversed.length() - 1; idx >= 0; idx = idx - 1 {
    steps.push(reversed[idx])
  }
  steps
}

///|
fn push_pending_edit(
  edits : Array[@loom_core.Edit],
  pending_start : Int,
  pending_delete_len : Int,
  pending_insert_len : Int,
  has_pending : Bool,
) -> Unit {
  if has_pending {
    edits.push(
      @loom_core.Edit::new(
        pending_start, pending_delete_len, pending_insert_len,
      ),
    )
  }
}

///|
fn diff_steps_to_edits(
  steps : Array[DiffStep],
  start_offset : Int,
) -> Array[@loom_core.Edit] {
  let edits : Array[@loom_core.Edit] = []
  let mut cursor = start_offset
  let mut pending_start = 0
  let mut pending_delete_len = 0
  let mut pending_insert_len = 0
  let mut has_pending = false
  for step in steps {
    match step {
      Equal => {
        push_pending_edit(
          edits, pending_start, pending_delete_len, pending_insert_len, has_pending,
        )
        has_pending = false
        pending_delete_len = 0
        pending_insert_len = 0
        cursor = cursor + 1
      }
      Delete => {
        if not(has_pending) {
          pending_start = cursor
          has_pending = true
        }
        pending_delete_len = pending_delete_len + 1
      }
      Insert => {
        if not(has_pending) {
          pending_start = cursor
          has_pending = true
        }
        pending_insert_len = pending_insert_len + 1
        cursor = cursor + 1
      }
    }
  }
  push_pending_edit(
    edits, pending_start, pending_delete_len, pending_insert_len, has_pending,
  )
  edits
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
