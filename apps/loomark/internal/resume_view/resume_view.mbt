///|
using @rabbita {type Emit, type Html}

///|
/// A document offered to the view: its key, the name it is listed by, and
/// its current Document text.
pub(all) struct Source[K] {
  key : K
  name : String
  text : String
} derive(Eq)

///|
/// An entry chosen to be read where it was written. `source` is the text its
/// range was taken from; `id` is the element that asked.
pub(all) struct Choice[K] {
  key : K
  source : String
  start : Int
  end : Int
  id : String
} derive(Eq)

///|
let kinds : Array[(@resume_entries.EntryKind, String)] = [
  (Observation, "Tried"),
  (Decision, "Decisions"),
  (OpenQuestion, "Open questions"),
  (NextStep, "Next steps"),
]

///|
priv struct Item[K] {
  choice : Choice[K]
  kind : @resume_entries.EntryKind
  project : String?
  name : String
}

///|
fn[K : Eq + Hash + Show] items(
  sources : Array[Source[K]],
) -> (Array[Item[K]], Array[String]) {
  let items = []
  let unread = []
  let documents = @resume_entries.extract(
    sources.map(source => (source.key, source.text)),
  )
  for i, document in documents {
    let name = sources[i].name
    guard document.entries is Some(entries) else {
      unread.push(name)
      continue
    }
    for entry in entries {
      let id = "resume-\{document.key}-\{entry.start}"
      items.push({
        choice: {
          key: document.key,
          source: document.source,
          start: entry.start,
          end: entry.end,
          id,
        },
        kind: entry.kind,
        project: entry.project,
        name,
      })
    }
  }
  (items, unread)
}

///|
fn[K] item_view(item : Item[K], on_choose : Emit[Choice[K]]) -> Html {
  let choice = item.choice
  @html.li([
    @html.button(
      id=choice.id,
      type_="button",
      class="entry",
      on_click=on_choose(choice),
      [
        @html.span(
          class="entry-text",
          choice.source[choice.start:choice.end].to_owned(),
        ),
        @html.span(class="entry-source", item.name),
      ],
    ),
  ])
}

///|
/// Entries from lists under kind headings in `sources`, most recently changed
/// first, grouped by project and kind. Nothing is merged, ranked, or dropped.
pub fn[K : Eq + Hash + Show] view(
  sources : Array[Source[K]],
  notes_href~ : String,
  on_choose : Emit[Choice[K]],
) -> Html {
  let (items, unread) = items(sources)
  let projects : Array[String?] = []
  for item in items {
    if !projects.contains(item.project) {
      projects.push(item.project)
    }
  }
  let sections = projects.map(project => {
    let groups = kinds.filter_map(pair => {
      let (kind, label) = pair
      let listed = items.filter(item => {
        item.project == project && item.kind == kind
      })
      guard !listed.is_empty() else { None }
      Some(
        @html.div(class="kind", [
          @html.h3(label),
          @html.ul(listed.map(item => item_view(item, on_choose))),
        ]),
      )
    })
    @html.section(
      class="project",
      [@html.h2(project.unwrap_or("No project")), ..groups],
    )
  })
  let empty = if items.is_empty() {
    @html.p(
      class="note",
      "Nothing to list. Lists under headings such as ## 判断 or ### 次にやること appear here.",
    )
  } else {
    @html.nothing
  }
  let unread = unread.map(name => {
    @html.p(class="note", "Could not read \{name}")
  })
  @html.div(class="loomark-resume", [
    @html.main_(
      class="resume",
      [
        @html.header(class="bar", [
          @html.a(href=notes_href, class="link", "Notes"),
          @html.h1("Resume"),
        ]),
        @html.p(
          class="note",
          "Lists found under 試したこと, 判断, 未解決事項, and 次にやること headings. Choose one to read it where it was written.",
        ),
        empty,
        ..unread,
        ..sections,
      ],
    ),
  ])
}

///|
pub extend Choice with Eq::{equal, not_equal}

///|
pub extend Source with Eq::{equal, not_equal}
