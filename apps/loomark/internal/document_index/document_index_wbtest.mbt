///|
fn seed(key : String, text : String) -> Seed[String] {
  {
    key,
    href: "#/n/\{key}",
    text,
    status: Saved,
    deletion: Available(ThisBrowser),
    loading: false,
  }
}

///|
/// Three documents, most recently changed first.
let alpha_beta_gamma : Array[Seed[String]] = [
  seed("a", "# Alpha"),
  seed("b", "# Beta"),
  seed("c", "# Gamma"),
]

///|
fn three_cards() -> DocumentIndex[String] {
  step(
    DocumentIndex(alpha_beta_gamma[:], new_href="#/new"),
    GridMeasured(1232.0),
  )
}

///|
fn step(
  index : DocumentIndex[String],
  msg : Msg[String],
) -> DocumentIndex[String] {
  index.update(msg).0
}

///|
/// The shell reports every card it was asked to measure as `height` tall.
fn measured(
  index : DocumentIndex[String],
  height : Int,
) -> DocumentIndex[String] {
  step(
    index,
    CardsMeasured(unmeasured(index).map(request => (request.measure, height))),
  )
}

///|
/// The cards on screen in reading order, as key and text.
fn shown(grid : ShownGrid[String]) -> Array[(String, String)] {
  match grid {
    Packed(layout) =>
      layout.cards.to_array().map(card => (card.card.key, card.card.text))
    NotMeasured => []
  }
}

///|
test "a document returned to unchanged keeps its place and announces nothing" {
  let back = measured(three_cards(), 50).returned_from(
    alpha_beta_gamma[:],
    key="b",
  )
  assert_eq(shown(back.grid).map(card => card.0), ["a", "b", "c"])
  assert_eq(back.focus_pending, Some("b"))
  assert_eq(back.highlight, None)
  assert_eq(back.announcement, "")
}

///|
test "a changed document moves to the front, highlighted for a moment" {
  let back = measured(three_cards(), 50).returned_from(
    [seed("c", "# Gamma, revised"), seed("a", "# Alpha"), seed("b", "# Beta")],
    key="c",
  )
  assert_eq(back.focus_pending, Some("c"))
  assert_eq(back.highlight, Some("c"))
  assert_eq(back.announcement, "Moved to first: Gamma, revised")
  assert_eq(step(back, HighlightEnded).highlight, None)
}

///|
test "a changed document is shown as it was until its new text is measured" {
  let back = measured(three_cards(), 50).returned_from(
    [seed("c", "# Gamma, revised"), seed("a", "# Alpha"), seed("b", "# Beta")],
    key="c",
  )
  assert_eq(shown(back.grid)[2], ("c", "# Gamma"))
  assert_eq(unmeasured(back).map(request => request.measure.text), [
    "# Gamma, revised",
  ])
  assert_eq(shown(measured(back, 70).grid)[0], ("c", "# Gamma, revised"))
}

///|
test "a new document is focused once its card is measured" {
  let back = measured(three_cards(), 50).returned_from(
    [seed("n4", "Idea"), ..alpha_beta_gamma],
    key="n4",
  )
  assert_eq(back.focus_pending, Some("n4"))
  assert_eq(back.highlight, Some("n4"))
  // Its card is not drawn yet, so nothing may try to focus it.
  assert_false(shows_card(back, "n4"))
  let drawn = measured(back, 60)
  assert_true(shows_card(drawn, "n4"))
  assert_eq(step(drawn, CardFocused("n4")).focus_pending, None)
}

///|
test "focus moves to the card in a removed card's place, or the one before" {
  let index = measured(three_cards(), 50)
  let (middle, _) = index.removed(
    [seed("a", "# Alpha"), seed("c", "# Gamma")],
    key="b",
    announcement="Removed empty document",
  )
  assert_eq(middle.focus_pending, Some("c"))
  assert_eq(middle.announcement, "Removed empty document")
  assert_eq(shown(middle.grid).map(card => card.0), ["a", "c"])
  let (last, _) = index.removed(
    [seed("a", "# Alpha"), seed("b", "# Beta")],
    key="c",
    announcement="",
  )
  assert_eq(last.focus_pending, Some("b"))
  // With no card left, focus goes to Search, which the index does not hold.
  let (none, _) = measured(
    step(
      DocumentIndex([seed("a", "# Alpha")][:], new_href="#/new"),
      GridMeasured(1232.0),
    ),
    50,
  ).removed([][:], key="a", announcement="")
  assert_eq(none.focus_pending, None)
  assert_true(visible_cursor(none) is None)
}

///|
test "unchanged documents keep their parsed leads" {
  let index = three_cards()
  let relisted = index.listing([
    seed("b", "# Beta"),
    seed("a", "# Alpha, again"),
    seed("c", "# Gamma"),
  ])
  assert_true(physical_equal(relisted.cards[0].lead, index.cards[1].lead))
  assert_false(physical_equal(relisted.cards[1].lead, index.cards[0].lead))
  assert_eq(relisted.cards[1].search_text, "# alpha, again")
}

