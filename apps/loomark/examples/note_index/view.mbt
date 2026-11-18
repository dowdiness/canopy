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
    List(marker) => @html.div(class="lead", marker + " " + text)
    Plain => @html.div(class="lead", text)
  }
  let description = match (lead.form(), lead.description()) {
    (Empty, _) | (_, "") => @html.nothing
    (_, description) =>
      @html.div(class="desc", marked(description, lead.description_truncated()))
  }
  [primary, description]
}

///|
/// Attributes every card shares, whether shown or only measured.
fn card_attrs(note : Note) -> @html.Attrs {
  let attrs = @html.Attrs::build()
  if is_japanese(note.text) {
    ignore(attrs.lang("ja"))
  }
  attrs
}

///|
fn card_view(
  emit : Emit[Msg],
  note : Note,
  just_arrived : Bool,
  tab_stop : Bool,
) -> Html {
  let lead = note.lead
  let id = note.id
  let attrs = card_attrs(note)
    .tabindex(if tab_stop { 0 } else { -1 })
    .on_focus(_ => emit(CardFocused(id)))
  @html.a(
    href="#/n/\{id}",
    id=card_dom_id(id),
    class=if just_arrived { "card just-moved" } else { "card" },
    attrs~,
    lead_view(lead),
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
          attrs=card_attrs(request.note),
          lead_view(request.note.lead),
        ),
      ])
    }),
  )
}

///|
/// Where a card's slot sits.
priv enum SlotPlace {
  PackedAt(x~ : Int, y~ : Int, width~ : Int, height~ : Int)
  InList
} derive(Eq, Hash)

///|
/// Everything one card slot shows. Each card is its own branch of the
/// incremental graph, so it is rebuilt only when its slot changes.
priv struct CardSlot {
  note : Note
  place : SlotPlace
  tab_stop : Bool
  just_arrived : Bool
} derive(Eq, Hash)

///|
/// The slots the grid shows, in reading order: the packed grid on screen in
/// Cards, the visible notes in List.
fn card_slots(model : Model) -> @vector.Vector[CardSlot] {
  let slot = (note : Note, place, tab_stop) => {
    note,
    place,
    tab_stop,
    just_arrived: model.highlight == Some(note.id),
  }
  let slots = match (model.layout, model.grid, visible_cursor(model)) {
    (_, _, None) | (Cards, NotMeasured, _) => []
    (Cards, Packed(layout), Some(_)) => {
      let tab_stop = layout.cards.current.note.id
      layout.cards
      .to_array()
      .map(card => {
        slot(
          card.note,
          PackedAt(x=card.x, y=card.y, width=card.width, height=card.height),
          card.note.id == tab_stop,
        )
      })
    }
    (List, _, Some(visible)) =>
      visible
      .to_array()
      .map(note => slot(note, InList, note.id == visible.current.id))
  }
  @vector.Vector(slots)
}

///|
/// One card slot as its own component. It is memoized on the whole slot,
/// whose derived hash covers everything the card shows, so the virtual DOM
/// skips comparing a card whose slot is unchanged. `emit` is the same for
/// every render.
fn card_slot(slot : Val[CardSlot], emit : Emit[Msg]) -> Val[Html] {
  slot.view(slot => @html.memo(slot, slot => card_slot_view(slot, emit)))
}

///|
fn card_slot_view(slot : CardSlot, emit : Emit[Msg]) -> Html {
  let card = card_view(emit, slot.note, slot.just_arrived, slot.tab_stop)
  match slot.place {
    PackedAt(x~, y~, width~, height~) =>
      @html.li(
        class="slot",
        style=[
          "transform:translate(\{x}px,\{y}px);width:\{width}px;height:\{height}px",
        ],
        card,
      )
    InList => @html.li(class="slot", card)
  }
}

///|
/// The grid's own box, apart from the cards in it.
priv struct GridFrame {
  layout : Layout
  grid : ShownGrid
} derive(Eq)

///|
fn grid_frame(model : Model) -> GridFrame {
  { layout: model.layout, grid: model.grid, }
}

