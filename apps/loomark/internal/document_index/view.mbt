///|
using @rabbita {type Html, type Val}

///|
/// Code shows at most this many lines; longer lines end in an ellipsis.
const CODE_LINES : Int32 = 8

///|
fn marked(text : String, truncated : Bool) -> String {
  if truncated {
    text + "…"
  } else {
    text
  }
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
      return marker.1 + line.exact_view(start=marker.0.length()).to_owned()
    }
  }
  line
}

///|
fn tidied_lines(text : String) -> String {
  text.split("\n").map(line => tidied(line.to_owned())).collect().join("\n")
}

///|
/// A card's Document lead. The browser breaks and clamps its lines.
fn lead_view(lead : @document_lead.DocumentLead) -> Array[Html] {
  let text = marked(lead.primary(), lead.primary_truncated())
  let primary = match lead.form() {
    Empty => @html.nothing
    Heading => @html.div(class="lead lead-heading", text)
    Quote => @html.div(class="lead lead-quote", text)
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
        shown.map(line => @html.div(class="code-line", line)),
      )
    }
    Task(done) =>
      @html.div(
        class=if done { "lead lead-task done" } else { "lead lead-task" },
        (if done { "☑ " } else { "☐ " }) + text,
      )
    List(marker) => @html.div(class="lead", tidied(marker + " " + text))
    Plain => @html.div(class="lead", text)
  }
  let description = match (lead.form(), lead.description()) {
    (Empty, _) | (_, "") => @html.nothing
    (_, description) =>
      @html.div(
        class="desc",
        tidied_lines(marked(description, lead.description_truncated())),
      )
  }
  [primary, description]
}

///|
/// Attributes every card shares, whether shown or only measured.
fn[K] card_attrs(card : Card[K]) -> @html.Attrs {
  let attrs = @html.Attrs::build()
  if is_japanese(card.text) {
    ignore(attrs.lang("ja"))
  }
  attrs
}