///|
test "a card says what its document is doing, deletion first" {
  let notice = (seed : Seed[String]) => Card::of(seed, None).notice
  let unsaved = { ..seed("a", "# Alpha"), status: Unsaved, }
  assert_true(notice(seed("a", "# Alpha")) is Quiet)
  assert_true(notice(unsaved) is NotSaved)
  assert_true(
    notice({ ..unsaved, loading: true, }) is Progress("Loading document"),
  )
  assert_true(
    notice({ ..unsaved, loading: true, deletion: Pending, })
    is Progress("Deleting"),
  )
  assert_true(
    notice({ ..unsaved, deletion: Failed(AllDevices), })
    is Problem("Delete failed"),
  )
}

///|
test "a card being deleted stays in place and cannot be chosen or deleted again" {
  let packed = measured(three_cards(), 50)
  let pending = packed.listing([
    seed("a", "# Alpha"),
    { ..seed("b", "# Beta"), deletion: Pending, },
    seed("c", "# Gamma"),
  ])
  assert_true(pending.cards[1].actions is Neither)
  assert_true(
    Card::of({ ..seed("b", "# Beta"), deletion: Blocked, }, None).actions
    is ChooseOnly,
  )
  assert_true(
    Card::of({ ..seed("b", "# Beta"), deletion: Failed(ThisBrowser), }, None).actions
    is ChooseOrDelete,
  )
  // States are drawn over cards, so nothing is measured again and every
  // card keeps its slot.
  assert_true(to_measure(pending).is_empty())
  guard (packed.grid, pending.grid) is (Packed(before), Packed(after)) else {
    fail("expected both grids packed")
  }
  assert_eq(
    after.cards.to_array().map(card => (card.x, card.y, card.height)),
    before.cards.to_array().map(card => (card.x, card.y, card.height)),
  )
}

///|
test "Escape in search clears it before it leaves" {
  let searching = step(three_cards(), Searched("beta"))
  let cleared = step(searching, SearchLeft)
  assert_eq(cleared.query, "")
  // A second Escape leaves the search for the focused card.
  let left = step(cleared, SearchLeft)
  assert_eq(left.query, "")
  assert_eq(left.focus_pending, Some("a"))
}

///|
test "arrows follow the grid on screen" {
  let packed = step(measured(three_cards(), 50), CardFocused("a"))
  assert_eq(step(packed, CardKey(MoveFocus(Right))).focused, Some("b"))
  // Before the grid is measured there is nothing to move along.
  assert_eq(
    step(step(three_cards(), CardFocused("a")), CardKey(MoveFocus(Right))).focused,
    Some("a"),
  )
}

///|
test "the focus follows the search when the focused card is filtered out" {
  let index = step(step(three_cards(), CardFocused("a")), Searched("gamma"))
  guard visible_cursor(index) is Some(cursor) else {
    fail("expected gamma to match")
  }
  assert_eq(cursor.current.key, "c")
  assert_true(visible_cursor(step(index, Searched("zzz"))) is None)
}

///|
test "the grid appears once every card is measured, and search does not wait" {
  let index = three_cards()
  assert_true(index.grid is NotMeasured)
  assert_eq(to_measure(index).map(request => request.card.key), ["a", "b", "c"])
  let packed = measured(index, 50)
  assert_true(to_measure(packed).is_empty())
  assert_eq(shown(packed.grid).map(card => card.0), ["a", "b", "c"])
  // Search is case-insensitive and needs no new measurements.
  let searched = step(packed, Searched("BETA"))
  assert_true(to_measure(searched).is_empty())
  assert_eq(shown(searched.grid), [("b", "# Beta")])
}

///|
test "cards are measured once the width holds still, and the grid stays until then" {
  let packed = measured(three_cards(), 50)
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
test "a width changed while covered is measured as soon as the index returns" {
  let packed = measured(three_cards(), 50)
  let covered = step(packed.covered(), GridMeasured(500.0))
  assert_true(to_measure(covered).is_empty())
  assert_true(covered.grid == packed.grid)
  let back = covered.shown().returned_from(alpha_beta_gamma[:], key="b")
  assert_true(to_measure(back).length() > 0)
  guard measured(back, 50).grid is Packed(layout) else {
    fail("expected the grid at the new width")
  }
  assert_eq(layout.width, 500)
}

///|
test "faces loaded while covered are measured only once the index is shown" {
  let packed = measured(three_cards(), 50)
  let covered = step(packed.covered(), FontsLoaded)
  assert_true(to_measure(covered).is_empty())
  assert_true(covered.grid == packed.grid)
  let back = covered.shown()
  assert_true(to_measure(back).length() > 0)
  assert_true(back.grid == packed.grid)
}

///|
test "loaded fonts make every card measured again, keeping the grid until then" {
  let packed = measured(three_cards(), 50)
  let reloaded = step(packed, FontsLoaded)
  assert_true(reloaded.grid == packed.grid)
  assert_eq(unmeasured(reloaded).length(), unmeasured(three_cards()).length())
  guard measured(reloaded, 80).grid is Packed(layout) else {
    fail("expected the grid packed again")
  }
  assert_eq(layout.cards.current.height, 80)
}
