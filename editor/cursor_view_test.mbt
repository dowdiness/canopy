///|
test "adjust_position: cursor before edit is unchanged" {
  // Cursor at 3, edit starts at 5 — cursor is unaffected
  inspect(@editor.adjust_position(3, 5, 2, 4), content="3")
}

///|
test "adjust_position: cursor at edit_start is unchanged" {
  // Cursor at 5, edit starts at 5 — cursor is at boundary, stays
  inspect(@editor.adjust_position(5, 5, 2, 4), content="5")
}

///|
test "adjust_position: cursor inside deleted range snaps to edit_start + new_len" {
  // Cursor at 6, edit starts at 5, old_len=3 (range 5..8), new_len=1
  // Cursor is inside deleted range -> snaps to 5+1=6
  inspect(@editor.adjust_position(6, 5, 3, 1), content="6")
  // Cursor at 7, same edit -> also snaps to 6
  inspect(@editor.adjust_position(7, 5, 3, 1), content="6")
}

///|
test "adjust_position: cursor at end of deleted range snaps" {
  // Cursor at 8 (= edit_start 5 + old_len 3), snaps to 5+1=6
  inspect(@editor.adjust_position(8, 5, 3, 1), content="6")
}

///|
test "adjust_position: cursor after edit shifts by delta" {
  // Cursor at 10, edit starts at 5, old_len=2, new_len=4 (delta=+2)
  // Result: 10 - 2 + 4 = 12
  inspect(@editor.adjust_position(10, 5, 2, 4), content="12")
}

///|
test "adjust_position: pure insert (old_len=0)" {
  // Insert 3 chars at position 5, cursor at 7 -> 7+3=10
  inspect(@editor.adjust_position(7, 5, 0, 3), content="10")
  // Cursor at 5 (at edit_start) -> unchanged (pos <= edit_start)
  inspect(@editor.adjust_position(5, 5, 0, 3), content="5")
}

///|
test "adjust_position: pure delete (new_len=0)" {
  // Delete 3 chars at position 5, cursor at 10 -> 10-3=7
  inspect(@editor.adjust_position(10, 5, 3, 0), content="7")
  // Cursor inside deleted range (at 6) -> snaps to 5+0=5
  inspect(@editor.adjust_position(6, 5, 3, 0), content="5")
}

///|
test "PeerCursorView: set and get cursor" {
  let view = @editor.PeerCursorView::new()
  view.set_cursor("peer1", 10, "Alice", "#ff0000")
  let cursor = view.get_cursor("peer1").unwrap()
  inspect(cursor.raw_cursor, content="10")
  inspect(cursor.adjusted_cursor, content="10")
  inspect(cursor.display_name, content="Alice")
  inspect(cursor.color, content="#ff0000")
  inspect(cursor.selection, content="None")
}

///|
test "PeerCursorView: get_cursor returns None for unknown peer" {
  let view = @editor.PeerCursorView::new()
  inspect(view.get_cursor("unknown"), content="None")
}

///|
test "PeerCursorView: adjust_for_edit shifts all cursors" {
  let view = @editor.PeerCursorView::new()
  view.set_cursor("peer1", 3, "Alice", "#ff0000")
  view.set_cursor("peer2", 10, "Bob", "#00ff00")
  // Insert 2 chars at position 5 (old_len=0, new_len=2)
  view.adjust_for_edit(5, 0, 2)
  let c1 = view.get_cursor("peer1").unwrap()
  let c2 = view.get_cursor("peer2").unwrap()
  // peer1 at 3 (before edit_start 5) -> unchanged
  inspect(c1.adjusted_cursor, content="3")
  // peer2 at 10 (after edit_start 5) -> 10+2=12
  inspect(c2.adjusted_cursor, content="12")
  // raw_cursor should be unchanged
  inspect(c1.raw_cursor, content="3")
  inspect(c2.raw_cursor, content="10")
}

///|
test "PeerCursorView: set_cursor resets adjusted_cursor" {
  let view = @editor.PeerCursorView::new()
  view.set_cursor("peer1", 10, "Alice", "#ff0000")
  // Adjust for an insert
  view.adjust_for_edit(5, 0, 3)
  let c1 = view.get_cursor("peer1").unwrap()
  inspect(c1.adjusted_cursor, content="13")
  // Re-set cursor with new raw value — adjusted should reset to match raw
  view.set_cursor("peer1", 20, "Alice", "#ff0000")
  let c2 = view.get_cursor("peer1").unwrap()
  inspect(c2.raw_cursor, content="20")
  inspect(c2.adjusted_cursor, content="20")
}

