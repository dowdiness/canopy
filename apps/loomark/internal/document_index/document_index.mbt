// The Document index: state transitions and their commands. DOM effects are
// requested from `@browser` and `@timeout` as subscriptions and commands,
// such as measuring the grid width and the cards, and moving focus.
//
// The host keeps a `DocumentIndex` in its Model, forwards `Msg` to `update`,
// and tells it what happened elsewhere through `returned_from`, `removed`,
// and `return_focus`. A wait, such as a highlight fading, is a subscription
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
/// The packed grid on screen: the last layout `packed_now` produced, kept
/// until the next one, so for a while it may show the cards as they were.
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
struct DocumentIndex {
  /// Most recently changed first.
  cards : Vector[Card]
  /// Where New leads.
  new_href : String
  query : String
  /// Width available to the card grid, measured by the shell.
  grid_width : Int
  resize : GridResize
  /// The card just moved to the front, highlighted for `HIGHLIGHT_MS`.
  highlight : String?
  /// Card heights the shell measured at the current column widths.
  heights : @hashmap.HashMap[CardMeasure, Int]
  /// The card that last held focus. A cursor built from it falls back to the
  /// first visible card, so this is a preference, not a guarantee.
  focused : String?
  /// The grid on screen, brought up to date after every change.
  grid : ShownGrid
  /// The card to focus once the grid on screen draws it. A changed card is
  /// drawn only after its measurement, so focus waits for it here.
  focus_pending : String?
  announcement : String
} derive(Eq)

///|
pub extend DocumentIndex with Eq::{equal, not_equal}

///|
/// What the index observes on the host page, resolved once at startup.
struct HostPage {
  /// An empty element laid out like the index's content box; its width is
  /// the grid's.
  grid_probe : @dom.HTMLElement
  /// The document's font faces, which report faces that finish loading.
  fonts : @dom.EventTarget
}

///|
pub fn HostPage::HostPage(
  grid_probe~ : @dom.HTMLElement,
  fonts~ : @dom.EventTarget,
) -> HostPage {
  { grid_probe, fonts, }
}

///|
enum Msg {
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
  CardFocused(String)
  /// The card that moved to the front has been highlighted long enough.
  HighlightEnded
}

