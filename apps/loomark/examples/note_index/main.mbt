// App code: state transitions and their commands. DOM effects are requested
// through the shell's `focus_after_render`, `grid_width_subscription`,
// `card_height_subscription`, `fonts_loaded_subscription`, and
// `once_after_subscription`.
//
// The Model is shaped so that each page carries exactly what it needs: the
// note being written travels inside `Writing`. Nothing refers to a note by id
// and looks it up again later. A wait, such as a highlight fading, is a
// subscription that exists only while its state does, so no message arrives
// for a state that is gone.

///|
using @rabbita {type Cmd, type Emit, type Html, type Val}

///|
priv enum Layout {
  Cards
  List
} derive(Eq)

///|
priv enum CardSize {
  Small
  Medium
  Large
} derive(Eq)

///|
fn CardSize::min_width(self : CardSize) -> Int {
  match self {
    Small => 200
    Medium => 250
    Large => 320
  }
}

///|
/// What the URL asks for, parsed once from its fragment.
priv enum Route {
  IndexRoute
  NoteRoute(String)
  NewRoute
}

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
priv enum Page {
  Index
  Editing(Editor)
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
/// The packed grid on screen: the last layout `packed_now` produced, kept
/// until the next one, so for a while it may show the notes as they were.
priv enum ShownGrid {
  NotMeasured
  Packed(CardLayout)
} derive(Eq)

///|
/// Whether the grid width is still changing. Cards are measured only once it
/// has held still, so a window drag measures them once rather than per frame.
priv enum GridResize {
  Steady
  /// Waiting for `ResizeSettled`; each width change restarts the wait.
  Resizing
} derive(Eq)

///|
/// How long the grid width must hold still before cards are measured again.
const RESIZE_SETTLE_MS : Int = 150

///|
/// How long a note moved to the front stays highlighted.
const HIGHLIGHT_MS : Int = 1200

///|
priv struct Model {
  /// Most recently changed first, without a note held by the page.
  notes : Array[Note]
  page : Page
  query : String
  layout : Layout
  size : CardSize
  /// Width available to the card grid, measured by the shell.
  grid_width : Int
  resize : GridResize
  /// The note just moved to the front, highlighted for `HIGHLIGHT_MS`.
  highlight : String?
  /// Card heights the shell measured at the current column widths.
  heights : @hashmap.HashMap[CardMeasure, Int]
  /// The card that last held focus. A cursor built from it falls back to the
  /// first visible card, so this is a preference, not a guarantee.
  focused : String?
  /// The grid on screen, brought up to date by `update` after every message.
  grid : ShownGrid
  /// The card to focus once the grid on screen draws it. A new note's card
  /// is drawn only after its first measurement, so focus waits for it here.
  focus_pending : String?
  announcement : String
  next_id : Int
} derive(Eq)

///|
priv enum Msg {
  UrlChanged(@url.Url)
  UrlRequested(@url.UrlRequest)
  GridMeasured(Double)
  /// The grid width has not changed for `RESIZE_SETTLE_MS`.
  ResizeSettled
  CardsMeasured(Array[(CardMeasure, Int)])
  /// Faces finished loading after startup; measured heights may be stale.
  FontsLoaded
  Searched(String)
  SearchLeft
  LayoutChosen(Layout)
  SizeChosen(CardSize)
  /// The text typed into `Editor`.
  Edited(Editor, String)
  EditorLeft
  CardKey(CardKeyAction)
  CardFocused(String)
  /// The note that moved to the front has been highlighted long enough.
  HighlightEnded
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
/// The notes the index lists. A note being written is listed as it was when
/// writing began, so the index behind the editor keeps its measured layout,
/// and on leaving, the card moves from there to its new place.
fn listed(model : Model) -> Array[Note] {
  match model.page {
    Editing(Writing({ origin: Listed(at~, original~), .. })) => {
      let notes = model.notes.copy()
      notes.insert(at, original)
      notes
    }
    Index | Editing(Writing({ origin: Created, .. }) | Drafting) => model.notes
  }
}

///|
/// Every note, with whatever the page holds put back where it belongs once
/// the page is left: a written note at the front if it changed, otherwise
/// at its old place.
fn settled_notes(model : Model) -> Array[Note] {
  match model.page {
    Editing(Writing({ note, origin: Listed(at~, original~), })) if note.text ==
      original.text => {
      let notes = model.notes.copy()
      notes.insert(at, note)
      notes
    }
    Editing(Writing({ note, .. })) =>
      match kept(note) {
        Some(note) => [note, ..model.notes]
        None => model.notes
      }
    Index | Editing(Drafting) => model.notes
  }
}

///|
/// A note is kept only while its card has something to show, so `notes`
/// never holds an empty one: a note emptied in the editor is dropped here,
/// when the editor is left.
fn kept(note : Note) -> Note? {
  match note.lead.form() {
    Empty => None
    Heading | Task(_) | Quote | Code | List(_) | Plain => Some(note)
  }
}

///|
/// The visible notes with the focused card, or `None` when none match.
fn visible_cursor(model : Model) -> Cursor[Note]? {
  let query = model.query.trim().to_owned().to_lower()
  let visible = listed(model).filter(note => {
    query == "" || note.search_text.contains(query)
  })
  Cursor::focus_on(visible, note => Some(note.id) == model.focused)
}

///|
fn columns(model : Model) -> Columns {
  columns_for(grid_width=model.grid_width, min_column=model.size.min_width())
}

///|
/// The cards the shell still has to measure before the grid can show every
/// listed note. All listed notes are measured, not only the visible ones, so
/// a search never waits for a measurement.
fn unmeasured(model : Model) -> Array[MeasureRequest] {
  match model.layout {
    Cards =>
      unmeasured_among(
        model.heights,
        measures_for(listed(model), columns(model)),
      )
    List => []
  }
}

///|
/// The cards the shell has to measure now. While the grid width changes,
/// none are, so a window drag measures them once rather than per frame.
fn to_measure(model : Model) -> Array[MeasureRequest] {
  match model.resize {
    Steady => unmeasured(model)
    Resizing => []
  }
}

///|
/// The visible cards packed, once all of them are measured; `None` means the
/// grid on screen stays as it is.
fn packed_now(model : Model) -> CardLayout? {
  guard model.layout is Cards && visible_cursor(model) is Some(visible) else {
    return None
  }
  let columns = columns(model)
  measured_notes(model.heights, visible, columns).map(notes => {
    pack_cards(notes, columns)
  })
}

///|
/// Keep the heights measured at the current column widths, with `measured`.
fn with_heights(model : Model, measured : Array[(CardMeasure, Int)]) -> Model {
  let columns = columns(model)
  let current = (measure : CardMeasure) => {
    measure.width == columns.span_width(1) ||
    measure.width == columns.span_width(2)
  }
  let kept = model.heights.filter((measure, _) => current(measure))
  {
    ..model,
    heights: measured.fold(init=kept, (heights, entry) => {
      heights.add(entry.0, entry.1)
    }),
  }
}

///|
fn card_dom_id(id : String) -> String {
  "card-\{id}"
}

///|
fn derived_name(note : Note) -> String {
  match @document_lead.derive_name(note.text).text() {
    "" => "Unnamed document"
    name => name
  }
}

///|
/// Focus `note` once its card is drawn, when the search still shows it;
/// otherwise focus stays put.
fn focus_note(model : Model, note : Note) -> Model {
  match visible_cursor({ ..model, focused: Some(note.id), }) {
    Some(cursor) if cursor.current.id == note.id =>
      { ..model, focus_pending: Some(note.id), }
    _ => model
  }
}

///|
/// Whether the grid the view draws for `model` holds the card of `id`.
fn shows_card(model : Model, id : String) -> Bool {
  guard model.page is Index && visible_cursor(model) is Some(visible) else {
    return false
  }
  match (model.layout, model.grid) {
    (Cards, Packed(layout)) =>
      layout.cards.to_array().any(card => card.note.id == id)
    (Cards, NotMeasured) => false
    (List, _) => visible.to_array().any(note => note.id == id)
  }
}

///|
/// Return to the index. A changed note moves to the front: its card, still
/// at its old place behind the editor, slides there and is highlighted.
fn leave_writing(model : Model, session : Session) -> (Model, Cmd) {
  match (kept(session.note), session.origin) {
    (None, origin) => {
      // The note is already out of `notes`; focus the card now in its place.
      let (focused, announcement) = match origin {
        Listed(at~, ..) =>
          (
            model.notes
            .get(at.min(model.notes.length() - 1))
            .map(note => note.id),
            "Removed empty document",
          )
        Created => (model.focused, model.announcement)
      }
      let back = { ..model, page: Index, focused, announcement, }
      match visible_cursor(back) {
        Some(cursor) => (focus_note(back, cursor.current), @cmd.none)
        None => (back, @cmd.none)
      }
    }
    (Some(note), Listed(original~, ..)) if note.text == original.text => {
      let back = {
        ..model,
        notes: settled_notes(model),
        page: Index,
        focused: Some(note.id),
      }
      (focus_note(back, note), @cmd.none)
    }
    (Some(note), Listed(_) | Created) => {
      let back = {
        ..model,
        notes: [note, ..model.notes],
        page: Index,
        focused: Some(note.id),
        highlight: Some(note.id),
        announcement: "Moved to first: \{derived_name(note)}",
      }
      (focus_note(back, note), @cmd.none)
    }
  }
}

///|
fn open_note(model : Model, id : String) -> (Model, Cmd) {
  let notes = settled_notes(model)
  match notes.search_by(note => note.id == id) {
    Some(at) => {
      let note = notes[at]
      let rest = notes.copy()
      rest.remove(at) |> ignore
      (
        {
          ..model,
          notes: rest,
          page: Editing(Writing({ note, origin: Listed(at~, original=note), })),
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
    (Editing(Drafting), IndexRoute) => {
      let back = { ..model, page: Index, }
      match visible_cursor(back) {
        Some(cursor) => (focus_note(back, cursor.current), @cmd.none)
        None => (back, @cmd.none)
      }
    }
    (_, NoteRoute(id)) => open_note(model, id)
    (_, NewRoute) =>
      (
        { ..model, notes: settled_notes(model), page: Editing(Drafting), },
        @cmd.none,
      )
  }
}

///|
fn edit(model : Model, editor : Editor, text : String) -> (Model, Cmd) {
  match editor {
    Drafting => {
      let note = Note("n\{model.next_id}", text)
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
            Writing({ ..session, note: Note(session.note.id, text), }),
          ),
        },
        @cmd.none,
      )
  }
}

///|
/// Arrows follow the cards as they are shown: in Cards, the packed grid on
/// screen.
fn move_focus(model : Model, direction : Direction) -> (Model, Cmd) {
  let next = match (model.layout, model.grid, visible_cursor(model)) {
    (Cards, Packed(layout), _) =>
      neighbour(layout.cards.map(card => card.rect()), direction).map(card => {
        card.id
      })
    (Cards, NotMeasured, _) | (List, _, None) => None
    (List, _, Some(cursor)) =>
      list_neighbour(cursor, direction).map(note => note.id)
  }
  match next {
    Some(id) =>
      ({ ..model, focused: Some(id), }, focus_after_render(card_dom_id(id)))
    None => (model, @cmd.none)
  }
}

///|
/// Every transition, then the grid on screen brought up to date: the visible
/// cards packed once all are measured, otherwise the grid as it was.
fn update(model : Model, msg : Msg, _ : Emit[Msg]) -> (Model, Cmd) {
  let (next, cmd) = transition(model, msg)
  match packed_now(next) {
    Some(layout) => ({ ..next, grid: Packed(layout), }, cmd)
    None => (next, cmd)
  }
}

///|
fn transition(model : Model, msg : Msg) -> (Model, Cmd) {
  match msg {
    UrlRequested(Internal(url)) =>
      (model, @nav.push_url("#" + url.fragment.unwrap_or("/")))
    UrlRequested(External(href)) => (model, @nav.load(href))
    UrlChanged(url) => navigate(model, route_of(url))
    GridMeasured(measured) =>
      match grid_width_of(measured) {
        width if width == model.grid_width => (model, @cmd.none)
        grid_width => ({ ..model, grid_width, resize: Resizing, }, @cmd.none)
      }
    ResizeSettled => ({ ..model, resize: Steady, }, @cmd.none)
    CardsMeasured(measured) => (with_heights(model, measured), @cmd.none)
    // Every card is measured again; the grid on screen stays until then.
    FontsLoaded => ({ ..model, heights: @hashmap.HashMap([]), }, @cmd.none)
    Searched(query) => ({ ..model, query, }, @cmd.none)
    SearchLeft =>
      match (model.query, visible_cursor(model)) {
        ("", Some(cursor)) =>
          ({ ..model, focus_pending: Some(cursor.current.id), }, @cmd.none)
        ("", None) => (model, @cmd.none)
        (_, _) => ({ ..model, query: "", }, @cmd.none)
      }
    LayoutChosen(layout) => ({ ..model, layout, }, @cmd.none)
    SizeChosen(size) => ({ ..model, size, }, @cmd.none)
    Edited(editor, text) => edit(model, editor, text)
    EditorLeft => (model, @nav.push_url("#/"))
    // Focus moves after the next render; a key pressed before then still
    // starts from the card the model already chose.
    CardKey(MoveFocus(direction)) => move_focus(model, direction)
    CardKey(FocusSearch) => (model, focus_after_render("search"))
    CardKey(OpenNewDocument) => (model, @nav.push_url("#/new"))
    CardKey(LetBrowserHandle) => (model, @cmd.none)
    CardFocused(id) =>
      ({ ..model, focused: Some(id), focus_pending: None, }, @cmd.none)
    HighlightEnded => ({ ..model, highlight: None, }, @cmd.none)
  }
}

///|
fn subscriptions(page : HostPage, model : Model, emit : Emit[Msg]) -> @sub.Sub {
  @sub.batch([
    @sub.on_url_changed(url => emit(UrlChanged(url))),
    @sub.on_url_request(request => emit(UrlRequested(request))),
    grid_width_subscription(page.grid_probe, width => emit(GridMeasured(width))),
    fonts_loaded_subscription(page.fonts, emit(FontsLoaded)),
    match model.resize {
      Steady => @sub.none
      // Keyed by the width, so each change restarts the wait.
      Resizing =>
        once_after_subscription(
          "note-index.resize-settled(\{model.grid_width})",
          RESIZE_SETTLE_MS,
          emit(ResizeSettled),
        )
    },
    match model.focus_pending {
      Some(id) if shows_card(model, id) =>
        focus_card_subscription(card_dom_id(id), emit(CardFocused(id)))
      _ => @sub.none
    },
    match model.highlight {
      None => @sub.none
      Some(id) =>
        once_after_subscription(
          "note-index.highlight(\{id})",
          HIGHLIGHT_MS,
          emit(HighlightEnded),
        )
    },
    match to_measure(model) {
      [] => @sub.none
      requests =>
        card_height_subscription(requests.map(request => request.measure), measured => {
          emit(CardsMeasured(measured))
        })
    },
  ])
}

///|
fn initial_state(route : Route, grid_width : Int) -> (Model, Cmd) {
  let notes = sample_texts.mapi((i, text) => Note("n\{i + 1}", text))
  let model = {
    notes,
    page: Index,
    query: "",
    layout: Cards,
    size: Medium,
    grid_width,
    resize: Steady,
    highlight: None,
    heights: @hashmap.HashMap([]),
    focused: None,
    focus_pending: None,
    grid: NotMeasured,
    announcement: "",
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
fn app(startup_route : Route, page : HostPage) -> @rabbita.Val[Html] {
  let grid_width = grid_width_of(page.grid_probe.get_client_width())
  let (model, emit) = @rabbita.create_state_with_init(
    init=_ => initial_state(startup_route, grid_width),
    update~,
    subscriptions=(model, emit) => subscriptions(page, model, emit),
  )
  view(model, emit)
}
