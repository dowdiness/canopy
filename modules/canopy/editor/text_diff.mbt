// Text diffing utility for computing parser Edits from the shared
// dowdiness/text_change leaf module.

///|
/// Compute a parser Edit from the difference between old and new text.
pub fn compute_edit(old_text : String, new_text : String) -> @loom_core.Edit {
  let change = match fast_append_text_change(old_text, new_text) {
    Some(change) => change
    None => @text_change.compute_text_change(old_text, new_text)
  }
  @loom_core.Edit::new(
    change.start,
    change.delete_len,
    change.inserted.length(),
  )
}

///|
priv enum DiffStep {
  Equal(Int)
  Insert(Int)
  Delete(Int)
}

///|
fn compute_text_edits(
  old_text : String,
  new_text : String,
) -> Array[@loom_core.Edit] {
  if old_text == new_text {
    return []
  }
  let old_boundaries = @moji.grapheme_boundaries(old_text)
  let new_boundaries = @moji.grapheme_boundaries(new_text)
  let prefix_count = find_common_prefix_cluster_count(
    old_text, old_boundaries, new_text, new_boundaries,
  )
  let suffix_count = find_common_suffix_cluster_count(
    old_text, old_boundaries, new_text, new_boundaries, prefix_count,
  )
  let old_cluster_count = old_boundaries.length() - 1
  let new_cluster_count = new_boundaries.length() - 1
  let old_mid_count = old_cluster_count - prefix_count - suffix_count
  let new_mid_count = new_cluster_count - prefix_count - suffix_count
  let start_offset = old_boundaries[prefix_count]
  let old_mid_utf16_len = old_boundaries[prefix_count + old_mid_count] -
    start_offset
  let new_mid_utf16_len = new_boundaries[prefix_count + new_mid_count] -
    new_boundaries[prefix_count]
  let old_cells = old_mid_count + 1
  let new_cells = new_mid_count + 1
  // Preserve separated edits only while the LCS matrix stays bounded.
  // Large changed middles use one grapheme-aligned replacement instead.
  if old_mid_count == 0 || new_mid_count == 0 || old_cells > 65536 / new_cells {
    return [
      @loom_core.Edit::new(start_offset, old_mid_utf16_len, new_mid_utf16_len),
    ]
  }
  let steps = compute_diff_steps(
    old_text, old_boundaries, prefix_count, old_mid_count, new_text, new_boundaries,
    prefix_count, new_mid_count,
  )
  diff_steps_to_edits(steps, start_offset)
}

///|
fn compute_diff_steps(
  old_text : String,
  old_boundaries : Array[Int],
  old_start : Int,
  old_count : Int,
  new_text : String,
  new_boundaries : Array[Int],
  new_start : Int,
  new_count : Int,
) -> Array[DiffStep] {
  let dp : Array[Array[Int]] = []
  for i = 0; i <= old_count; i = i + 1 {
    let row : Array[Int] = []
    for j = 0; j <= new_count; j = j + 1 {
      row.push(0)
    }
    dp.push(row)
  }
  for i = 1; i <= old_count; i = i + 1 {
    for j = 1; j <= new_count; j = j + 1 {
      let old_idx = old_start + i - 1
      let new_idx = new_start + j - 1
      if cluster_equal_at(
          old_text, old_boundaries, old_idx, new_text, new_boundaries, new_idx,
        ) {
        dp[i][j] = dp[i - 1][j - 1] + 1
      } else if dp[i][j - 1] >= dp[i - 1][j] {
        dp[i][j] = dp[i][j - 1]
      } else {
        dp[i][j] = dp[i - 1][j]
      }
    }
  }
  let reversed : Array[DiffStep] = []
  let mut i = old_count
  let mut j = new_count
  while i > 0 || j > 0 {
    let old_idx = old_start + i - 1
    let new_idx = new_start + j - 1
    if i > 0 &&
      j > 0 &&
      cluster_equal_at(
        old_text, old_boundaries, old_idx, new_text, new_boundaries, new_idx,
      ) {
      reversed.push(
        Equal(old_boundaries[old_idx + 1] - old_boundaries[old_idx]),
      )
      i = i - 1
      j = j - 1
    } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
      reversed.push(
        Insert(new_boundaries[new_idx + 1] - new_boundaries[new_idx]),
      )
      j = j - 1
    } else {
      reversed.push(
        Delete(old_boundaries[old_idx + 1] - old_boundaries[old_idx]),
      )
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
  // cursor tracks position in the *new* text. Delete consumes from old
  // text only (no cursor advance); Insert and Equal advance in new text.
  for step in steps {
    match step {
      Equal(width) => {
        push_pending_edit(
          edits, pending_start, pending_delete_len, pending_insert_len, has_pending,
        )
        has_pending = false
        pending_delete_len = 0
        pending_insert_len = 0
        cursor = cursor + width
      }
      Delete(width) => {
        if !has_pending {
          pending_start = cursor
          has_pending = true
        }
        pending_delete_len = pending_delete_len + width
      }
      Insert(width) => {
        if !has_pending {
          pending_start = cursor
          has_pending = true
        }
        pending_insert_len = pending_insert_len + width
        cursor = cursor + width
      }
    }
  }
  push_pending_edit(
    edits, pending_start, pending_delete_len, pending_insert_len, has_pending,
  )
  edits
}

///|
fn cluster_equal_at(
  s1 : String,
  s1_boundaries : Array[Int],
  s1_idx : Int,
  s2 : String,
  s2_boundaries : Array[Int],
  s2_idx : Int,
) -> Bool {
  s1[s1_boundaries[s1_idx]:s1_boundaries[s1_idx + 1]] ==
  s2[s2_boundaries[s2_idx]:s2_boundaries[s2_idx + 1]]
}

///|
fn find_common_prefix_cluster_count(
  s1 : String,
  s1_boundaries : Array[Int],
  s2 : String,
  s2_boundaries : Array[Int],
) -> Int {
  let s1_count = s1_boundaries.length() - 1
  let s2_count = s2_boundaries.length() - 1
  let mut prefix_count = 0
  while prefix_count < s1_count &&
        prefix_count < s2_count &&
        cluster_equal_at(
          s1, s1_boundaries, prefix_count, s2, s2_boundaries, prefix_count,
        ) {
    prefix_count += 1
  }
  prefix_count
}

///|
fn find_common_suffix_cluster_count(
  s1 : String,
  s1_boundaries : Array[Int],
  s2 : String,
  s2_boundaries : Array[Int],
  prefix_count : Int,
) -> Int {
  let s1_count = s1_boundaries.length() - 1
  let s2_count = s2_boundaries.length() - 1
  let mut suffix_count = 0
  while suffix_count < s1_count - prefix_count &&
        suffix_count < s2_count - prefix_count &&
        cluster_equal_at(
          s1,
          s1_boundaries,
          s1_count - suffix_count - 1,
          s2,
          s2_boundaries,
          s2_count - suffix_count - 1,
        ) {
    suffix_count += 1
  }
  suffix_count
}