///|
/// Keys pressed on a card reach the grid.
fn grid_view(
  emit : Emit[Msg],
  frame : GridFrame,
  slots : @vector.Vector[CardSlot],
  rows : @vector.Vector[Html],
) -> Html {
  let items : Map[String, Html] = Map([])
  for pair in slots.iter().zip(rows.iter()) {
    items[pair.0.note.id] = pair.1
  }
  let class = match frame.layout {
    Cards => "grid cards"
    List => "grid list"
  }
  let style = match (frame.layout, frame.grid) {
    (Cards, Packed(layout)) =>
      ["width:\{layout.width}px;height:\{layout.height}px"]
    (Cards, NotMeasured) | (List, _) => []
  }
  @html.ol(
    class~,
    style~,
    attrs=@html.Attrs::build()
      .aria_label("Documents, most recently changed first")
      .on_keydown(event => {
        let action = card_key_action(key_press(event))
        if action.replaces_default() {
          event.prevent_default()
        }
        emit(CardKey(action))
      }),
    items,
  )
}

///|
fn toggle(label : String, pressed : Bool, on_click : Cmd) -> Html {
  @html.button(
    class="toggle",
    type_="button",
    attrs=@html.Attrs::build().aria_pressed(pressed.to_string()),
    on_click~,
    label,
  )
}

///|
fn segmented(label : String, buttons : Array[Html]) -> Html {
  @html.div(
    class="segmented",
    attrs=@html.Attrs::build().role("group").aria_label(label),
    buttons,
  )
}

///|
/// The prototype options a reader can change.
priv struct Options {
  layout : Layout
  size : CardSize
} derive(Eq)

///|
fn options_of(model : Model) -> Options {
  { layout: model.layout, size: model.size, }
}

///|
fn options_view(model : Options, emit : Emit[Msg]) -> Html {
  let cards = model.layout == Cards
  let options = [
    @html.span(class="options-label", "Prototype"),
    segmented("Layout", [
      toggle("Cards", cards, emit(LayoutChosen(Cards))),
      toggle("List", !cards, emit(LayoutChosen(List))),
    ]),
  ]
  if cards {
    options.push(
      segmented("Card size", [
        toggle("S", model.size == Small, emit(SizeChosen(Small))),
        toggle("M", model.size == Medium, emit(SizeChosen(Medium))),
        toggle("L", model.size == Large, emit(SizeChosen(Large))),
      ]),
    )
  }
  @html.div(
    class="options",
    attrs=@html.Attrs::build().role("group").aria_label("Prototype options"),
    options,
  )
}

///|
/// What the header shows: the document count and the search query.
priv struct Header {
  count : String
  query : String
} derive(Eq)

///|
/// What the documents area shows besides the grid.
priv enum Documents {
  Shown
  NoDocuments
  NoMatch(String)
} derive(Eq)

///|
fn header_and_documents(model : Model) -> (Header, Documents) {
  let total = listed(model).length()
  let cursor = visible_cursor(model)
  let count = match (model.query, cursor) {
    ("", _) => "\{total} documents"
    (_, Some(shown)) => "\{shown.length()} of \{total}"
    (_, None) => "0 of \{total}"
  }
  let documents = match (cursor, total) {
    (Some(_), _) => Shown
    (None, 0) => NoDocuments
    (None, _) => NoMatch(model.query)
  }
  ({ count, query: model.query, }, documents)
}

///|
fn header_view(header : Header, emit : Emit[Msg]) -> Html {
  @html.header(class="bar", [
    @html.h1([@html.text("Notes "), @html.span(class="count", header.count)]),
    @html.label(class="search", [
      @html.span(class="visually-hidden", "Search documents"),
      @html.input(
        id="search",
        input_type=Search,
        value=header.query,
        placeholder="Search",
        on_input=query => emit(Searched(query)),
        attrs=@html.Attrs::build()
          .spellcheck(false)
          .on_keydown(event => {
            if is_leaving_key(key_press(event)) {
              emit(SearchLeft)
            } else {
              @cmd.none
            }
          }),
      ),
    ]),
    @html.a(href="#/new", class="new", title="New document (N)", "＋ New"),
  ])
}

///|
fn documents_view(documents : Documents, grid : Html) -> Html {
  match documents {
    Shown => grid
    NoDocuments => @html.p(class="empty", "No documents yet")
    NoMatch(query) =>
      @html.p(class="empty", "No documents contain “\{query}”")
  }
}

