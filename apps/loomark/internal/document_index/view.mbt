///|
using @rabbita {type Html, type Val}

///|
/// Code shows at most this many lines; longer lines end in an ellipsis.
const CODE_LINES : Int = 8

///|
fn marked(text : String, truncated : Bool) -> String {
  if truncated {
    text + "…"
  } else {
    text
  }
}

///|
/// `text` with each occurrence of `query`, already in lower case, marked.
/// Marks only colour the text, so a card measures the same with or without.
fn matched(text : String, query : String) -> Array[Html] {
  let lower = text.to_lower()
  guard query != "" && lower.length() == text.length() else {
    return [@html.text(text)]
  }
  let runs = []
  let mut from = 0
  while lower.view(start_offset=from).find(query) is Some(offset) {
    let at = from + offset
    let end = at + query.length()
    if at > from {
      runs.push(
        @html.text(text.view(start_offset=from, end_offset=at).to_owned()),
      )
    }
    runs.push(@html.mark(text.view(start_offset=at, end_offset=end).to_owned()))
    from = end
  }
  if from < text.length() {
    runs.push(@html.text(text.view(start_offset=from).to_owned()))
  }
  runs
}

///|
/// A Markdown list or task marker drawn as the mark a reader sees.
fn tidied(line : String) -> String {
  let markers = [
    ("- [ ] ", "☐ "),
    ("- [x] ", "☑ "),
    ("- [X] ", "☑ "),
    ("- ", "• "),
    ("* ", "• "),
    ("+ ", "• "),
  ]
  for marker in markers {
    if line.has_prefix(marker.0) {
      return marker.1 + line.view(start_offset=marker.0.length()).to_owned()
    }
  }
  line
}

///|
fn tidied_lines(text : String) -> String {
  text.split("\n").map(line => tidied(line.to_owned())).collect().join("\n")
}

///|
/// A card's Document lead, with `query` marked. The browser breaks and
/// clamps its lines.
fn lead_view(lead : @document_lead.DocumentLead, query : String) -> Array[Html] {
  let text = marked(lead.primary(), lead.primary_truncated())
  let primary = match lead.form() {
    Empty => @html.nothing
    Heading => @html.div(class="lead lead-heading", matched(text, query))
    Quote => @html.div(class="lead lead-quote", matched(text, query))
    Code => {
      let lines = lead
        .primary()
        .split("\n")
        .map(line => line.to_owned())
        .collect()
      let shown = lines.iter().take(CODE_LINES).collect()
      let last = shown.length() - 1
      shown[last] = marked(
        shown[last],
        lines.length() > CODE_LINES || lead.primary_truncated(),
      )
      @html.div(
        class="lead lead-code",
        shown.map(line => @html.div(class="code-line", matched(line, query))),
      )
    }
    Task(done) =>
      @html.div(
        class=if done { "lead lead-task done" } else { "lead lead-task" },
        matched((if done { "☑ " } else { "☐ " }) + text, query),
      )
    List(marker) =>
      @html.div(class="lead", matched(tidied(marker + " " + text), query))
    Plain => @html.div(class="lead", matched(text, query))
  }
  let description = match (lead.form(), lead.description()) {
    (Empty, _) | (_, "") => @html.nothing
    (_, description) =>
      @html.div(
        class="desc",
        matched(
          tidied_lines(marked(description, lead.description_truncated())),
          query,
        ),
      )
  }
  [primary, description]
}

///|
/// Attributes every card shares, whether shown or only measured.
fn card_attrs(card : Card) -> @html.Attrs {
  let attrs = @html.Attrs::build()
  if is_japanese(card.text) {
    ignore(attrs.lang("ja"))
  }
  attrs
}

///|
fn card_view(
  emit : Emit[Msg],
  card : Card,
  just_arrived : Bool,
  tab_stop : Bool,
  query : String,
) -> Html {
  let key = card.key
  let attrs = card_attrs(card)
    .tabindex(if tab_stop { 0 } else { -1 })
    .on_focus(_ => emit(CardFocused(key)))
  // An empty document draws no text, so its card names what it is.
  if card.lead.form() is Empty {
    ignore(attrs.aria_label("Empty document"))
  }
  let class = if just_arrived { "card just-moved" } else { "card" }
  match card.actions {
    ChooseOrDelete | ChooseOnly =>
      @html.a(
        href=card.href,
        id=card_dom_id(key),
        class~,
        attrs~,
        lead_view(card.lead, query),
      )
    // A card being deleted stays in place but leads nowhere.
    Neither =>
      @html.div(
        id=card_dom_id(key),
        class~,
        attrs=attrs.role("link").aria_disabled("true"),
        lead_view(card.lead, query),
      )
  }
}

