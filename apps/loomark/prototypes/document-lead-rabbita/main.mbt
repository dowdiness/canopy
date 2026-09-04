///|
/// PROTOTYPE — actual Rabbita runtime probe for the proposed two-layer graph.
using @vector {type Vector}

///|
priv struct LeadSource {
  id : String
  revision : Int
  text : String
} derive(Eq)

///|
priv struct Lead {
  id : String
  revision : Int
  text : String
} derive(Eq)

///|
priv struct Model {
  visible : Bool
  sources : Vector[LeadSource]
  next_revision : Int
  refresh : Int
} derive(Eq)

///|
priv enum Msg {
  Toggle
  ChangeA
  ChangeB
  DeleteB
  RestoreB
  Refresh
}

///|
priv enum BranchKind {
  PureBranch
  RowBranch
  VisibleBranch
}

///|
priv suberror CleanupSignal {
  CleanupSignal(BranchKind, String)
}

///|
let pure_branch_builds : Ref[Int] = Ref(0)

///|
let extraction_runs : Ref[Int] = Ref(0)

///|
let row_branch_builds : Ref[Int] = Ref(0)

///|
let row_render_runs : Ref[Int] = Ref(0)

///|
let visible_branch_builds : Ref[Int] = Ref(0)

///|
let pure_branch_disposals : Ref[Int] = Ref(0)

///|
let row_branch_disposals : Ref[Int] = Ref(0)

///|
let visible_branch_disposals : Ref[Int] = Ref(0)

///|
let event_log : Array[String] = []

///|
fn record(event : String) -> Unit {
  event_log.push(event)
}

///|
fn BranchKind::label(self : Self) -> String {
  match self {
    PureBranch => "pure"
    RowBranch => "row"
    VisibleBranch => "visible"
  }
}

///|
fn cleanup_sub(kind : BranchKind, id : String) -> @sub.Sub {
  @sub.custom_sub(
    "probe-cleanup",
    @sub.Scope::Local,
    CleanupSignal(kind, id),
    @sub.SubLoader((payload, _) => {
      match payload {
        CleanupSignal(kind, id) =>
          Some({
            unload: _ => {
              match kind {
                PureBranch => pure_branch_disposals.val += 1
                RowBranch => row_branch_disposals.val += 1
                VisibleBranch => visible_branch_disposals.val += 1
              }
              record("dispose \{kind.label()}:\{id}")
            },
            update_tagger: _ => (),
          })
        _ => None
      }
    }),
  )
}

///|
fn instrumented_anchor(kind : BranchKind, id : String) -> @rabbita.Val[Unit] {
  let (anchor, _) = @rabbita.create_state(
    (),
    update=(_ : Unit, _ : Unit, _) => ((), @rabbita.none),
    subscriptions=(_, _) => cleanup_sub(kind, id),
  )
  anchor
}

///|
fn lead_component(
  id : String,
  source : @rabbita.Val[LeadSource],
) -> @rabbita.Val[Lead] {
  pure_branch_builds.val += 1
  record("build pure:\{id}")
  let anchor = instrumented_anchor(PureBranch, id)
  source.map2(anchor, (source, _) => {
    extraction_runs.val += 1
    record("extract \{source.id}@\{source.revision}")
    { id: source.id, revision: source.revision, text: source.text }
  })
}

///|
fn row_component(
  id : String,
  lead : @rabbita.Val[Lead],
) -> @rabbita.Val[@html.Html] {
  row_branch_builds.val += 1
  record("build row:\{id}")
  let anchor = instrumented_anchor(RowBranch, id)
  lead.map2(anchor, (lead, _) => {
    row_render_runs.val += 1
    record("render row \{lead.id}@\{lead.revision}")
    @html.li([
      @html.strong("\{lead.id}@\{lead.revision}"),
      @html.span(class="lead-text", lead.text),
    ])
  })
}

///|
fn visible_component(
  leads : @rabbita.Val[Vector[Lead]],
) -> @rabbita.Val[@html.Html] {
  visible_branch_builds.val += 1
  record("build visible")
  let anchor = instrumented_anchor(VisibleBranch, "recent-documents")
  let rows = leads.assoc_by(row_component, by=lead => lead.id)
  rows.map2(anchor, (rows, _) => {
    @html.section(class="recent", [@html.h2("Visible rows"), @html.ul(rows)])
  })
}

///|
fn hidden_component() -> @rabbita.Val[@html.Html] {
  @rabbita.Val::constant(
    @html.section(class="hidden", [
      @html.h2("Recent documents hidden"),
      @html.p("The outer lead graph has no active consumer."),
    ]),
  )
}

