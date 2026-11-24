// Functional core: packs cards into columns from heights the shell measured.
// The browser breaks and clamps card text; this code never predicts a height.

///|
/// Space between cards, in both axes.
const GAP : Int = 14

///|
/// Empty column height a wide card may leave beneath it before it is placed
/// at one column instead.
const FALLBACK_GAP : Int = 60

///|
/// A document as the index lists it, resolved by the host with the same
/// states its Recent documents entry shows.
pub(all) struct Seed[K] {
  /// The host's own key for the document, handed back by `on_delete` and
  /// unique among the listed documents. Its text names the card's elements,
  /// so no two keys may read the same.
  key : K
  /// Where choosing the card leads.
  href : String
  text : String
  status : @recent_documents.RowStatus
  deletion : @recent_documents.DeletionAvailability
  /// The document was chosen and is still loading.
  loading : Bool
} derive(Eq)

///|
pub extend Seed with Eq::{equal, not_equal}

///|
/// What a card says about its document besides its text. Every notice is
/// drawn over the card, so a card measures the same whatever it says.
priv enum Notice {
  Quiet
  NotSaved
  Progress(String)
  Problem(String)
} derive(Eq, Hash)

///|
/// What a card lets its reader do.
priv enum Actions {
  ChooseOrDelete
  /// Deleting is not available now, as in Recent documents.
  ChooseOnly
  /// The document is being deleted; it stays in place until it is gone.
  Neither
} derive(Eq, Hash)

///|
fn[K] notice_of(seed : Seed[K]) -> Notice {
  match (seed.deletion, seed.loading, seed.status) {
    (Pending, _, _) => Progress("Deleting")
    (Failed(_), _, _) => Problem("Delete failed")
    (Available(_) | Blocked, true, _) => Progress("Loading document")
    (Available(_) | Blocked, false, Unsaved) => NotSaved
    (Available(_) | Blocked, false, Saved) => Quiet
  }
}

///|
fn actions_of(deletion : @recent_documents.DeletionAvailability) -> Actions {
  match deletion {
    Available(_) | Failed(_) => ChooseOrDelete
    Blocked => ChooseOnly
    Pending => Neither
  }
}

///|
/// A listed document with its Document lead, parsed once when its text is set.
priv struct Card[K] {
  key : K
  href : String
  text : String
  lead : @document_lead.DocumentLead
  /// `text` in lower case, which search matches against.
  search_text : String
  notice : Notice
  actions : Actions
} derive(Eq, Hash)

///|
/// Make a card for `seed`, reusing the lead and search text of `previous`
/// when its text is the same, so only a changed text is parsed again.
fn[K] Card::of(seed : Seed[K], previous : Card[K]?) -> Card[K] {
  let (lead, search_text) = match previous {
    Some(card) if card.text == seed.text => (card.lead, card.search_text)
    _ => (@document_lead.extract(seed.text), seed.text.to_lower())
  }
  {
    key: seed.key,
    href: seed.href,
    text: seed.text,
    lead,
    search_text,
    notice: notice_of(seed),
    actions: actions_of(seed.deletion),
  }
}

///|
/// Cards for `seeds` in their order, built on the cards of `previous`.
fn[K : Eq + Hash] cards_of(seeds : ArrayView[Seed[K]], previous : Vector[Card[K]]) -> Vector[Card[K]] {
  let known : Map[K, Card[K]] = Map([])
  for card in previous {
    known[card.key] = card
  }
  Vector(seeds.map(seed => Card::of(seed, known.get(seed.key))))
}

///|
/// What a card is called where it has no room for its text: its lead, or
/// `Empty document`.
fn[K] card_label(card : Card[K]) -> String {
  match card.lead.primary() {
    "" => "Empty document"
    primary => primary
  }
}

///|
fn is_japanese(text : String) -> Bool {
  text.iter().any(c => c.to_int() >= 0x3040 && c.to_int() < 0x3100)
}

///|
/// Long code and long cards read better across two columns.
fn is_wide(lead : @document_lead.DocumentLead) -> Bool {
  if lead.form() is Code {
    lead.primary().split("\n").any(line => line.length() > 44)
  } else {
    lead.description().length() > 200
  }
}

///|
/// The column grid that fits `grid_width` with columns at least `min_column`
/// wide.
priv struct Columns {
  count : Int
  width : Int
}

///|
fn columns_for(grid_width~ : Int, min_column~ : Int) -> Columns {
  let count = ((grid_width + GAP) / (min_column + GAP)).max(1)
  { count, width: (grid_width - GAP * (count - 1)) / count, }
}