///|
/// The card's notice, drawn over it so the card keeps its measured height.
fn notice_view(notice : Notice) -> Html {
  match notice {
    Quiet => @html.nothing
    NotSaved =>
      @html.span(
        class="card-unsaved",
        attrs=@html.Attrs::build().role("img").aria_label("Not saved"),
        @html.nothing,
      )
    Progress(label) =>
      @html.span(
        class="card-notice card-progress",
        attrs=@html.Attrs::build().role("status"),
        label,
      )
    Problem(label) =>
      @html.span(
        class="card-notice card-problem",
        attrs=@html.Attrs::build().role("status"),
        label,
      )
  }
}

///|
/// Delete document, beside the card's link rather than inside it, so that
/// choosing and deleting stay separate targets. It follows the card in Tab
/// order only while the card holds the Tab stop.
fn delete_view(card : Card, tab_stop : Bool, on_delete : Emit[String]) -> Html {
  let label = "Delete \"\{card_label(card)}\""
  let attrs = @html.Attrs::build()
    .tabindex(if tab_stop { 0 } else { -1 })
    .aria_label(label)
  // Unavailable rather than `disabled`, so focus stays on it while the
  // deletion it started is pending.
  let on_click = match card.actions {
    ChooseOrDelete => on_delete(card.key)
    ChooseOnly | Neither => {
      ignore(attrs.aria_disabled("true"))
      @cmd.none
    }
  }
  @html.button(
    type_="button",
    class="card-delete",
    title=label,
    attrs~,
    on_click~,
    @html.span(
      class="card-delete-icon",
      attrs=@html.Attrs::build().aria_hidden("true"),
      @html.nothing,
    ),
  )
}

///|
/// Cards drawn off screen at the widths the shell measures, in the order of
/// `measures`. Each holds a card exactly as the grid draws it.
fn card_measure_view(requests : Array[MeasureRequest]) -> Html {
  @html.div(
    id="card-measure",
    class="card-measure",
    attrs=@html.Attrs::build().aria_hidden("true"),
    requests.map(request => {
      @html.div(style=["width:\{request.measure.width}px"], [
        @html.div(
          class="card",
          attrs=card_attrs(request.card),
          lead_view(request.card.lead, ""),
        ),
      ])
    }),
  )
}

///|
/// Everything one card slot shows: its card, placed in the packed grid.
/// Each card is its own branch of the incremental graph, so it is rebuilt
/// only when its slot changes.
priv struct CardSlot {
  card : Card
  x : Int
  y : Int
  width : Int
  height : Int
  tab_stop : Bool
  just_arrived : Bool
  /// The search, in lower case, whose matches the card marks.
  query : String
} derive(Eq, Hash)

///|
/// The slots of the packed grid on screen, in reading order.
fn card_slots(index : DocumentIndex) -> @vector.Vector[CardSlot] {
  match (index.grid, visible_cursor(index)) {
    (Packed(layout), Some(_)) => {
      let tab_stop = layout.cards.current.card.key
      let query = search_query(index)
      let slots = layout.cards.map(card => {
        card: card.card,
        x: card.x,
        y: card.y,
        width: card.width,
        height: card.height,
        tab_stop: card.card.key == tab_stop,
        just_arrived: index.highlight == Some(card.card.key),
        query,
      })
      @vector.Vector(slots.to_array())
    }
    (NotMeasured, _) | (_, None) => @vector.Vector([])
  }
}

///|
/// One card slot as its own component. It is memoized on the whole slot,
/// whose derived hash covers everything the card shows, so the virtual DOM
/// skips comparing a card whose slot is unchanged. `emit` and `on_delete`
/// are the same for every render.
fn card_slot(
  slot : Val[CardSlot],
  emit : Emit[Msg],
  on_delete : Emit[String],
) -> Val[Html] {
  slot.view(slot => {
    @html.memo(slot, slot => card_slot_view(slot, emit, on_delete))
  })
}

///|
fn card_slot_view(
  slot : CardSlot,
  emit : Emit[Msg],
  on_delete : Emit[String],
) -> Html {
  let card = card_view(
    emit,
    slot.card,
    slot.just_arrived,
    slot.tab_stop,
    slot.query,
  )
  @html.li(
    class=if slot.card.actions is Neither { "slot deleting" } else { "slot" },
    style=[
      "transform:translate(\{slot.x}px,\{slot.y}px);width:\{slot.width}px;height:\{slot.height}px",
    ],
    [
      card,
      notice_view(slot.card.notice),
      delete_view(slot.card, slot.tab_stop, on_delete),
    ],
  )
}

///|
/// Keys pressed on a card reach the grid.
fn grid_view(
  emit : Emit[Msg],
  grid : ShownGrid,
  slots : @vector.Vector[CardSlot],
  rows : @vector.Vector[Html],
) -> Html {
  let items : Map[String, Html] = Map([])
  for pair in slots.iter().zip(rows.iter()) {
    items[pair.0.card.key] = pair.1
  }
  let style = match grid {
    Packed(layout) => ["width:\{layout.width}px;height:\{layout.height}px"]
    NotMeasured => []
  }
  @html.ol(
    class="grid cards",
    style~,
    attrs=@html.Attrs::build()
      .aria_label("Documents, most recently changed first")
      .on_keydown(event => {
        let action = card_key_action(@browser.key_press(event))
        if action.replaces_default() {
          event.prevent_default()
        }
        emit(CardKey(action))
      }),
    items,
  )
}

