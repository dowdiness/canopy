// Tests for the pure move-planning core extracted from
// `SyncEditor::move_node`. See docs/decisions/2026-08-07-generic-language-spi-deepening.md:
// moves are edit-port computation, and `compute_move` is the shared
// expression-level helper (language text policies: placeholder, separator).
//
// These tests exercise the function in isolation — no SyncEditor, no CRDT.

///|
fn try_move_message(
  text : String,
  source_id : NodeId,
  source_range : @loomcore.Range,
  target_id : NodeId,
  target_range : @loomcore.Range,
  position : DropPosition,
  placeholder : String,
  separator : String,
) -> String {
  try {
    let (_, _) = compute_move(
      text, source_id, source_range, target_id, target_range, position, placeholder,
      separator,
    )
    "ok"
  } catch {
    e => e.message()
  }
}

///|
test "compute_move Before: replace source with placeholder, insert before target" {
  // "a b" — source "b" [2,3) moved Before target "a" [0,1).
  // Source span replaced by placeholder "?"; "b " inserted at target start.
  let (edits, focus) = compute_move(
    "a b",
    NodeId::from_int(2),
    @loomcore.Range::new(2, 3),
    NodeId::from_int(0),
    @loomcore.Range::new(0, 1),
    DropPosition::Before,
    "?",
    " ",
  )
  inspect(edits[0], content="@2 -1 +«?»")
  inspect(edits[1], content="@0 -0 +«b »")
  inspect(focus, content="RestoreCursor")
}

///|
test "compute_move After: insert at target end" {
  let (edits, _) = compute_move(
    "a b",
    NodeId::from_int(2),
    @loomcore.Range::new(2, 3),
    NodeId::from_int(0),
    @loomcore.Range::new(0, 1),
    DropPosition::After,
    "?",
    " ",
  )
  inspect(edits[0], content="@2 -1 +«?»")
  inspect(edits[1], content="@1 -0 +«b »")
}

///|
test "compute_move separator is a language policy" {
  let (edits, _) = compute_move(
    "a b",
    NodeId::from_int(2),
    @loomcore.Range::new(2, 3),
    NodeId::from_int(0),
    @loomcore.Range::new(0, 1),
    DropPosition::Before,
    "?",
    "\n",
  )
  inspect(edits[0], content="@2 -1 +«?»")
  inspect(edits[1], content="@0 -0 +«b\\n»")
}

///|
test "compute_move Inside: exchange preserves leading whitespace" {
  // "a +\n  b" (7 chars) — target range [4,7) includes leading separator
  // "  ". Exchange swaps expression bodies, keeping separators in place:
  //   src_expr_start = skip_ws("a +\n  b", 4, 7) = 6  ("b" at [6,7))
  //   source "a" [0,1) ← "b"; target expr [6,7) ← "a"
  let (edits, focus) = compute_move(
    "a +\n  b",
    NodeId::from_int(0),
    @loomcore.Range::new(0, 1),
    NodeId::from_int(1),
    @loomcore.Range::new(4, 7),
    DropPosition::Inside,
    "?",
    " ",
  )
  inspect(edits[0], content="@0 -1 +«b»")
  inspect(edits[1], content="@6 -1 +«a»")
  inspect(focus, content="RestoreCursor")
}

///|
test "compute_move self-drop raises (id-based legality)" {
  let message = try_move_message(
    "a b",
    NodeId::from_int(0),
    @loomcore.Range::new(0, 1),
    NodeId::from_int(0),
    @loomcore.Range::new(2, 3),
    DropPosition::Before,
    "?",
    " ",
  )
  inspect(message, content="Cannot drop onto self")
}

///|
test "compute_move descendant-drop raises (target inside source)" {
  let message = try_move_message(
    "x + 1",
    NodeId::from_int(10),
    @loomcore.Range::new(0, 5),
    NodeId::from_int(11),
    @loomcore.Range::new(1, 2),
    DropPosition::After,
    "?",
    " ",
  )
  inspect(message, content="Cannot drop into own descendant")
}

///|
test "compute_move Inside: source inside target raises" {
  let message = try_move_message(
    "x + 1",
    NodeId::from_int(11),
    @loomcore.Range::new(1, 2),
    NodeId::from_int(10),
    @loomcore.Range::new(0, 5),
    DropPosition::Inside,
    "?",
    " ",
  )
  inspect(message, content="Cannot drop into own descendant")
}
