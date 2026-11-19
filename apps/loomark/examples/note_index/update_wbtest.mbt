///|
/// Commands are not run in these tests; only the next Model is checked.
let ignore_messages : Emit[Msg] = @cmd.Emit(_ => @cmd.none)

///|
fn step(model : Model, msg : Msg) -> Model {
  update(model, msg, ignore_messages).0
}

///|
/// Type into the editor on screen, as its input handler does.
fn type_text(model : Model, text : String) -> Model raise {
  guard model.page is Editing(editor) else { fail("no editor is open") }
  step(model, Edited(editor, text))
}

///|
/// Navigate as the browser does: the URL fragment changes.
fn go(model : Model, fragment : String) -> Model {
  step(model, UrlChanged(try! @url.parse("http://localhost/#\{fragment}")))
}

///|
/// Three notes, most recently changed first.
fn three_notes() -> Model {
  {
    ..initial_state(IndexRoute, 1232).0,
    notes: Vector([
      Note("a", "# Alpha"),
      Note("b", "# Beta"),
      Note("c", "# Gamma"),
    ]),
    next_id: 4,
  }
}

///|
/// The shell reports every card it was asked to measure as `height` tall.
fn measured(model : Model, height : Int) -> Model {
  step(
    model,
    CardsMeasured(unmeasured(model).map(request => (request.measure, height))),
  )
}

///|
/// The notes on screen in reading order, as id and text.
fn shown(grid : ShownGrid) -> Array[(String, String)] {
  match grid {
    Packed(layout) =>
      layout.cards.to_array().map(card => (card.note.id, card.note.text))
    NotMeasured => []
  }
}

///|
fn ids_of(notes : Vector[Note]) -> Array[String] {
  notes.map(note => note.id).to_array()
}

///|
test "opening a note holds it outside the list until the editor is left" {
  let writing = go(three_notes(), "/n/b")
  guard writing.page is Editing(Writing({ note, origin: Listed(at=1, ..), })) else {
    fail("expected to write b, opened from position 1")
  }
  assert_eq(note.id, "b")
  assert_eq(ids_of(writing.notes), ["a", "c"])
  assert_eq(ids_of(settled_notes(writing)), ["a", "b", "c"])
}

///|
test "leaving an unchanged note keeps its place and announces nothing" {
  let back = go(go(three_notes(), "/n/b"), "/")
  assert_true(back.page is Index)
  assert_eq(ids_of(back.notes), ["a", "b", "c"])
  assert_eq(back.focused, Some("b"))
  assert_eq(back.announcement, "")
}

///|
test "an edited note moves to the front and is highlighted for a moment" {
  let edited = type_text(go(three_notes(), "/n/c"), "# Gamma, revised")
  let back = go(edited, "/")
  assert_true(back.page is Index)
  assert_eq(ids_of(back.notes), ["c", "a", "b"])
  assert_eq(back.focused, Some("c"))
  assert_eq(back.highlight, Some("c"))
  assert_eq(back.announcement, "Moved to first: Gamma, revised")
  assert_eq(step(back, HighlightEnded).highlight, None)
}

///|
test "an untouched New document adds nothing" {
  let drafting = go(three_notes(), "/new")
  assert_true(drafting.page is Editing(Drafting))
  let back = go(drafting, "/")
  assert_true(back.page is Index)
  assert_eq(ids_of(back.notes), ["a", "b", "c"])
}

///|
test "a New document becomes one note on its first change" {
  let first = type_text(go(three_notes(), "/new"), "I")
  guard first.page is Editing(Writing({ note, origin: Created, })) else {
    fail("expected a created note")
  }
  assert_eq(note.id, "n4")
  let typed = type_text(first, "Idea")
  guard typed.page is Editing(Writing({ note, .. })) else {
    fail("expected writing")
  }
  assert_eq((note.id, note.text), ("n4", "Idea"))
  assert_eq(typed.next_id, 5)

  assert_eq(ids_of(go(typed, "/").notes), ["n4", "a", "b", "c"])
}

///|
test "a link to a missing note leaves the index as it is" {
  let model = three_notes()
  assert_true(go(model, "/n/missing") == model)
}

///|
test "Escape in search clears it before it leaves" {
  let searching = step(three_notes(), Searched("beta"))
  let cleared = step(searching, SearchLeft)
  assert_eq(cleared.query, "")
  // A second Escape leaves the search for the focused card.
  let left = step(cleared, SearchLeft)
  assert_eq(left.query, "")
  assert_eq(left.focus_pending, Some("a"))
}

