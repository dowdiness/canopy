// App code: routing between the Document index and the editor. The index is
// `@document_index`; this app keeps the notes, tells the index what they are
// after each change, and forwards the index's messages to it.
//
// The Model is shaped so that each page carries exactly what it needs: the
// note being written travels inside `Writing`. While it is written, the index
// keeps listing it as it was, so the cards behind the editor keep their
// places and the card slides from there on return.

///|
using @rabbita {type Cmd, type Emit}

///|
using @vector {type Vector}

///|
/// What the URL asks for, parsed once from its fragment.
priv enum Route {
  IndexRoute
  NoteRoute(String)
  NewRoute
}

///|
priv struct Note {
  id : String
  text : String
} derive(Eq)

///|
/// Where the note being written came from.
priv enum Origin {
  /// It was listed at `at` as `original` when writing began.
  Listed(at~ : Int, original~ : Note)
  /// It was a New document that became a note on its first change.
  Created
} derive(Eq)

///|
priv struct Session {
  note : Note
  origin : Origin
} derive(Eq)

///|
/// What the open editor writes into. The view draws the editor again before
/// the next input event, so the editor it hands to `Edited` is always the one
/// on screen.
priv enum Editor {
  /// The note is out of `notes` while it is written and returns on leaving.
  Writing(Session)
  /// The untouched New document; it holds no note until its first change.
  Drafting
} derive(Eq)

///|
priv enum Page {
  Index
  Editing(Editor)
} derive(Eq)

///|
/// Delete document, from its request to the note leaving the index.
priv enum Deletion {
  NoDeletion
  /// The confirmation for `Note` is open.
  Confirming(Note)
  /// Confirmed; the note stays listed, Pending deletion, until it is gone.
  Deleting(Note)
} derive(Eq)

///|
/// How long a confirmed deletion stays pending. Notes live in memory, so
/// this stands in for the storage acknowledgment.
const DELETE_MS : Int = 700

///|
/// The element ID of the Delete confirmation.
const DELETE_DIALOG_ID : String = "delete-document"

///|
priv struct Model {
  /// Most recently changed first, without a note held by the page.
  notes : Vector[Note]
  page : Page
  index : @document_index.DocumentIndex
  deletion : Deletion
  next_id : Int
} derive(Eq)

///|
priv enum Msg {
  UrlChanged(@url.Url)
  UrlRequested(@url.UrlRequest)
  IndexMsg(@document_index.Msg)
  /// The text typed into `Editor`.
  Edited(Editor, String)
  EditorLeft
  /// Delete document was chosen on the card of this note.
  DeleteRequested(String)
  /// Delete document was confirmed.
  DeleteConfirmed
  /// The Delete confirmation was cancelled, with its button or Escape.
  DeleteCancelled
  /// The pending deletion of this note is done.
  DeleteFinished(Note)
}

///|
fn route_of(url : @url.Url) -> Route {
  let fragment = url.fragment.unwrap_or("")
  let path = if fragment.has_prefix("#") {
    fragment.view(start_offset=1).to_owned()
  } else {
    fragment
  }
  if path == "/new" {
    NewRoute
  } else if path.has_prefix("/n/") && path.length() > 3 {
    NoteRoute(path.view(start_offset=3).to_owned())
  } else {
    IndexRoute
  }
}

///|
fn route_of_href(href : String) -> Route {
  try @url.parse(href) catch {
    _ => IndexRoute
  } noraise {
    url => route_of(url)
  }
}

///|
/// The notes as the index lists them. They live in memory, so every one is
/// saved and loaded; only deletion changes what a card shows.
/// While one note is being deleted, the others cannot be.
fn seeds(
  notes : Vector[Note],
  deletion : Deletion,
) -> Array[@document_index.Seed] {
  notes
  .map(note => @document_index.Seed::{
    key: note.id,
    href: "#/n/\{note.id}",
    text: note.text,
    status: Saved,
    deletion: match deletion {
      Deleting(deleting) if deleting.id == note.id => Pending
      // One deletion at a time, as in Recent documents.
      Deleting(_) => Blocked
      NoDeletion | Confirming(_) => Available(ThisBrowser)
    },
    loading: false,
  })
  .to_array()
}

