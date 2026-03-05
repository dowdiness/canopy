// Edit Bridge: converts (old_text, new_text) pairs to Array[Edit]
// for the incremental parser, using loom's TextDelta API.
//
// This is the fallback path for batch remote merges (Design §1).
// The direct Op → Edit path (O(1)) will be added in a later phase
// once event-graph-walker/text exposes lv_to_position and insert_with_op.

///|
/// Convert an (old_text, new_text) pair into parser Edits using loom's
/// TextDelta API instead of a bespoke string diff.
///
/// Returns an empty array when old == new (no edit needed).
/// Returns exactly one Edit for any single contiguous change (the common case
/// for both local keystrokes and batch remote merges).
pub fn merge_to_edits(
  old_text : String,
  new_text : String,
) -> Array[@loom_core.Edit] {
  @loom_core.to_edits(@loom_core.text_to_delta(old_text, new_text))
}
