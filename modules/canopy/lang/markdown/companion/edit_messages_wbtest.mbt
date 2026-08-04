// Message/no-op contract pins for apply_markdown_edit error paths (S3
// lang/runtime migration safety net —
// docs/plans/2026-06-11-s3-lang-runtime-extraction.md Step 3). Expectations
// are frozen; do not regenerate them by calling the migrated path.

///|
test "apply_markdown_edit pin: merge on first block -> silent no-op" {
  // compute_markdown_edit returns Ok(None) for MergeWithPrevious on the
  // first sibling; markdown's on_no_edit maps that to Ok(()) with the
  // document untouched (unlike JSON, which reports an unhandled-op error).
  let ed = try! new_markdown_editor("pin")
  ed.set_text("Hello\n\nWorld\n")
  guard ed.get_proj_node() is Some(p) && p.children is [first, ..] else {
    fail("expected projection with children")
  }
  let result = apply_markdown_edit(
    ed,
    MarkdownEditOp::MergeWithPrevious(node_id=first.id()),
    0,
  )
  inspect(result is Ok(_), content="true")
  // Non-vacuity: the no-op must leave the document byte-identical.
  inspect(
    ed.get_text(),
    content=(
      #|Hello
      #|
      #|World
      #|
    ),
  )
}

///|
test "apply_markdown_edit pin: absent node id -> compute error" {
  // High child id from a donor doc with more blocks than the target has.
  let donor = try! new_markdown_editor("donor")
  donor.set_text("A\n\nB\n\nC\n\nD\n")
  guard donor.get_proj_node() is Some(p) && p.children is [.., last] else {
    fail("donor: expected projection with children")
  }
  let ed = try! new_markdown_editor("target")
  ed.set_text("Hello\n")
  match
    apply_markdown_edit(
      ed,
      MarkdownEditOp::MergeWithPrevious(node_id=last.id()),
      0,
    ) {
    Err(msg) =>
      inspect(
        msg,
        content=(
          #|compute_markdown_edit: node NodeId(3) not found
        ),
      )
    Ok(_) => fail("expected Err for absent node id")
  }
}
