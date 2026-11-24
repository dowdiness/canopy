///|
/// Commands are not run in these tests; only the next Model is checked. The
/// index's own behaviour is tested in `@document_index`.
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
  let notes = Vector([
    { id: "a", text: "# Alpha", },
    { id: "b", text: "# Beta", },
    { id: "c", text: "# Gamma", },
  ])
  {
    notes,
    page: Index,
    index: @document_index.DocumentIndex(
      seeds(notes, NoDeletion)[:],
      new_href="#/new",
    ),
    deletion: NoDeletion,
    next_id: 4,
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
  // The index keeps listing it, covered, so the cards behind the editor
  // stay put.
  assert_true(writing.index == three_notes().index.covered())
}

///|
test "leaving an unchanged note keeps its place" {
  let back = go(go(three_notes(), "/n/b"), "/")
  assert_true(back.page is Index)
  assert_eq(ids_of(back.notes), ["a", "b", "c"])
}

///|
test "an edited note moves to the front when it is left" {
  let edited = type_text(go(three_notes(), "/n/c"), "# Gamma, revised")
  // Typing changes nothing the index draws.
  assert_true(edited.index == three_notes().index.covered())
  let back = go(edited, "/")
  assert_true(back.page is Index)
  assert_eq(ids_of(back.notes), ["c", "a", "b"])
  assert_eq(back.notes[0].text, "# Gamma, revised")
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
test "a note emptied in the editor is removed when it is left" {
  let emptied = type_text(go(three_notes(), "/n/b"), "  \n")
  let back = go(emptied, "/")
  assert_true(back.page is Index)
  assert_eq(ids_of(back.notes), ["a", "c"])
  // Leaving for another note drops it the same way.
  assert_eq(ids_of(go(emptied, "/n/a").notes), ["c"])
}

///|
test "a New document erased before it is left adds nothing" {
  let erased = type_text(type_text(go(three_notes(), "/new"), "I"), "")
  let back = go(erased, "/")
  assert_true(back.page is Index)
  assert_eq(ids_of(back.notes), ["a", "b", "c"])
}

///|
test "a confirmed deletion stays pending, then removes the note" {
  let confirming = step(three_notes(), DeleteRequested("b"))
  assert_true(confirming.deletion is Confirming({ id: "b", .. }))
  let deleting = step(confirming, DeleteConfirmed)
  guard deleting.deletion is Deleting(note) else { fail("expected Deleting") }
  // Listed until it is gone; the others cannot be deleted meanwhile.
  assert_eq(ids_of(deleting.notes), ["a", "b", "c"])
  assert_true(
    listed_seeds(deleting).map(seed => seed.deletion) ==
    [Blocked, Pending, Blocked],
  )
  let gone = step(deleting, DeleteFinished(note))
  assert_eq(ids_of(gone.notes), ["a", "c"])
  assert_true(gone.deletion is NoDeletion)
}

///|
test "a cancelled deletion keeps the note" {
  let confirming = step(three_notes(), DeleteRequested("b"))
  let kept = step(confirming, DeleteCancelled)
  assert_true(kept.deletion is NoDeletion)
  assert_eq(ids_of(kept.notes), ["a", "b", "c"])
  // Cancelling and asking again at once opens it again.
  assert_true(
    step(kept, DeleteRequested("c")).deletion is Confirming({ id: "c", .. }),
  )
}
