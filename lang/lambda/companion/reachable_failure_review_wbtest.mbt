// Behavioral boundary matrix:
// syntax: lambda binder/reference rename; terminator: in-memory SpanEdit;
// operation: pure report and delegated editor edit; ownership: agent-host report.
// Cases: introduced (binder rename), resolved (reference rename), position-only
// shift, identical rebuild, and detached output/input collections.

///|
fn review_attribution() -> ReachableFailureAttribution {
  { producer: "agent", edit_id: "edit-42", summary: "rename a reference" }
}

///|
fn failure(name : String, start : Int) -> @lambda_scope.ReachableFailure {
  {
    name,
    location: Some({ start, end: start + 1 }),
    witness: [@lambda_scope.ScopeId(0)],
  }
}

///|
test "reachable failure review introduces a failure when a binder rename frees its reference" {
  let report = build_reachable_failure_review(
    review_attribution(),
    [{ start: 1, delete_len: 1, inserted: "z" }],
    [],
    [failure("x", 7)],
  )
  let diff = report.diff()
  inspect(diff.newly_reachable.length(), content="1")
  inspect(diff.newly_reachable[0].name, content="x")
  inspect(diff.newly_reachable[0].location is Some(_), content="true")
  inspect(diff.newly_reachable[0].witness.is_empty(), content="false")
  inspect(report.attribution().producer, content="agent")
  inspect(report.edits()[0].inserted, content="z")
}

///|
test "reachable failure review resolves a renamed reference" {
  let report = build_reachable_failure_review(
    review_attribution(),
    [{ start: 7, delete_len: 1, inserted: "x" }],
    [failure("y", 7)],
    [],
  )
  let diff = report.diff()
  inspect(diff.newly_reachable.length(), content="0")
  inspect(diff.resolved.length(), content="1")
  inspect(diff.resolved[0].name, content="y")
}

///|
test "reachable failure review remaps a position-only shift to an empty diff" {
  let report = build_reachable_failure_review(
    review_attribution(),
    [{ start: 0, delete_len: 0, inserted: "let w = 0\n" }],
    [failure("y", 3)],
    [failure("y", 13)],
  )
  let diff = report.diff()
  inspect(diff.newly_reachable.length(), content="0")
  inspect(diff.resolved.length(), content="0")
}

///|
test "reachable failure review is empty for an identical rebuild" {
  let report = build_reachable_failure_review(
    review_attribution(),
    [],
    [failure("x", 3)],
    [failure("x", 3)],
  )
  let diff = report.diff()
  inspect(diff.newly_reachable.length(), content="0")
  inspect(diff.resolved.length(), content="0")
}

///|
test "reachable failure review detaches input and accessor collections" {
  let edits : Array[@core.SpanEdit] = [
    { start: 0, delete_len: 0, inserted: "a" },
  ]
  let witness = [@lambda_scope.ScopeId(1)]
  let scoped_failure : @lambda_scope.ReachableFailure = {
    name: "x",
    location: Some({ start: 2, end: 3 }),
    witness,
  }
  let after = [scoped_failure]
  let report = build_reachable_failure_review(
    review_attribution(),
    edits,
    [],
    after,
  )
  edits.push({ start: 1, delete_len: 0, inserted: "b" })
  witness.push(@lambda_scope.ScopeId(2))
  let first_edits = report.edits()
  first_edits.push({ start: 2, delete_len: 0, inserted: "c" })
  let first_diff = report.diff()
  first_diff.newly_reachable[0].witness.push(@lambda_scope.ScopeId(3))
  inspect(report.edits().length(), content="1")
  inspect(report.diff().newly_reachable[0].witness.length(), content="1")
}

///|
test "reviewing CommitEdit recomputes scope failures after the delegated edit" {
  let (editor, companion) = try! new_lambda_editor("reachable-review")
  editor.set_text("(x) => x")
  let reference_id = match editor.get_proj_node() {
    Some(root) => root.children[0].id()
    None => fail("expected lambda projection")
  }
  let report = apply_lambda_tree_edit_with_reachable_failure_review(
    editor,
    companion,
    @lambda_edits.TreeEditOp::CommitEdit(node_id=reference_id, new_value="y"),
    1,
    review_attribution(),
  ).unwrap()
  inspect(editor.get_text(), content="(x) =>y")
  inspect(report.attribution().edit_id, content="edit-42")
  let diff = report.diff()
  inspect(diff.resolved.length(), content="0")
  inspect(diff.newly_reachable.length(), content="1")
  inspect(diff.newly_reachable[0].name, content="y")
  inspect(diff.newly_reachable[0].location is Some(_), content="true")
  inspect(diff.newly_reachable[0].witness.is_empty(), content="false")
  inspect(report.edits().length() > 0, content="true")
}

///|
test "review wrapper retains the exact SpanEdit batch from the ordinary edit boundary" {
  let (control, control_companion) = try! new_lambda_editor("reachable-control")
  control.set_text("(x) => x")
  let control_reference = match control.get_proj_node() {
    Some(root) => root.children[0].id()
    None => fail("expected control lambda projection")
  }
  let expected = apply_lambda_tree_edit(
    control,
    control_companion,
    @lambda_edits.TreeEditOp::CommitEdit(
      node_id=control_reference,
      new_value="y",
    ),
    1,
  ).unwrap()
  let (reviewed, reviewed_companion) = try! new_lambda_editor(
    "reachable-reviewed",
  )
  reviewed.set_text("(x) => x")
  let reviewed_reference = match reviewed.get_proj_node() {
    Some(root) => root.children[0].id()
    None => fail("expected reviewed lambda projection")
  }
  let actual = apply_lambda_tree_edit_with_reachable_failure_review(
      reviewed,
      reviewed_companion,
      @lambda_edits.TreeEditOp::CommitEdit(
        node_id=reviewed_reference,
        new_value="y",
      ),
      1,
      review_attribution(),
    )
    .unwrap()
    .edits()
  assert_eq(actual, expected)
}

///|
test "review wrapper returns the delegated error without mutating the editor" {
  let (editor, companion) = try! new_lambda_editor("reachable-error")
  editor.set_text("(x) => x")
  let result = apply_lambda_tree_edit_with_reachable_failure_review(
    editor,
    companion,
    @lambda_edits.TreeEditOp::CommitEdit(
      node_id=@core.NodeId::from_int(999),
      new_value="y",
    ),
    1,
    review_attribution(),
  )
  inspect(result is Err(_), content="true")
  inspect(editor.get_text(), content="(x) => x")
}
