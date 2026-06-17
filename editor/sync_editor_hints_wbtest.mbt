// Whitebox tests for the structural-edit identity hint channel.
//
// Invariants verified here:
//   T2: raw-text edits push Opaque taint when pending_transforms is non-empty
//   T4: hints start empty; each structural op appends one hint

///|
test "pending_transforms starts empty" {
  let editor = @probe.new_test_editor("test")
  inspect(editor.pending_transforms.val.is_empty(), content="true")
}

///|
test "apply_span_edits with Wrap hint pushes hint" {
  let editor = @probe.new_test_editor("test")
  editor.set_text("a")
  let inner_id = @core.NodeId::from_int(42)
  let edits : Array[@core.SpanEdit] = [
    { start: 0, delete_len: 0, inserted: "x(" },
    { start: 2, delete_len: 0, inserted: ")" },
  ]
  editor.apply_span_edits(
    edits,
    @core.FocusHint::RestoreCursor,
    0,
    hint=@core.IdentityTransform::Wrap(inner=inner_id),
  )
  inspect(editor.pending_transforms.val.length(), content="1")
  let stored = editor.pending_transforms.val[0]
  inspect(stored is @core.IdentityTransform::Wrap(inner=_), content="true")
  match stored {
    @core.IdentityTransform::Wrap(inner=id) =>
      inspect(id == inner_id, content="true")
    _ => fail("expected Wrap")
  }
}

///|
test "apply_span_edits without hint leaves pending_transforms unchanged" {
  let editor = @probe.new_test_editor("test")
  editor.set_text("a")
  let edits : Array[@core.SpanEdit] = [
    { start: 0, delete_len: 0, inserted: "x" },
  ]
  editor.apply_span_edits(edits, @core.FocusHint::RestoreCursor, 0)
  inspect(editor.pending_transforms.val.is_empty(), content="true")
}

///|
test "apply_span_edits with empty edits does not push hint (T4)" {
  let editor = @probe.new_test_editor("test")
  let fake_id = @core.NodeId::from_int(7)
  let edits : Array[@core.SpanEdit] = []
  editor.apply_span_edits(
    edits,
    @core.FocusHint::RestoreCursor,
    0,
    hint=@core.IdentityTransform::Wrap(inner=fake_id),
  )
  inspect(editor.pending_transforms.val.is_empty(), content="true")
}

///|
test "apply_span_edits with net-no-op edits does not push hint (T4)" {
  // A non-empty span batch that replaces text with itself produces no text
  // change, so sync_parser_after_text_change returns early without triggering
  // a reparse. The hint must not be queued — otherwise it becomes stale and
  // corrupts the next structural op's hint map.
  let editor = @probe.new_test_editor("test")
  editor.set_text("x")
  let replace_id = @core.NodeId::from_int(5)
  let edits : Array[@core.SpanEdit] = [
    { start: 0, delete_len: 1, inserted: "x" },
  ]
  editor.apply_span_edits(
    edits,
    @core.FocusHint::RestoreCursor,
    0,
    hint=@core.IdentityTransform::Replace(old=replace_id),
  )
  inspect(editor.pending_transforms.val.is_empty(), content="true")
}

///|
test "T2: set_text taints if pending_transforms non-empty" {
  let editor = @probe.new_test_editor("test")
  let fake_id = @core.NodeId::from_int(1)
  editor.pending_transforms.val.push(
    @core.IdentityTransform::Wrap(inner=fake_id),
  )
  editor.set_text("hello")
  inspect(editor.pending_transforms.val.length(), content="2")
  inspect(
    editor.pending_transforms.val[1] is @core.IdentityTransform::Opaque,
    content="true",
  )
}

///|
test "T2: set_text does NOT taint when pending_transforms empty" {
  let editor = @probe.new_test_editor("test")
  editor.set_text("hello")
  inspect(editor.pending_transforms.val.is_empty(), content="true")
}

///|
test "T2: insert taints if pending_transforms non-empty" {
  let editor = @probe.new_test_editor("test")
  let fake_id = @core.NodeId::from_int(2)
  editor.pending_transforms.val.push(
    @core.IdentityTransform::Wrap(inner=fake_id),
  )
  editor.insert("x") catch {
    _ => ()
  }
  inspect(editor.pending_transforms.val.length(), content="2")
  inspect(
    editor.pending_transforms.val[1] is @core.IdentityTransform::Opaque,
    content="true",
  )
}

///|
test "multiple structural hints accumulate in order" {
  let editor = @probe.new_test_editor("test")
  editor.set_text("ab")
  let id1 = @core.NodeId::from_int(10)
  let id2 = @core.NodeId::from_int(20)
  let id3 = @core.NodeId::from_int(30)
  let edits1 : Array[@core.SpanEdit] = [
    { start: 0, delete_len: 0, inserted: "w(" },
  ]
  let edits2 : Array[@core.SpanEdit] = [
    { start: 4, delete_len: 0, inserted: ")" },
  ]
  editor.apply_span_edits(
    edits1,
    @core.FocusHint::RestoreCursor,
    0,
    hint=@core.IdentityTransform::Wrap(inner=id1),
  )
  editor.apply_span_edits(
    edits2,
    @core.FocusHint::RestoreCursor,
    0,
    hint=@core.IdentityTransform::Unwrap(wrapper=id2, keep=id3),
  )
  inspect(editor.pending_transforms.val.length(), content="2")
  inspect(
    editor.pending_transforms.val[0] is @core.IdentityTransform::Wrap(inner=_),
    content="true",
  )
  inspect(
    editor.pending_transforms.val[1]
    is @core.IdentityTransform::Unwrap(wrapper=_, keep=_),
    content="true",
  )
}

///|
test "move_node taints pending_transforms (Finding 3: Move is not identity-preserving)" {
  let editor = @probe.new_test_editor("test")
  editor.set_text("f(x) y")
  let _ = editor.get_proj_node() // force first parse
  let fake_id = @core.NodeId::from_int(5)
  // Simulate a pending Wrap op from a prior structural edit
  editor.pending_transforms.val.push(
    @core.IdentityTransform::Wrap(inner=fake_id),
  )
  // move_node on unknown ids returns Err, but taint_pending_transforms runs first
  let bad_src = @core.NodeId::from_int(99998)
  let bad_tgt = @core.NodeId::from_int(99999)
  let _ = editor.move_node(bad_src, bad_tgt, @core.DropPosition::Before, 0)
  // Opaque taint was pushed regardless of move_node result
  inspect(editor.pending_transforms.val.length(), content="2")
  inspect(
    editor.pending_transforms.val[1] is @core.IdentityTransform::Opaque,
    content="true",
  )
}
