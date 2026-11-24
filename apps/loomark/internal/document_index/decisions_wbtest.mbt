///|
/// Two cards side by side, a wide card under both, and a short card that
/// sits beside the wide one in the third column.
///
/// a a b b c
/// w w w w c
///         d
let wide_card_under_two : Array[CardRect[String]] = [
  { id: "a", left: 0, top: 0, width: 100, height: 50, },
  { id: "b", left: 114, top: 0, width: 100, height: 80, },
  { id: "c", left: 228, top: 0, width: 100, height: 120, },
  { id: "w", left: 0, top: 94, width: 214, height: 40, },
  { id: "d", left: 228, top: 134, width: 100, height: 30, },
]

///|
/// The layout above with the focus on card `id`.
fn focused_on(id : String) -> Cursor[CardRect[String]] {
  Cursor::focus_on(Vector(wide_card_under_two), card => card.id == id).unwrap()
}

///|
fn moved_to(id : String, direction : Direction) -> String? {
  neighbour(focused_on(id), direction).map(card => card.id)
}

///|
test "arrows follow the packed positions, not the reading order" {
  // Both cards above the wide card lead down into it.
  assert_eq(moved_to("a", Down), Some("w"))
  assert_eq(moved_to("b", Down), Some("w"))
  // Up from the wide card prefers the nearer card above it.
  assert_eq(moved_to("w", Up), Some("b"))
  // Right from the wide card reaches the tall card sharing its row.
  assert_eq(moved_to("w", Right), Some("c"))
  assert_eq(moved_to("a", Up), None)
}

///|
test "at the right edge, Right continues in reading order" {
  assert_eq(moved_to("c", Right), Some("w"))
  assert_eq(moved_to("a", Left), None)
  assert_eq(moved_to("a", Last), Some("d"))
}

///|
test "a cursor focuses the wanted item, or the first, and is absent only when empty" {
  let filtered_out = Cursor::focus_on(Vector(["a", "b", "c"]), id => id == "z").unwrap()
  assert_eq(filtered_out.current, "a")
  let wanted = Cursor::focus_on(Vector(["a", "b", "c"]), id => id == "c").unwrap()
  assert_eq(
    (wanted.before.to_array(), wanted.current, wanted.after.to_array()),
    (["a", "b"], "c", []),
  )
  assert_eq(wanted.next(), None)
  assert_eq(wanted.previous(), Some("b"))
  assert_true(Cursor::focus_on(Vector([]), (_ : String) => true) is None)
}

///|
test "card keys move focus only without modifiers or composition" {
  let press = fn(key : String) -> KeyPress {
    { key, modified: false, composing: false, }
  }
  assert_true(card_key_action(press("ArrowDown")) is MoveFocus(Down))
  assert_true(card_key_action(press("/")) is FocusSearch)
  assert_true(card_key_action(press("Enter")) is LetBrowserHandle)
  assert_true(
    card_key_action({ ..press("n"), modified: true, }) is LetBrowserHandle,
  )
  assert_true(
    card_key_action({ ..press("ArrowDown"), composing: true, })
    is LetBrowserHandle,
  )
  assert_false(
    is_leaving_key({ key: "Escape", modified: false, composing: true, }),
  )
}

///|
test "a narrow window still lays out one card" {
  assert_eq(grid_width_of(1232.4), 1232)
  assert_eq(grid_width_of(90.0), MIN_GRID_WIDTH)
}
