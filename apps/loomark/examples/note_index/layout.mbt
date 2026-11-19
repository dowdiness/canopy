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
/// A note with its Document lead, parsed once when its text is set.
priv struct Note {
  id : String
  text : String
  lead : @document_lead.DocumentLead
  /// `text` in lower case, which search matches against.
  search_text : String
} derive(Eq, Hash)

///|
/// Make a note; its lead and search text are derived here and nowhere else.
fn Note::Note(id : String, text : String) -> Note {
  {
    id,
    text,
    lead: @document_lead.extract(text),
    search_text: text.to_lower(),
  }
}

///|
fn is_japanese(text : String) -> Bool {
  text.iter().any(c => c.to_int() >= 0x3040 && c.to_int() < 0x3100)
}

///|
/// Long code and long notes read better across two columns.
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
/// Whether `note` may take two columns in `columns`.
fn may_be_wide(note : Note, columns : Columns) -> Bool {
  columns.count >= 3 && is_wide(note.lead)
}

///|
/// A card to draw off screen so the shell can measure it.
priv struct MeasureRequest {
  measure : CardMeasure
  note : Note
} derive(Eq)

///|
/// Every width each note's card may be drawn at.
fn measures_for(
  notes : Vector[Note],
  columns : Columns,
) -> Array[MeasureRequest] {
  notes
  .iter()
  .flat_map(note => {
    let at = (span : Int) => {
      measure: { width: columns.span_width(span), text: note.text, },
      note,
    }
    if may_be_wide(note, columns) {
      [at(1), at(2)].iter()
    } else {
      [at(1)].iter()
    }
  })
  .collect()
}

///|
/// The requests among `wanted` whose measures `heights` lacks, each once.
fn unmeasured_among(
  heights : @hashmap.HashMap[CardMeasure, Int],
  wanted : Array[MeasureRequest],
) -> Array[MeasureRequest] {
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
/// A note with the measured heights of its card.
priv struct MeasuredNote {
  note : Note
  narrow : Int
  /// The height at two columns, for a note that may take them.
  wide : Int?
}

///|
/// Parse the notes into measured ones, or `None` while any card that may be
/// drawn is not measured yet.
fn measured_notes(
  heights : @hashmap.HashMap[CardMeasure, Int],
  notes : Cursor[Note],
  columns : Columns,
) -> Cursor[MeasuredNote]? {
  notes.map_all(note => {
    let height = (span : Int) => {
      heights.get({ width: columns.span_width(span), text: note.text, })
    }
    match (height(1), may_be_wide(note, columns)) {
      (Some(narrow), false) => Some({ note, narrow, wide: None, })
      (Some(narrow), true) =>
        height(2).map(wide_height => { note, narrow, wide: Some(wide_height), })
      (None, _) => None
    }
  })
}

///|
priv struct Placed {
  note : Note
  x : Int
  y : Int
  width : Int
  height : Int
} derive(Eq)

///|
priv struct CardLayout {
  cards : Cursor[Placed]
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
fn pack_cards(notes : Cursor[MeasuredNote], columns : Columns) -> CardLayout {
  let step = columns.width + GAP
  let starts = Array::makei(columns.count, i => i * step)
  let packer = try! @skyline.Packer(width=columns.count * step)
  let cards = notes.map(measured => {
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
      note: measured.note,
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
fn Placed::rect(self : Placed) -> CardRect {
  {
    id: self.note.id,
    left: self.x,
    top: self.y,
    width: self.width,
    height: self.height,
  }
}