///|
fn update_source(model : Model, id : String) -> Model {
  let revision = model.next_revision
  let sources = model.sources.map(source => {
    if source.id == id {
      { ..source, revision, text: "\{id} changed at revision \{revision}" }
    } else {
      source
    }
  })
  { ..model, sources, next_revision: revision + 1, refresh: model.refresh + 1 }
}

///|
fn update(model : Model, msg : Msg) -> Model {
  match msg {
    Toggle => { ..model, visible: !model.visible, refresh: model.refresh + 1 }
    ChangeA => update_source(model, "A")
    ChangeB => update_source(model, "B")
    DeleteB =>
      {
        ..model,
        sources: model.sources.filter(source => source.id != "B"),
        refresh: model.refresh + 1,
      }
    RestoreB => {
      let has_b = model.sources.iter().any(source => source.id == "B")
      if has_b {
        { ..model, refresh: model.refresh + 1 }
      } else {
        let revision = model.next_revision
        {
          ..model,
          sources: model.sources.push({
            id: "B",
            revision,
            text: "B restored at revision \{revision}",
          }),
          next_revision: revision + 1,
          refresh: model.refresh + 1,
        }
      }
    }
    Refresh => { ..model, refresh: model.refresh + 1 }
  }
}

///|
fn metric(name : String, value : Int) -> @html.Html {
  @html.div(class="metric", [
    @html.span(class="metric-value", value.to_string()),
    @html.span(class="metric-name", name),
  ])
}

///|
fn shell(
  model : Model,
  emit : @cmd.Emit[Msg],
  content : @html.Html,
) -> @html.Html {
  let sources = model.sources.map(source => {
    @html.li("\{source.id}@\{source.revision}: \{source.text}")
  })
  @html.div(class="probe-shell", [
    @html.header([
      @html.p(class="eyebrow", "THROWAWAY RABBITA RUNTIME PROBE"),
      @html.h1("Document-lead graph lifecycle"),
      @html.p([
        @html.text("Current visibility: "),
        @html.strong(if model.visible { "VISIBLE" } else { "HIDDEN" }),
      ]),
    ]),
    @html.nav(class="actions", [
      @html.button(
        on_click=emit(Toggle),
        if model.visible {
          "Hide"
        } else {
          "Show"
        },
      ),
      @html.button(on_click=emit(ChangeA), "Change A"),
      @html.button(on_click=emit(ChangeB), "Change B"),
      @html.button(on_click=emit(DeleteB), "Delete B"),
      @html.button(on_click=emit(RestoreB), "Restore B"),
      @html.button(on_click=emit(Refresh), "Refresh counters"),
    ]),
    @html.section(class="grid", [
      metric("pure branches built", pure_branch_builds.val),
      metric("extractions", extraction_runs.val),
      metric("row branches built", row_branch_builds.val),
      metric("row renders", row_render_runs.val),
      metric("visible branches built", visible_branch_builds.val),
      metric("pure branches disposed", pure_branch_disposals.val),
      metric("row branches disposed", row_branch_disposals.val),
      metric("visible branches disposed", visible_branch_disposals.val),
    ]),
    @html.section(class="columns", [
      @html.div([@html.h2("Root sources"), @html.ul(sources), content]),
      @html.div([
        @html.h2("Lifecycle log"),
        @html.pre(
          if event_log.length() == 0 {
            "No graph callbacks yet."
          } else {
            event_log.join("\n")
          },
        ),
      ]),
    ]),
  ])
}

///|
fn app() -> @rabbita.Val[@html.Html] {
  let (model, emit) = @rabbita.create_state(
    {
      visible: false,
      sources: @vector.Vector([
        { id: "A", revision: 1, text: "# Alpha" },
        { id: "B", revision: 2, text: "- [ ] Beta" },
      ]),
      next_revision: 3,
      refresh: 0,
    },
    update=(model, msg, _) => (update(model, msg), @rabbita.none),
  )
  let sources = model.map(model => model.sources)
  let leads = sources.assoc_by(lead_component, by=source => source.id)
  let visible = model.map(model => model.visible)
  let content = visible.switch_by(
    visible => {
      if visible {
        visible_component(leads)
      } else {
        hidden_component()
      }
    },
    by=visible => if visible { "visible" } else { "hidden" },
  )
  model.map2(content, (model, content) => shell(model, emit, content))
}

///|
fn main {
  @rabbita.new(app).mount("app")
}
