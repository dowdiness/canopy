// Tests for the Show impls on core/types.mbt (SpanEdit, GenericTreeOp).
// See docs/plans/2026-05-16-show-unification.md.

///|
test "SpanEdit Show — pure insert" {
  let e = SpanEdit::{ start: 25, delete_len: 0, inserted: "add" }
  inspect(e, content="@25 -0 +«add»")
}

///|
test "SpanEdit Show — pure delete" {
  let e = SpanEdit::{ start: 25, delete_len: 3, inserted: "" }
  inspect(e, content="@25 -3 +«»")
}

///|
test "SpanEdit Show — replace" {
  let e = SpanEdit::{ start: 10, delete_len: 5, inserted: "abc" }
  inspect(e, content="@10 -5 +«abc»")
}

///|
test "SpanEdit Show — inserted with closing guillemet" {
  let e = SpanEdit::{ start: 0, delete_len: 0, inserted: "a»b" }
  inspect(e, content="@0 -0 +«a\\»b»")
}

///|
test "SpanEdit Show — inserted with backslash" {
  let e = SpanEdit::{ start: 0, delete_len: 0, inserted: "a\\b" }
  inspect(e, content="@0 -0 +«a\\\\b»")
}

///|
test "SpanEdit Show — inserted with newline" {
  let e = SpanEdit::{ start: 0, delete_len: 0, inserted: "a\nb" }
  inspect(e, content="@0 -0 +«a\\nb»")
}

///|
test "SpanEdit Show — inserted with NUL (U+0000)" {
  let e = SpanEdit::{ start: 0, delete_len: 0, inserted: "a\u{00}b" }
  inspect(e, content="@0 -0 +«a\\u{00}b»")
}

///|
test "SpanEdit Show — inserted with DEL (U+007F)" {
  let e = SpanEdit::{ start: 0, delete_len: 0, inserted: "a\u{7F}b" }
  inspect(e, content="@0 -0 +«a\\u{7f}b»")
}

///|
test "SpanEdit Show — inserted with NEL (U+0085, C1 control)" {
  let e = SpanEdit::{ start: 0, delete_len: 0, inserted: "a\u{85}b" }
  inspect(e, content="@0 -0 +«a\\u{85}b»")
}

///|
test "SpanEdit Show — inserted with U+2028 (line separator)" {
  let e = SpanEdit::{ start: 0, delete_len: 0, inserted: "a\u{2028}b" }
  inspect(e, content="@0 -0 +«a\\u{2028}b»")
}

///|
test "GenericTreeOp Show — Select" {
  inspect(GenericTreeOp::Select(node_id=NodeId(7)), content="Select(#7)")
}

///|
test "GenericTreeOp Show — SelectRange" {
  inspect(
    GenericTreeOp::SelectRange(start=NodeId(3), end=NodeId(9)),
    content="SelectRange(#3..#9)",
  )
}

///|
test "GenericTreeOp Show — StartEdit" {
  inspect(GenericTreeOp::StartEdit(node_id=NodeId(4)), content="StartEdit(#4)")
}

///|
test "GenericTreeOp Show — CommitEdit (escapes new_value)" {
  inspect(
    GenericTreeOp::CommitEdit(node_id=NodeId(3), new_value="x»y"),
    content="CommitEdit(#3 «x\\»y»)",
  )
}

///|
test "GenericTreeOp Show — CancelEdit" {
  inspect(GenericTreeOp::CancelEdit, content="CancelEdit")
}

///|
test "GenericTreeOp Show — Delete" {
  inspect(GenericTreeOp::Delete(node_id=NodeId(1)), content="Delete(#1)")
}

///|
test "GenericTreeOp Show — StructuralEdit" {
  inspect(
    GenericTreeOp::StructuralEdit(node_id=NodeId(5)),
    content="StructuralEdit(#5)",
  )
}

///|
test "GenericTreeOp Show — StructuralEditKeepSelected" {
  inspect(
    GenericTreeOp::StructuralEditKeepSelected(node_id=NodeId(5)),
    content="StructuralEditKeepSelected(#5)",
  )
}

///|
test "GenericTreeOp Show — InsertChild" {
  inspect(
    GenericTreeOp::InsertChild(parent=NodeId(2), index=3),
    content="InsertChild(#2, 3)",
  )
}

///|
test "GenericTreeOp Show — StartDrag" {
  inspect(GenericTreeOp::StartDrag(node_id=NodeId(8)), content="StartDrag(#8)")
}

///|
test "GenericTreeOp Show — DragOver" {
  inspect(
    GenericTreeOp::DragOver(target=NodeId(6), position=DropPosition::After),
    content="DragOver(#6, After)",
  )
}

///|
test "GenericTreeOp Show — Drop (uses → between source and target)" {
  inspect(
    GenericTreeOp::Drop(
      source=NodeId(11),
      target=NodeId(12),
      position=DropPosition::After,
    ),
    content="Drop(#11→#12 After)",
  )
}

///|
test "GenericTreeOp Show — Drop Before" {
  inspect(
    GenericTreeOp::Drop(
      source=NodeId(1),
      target=NodeId(2),
      position=DropPosition::Before,
    ),
    content="Drop(#1→#2 Before)",
  )
}

///|
test "GenericTreeOp Show — Drop Inside" {
  inspect(
    GenericTreeOp::Drop(
      source=NodeId(1),
      target=NodeId(2),
      position=DropPosition::Inside,
    ),
    content="Drop(#1→#2 Inside)",
  )
}

///|
test "GenericTreeOp Show — Collapse" {
  inspect(GenericTreeOp::Collapse(node_id=NodeId(4)), content="Collapse(#4)")
}

///|
test "GenericTreeOp Show — Expand" {
  inspect(GenericTreeOp::Expand(node_id=NodeId(4)), content="Expand(#4)")
}