///|
test "arrows follow the grid on screen" {
  let packed = step(measured(three_notes(), 50), CardFocused("a"))
  assert_eq(step(packed, CardKey(MoveFocus(Right))).focused, Some("b"))
  // Before the grid is measured there is nothing to move along.
  assert_eq(
    step(step(three_notes(), CardFocused("a")), CardKey(MoveFocus(Right))).focused,
    Some("a"),
  )
}

///|
test "the focus follows the search when the focused card is filtered out" {
  let model = step(step(three_notes(), CardFocused("a")), Searched("gamma"))
  guard visible_cursor(model) is Some(cursor) else {
    fail("expected gamma to match")
  }
  assert_eq(cursor.current.id, "c")
  assert_true(visible_cursor(step(model, Searched("zzz"))) is None)
}

///|
test "the grid appears once every card is measured, and search does not wait" {
  let model = three_notes()
  assert_true(model.grid is NotMeasured)
  assert_eq(to_measure(model).map(request => request.note.id), ["a", "b", "c"])
  let packed = measured(model, 50)
  assert_true(to_measure(packed).is_empty())
  assert_eq(shown(packed.grid).map(card => card.0), ["a", "b", "c"])
  // Search is case-insensitive and needs no new measurements.
  let searched = step(packed, Searched("BETA"))
  assert_true(to_measure(searched).is_empty())
  assert_eq(shown(searched.grid), [("b", "# Beta")])
}

///|
test "cards are measured once the width holds still, and the grid stays until then" {
  let packed = measured(three_notes(), 50)
  // A drag: while the width changes, nothing is measured.
  let dragging = step(step(packed, GridMeasured(600.0)), GridMeasured(500.0))
  assert_true(dragging.resize is Resizing)
  assert_true(to_measure(dragging).is_empty())
  assert_true(dragging.grid == packed.grid)
  // Once it holds still, the cards at 500px are measured.
  let settled = step(dragging, ResizeSettled)
  assert_true(settled.resize is Steady)
  assert_true(to_measure(settled).length() > 0)
  assert_true(settled.grid == packed.grid)
  guard measured(settled, 50).grid is Packed(layout) else {
    fail("expected the grid at the new width")
  }
  assert_eq(layout.width, 500)
  // The same width again is not a resize.
  assert_true(step(packed, GridMeasured(1232.0)) == packed)
}

///|
test "an edited note is shown as it was until its new text is measured" {
  let packed = measured(three_notes(), 50)
  let back = go(type_text(go(packed, "/n/c"), "# Gamma, revised"), "/")
  // The grid still shows c as it was, at its old place.
  assert_eq(shown(back.grid)[2], ("c", "# Gamma"))
  assert_eq(unmeasured(back).map(request => request.measure.text), [
    "# Gamma, revised",
  ])
  assert_eq(shown(measured(back, 70).grid)[0], ("c", "# Gamma, revised"))
}

///|
test "a note emptied in the editor is removed when it is left" {
  let emptied = type_text(go(three_notes(), "/n/b"), "  \n")
  let back = go(emptied, "/")
  assert_true(back.page is Index)
  assert_eq(ids_of(back.notes), ["a", "c"])
  assert_eq(back.focused, Some("c"))
  assert_eq(back.announcement, "Removed empty document")
  // Leaving for another note drops it the same way.
  assert_eq(ids_of(go(emptied, "/n/a").notes), ["c"])
}

///|
test "a New document erased before it is left adds nothing" {
  let erased = type_text(type_text(go(three_notes(), "/new"), "I"), "")
  let back = go(erased, "/")
  assert_true(back.page is Index)
  assert_eq(ids_of(back.notes), ["a", "b", "c"])
  assert_eq(back.announcement, "")
}

///|
test "loaded fonts make every card measured again, keeping the grid until then" {
  let packed = measured(three_notes(), 50)
  let reloaded = step(packed, FontsLoaded)
  assert_true(reloaded.grid == packed.grid)
  assert_eq(unmeasured(reloaded).length(), unmeasured(three_notes()).length())
  guard measured(reloaded, 80).grid is Packed(layout) else {
    fail("expected the grid packed again")
  }
  assert_eq(layout.cards.current.height, 80)
}

///|
test "a New document left with text is focused once its card is measured" {
  let packed = measured(three_notes(), 50)
  let back = go(type_text(go(packed, "/new"), "Idea"), "/")
  assert_eq(back.focus_pending, Some("n4"))
  // Its card is not drawn yet, so nothing may try to focus it.
  assert_false(shows_card(back, "n4"))
  let drawn = measured(back, 60)
  assert_true(shows_card(drawn, "n4"))
  assert_eq(step(drawn, CardFocused("n4")).focus_pending, None)
}