///|
/// The notes listed as they are now.
fn listed_seeds(model : Model) -> Array[@document_index.Seed] {
  seeds(model.notes, model.deletion)
}

///|
/// Every note, with whatever the page holds put back where it belongs once
/// the page is left: a written note at the front if it changed, otherwise
/// at its old place.
fn settled_notes(model : Model) -> Vector[Note] {
  match model.page {
    Editing(Writing({ note, origin: Listed(at~, original~), })) if note.text ==
      original.text => inserted(model.notes, at, note)
    Editing(Writing({ note, .. })) =>
      match kept(note) {
        Some(note) => inserted(model.notes, 0, note)
        None => model.notes
      }
    Index | Editing(Drafting) => model.notes
  }
}

///|
/// `notes` with `note` inserted at `at`.
fn inserted(notes : Vector[Note], at : Int, note : Note) -> Vector[Note] {
  notes.take(at).push(note).concat(notes.drop(at))
}

///|
/// A note is kept only while its card has something to show, so `notes`
/// never holds an empty one: a note emptied in the editor is dropped here,
/// when the editor is left.
fn kept(note : Note) -> Note? {
  match @document_lead.extract(note.text).form() {
    Empty => None
    Heading | Task(_) | Quote | Code | List(_) | Plain => Some(note)
  }
}

///|
fn derived_name(note : Note) -> String {
  match @document_lead.derive_name(note.text).text() {
    "" => "Unnamed document"
    name => name
  }
}

///|
/// Return to the index, which learns where the note went.
fn leave_writing(model : Model, session : Session) -> (Model, Cmd) {
  let notes = settled_notes(model)
  let listed = seeds(notes, model.deletion)
  let (index, cmd) = match (kept(session.note), session.origin) {
    (None, Listed(_)) =>
      model.index.removed(
        listed[:],
        key=session.note.id,
        announcement="Removed empty document",
      )
    (None, Created) => (model.index.return_focus(), @cmd.none)
    (Some(note), _) =>
      (model.index.returned_from(listed[:], key=note.id), @cmd.none)
  }
  ({ ..model, notes, page: Index, index, }, cmd)
}

///|
fn open_note(model : Model, id : String) -> (Model, Cmd) {
  let notes = settled_notes(model)
  let mut found = None
  for i in 0..<notes.length() {
    if notes[i].id == id {
      found = Some(i)
      break
    }
  }
  match found {
    Some(at) => {
      let note = notes[at]
      (
        {
          ..model,
          notes: notes.take(at).concat(notes.drop(at + 1)),
          page: Editing(Writing({ note, origin: Listed(at~, original=note), })),
          index: model.index.listing(seeds(notes, model.deletion)[:]),
        },
        @cmd.none,
      )
    }
    None => (model, @nav.replace_url("#/"))
  }
}

///|
fn navigate(model : Model, route : Route) -> (Model, Cmd) {
  match (model.page, route) {
    (Index, IndexRoute) | (Editing(Drafting), NewRoute) => (model, @cmd.none)
    (Editing(Writing(session)), NoteRoute(id)) if session.note.id == id =>
      (model, @cmd.none)
    (Editing(Writing(session)), IndexRoute) => leave_writing(model, session)
    (Editing(Drafting), IndexRoute) =>
      ({ ..model, page: Index, index: model.index.return_focus(), }, @cmd.none)
    (_, NoteRoute(id)) => open_note(model, id)
    (_, NewRoute) => {
      let notes = settled_notes(model)
      (
        {
          ..model,
          notes,
          page: Editing(Drafting),
          index: model.index.listing(seeds(notes, model.deletion)[:]),
        },
        @cmd.none,
      )
    }
  }
}

///|
fn edit(model : Model, editor : Editor, text : String) -> (Model, Cmd) {
  match editor {
    Drafting => {
      let note = { id: "n\{model.next_id}", text, }
      (
        {
          ..model,
          page: Editing(Writing({ note, origin: Created, })),
          next_id: model.next_id + 1,
        },
        @nav.replace_url("#/n/\{note.id}"),
      )
    }
    Writing(session) =>
      (
        {
          ..model,
          page: Editing(
            Writing({ ..session, note: { id: session.note.id, text, }, }),
          ),
        },
        @cmd.none,
      )
  }
}

