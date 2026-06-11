// Message/no-op contract pins for apply_markdown_edit error paths (S3
// lang/runtime migration safety net —
// docs/plans/2026-06-11-s3-lang-runtime-extraction.md Step 3). Expectations
// are frozen; do not regenerate them by calling the migrated path.

///|
test "apply_markdown_edit pin: merge on first block -> silent no-op" {
  // compute_markdown_edit returns Ok(None) for MergeWithPrevious on the
  // first sibling; the companion contract maps that to Ok(()) with the
  // document untouched (markdown's SilentNoOp policy, unlike JSON's error).
  let ed = new_markdown_editor("pin")
  ed.set_text("Hello\n\nWorld\n")
  let first_id = match ed.get_proj_node() {
    Some(p) => p.children[0].id()
    None => {
      fail("expected projection")
      return
    }
  }
  let result = apply_markdown_edit(
    ed,
    MarkdownEditOp::MergeWithPrevious(node_id=first_id),
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
  let donor = new_markdown_editor("donor")
  donor.set_text("A\n\nB\n\nC\n\nD\n")
  let absent_id = match donor.get_proj_node() {
    Some(p) => p.children[p.children.length() - 1].id()
    None => {
      fail("donor: expected projection")
      return
    }
  }
  let ed = new_markdown_editor("target")
  ed.set_text("Hello\n")
  match
    apply_markdown_edit(
      ed,
      MarkdownEditOp::MergeWithPrevious(node_id=absent_id),
      0,
    ) {
    Err(msg) =>
      inspect(
        msg,
        content=(
          #|node not found in projection tree: NodeId(3)
        ),
      )
    Ok(_) => fail("expected Err for absent node id")
  }
}
