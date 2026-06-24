// Message-contract pins for apply_json_edit error paths (S3 lang/runtime
// migration safety net — docs/plans/2026-06-11-s3-lang-runtime-extraction.md
// Step 2). Expectations are frozen string literals; do not regenerate them
// by calling the migrated path.

// Note: the bridge's "no projection available" guard and the
// "unhandled edit op" policy branch are unreachable through the JSON surface
// (an empty JSON doc still yields a recovered projection root, and every
// JsonEditOp is handled). Those two messages are pinned in lang/runtime's
// own tests against a stubbed None projection / Ok(None) compute.

///|
test "apply_json_edit message pin: unwrap root scalar -> compute error" {
  let editor = new_json_editor("target")
  editor.set_text("42")
  let root_id = match editor.get_proj_node() {
    Some(p) => p.id()
    None => {
      fail("expected projection")
      return
    }
  }
  match apply_json_edit(editor, JsonEditOp::Unwrap(node_id=root_id), 0) {
    Err(msg) =>
      inspect(
        msg,
        content=(
          #|unwrap requires exactly one child, found 0
        ),
      )
    Ok(_) => fail("expected Err for unwrap on root scalar")
  }
}

///|
test "apply_json_edit message pin: absent node id -> compute error" {
  // Take a high child id from a donor with many nodes, then apply against a
  // single-scalar editor whose id space cannot contain it.
  let donor = new_json_editor("donor")
  donor.set_text("{\"a\": 1, \"b\": 2, \"c\": 3}")
  let absent_id = match donor.get_proj_node() {
    Some(p) => p.children[p.children.length() - 1].id()
    None => {
      fail("donor: expected projection")
      return
    }
  }
  let editor = new_json_editor("target")
  editor.set_text("42")
  match apply_json_edit(editor, JsonEditOp::Delete(node_id=absent_id), 0) {
    Err(msg) =>
      inspect(
        msg,
        content=(
          #|node not found in source map
        ),
      )
    Ok(_) => fail("expected Err for absent node id")
  }
}