///|
fn delete_step(model : Model, msg : Msg) -> (Model, Cmd) {
  match (msg, model.deletion) {
    (DeleteRequested(id), NoDeletion) =>
      match model.notes.iter().find_first(note => note.id == id) {
        Some(note) =>
          (
            { ..model, deletion: Confirming(note), },
            @dialog.show(DELETE_DIALOG_ID),
          )
        None => (model, @cmd.none)
      }
    (DeleteConfirmed, Confirming(note)) => {
      let deleting = { ..model, deletion: Deleting(note), }
      (
        { ..deleting, index: model.index.listing(listed_seeds(deleting)[:]), },
        @dialog.close(DELETE_DIALOG_ID),
      )
    }
    (DeleteCancelled, Confirming(_)) =>
      ({ ..model, deletion: NoDeletion, }, @dialog.close(DELETE_DIALOG_ID))
    (DeleteFinished(note), _) => {
      let gone = {
        ..model,
        notes: model.notes.filter(other => other.id != note.id),
        deletion: NoDeletion,
      }
      let (index, cmd) = model.index.removed(
        listed_seeds(gone)[:],
        key=note.id,
        announcement="Deleted \"\{derived_name(note)}\"",
      )
      ({ ..gone, index, }, cmd)
    }
    // The confirmation is modal and a pending deletion withholds every
    // trash button, so no other message reaches a deletion.
    _ => (model, @cmd.none)
  }
}

///|
fn update(model : Model, msg : Msg, _ : Emit[Msg]) -> (Model, Cmd) {
  match msg {
    UrlRequested(Internal(url)) =>
      (model, @nav.push_url("#" + url.fragment.unwrap_or("/")))
    UrlRequested(External(href)) => (model, @nav.load(href))
    UrlChanged(url) => navigate(model, route_of(url))
    IndexMsg(msg) => {
      let (index, cmd) = model.index.update(msg)
      ({ ..model, index, }, cmd)
    }
    Edited(editor, text) => edit(model, editor, text)
    EditorLeft => (model, @nav.push_url("#/"))
    DeleteRequested(_)
    | DeleteConfirmed
    | DeleteCancelled
    | DeleteFinished(_) => delete_step(model, msg)
  }
}

///|
fn subscriptions(
  fonts : @dom.EventTarget,
  model : Model,
  emit : Emit[Msg],
) -> @sub.Sub {
  @sub.batch([
    @sub.on_url_changed(url => emit(UrlChanged(url))),
    @sub.on_url_request(request => emit(UrlRequested(request))),
    model.index.subscriptions(fonts, emit.map(msg => IndexMsg(msg))),
    match model.deletion {
      Deleting(note) =>
        @timeout.after(
          "note-index.delete(\{note.id})",
          DELETE_MS,
          emit(DeleteFinished(note)),
        )
      NoDeletion | Confirming(_) => @sub.none
    },
  ])
}

///|
fn initial_state(route : Route) -> (Model, Cmd) {
  let notes = Vector(sample_texts.mapi((i, text) => { id: "n\{i + 1}", text, }))
  let model = {
    notes,
    page: Index,
    deletion: NoDeletion,
    index: @document_index.DocumentIndex(
      seeds(notes, NoDeletion)[:],
      new_href="#/new",
    ),
    next_id: notes.length() + 1,
  }
  match route {
    IndexRoute => (model, @cmd.none)
    NoteRoute(id) => open_note(model, id)
    NewRoute => ({ ..model, page: Editing(Drafting), }, @cmd.none)
  }
}

///|
/// The app, started once the card fonts have loaded.
fn app(
  startup_route : Route,
  fonts : @dom.EventTarget,
) -> @rabbita.Val[@rabbita.Html] {
  let (model, emit) = @rabbita.create_state_with_init(
    init=_ => initial_state(startup_route),
    update~,
    subscriptions=(model, emit) => subscriptions(fonts, model, emit),
  )
  view(model, emit)
}