///|
test "PeerCursorView: remove peer" {
  let view = @editor.PeerCursorView::new()
  view.set_cursor("peer1", 10, "Alice", "#ff0000")
  view.remove("peer1")
  inspect(view.get_cursor("peer1"), content="None")
}

///|
test "PeerCursorView: all_cursors returns all entries" {
  let view = @editor.PeerCursorView::new()
  view.set_cursor("peer1", 5, "Alice", "#ff0000")
  view.set_cursor("peer2", 15, "Bob", "#00ff00")
  let all = view.all_cursors()
  inspect(all.length(), content="2")
}

///|
test "PeerCursorView: selection adjustment on edit" {
  let view = @editor.PeerCursorView::new()
  // Set cursor with a selection spanning positions 5..10
  view.set_cursor("peer1", 5, "Alice", "#ff0000", selection=Some((5, 10)))
  let c = view.get_cursor("peer1").unwrap()
  inspect(c.selection, content="Some((5, 10))")
  // Insert 3 chars at position 2 (before selection) — both ends shift by +3
  view.adjust_for_edit(2, 0, 3)
  let c2 = view.get_cursor("peer1").unwrap()
  inspect(c2.selection, content="Some((8, 13))")
  inspect(c2.adjusted_cursor, content="8")
}

///|
test "PeerCursorView: apply_raw_update extracts cursor from Map" {
  let view = @editor.PeerCursorView::new()
  let value = @editor.EphemeralValue::Map({
    "cursor": @editor.EphemeralValue::I64(7L),
    "name": @editor.EphemeralValue::String("Bob"),
    "color": @editor.EphemeralValue::String("#00ff00"),
    "selection": @editor.EphemeralValue::List([
      @editor.EphemeralValue::I64(3L),
      @editor.EphemeralValue::I64(10L),
    ]),
  })
  view.apply_raw_update("peer1", value)
  let c = view.get_cursor("peer1").unwrap()
  inspect(c.raw_cursor, content="7")
  inspect(c.display_name, content="Bob")
  inspect(c.color, content="#00ff00")
  inspect(c.selection, content="Some((3, 10))")
}

///|
test "PeerCursorView: apply_raw_update honors logical peer_id and remove uses wire key" {
  let view = @editor.PeerCursorView::new()
  let value = @editor.EphemeralValue::Map({
    "peer_id": @editor.EphemeralValue::String("web-user"),
    "cursor": @editor.EphemeralValue::I64(7L),
    "name": @editor.EphemeralValue::String("Bob"),
    "color": @editor.EphemeralValue::String("#00ff00"),
  })
  view.apply_raw_update("123", value)
  inspect(view.get_cursor("123"), content="None")
  inspect(view.get_cursor("web-user").unwrap().display_name, content="Bob")
  view.remove("123")
  inspect(view.get_cursor("web-user"), content="None")
}

///|
test "PeerCursorView: apply_raw_update ignores non-Map values" {
  let view = @editor.PeerCursorView::new()
  view.apply_raw_update("peer1", @editor.EphemeralValue::I64(42L))
  inspect(view.get_cursor("peer1"), content="None")
}

///|
test "PeerCursorView: from_store skips local peer" {
  let store = @editor.EphemeralStore::new(60000UL)
  store.set(
    "1",
    @editor.EphemeralValue::Map({
      "cursor": @editor.EphemeralValue::I64(5L),
      "name": @editor.EphemeralValue::String("Alice"),
      "color": @editor.EphemeralValue::String("#ff0000"),
    }),
  )
  store.set(
    "2",
    @editor.EphemeralValue::Map({
      "cursor": @editor.EphemeralValue::I64(10L),
      "name": @editor.EphemeralValue::String("Bob"),
      "color": @editor.EphemeralValue::String("#00ff00"),
    }),
  )
  // Build view excluding local peer "1"
  let view = @editor.PeerCursorView::from_store(store, "1")
  // Local peer "1" should be excluded
  inspect(view.get_cursor("1"), content="None")
  // Remote peer "2" should be included
  let c = view.get_cursor("2").unwrap()
  inspect(c.raw_cursor, content="10")
  inspect(c.display_name, content="Bob")
}
