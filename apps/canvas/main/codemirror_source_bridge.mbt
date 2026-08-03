///|
/// Bridge from CodeMirror change deltas to sequential loom source edits.
///
/// CodeMirror delivers every replaced range of a single transaction in the
/// coordinates of the document *before* that transaction. Loom's
/// `GraphAttachment::apply_edit` instead expects a sequence of edits, each
/// expressed against the document as it stands immediately before that one
/// edit, paired with the full source text the edit produces. This module
/// performs that translation so a multi-change transaction reaches the source
/// store as ordered, individually-applicable `@core.Edit`s.

///|
/// Translate an ordered batch of CodeMirror changes into the sequence of
/// `(@core.Edit, new_source)` pairs that reproduce the same final document
/// when applied left to right.
fn changes_to_edits(
  base_doc : String,
  changes : Array[@codemirror.ChangeDelta],
) -> Array[(@core.Edit, String)] {
  let edits = []
  let mut source = base_doc
  // Running shift between pre-transaction coordinates (what CodeMirror reports)
  // and the evolving document: every applied change moves later offsets by
  // `new_len - old_len`. CodeMirror yields changes ascending and
  // non-overlapping, so accumulating the shift left to right is sufficient.
  let mut shift = 0
  for change in changes {
    let start = change.from + shift
    let old_len = change.to - change.from
    let new_len = change.insert.length()
    source = splice_code_units(source, start, old_len, change.insert)
    edits.push((@core.Edit::new(start, old_len, new_len), source))
    shift += new_len - old_len
  }
  edits
}

///|
/// Replace `[start, start + old_len)` of `source` with `insert`, indexing in
/// UTF-16 code units to match CodeMirror and loom edit coordinates.
fn splice_code_units(
  source : String,
  start : Int,
  old_len : Int,
  insert : String,
) -> String {
  source.view(end_offset=start).to_owned() +
  insert +
  source.view(start_offset=start + old_len).to_owned()
}