///|
/// The width of a card spanning `span` columns.
fn Columns::span_width(self : Columns, span : Int) -> Int {
  span * self.width + (span - 1) * GAP
}

///|
/// A card's height depends only on the text it shows and its width.
priv struct CardMeasure {
  width : Int
  text : String
} derive(Eq, Hash)

///|
/// Whether `card` may take two columns in `columns`.
fn[K] may_be_wide(card : Card[K], columns : Columns) -> Bool {
  columns.count >= 3 && is_wide(card.lead)
}

///|
/// A card to draw off screen so the shell can measure it.
priv struct MeasureRequest[K] {
  measure : CardMeasure
  card : Card[K]
} derive(Eq)

///|
/// Every width each card's card may be drawn at.
fn[K] measures_for(
  cards : Vector[Card[K]],
  columns : Columns,
) -> Array[MeasureRequest[K]] {
  cards
  .iter()
  .flat_map(card => {
    let at = (span : Int) => {
      measure: { width: columns.span_width(span), text: card.text, },
      card,
    }
    if may_be_wide(card, columns) {
      [at(1), at(2)].iter()
    } else {
      [at(1)].iter()
    }
  })
  .collect()
}

///|
/// The requests among `wanted` whose measures `heights` lacks, each once.
fn[K] unmeasured_among(
  heights : @hashmap.HashMap[CardMeasure, Int],
  wanted : Array[MeasureRequest[K]],
) -> Array[MeasureRequest[K]] {
  let seen : Set[CardMeasure] = Set([])
  let missing = []
  for request in wanted {
    if !heights.contains(request.measure) && seen.add_and_check(request.measure) {
      missing.push(request)
    }
  }
  missing
}

///|
/// A card with its measured heights.
priv struct MeasuredCard[K] {
  card : Card[K]
  narrow : Int
  /// The height at two columns, for a card that may take them.
  wide : Int?
}

///|
/// Parse the cards into measured ones, or `None` while any card that may be
/// drawn is not measured yet.
fn[K] measured_cards(
  heights : @hashmap.HashMap[CardMeasure, Int],
  cards : Cursor[Card[K]],
  columns : Columns,
) -> Cursor[MeasuredCard[K]]? {
  cards.map_all(card => {
    let height = (span : Int) => {
      heights.get({ width: columns.span_width(span), text: card.text, })
    }
    match (height(1), may_be_wide(card, columns)) {
      (Some(narrow), false) => Some({ card, narrow, wide: None, })
      (Some(narrow), true) =>
        height(2).map(wide_height => { card, narrow, wide: Some(wide_height), })
      (None, _) => None
    }
  })
}

///|
priv struct Placed[K] {
  card : Card[K]
  x : Int
  y : Int
  width : Int
  height : Int
} derive(Eq)

///|
priv struct CardLayout[K] {
  cards : Cursor[Placed[K]]
  width : Int
  height : Int
} derive(Eq)

///|
/// Pack measured cards into the column grid with skyline Bottom-Left
/// placement.
///
/// Cards keep their order; each lands at the lowest, then leftmost, column
/// start where it fits. A wide card whose placement would trap more than
/// `FALLBACK_GAP` pixels of column height is placed at one column.
/// Every card is packed one gap wider and taller than it is drawn.
fn[K] pack_cards(cards : Cursor[MeasuredCard[K]], columns : Columns) -> CardLayout[K] {
  let step = columns.width + GAP
  let starts = Array::makei(columns.count, i => i * step)
  let packer = try! @skyline.Packer(width=columns.count * step)
  let cards = cards.map(measured => {
    let narrow = (1, measured.narrow)
    let (span, height) = match measured.wide {
      None => narrow
      Some(wide_height) => {
        let size = try! @skyline.Size(width=2 * step, height=wide_height + GAP)
        let fits = (try! packer.preview(size, allowed_x=starts)).map(preview => {
          preview.trapped_area <= FALLBACK_GAP.to_int64() * step.to_int64()
        })
        if fits is Some(true) {
          (2, wide_height)
        } else {
          narrow
        }
      }
    }
    let size = try! @skyline.Size(width=span * step, height=height + GAP)
    let placement = try! packer.place_constrained(size, starts)
    {
      card: measured.card,
      x: placement.x,
      y: placement.y,
      width: columns.span_width(span),
      height,
    }
  })
  {
    cards,
    width: columns.count * step - GAP,
    height: (packer.height() - GAP).max(0),
  }
}

///|
fn[K] Placed::rect(self : Placed[K]) -> CardRect[K] {
  {
    id: self.card.key,
    left: self.x,
    top: self.y,
    width: self.width,
    height: self.height,
  }
}