///|
/// The editor exists only while a note or a New document is open.
fn editor_view(editor : Editor, emit : Emit[Msg]) -> Html {
  let text = match editor {
    Writing(session) => session.note.text
    Drafting => ""
  }
  @html.section(
    id="editor",
    class="editor",
    attrs=@html.Attrs::build().aria_label("Editor"),
    [
      @html.header(class="bar", [
        @html.a(
          href="#/",
          class="back",
          title="Back to notes (Esc)",
          "← Notes",
        ),
      ]),
      @html.textarea(
        id="editor-text",
        value=text,
        placeholder="Start writing…",
        on_input=text => emit(Edited(editor, text)),
        attrs=@html.Attrs::build()
          .aria_label("Document text")
          .spellcheck(false)
          .on_keydown(event => {
            if is_leaving_key(key_press(event)) {
              emit(EditorLeft)
            } else {
              @cmd.none
            }
          }),
        @html.nothing,
      ),
    ],
  )
}

///|
/// The editor page. Opening it moves focus into its text, from note to note
/// or the New document alike, until it is left.
fn editor_page(editing : Val[Editor?], emit : Emit[Msg]) -> Val[Html] {
  let _ = @rabbita.create_state_with_init(
    init=_ => ((), focus_after_render("editor-text")),
    update=(_, _ : Unit, _) => ((), @cmd.none),
  )
  editing.view(editor => {
    match editor {
      Some(editor) => editor_view(editor, emit)
      // The branch is disposed as the page leaves the editor.
      None => @html.nothing
    }
  })
}

///|
/// The Model as the index draws it. The index lists a note being written as
/// it was when writing began, so its current text is left out, and typing
/// changes nothing downstream of this node.
fn as_listed(model : Model) -> Model {
  match model.page {
    Editing(Writing({ origin: Listed(original~, ..) as origin, .. })) =>
      { ..model, page: Editing(Writing({ note: original, origin, })), }
    // `listed` treats a created note like the New document.
    Editing(Writing({ origin: Created, .. })) =>
      { ..model, page: Editing(Drafting), }
    Index | Editing(Drafting) => model
  }
}

///|
/// The page as an incremental graph. Each part derives the few values it
/// shows from the Model and is rebuilt only when they change; each card is a
/// branch keyed by its note, so moving the focus rebuilds two cards, not all.
fn view(model : Val[Model], emit : Emit[Msg]) -> Val[Html] {
  let index_model = model.map(as_listed)
  let header_and_documents = index_model.map(header_and_documents)
  let header = header_and_documents
    .map(pair => pair.0)
    .view(header => header_view(header, emit))
  let options = index_model
    .map(options_of)
    .view(options => options_view(options, emit))
  let slots = index_model.map(card_slots)
  let rows = slots.assoc_by((_, slot) => card_slot(slot, emit), by=slot => {
    slot.note.id
  })
  let grid = index_model
    .map(grid_frame)
    .view3(slots, rows, (frame, slots, rows) => {
      grid_view(emit, frame, slots, rows)
    })
  let documents = header_and_documents
    .map(pair => pair.1)
    .view2(grid, documents_view)
  // Under the editor the index stays laid out but invisible, rather than
  // `hidden`, so its cards keep their positions and slide from them on return.
  let index_covered = model.map(model => !(model.page is Index))
  let index = header.view4(options, documents, index_covered, (
    header,
    options,
    documents,
    covered,
  ) => {
    @html.main_(
      id="index",
      class=if covered { "index covered" } else { "index" },
      [header, options, documents],
    )
  })
  // Outside the index, so cards are measured while it is hidden as well.
  let measure = index_model
    .map(to_measure)
    .view(requests => {
      match requests {
        [] => @html.nothing
        requests => card_measure_view(requests)
      }
    })
  let editing = model.map(model => {
    match model.page {
      Editing(editor) => Some(editor)
      Index => None
    }
  })
  // A branch per page, so the editor exists from opening to leaving.
  let editor = editing.switch_by(
    editor => {
      match editor {
        Some(_) => editor_page(editing, emit)
        None => Val::constant(@html.nothing)
      }
    },
    by=editor => if editor is Some(_) { "editor" } else { "index" },
  )
  let announcement = model
    .map(model => model.announcement)
    .view(announcement => {
      @html.div(
        class="visually-hidden",
        attrs=@html.Attrs::build().aria_live("polite"),
        announcement,
      )
    })
  index.view4(measure, editor, announcement, (index, measure, editor, said) => {
    @html.div([index, measure, editor, said])
  })
}
