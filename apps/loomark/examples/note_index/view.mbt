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
  query : String,
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
    lead_view(lead, query),
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
          lead_view(request.note.lead, ""),
        ),
      ])
    }),
  )
}

///|
/// Everything one card slot shows: its note, placed in the packed grid.
/// Each card is its own branch of the incremental graph, so it is rebuilt
/// only when its slot changes.
priv struct CardSlot {
  note : Note
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
fn card_slots(model : Model) -> @vector.Vector[CardSlot] {
  match (model.grid, visible_cursor(model)) {
    (Packed(layout), Some(_)) => {
      let tab_stop = layout.cards.current.note.id
      let query = search_query(model)
      let slots = layout.cards.map(card => {
        note: card.note,
        x: card.x,
        y: card.y,
        width: card.width,
        height: card.height,
        tab_stop: card.note.id == tab_stop,
        just_arrived: model.highlight == Some(card.note.id),
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
/// skips comparing a card whose slot is unchanged. `emit` is the same for
/// every render.
fn card_slot(slot : Val[CardSlot], emit : Emit[Msg]) -> Val[Html] {
  slot.view(slot => @html.memo(slot, slot => card_slot_view(slot, emit)))
}

///|
fn card_slot_view(slot : CardSlot, emit : Emit[Msg]) -> Html {
  let card = card_view(
    emit,
    slot.note,
    slot.just_arrived,
    slot.tab_stop,
    slot.query,
  )
  @html.li(
    class="slot",
    style=[
      "transform:translate(\{slot.x}px,\{slot.y}px);width:\{slot.width}px;height:\{slot.height}px",
    ],
    card,
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
    items[pair.0.note.id] = pair.1
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
        placeholder="Search notes",
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
    @html.a(href="#/new", class="new", title="New document (N)", [
      @html.span(
        class="new-plus",
        attrs=@html.Attrs::build().aria_hidden("true"),
        "+",
      ),
      @html.text("New"),
    ]),
  ])
}

///|
fn documents_view(documents : Documents, grid : Html, emit : Emit[Msg]) -> Html {
  match documents {
    Shown => grid
    NoDocuments =>
      @html.div(class="empty", [
        @html.p(class="empty-title", "No documents yet"),
        @html.a(href="#/new", class="empty-action", "Write the first one"),
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
/// The editor exists only while a note or a New document is open.
fn editor_view(editor : Editor, emit : Emit[Msg]) -> Html {
  let (text, name) = match editor {
    Writing(session) => (session.note.text, derived_name(session.note))
    Drafting => ("", "New document")
  }
  @html.section(
    id="editor",
    class="editor",
    attrs=@html.Attrs::build().aria_label("Editor"),
    [
      @html.header(class="bar", [
        @html.a(href="#/", class="back", title="Back to notes (Esc)", [
          @html.span(
            class="back-arrow",
            attrs=@html.Attrs::build().aria_hidden("true"),
            "←",
          ),
          @html.text("Notes"),
        ]),
        @html.span(class="editor-name", name),
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
            if is_leaving_key(@browser.key_press(event)) {
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
    init=_ => ((), @browser.focus_after_render("editor-text")),
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
  let slots = index_model.map(card_slots)
  let rows = slots.assoc_by((_, slot) => card_slot(slot, emit), by=slot => {
    slot.note.id
  })
  let grid = index_model
    .map(model => model.grid)
    .view3(slots, rows, (grid, slots, rows) => {
      grid_view(emit, grid, slots, rows)
    })
  let documents = header_and_documents
    .map(pair => pair.1)
    .view2(grid, (documents, grid) => documents_view(documents, grid, emit))
  // Under the editor the index stays laid out but invisible, rather than
  // `hidden`, so its cards keep their positions and slide from them on return.
  let index_covered = model.map(model => !(model.page is Index))
  let index = header.view3(documents, index_covered, (
    header,
    documents,
    covered,
  ) => {
    @html.main_(
      id="index",
      class=if covered { "index covered" } else { "index" },
      [header, documents],
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