///|
/// An index listing `seeds`, most recently changed first, in a grid
/// `grid_width` wide, as the shell measured the host page's grid probe.
pub fn DocumentIndex::DocumentIndex(
  seeds : ArrayView[Seed],
  grid_width~ : Double,
  new_href~ : String,
) -> DocumentIndex {
  {
    cards: cards_of(seeds, Vector([])),
    new_href,
    query: "",
    grid_width: grid_width_of(grid_width),
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
/// The search as cards are matched against it.
fn search_query(index : DocumentIndex) -> String {
  index.query.trim().to_owned().to_lower()
}

///|
/// The visible cards with the focused one, or `None` when none match.
fn visible_cursor(index : DocumentIndex) -> Cursor[Card]? {
  let query = search_query(index)
  let visible = index.cards.filter(card => {
    query == "" || card.search_text.contains(query)
  })
  Cursor::focus_on(visible, card => Some(card.key) == index.focused)
}

///|
fn columns(index : DocumentIndex) -> Columns {
  columns_for(grid_width=index.grid_width, min_column=MIN_COLUMN)
}

///|
/// The cards the shell still has to measure before the grid can show every
/// listed card. All of them are measured, not only the visible ones, so a
/// search never waits for a measurement.
fn unmeasured(index : DocumentIndex) -> Array[MeasureRequest] {
  unmeasured_among(index.heights, measures_for(index.cards, columns(index)))
}

///|
/// The cards the shell has to measure now. While the grid width changes,
/// none are, so a window drag measures them once rather than per frame.
fn to_measure(index : DocumentIndex) -> Array[MeasureRequest] {
  match index.resize {
    Steady => unmeasured(index)
    Resizing => []
  }
}

///|
/// The visible cards packed, once all of them are measured; `None` means the
/// grid on screen stays as it is.
fn packed_now(index : DocumentIndex) -> CardLayout? {
  guard visible_cursor(index) is Some(visible) else { return None }
  let columns = columns(index)
  measured_cards(index.heights, visible, columns).map(cards => {
    pack_cards(cards, columns)
  })
}

///|
/// `index` with the grid on screen brought up to date: the visible cards
/// packed once all are measured, otherwise the grid as it was.
fn settled(index : DocumentIndex) -> DocumentIndex {
  match packed_now(index) {
    Some(layout) => { ..index, grid: Packed(layout), }
    None => index
  }
}

///|
/// Keep the heights measured at the current column widths, with `measured`.
fn with_heights(
  index : DocumentIndex,
  measured : Array[(CardMeasure, Int)],
) -> DocumentIndex {
  let columns = columns(index)
  let current = (measure : CardMeasure) => {
    measure.width == columns.span_width(1) ||
    measure.width == columns.span_width(2)
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
fn card_dom_id(key : String) -> String {
  "card-\{key}"
}

///|
fn derived_name(card : Card) -> String {
  match @document_lead.derive_name(card.text).text() {
    "" => "Unnamed document"
    name => name
  }
}

///|
/// Focus the card of `key` once it is drawn, when the search still shows it;
/// otherwise focus stays put.
fn focus_card(index : DocumentIndex, key : String) -> DocumentIndex {
  match visible_cursor({ ..index, focused: Some(key), }) {
    Some(cursor) if cursor.current.key == key =>
      { ..index, focused: Some(key), focus_pending: Some(key), }
    _ => index
  }
}

///|
/// Whether the grid on screen holds the card of `key`.
fn shows_card(index : DocumentIndex, key : String) -> Bool {
  match index.grid {
    Packed(layout) => layout.cards.to_array().any(card => card.card.key == key)
    NotMeasured => false
  }
}

///|
/// The index listing `seeds` instead, with focus left as it is.
pub fn DocumentIndex::listing(
  self : DocumentIndex,
  seeds : ArrayView[Seed],
) -> DocumentIndex {
  settled({ ..self, cards: cards_of(seeds, self.cards), })
}

///|
/// The index shown again with focus on the card that holds the Tab stop.
pub fn DocumentIndex::return_focus(self : DocumentIndex) -> DocumentIndex {
  match visible_cursor(self) {
    Some(cursor) => focus_card(self, cursor.current.key)
    None => self
  }
}

///|
/// The index shown again after the document of `key` was open, now listing
/// `seeds`. A document whose text changed, or that is new, has moved to the
/// front: its card slides there from its old place, is highlighted, and is
/// announced. Either way its card takes focus.
pub fn DocumentIndex::returned_from(
  self : DocumentIndex,
  seeds : ArrayView[Seed],
  key~ : String,
) -> DocumentIndex {
  let before = self.cards.iter().find_first(card => card.key == key)
  let index = { ..self, cards: cards_of(seeds, self.cards), }
  match index.cards.iter().find_first(card => card.key == key) {
    None => settled(index.return_focus())
    Some(card) if before is Some(old) && old.text == card.text =>
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
pub fn DocumentIndex::removed(
  self : DocumentIndex,
  seeds : ArrayView[Seed],
  key~ : String,
  announcement~ : String,
) -> (DocumentIndex, Cmd) {
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
fn move_focus(
  index : DocumentIndex,
  direction : Direction,
) -> (DocumentIndex, Cmd) {
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
pub fn DocumentIndex::update(
  self : DocumentIndex,
  msg : Msg,
) -> (DocumentIndex, Cmd) {
  let (next, cmd) = transition(self, msg)
  (settled(next), cmd)
}

///|
fn transition(index : DocumentIndex, msg : Msg) -> (DocumentIndex, Cmd) {
  match msg {
    GridMeasured(measured) =>
      match grid_width_of(measured) {
        width if width == index.grid_width => (index, @cmd.none)
        grid_width => ({ ..index, grid_width, resize: Resizing, }, @cmd.none)
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
pub fn DocumentIndex::subscriptions(
  self : DocumentIndex,
  page : HostPage,
  emit : Emit[Msg],
) -> @sub.Sub {
  @sub.batch([
    @browser.element_width("document-index.grid", page.grid_probe, width => {
      emit(GridMeasured(width))
    }),
    @browser.fonts_loaded(page.fonts, emit(FontsLoaded)),
    match self.resize {
      Steady => @sub.none
      // Keyed by the width, so each change restarts the wait.
      Resizing =>
        @timeout.after(
          "document-index.resize-settled(\{self.grid_width})",
          RESIZE_SETTLE_MS,
          emit(ResizeSettled),
        )
    },
    match self.focus_pending {
      Some(key) if shows_card(self, key) =>
        @browser.focus_when_drawn(card_dom_id(key), emit(CardFocused(key)))
      _ => @sub.none
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
