// The Document index: state transitions and their commands. DOM effects are
// requested from `@browser` and `@timeout` as subscriptions and commands,
// such as measuring the grid width and the cards, and moving focus.
//
// The host keeps a `DocumentIndex` in its Model, forwards `Msg` to `update`,
// runs `subscriptions` while the index is drawn, says when another screen
// covers it and when it is shown again with `covered` and `shown`, and tells
// it what happened elsewhere through `returned_from`, `removed`, and
// `return_focus`. A wait, such as a highlight fading, is a subscription
// that exists only while its state does, so no message arrives for a state
// that is gone.

///|
using @rabbita {type Cmd, type Emit}

///|
/// The narrowest a card column may be; the grid fits as many as it can.
const MIN_COLUMN : Int = 250

///|
/// How long the grid width must hold still before cards are measured again.
const RESIZE_SETTLE_MS : Int = 150

///|
/// How long a card moved to the front stays highlighted.
const HIGHLIGHT_MS : Int = 1200

///|
/// The element ID of the Search field.
const SEARCH_ID : String = "document-index-search"

///|
/// The element ID of the card grid, whose text search matches are painted in.
const GRID_ID : String = "document-index-grid"

///|
/// The name of the CSS highlight that paints search matches.
const MATCH_HIGHLIGHT : String = "document-index-match"

///|
/// The element ID of the empty element laid out like the grid, whose width
/// the grid follows.
const GRID_WIDTH_ID : String = "document-index-grid-width"