///|
fn[K : Show] card_view(
  emit : Emit[Msg[K]],
  card : Card[K],
  just_arrived : Bool,
  tab_stop : Bool,
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
        lead_view(card.lead),
      )
    // A card being deleted stays in place but leads nowhere.
    Neither =>
      @html.div(
        id=card_dom_id(key),
        class~,
        attrs=attrs.role("link").aria_disabled("true"),
        lead_view(card.lead),
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
fn[K : Show] delete_view(
  card : Card[K],
  tab_stop : Bool,
  on_delete : Emit[K],
) -> Html {
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
    id=card_delete_dom_id(card.key),
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
fn[K] card_measure_view(requests : Array[MeasureRequest[K]]) -> Html {
  @html.div(
    id="card-measure",
    class="card-measure",
    attrs=@html.Attrs::build().aria_hidden("true"),
    requests.map(request => {
      @html.div(style=["width:\{request.measure.width}px"], [
        @html.div(
          class="card",
          attrs=card_attrs(request.card),
          lead_view(request.card.lead),
        ),
      ])
    }),
  )
}

///|
/// Where a card slot is on screen.
#derive(Eq, Hash)
priv enum SlotPlace {
  /// Placed in the packed grid on screen.
  At(x~ : Int32, y~ : Int32, width~ : Int32, height~ : Int32, tab_stop~ : Bool)
  /// Left out of the grid on screen, such as by the search, yet still drawn,
  /// so that typing in Search never removes a node from the document:
  /// Chromium ends a typing Undo step whenever one leaves.
  Hidden
}

///|
/// Everything one card slot shows: its card, and where it is on screen.
/// Each card is its own branch of the incremental graph, so it is rebuilt
/// only when its slot changes.
#derive(Eq, Hash)
priv struct CardSlot[K] {
  card : Card[K]
  place : SlotPlace
  just_arrived : Bool
}

///|
/// A slot for every listed card, most recently changed first, so the order
/// of the drawn slots never changes with the search. A card the grid on
/// screen places shows as it was placed.
fn[K : Eq + Hash] card_slots(
  index : DocumentIndex[K],
) -> @vector.Vector[CardSlot[K]] {
  let (placed, tab_stop) = match (index.grid, visible_cursor(index)) {
    (Packed(layout), Some(_)) =>
      (layout.cards.to_array(), Some(layout.cards.current.card.key))
    (NotMeasured, _) | (_, None) => ([], None)
  }
  let placed = @hashmap.HashMap(placed.map(card => (card.card.key, card)))
  let slots = index.cards
    .iter()
    .map(card => {
      let just_arrived = index.highlight == Some(card.key)
      match placed.get(card.key) {
        Some(placed) =>
          {
            card: placed.card,
            place: At(
              x=placed.x,
              y=placed.y,
              width=placed.width,
              height=placed.height,
              tab_stop=tab_stop == Some(card.key),
            ),
            just_arrived,
          }
        None => { card, place: Hidden, just_arrived, }
      }
    })
    .collect()
  @vector.Vector(slots)
}

///|
/// One card slot as its own component. It is memoized on the whole slot,
/// whose derived hash covers everything the card shows, so the virtual DOM
/// skips comparing a card whose slot is unchanged. `emit` and `on_delete`
/// are the same for every render.
fn[K : Eq + Hash + Show] card_slot(
  slot : Val[CardSlot[K]],
  emit : Emit[Msg[K]],
  on_delete : Emit[K],
) -> Val[Html] {
  slot.view(slot => {
    @html.memo(slot, slot => card_slot_view(slot, emit, on_delete))
  })
}

///|
/// A hidden slot keeps the same children as a placed one, so placing it or
/// hiding it again changes only attributes.
fn[K : Show] card_slot_view(
  slot : CardSlot[K],
  emit : Emit[Msg[K]],
  on_delete : Emit[K],
) -> Html {
  let (style, tab_stop) = match slot.place {
    At(x~, y~, width~, height~, tab_stop~) =>
      (
        [
          "transform:translate(\{x}px,\{y}px);width:\{width}px;height:\{height}px",
        ],
        tab_stop,
      )
    Hidden => ([], false)
  }
  @html.li(
    class=if slot.card.actions is Neither { "slot deleting" } else { "slot" },
    style~,
    attrs=@html.Attrs::build().hidden(slot.place is Hidden),
    [
      card_view(emit, slot.card, slot.just_arrived, tab_stop),
      notice_view(slot.card.notice),
      delete_view(slot.card, tab_stop, on_delete),
    ],
  )
}

///|
/// Keys pressed on a card reach the grid.
fn[K : Show] grid_view(
  emit : Emit[Msg[K]],
  size : (Int32, Int32)?,
  slots : @vector.Vector[CardSlot[K]],
  rows : @vector.Vector[Html],
) -> Html {
  let items : Map[String, Html] = Map([])
  for pair in slots.iter().zip(rows.iter()) {
    items[pair.0.card.key.to_string()] = pair.1
  }
  let style = match size {
    Some((width, height)) => ["width:\{width}px;height:\{height}px"]
    None => []
  }
  @html.ol(
    id=GRID_ID,
    class="grid cards",
    style~,
    attrs=@html.Attrs::build()
      .hidden(size is None)
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
/// What the header shows: the search query, and while searching how many
/// documents match it.
#derive(Eq)
priv struct Header {
  count : String?
  query : String
  new_href : String
}

///|
/// What the documents area shows besides the grid. While any document is
/// listed, the note for a search that matches none stays drawn, hidden while
/// cards match, so searching never removes it from the document.
#derive(Eq)
priv enum Documents {
  NoDocuments
  Listed(query~ : String, matched~ : Bool)
}

///|
fn[K : Eq] header_and_documents(
  index : DocumentIndex[K],
) -> (Header, Documents) {
  let total = index.cards.length()
  let cursor = visible_cursor(index)
  let count = match (index.query, cursor) {
    ("", _) => None
    (_, Some(shown)) => Some("\{shown.length()} of \{total}")
    (_, None) => Some("0 of \{total}")
  }
  let documents = match total {
    0 => NoDocuments
    _ => Listed(query=index.query, matched=cursor is Some(_))
  }
  ({ count, query: index.query, new_href: index.new_href, }, documents)
}

///|
fn[K] header_view(header : Header, emit : Emit[Msg[K]]) -> Html {
  @html.header(class="bar", [
    // Named for assistive technology; the cards themselves show what this is.
    @html.h1(class="visually-hidden", "Notes"),
    // Always drawn, so typing that starts or ends a search changes only
    // attributes and text.
    @html.span(
      class="count",
      attrs=@html.Attrs::build().hidden(header.count is None),
      match header.count {
        Some(count) => count
        None => ""
      },
    ),
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
fn[K] documents_view(
  documents : Documents,
  new_href : String,
  grid : Html,
  emit : Emit[Msg[K]],
) -> Html {
  let empty = match documents {
    NoDocuments =>
      @html.div(class="empty", [
        @html.p(class="empty-title", "No documents yet"),
        @html.a(href=new_href, class="empty-action", "Write the first one"),
      ])
    Listed(query~, matched~) =>
      @html.div(class="empty", attrs=@html.Attrs::build().hidden(matched), [
        @html.p(class="empty-title", "No documents contain “\{query}”"),
        @html.button(
          type_="button",
          class="empty-action",
          on_click=emit(SearchCleared),
          "Clear search",
        ),
      ])
  }
  @html.div(class="documents", [grid, empty])
}

///|
/// The size of the packed grid on screen while it shows any card.
fn[K : Eq] grid_size(index : DocumentIndex[K]) -> (Int32, Int32)? {
  match (index.grid, visible_cursor(index)) {
    (Packed(layout), Some(_)) => Some((layout.width, layout.height))
    (NotMeasured, _) | (_, None) => None
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
/// The host shows and hides the index. Hiding it with `visibility: hidden`
/// keeps it laid out, so its cards keep their positions and slide from them
/// when it is shown again, and its grid width stays measured.
pub fn[K : Eq + Hash + Show] view(
  index : Val[DocumentIndex[K]],
  on_delete~ : Emit[K],
  emit : Emit[Msg[K]],
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
    .map(grid_size)
    .view3(slots, rows, (size, slots, rows) => {
      grid_view(emit, size, slots, rows)
    })
  let new_href = index.map(index => index.new_href)
  let documents = header_and_documents
    .map(pair => pair.1)
    .view3(new_href, grid, (documents, new_href, grid) => {
      documents_view(documents, new_href, grid, emit)
    })
  let main = header.view2(documents, (header, documents) => {
    @html.main_(id="index", class="index", [
      // Laid out like the grid, so its width is the grid's.
      @html.div(
        id=GRID_WIDTH_ID,
        class="grid-width",
        attrs=@html.Attrs::build().aria_hidden("true"),
        @html.nothing,
      ),
      header,
      documents,
    ])
  })
  // Outside the grid, so it never shifts the cards on screen.
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
    @html.div(class="loomark-index", [main, measure, said])
  })
}