///|
/// What the header shows: the document count and the search query.
priv struct Header {
  count : String
  query : String
  new_href : String
} derive(Eq)

///|
/// What the documents area shows besides the grid.
priv enum Documents {
  Shown
  NoDocuments
  NoMatch(String)
} derive(Eq)

///|
fn header_and_documents(index : DocumentIndex) -> (Header, Documents) {
  let total = index.cards.length()
  let cursor = visible_cursor(index)
  let count = match (index.query, cursor) {
    ("", _) => "\{total} documents"
    (_, Some(shown)) => "\{shown.length()} of \{total}"
    (_, None) => "0 of \{total}"
  }
  let documents = match (cursor, total) {
    (Some(_), _) => Shown
    (None, 0) => NoDocuments
    (None, _) => NoMatch(index.query)
  }
  ({ count, query: index.query, new_href: index.new_href, }, documents)
}

///|
fn header_view(header : Header, emit : Emit[Msg]) -> Html {
  @html.header(class="bar", [
    @html.h1([@html.text("Notes "), @html.span(class="count", header.count)]),
    @html.label(class="search", [
      @html.span(class="visually-hidden", "Search documents"),
      @html.input(
        id=SEARCH_ID,
        input_type=Search,
        value=header.query,
        placeholder="Search documents",
        on_input=query => emit(Searched(query)),
        attrs=@html.Attrs::build()
          .spellcheck(false)
          .on_keydown(event => {
            if is_leaving_key(@browser.key_press(event)) {
              emit(SearchLeft)
            } else {
              @cmd.none
            }
          }),
      ),
    ]),
    // The same quiet control as New document in the Editor and the sidebar.
    @html.a(
      href=header.new_href,
      class="new",
      title="New document (N)",
      attrs=@html.Attrs::build().aria_label("New document"),
      @html.span(
        class="new-icon",
        attrs=@html.Attrs::build().aria_hidden("true"),
        @html.nothing,
      ),
    ),
  ])
}

///|
fn documents_view(
  documents : Documents,
  new_href : String,
  grid : Html,
  emit : Emit[Msg],
) -> Html {
  match documents {
    Shown => grid
    NoDocuments =>
      @html.div(class="empty", [
        @html.p(class="empty-title", "No documents yet"),
        @html.a(href=new_href, class="empty-action", "Write the first one"),
      ])
    NoMatch(query) =>
      @html.div(class="empty", [
        @html.p(class="empty-title", "No documents contain “\{query}”"),
        @html.button(
          type_="button",
          class="empty-action",
          on_click=emit(SearchCleared),
          "Clear search",
        ),
      ])
  }
}

///|
/// The index as an incremental graph. Each part derives the few values it
/// shows and is rebuilt only when they change; each card is a branch keyed by
/// its document, so moving the focus rebuilds two cards, not all.
///
/// Delete document on a card asks the host through `on_delete` with the
/// card's key; the host confirms and deletes, and lists the result.
///
/// While `covered`, the index stays laid out but invisible, rather than
/// `hidden`, so its cards keep their positions and slide from them when it
/// is shown again.
pub fn view(
  index : Val[DocumentIndex],
  covered~ : Val[Bool],
  on_delete~ : Emit[String],
  emit : Emit[Msg],
) -> Val[Html] {
  let header_and_documents = index.map(header_and_documents)
  let header = header_and_documents
    .map(pair => pair.0)
    .view(header => header_view(header, emit))
  let slots = index.map(card_slots)
  let rows = slots.assoc_by((_, slot) => card_slot(slot, emit, on_delete), by=slot => {
    slot.card.key
  })
  let grid = index
    .map(index => index.grid)
    .view3(slots, rows, (grid, slots, rows) => {
      grid_view(emit, grid, slots, rows)
    })
  let new_href = index.map(index => index.new_href)
  let documents = header_and_documents
    .map(pair => pair.1)
    .view3(new_href, grid, (documents, new_href, grid) => {
      documents_view(documents, new_href, grid, emit)
    })
  let main = header.view3(documents, covered, (header, documents, covered) => {
    @html.main_(
      id="index",
      class=if covered { "index covered" } else { "index" },
      [header, documents],
    )
  })
  // Outside the index, so cards are measured while it is covered as well.
  let measure = index
    .map(to_measure)
    .view(requests => {
      match requests {
        [] => @html.nothing
        requests => card_measure_view(requests)
      }
    })
  let announcement = index
    .map(index => index.announcement)
    .view(announcement => {
      @html.div(
        class="visually-hidden",
        attrs=@html.Attrs::build().aria_live("polite"),
        announcement,
      )
    })
  main.view3(measure, announcement, (main, measure, said) => {
    @html.div([main, measure, said])
  })
}