///|
/// The packed grid on screen: the last layout `packed_now` produced, kept
/// until the next one, so for a while it may show the cards as they were.
priv enum ShownGrid[K] {
  NotMeasured
  Packed(CardLayout[K])
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
/// Whether the index is in front. Covered, it stays laid out but draws
/// nothing new. Chromium closes the open typing undo group whenever any node
/// leaves the document, wherever it is, and measuring cards removes the cards
/// it drew; so measuring behind the Editor would split what the reader types
/// into separate Undo steps. Covered, the index only notes the grid width
/// and loaded faces, and catches up once it is in front again.
priv enum Presence {
  InFront
  Covered
} derive(Eq)

///|
struct DocumentIndex[K] {
  presence : Presence
  /// Most recently changed first.
  cards : Vector[Card[K]]
  /// Where New leads.
  new_href : String
  query : String
  /// Width available to the card grid, once the shell has measured it.
  /// Until then nothing is measured or packed.
  grid_width : Int?
  resize : GridResize
  /// The card just moved to the front, highlighted for `HIGHLIGHT_MS`.
  highlight : K?
  /// Card heights the shell measured at the current column widths.
  heights : @hashmap.HashMap[CardMeasure, Int]
  /// The card that last held focus. A cursor built from it falls back to the
  /// first visible card, so this is a preference, not a guarantee.
  focused : K?
  /// The grid on screen, brought up to date after every change.
  grid : ShownGrid[K]
  /// The card to focus once the grid on screen draws it. A changed card is
  /// drawn only after its measurement, so focus waits for it here.
  focus_pending : K?
  announcement : String
} derive(Eq)

///|
pub extend DocumentIndex with Eq::{equal, not_equal}

///|
enum Msg[K] {
  GridMeasured(Double)
  /// The grid width has not changed for `RESIZE_SETTLE_MS`.
  ResizeSettled
  CardsMeasured(Array[(CardMeasure, Int)])
  /// Faces finished loading after startup; measured heights may be stale.
  FontsLoaded
  Searched(String)
  SearchLeft
  /// The search was cleared from the empty result; typing resumes there.
  SearchCleared
  CardKey(CardKeyAction)
  CardFocused(K)
  /// The card that moved to the front has been highlighted long enough.
  HighlightEnded
}

///|
/// An index listing `seeds`, most recently changed first. Its cards appear
/// once it has measured the grid it draws and the cards in it.
pub fn[K : Eq + Hash] DocumentIndex::DocumentIndex(
  seeds : ArrayView[Seed[K]],
  new_href~ : String,
) -> DocumentIndex[K] {
  {
    presence: InFront,
    cards: cards_of(seeds, Vector([])),
    new_href,
    query: "",
    grid_width: None,
    resize: Steady,
    highlight: None,
    heights: @hashmap.HashMap([]),
    focused: None,
    grid: NotMeasured,
    focus_pending: None,
    announcement: "",
  }
}

///|
/// The search as cards are matched against it, or `None` when it asks for
/// nothing.
fn[K] search_query(index : DocumentIndex[K]) -> @text_search.Query? {
  @text_search.Query::parse(index.query)
}

///|
/// The visible cards with the focused one, or `None` when none match.
fn[K : Eq] visible_cursor(index : DocumentIndex[K]) -> Cursor[Card[K]]? {
  let query = search_query(index)
  let visible = index.cards.filter(card => {
    match query {
      None => true
      Some(query) => query.found_in(card.search_text)
    }
  })
  Cursor::focus_on(visible, card => Some(card.key) == index.focused)
}

///|
/// The column grid, once the grid width is known.
fn[K] columns(index : DocumentIndex[K]) -> Columns? {
  index.grid_width.map(grid_width => {
    columns_for(grid_width~, min_column=MIN_COLUMN)
  })
}

///|
/// The cards the shell still has to measure before the grid can show every
/// listed card. All of them are measured, not only the visible ones, so a
/// search never waits for a measurement.
fn[K] unmeasured(index : DocumentIndex[K]) -> Array[MeasureRequest[K]] {
  match columns(index) {
    Some(columns) =>
      unmeasured_among(index.heights, measures_for(index.cards, columns))
    None => []
  }
}

///|
/// The cards the shell has to measure now. While the grid width changes,
/// none are, so a window drag measures them once rather than per frame.
fn[K] to_measure(index : DocumentIndex[K]) -> Array[MeasureRequest[K]] {
  match (index.presence, index.resize) {
    (InFront, Steady) => unmeasured(index)
    (InFront, Resizing) | (Covered, _) => []
  }
}

///|
/// The visible cards packed, once all of them are measured; `None` means the
/// grid on screen stays as it is.
fn[K : Eq] packed_now(index : DocumentIndex[K]) -> CardLayout[K]? {
  guard visible_cursor(index) is Some(visible) &&
    columns(index) is Some(columns) else {
    return None
  }
  measured_cards(index.heights, visible, columns).map(cards => {
    pack_cards(cards, columns)
  })
}

///|
/// `index` with the grid on screen brought up to date: the visible cards
/// packed once all are measured, otherwise the grid as it was.
fn[K : Eq] settled(index : DocumentIndex[K]) -> DocumentIndex[K] {
  match (index.presence, packed_now(index)) {
    (InFront, Some(layout)) => { ..index, grid: Packed(layout), }
    (InFront, None) | (Covered, _) => index
  }
}

///|
/// Keep the heights measured at the current column widths, with `measured`.
fn[K] with_heights(
  index : DocumentIndex[K],
  measured : Array[(CardMeasure, Int)],
) -> DocumentIndex[K] {
  let columns = columns(index)
  let current = (measure : CardMeasure) => {
    columns is Some(columns) &&
    (
      measure.width == columns.span_width(1) ||
      measure.width == columns.span_width(2)
    )
  }
  let kept = index.heights.filter((measure, _) => current(measure))
  {
    ..index,
    heights: measured.fold(init=kept, (heights, entry) => {
      heights.add(entry.0, entry.1)
    }),
  }
}

///|
fn[K : Show] card_dom_id(key : K) -> String {
  "card-\{key}"
}

///|
/// The element ID of the trash button on the card of `key`, where focus
/// returns when its Delete confirmation is cancelled.
pub fn[K : Show] card_delete_dom_id(key : K) -> String {
  "card-delete-\{key}"
}

///|
fn[K] derived_name(card : Card[K]) -> String {
  match @document_lead.derive_name(card.text).text() {
    "" => "Unnamed document"
    name => name
  }
}

///|
/// Focus the card of `key` once it is drawn, when the search still shows it;
/// otherwise focus stays put.
fn[K : Eq] focus_card(index : DocumentIndex[K], key : K) -> DocumentIndex[K] {
  match visible_cursor({ ..index, focused: Some(key), }) {
    Some(cursor) if cursor.current.key == key =>
      { ..index, focused: Some(key), focus_pending: Some(key), }
    _ => index
  }
}

///|
/// Whether the grid on screen holds the card of `key`.
fn[K : Eq] shows_card(index : DocumentIndex[K], key : K) -> Bool {
  match index.grid {
    Packed(layout) => layout.cards.to_array().any(card => card.card.key == key)
    NotMeasured => false
  }
}

///|
/// The index listing `seeds` instead, with focus left as it is.
pub fn[K : Eq + Hash] DocumentIndex::listing(
  self : DocumentIndex[K],
  seeds : ArrayView[Seed[K]],
) -> DocumentIndex[K] {
  settled({ ..self, cards: cards_of(seeds, self.cards), })
}

///|
/// The index covered by another screen, such as the Editor, until `shown`.
pub fn[K] DocumentIndex::covered(self : DocumentIndex[K]) -> DocumentIndex[K] {
  { ..self, presence: Covered, }
}

///|
/// The index in front, catching up with what changed while it was covered. A
/// width that changed then is no window drag, so its cards are measured now
/// rather than after the wait for a drag to end.
pub fn[K : Eq] DocumentIndex::shown(
  self : DocumentIndex[K],
) -> DocumentIndex[K] {
  match self.presence {
    InFront => self
    Covered => settled({ ..self, presence: InFront, resize: Steady, })
  }
}

///|
/// The index shown again with focus on the card that holds the Tab stop.
pub fn[K : Eq] DocumentIndex::return_focus(
  self : DocumentIndex[K],
) -> DocumentIndex[K] {
  match visible_cursor(self) {
    Some(cursor) => focus_card(self, cursor.current.key)
    None => self
  }
}

///|
/// The index shown again after the document of `key` was open, now listing
/// `seeds`. A document whose Change time moved on, or that is new, has
/// moved to the front: its card slides there from its old place, is highlighted, and is
/// announced. Either way its card takes focus.
pub fn[K : Eq + Hash] DocumentIndex::returned_from(
  self : DocumentIndex[K],
  seeds : ArrayView[Seed[K]],
  key~ : K,
) -> DocumentIndex[K] {
  let before = self.cards.iter().find_first(card => card.key == key)
  let index = { ..self, cards: cards_of(seeds, self.cards), }
  match index.cards.iter().find_first(card => card.key == key) {
    None => settled(index.return_focus())
    Some(card) if before is Some(old) && old.changed_at == card.changed_at =>
      settled(focus_card(index, key))
    Some(card) =>
      settled(
        focus_card(
          {
            ..index,
            highlight: Some(key),
            announcement: "Moved to first: \{derived_name(card)}",
          },
          key,
        ),
      )
  }
}

///|
/// The index after the document of `key` left it, now listing `seeds`. Focus
/// moves to the card that holds its place in reading order, the previous one
/// when it was last, or Search when no card remains.
pub fn[K : Eq + Hash] DocumentIndex::removed(
  self : DocumentIndex[K],
  seeds : ArrayView[Seed[K]],
  key~ : K,
  announcement~ : String,
) -> (DocumentIndex[K], Cmd) {
  let mut at = 0
  for i in 0..<self.cards.length() {
    if self.cards[i].key == key {
      at = i
    }
  }
  let index = { ..self, cards: cards_of(seeds, self.cards), announcement, }
  match index.cards.get(at.min(index.cards.length() - 1)) {
    Some(card) => (settled(focus_card(index, card.key)), @cmd.none)
    None => (settled(index), @browser.focus_after_render(SEARCH_ID))
  }
}

///|
/// Arrows follow the cards as they are shown: the packed grid on screen.
fn[K : Show] move_focus(
  index : DocumentIndex[K],
  direction : Direction,
) -> (DocumentIndex[K], Cmd) {
  let next = match index.grid {
    Packed(layout) =>
      neighbour(layout.cards.map(card => card.rect()), direction).map(card => {
        card.id
      })
    NotMeasured => None
  }
  match next {
    Some(key) =>
      (
        { ..index, focused: Some(key), },
        @browser.focus_after_render(card_dom_id(key)),
      )
    None => (index, @cmd.none)
  }
}

///|
/// Every transition, then the grid on screen brought up to date.
pub fn[K : Eq + Show] DocumentIndex::update(
  self : DocumentIndex[K],
  msg : Msg[K],
) -> (DocumentIndex[K], Cmd) {
  let (next, cmd) = transition(self, msg)
  (settled(next), cmd)
}

///|
fn[K : Eq + Show] transition(
  index : DocumentIndex[K],
  msg : Msg[K],
) -> (DocumentIndex[K], Cmd) {
  match msg {
    GridMeasured(measured) =>
      match grid_width_of(measured) {
        width if Some(width) == index.grid_width => (index, @cmd.none)
        // With nothing measured, such as at first, nothing waits for a drag.
        width if index.heights.length() == 0 =>
          ({ ..index, grid_width: Some(width), }, @cmd.none)
        width =>
          ({ ..index, grid_width: Some(width), resize: Resizing, }, @cmd.none)
      }
    ResizeSettled => ({ ..index, resize: Steady, }, @cmd.none)
    CardsMeasured(measured) => (with_heights(index, measured), @cmd.none)
    // Every card is measured again; the grid on screen stays until then.
    FontsLoaded => ({ ..index, heights: @hashmap.HashMap([]), }, @cmd.none)
    Searched(query) => ({ ..index, query, }, @cmd.none)
    SearchLeft =>
      match (index.query, visible_cursor(index)) {
        ("", Some(cursor)) =>
          ({ ..index, focus_pending: Some(cursor.current.key), }, @cmd.none)
        ("", None) => (index, @cmd.none)
        (_, _) => ({ ..index, query: "", }, @cmd.none)
      }
    SearchCleared =>
      ({ ..index, query: "", }, @browser.focus_after_render(SEARCH_ID))
    // Focus moves after the next render; a key pressed before then still
    // starts from the card the index already chose.
    CardKey(MoveFocus(direction)) => move_focus(index, direction)
    CardKey(FocusSearch) => (index, @browser.focus_after_render(SEARCH_ID))
    CardKey(OpenNewDocument) => (index, @nav.push_url(index.new_href))
    CardKey(LetBrowserHandle) => (index, @cmd.none)
    CardFocused(key) =>
      ({ ..index, focused: Some(key), focus_pending: None, }, @cmd.none)
    HighlightEnded => ({ ..index, highlight: None, }, @cmd.none)
  }
}

///|
/// What the index waits for while it is drawn. Covered, it only notes the
/// grid width and faces that finish loading. `fonts` is the document's font
/// face set, which reports faces that finish loading.
pub fn[K : Eq + Show] DocumentIndex::subscriptions(
  self : DocumentIndex[K],
  fonts : @dom.EventTarget,
  emit : Emit[Msg[K]],
) -> @sub.Sub {
  let noted = @sub.batch([
    @browser.rendered_width(GRID_WIDTH_ID, width => emit(GridMeasured(width))),
    @browser.fonts_loaded(fonts, emit(FontsLoaded)),
  ])
  guard self.presence is InFront else { noted }
  @sub.batch([
    noted,
    match self.resize {
      Steady => @sub.none
      // Keyed by the width, so each change restarts the wait.
      Resizing =>
        @timeout.after(
          "document-index.resize-settled(\{self.grid_width.unwrap_or(0)})",
          RESIZE_SETTLE_MS,
          emit(ResizeSettled),
        )
    },
    match self.focus_pending {
      Some(key) if shows_card(self, key) =>
        @browser.focus_when_drawn(card_dom_id(key), emit(CardFocused(key)))
      _ => @sub.none
    },
    match search_query(self) {
      None => @sub.none
      Some(query) =>
        @browser.highlight_occurrences(MATCH_HIGHLIGHT, GRID_ID, query)
    },
    match self.highlight {
      None => @sub.none
      Some(key) =>
        @timeout.after(
          "document-index.highlight(\{key})",
          HIGHLIGHT_MS,
          emit(HighlightEnded),
        )
    },
    match to_measure(self) {
      [] => @sub.none
      requests => {
        let measures = requests.map(request => request.measure)
        @browser.rendered_heights(
          "document-index.cards(\{measures.hash()})",
          "card-measure",
          measures,
          measured => emit(CardsMeasured(measured)),
        )
      }
    },
  ])
}
