///|
/// PROTOTYPE — actual Rabbita runtime probe for the proposed two-layer graph.
using @vector {type Vector}

///|
/// Browser-only measurement sink. The object is intentionally plain data so a
/// parent browser trace can inspect it without traversing runtime objects.
extern "js" fn probe_event_start(mode : String) -> Unit =
  #|((mode) => {
  #|  performance.mark("textarea-input-start");
  #|  const p = window.__documentLeadProbe;
  #|  p.inputEvents++;
  #|  p.inDispatch = true;
  #|  p.trace.push({ kind: "event-dispatch-start", mode, inDispatch: p.inDispatch, at: performance.now() });
  #|  queueMicrotask(() => p.trace.push({ kind: "microtask", mode, inDispatch: p.inDispatch, at: performance.now() }));
  #|  setTimeout(() => p.trace.push({ kind: "later-task", mode, inDispatch: p.inDispatch, at: performance.now() }), 0);
  #|})

///|
extern "js" fn probe_event_end(mode : String) -> Unit =
  #|((mode) => { const p = window.__documentLeadProbe; performance.mark("textarea-input-end"); p.inDispatch = false; p.trace.push({ kind: "event-dispatch-end", mode, inDispatch: p.inDispatch, at: performance.now() }); })

///|
extern "js" fn probe_root_update_start() -> Unit =
  #|(() => { const p = window.__documentLeadProbe; performance.mark("rabbita-root-update-start"); p.trace.push({ kind: "root-update-start", inDispatch: p.inDispatch, at: performance.now() }); })

///|
extern "js" fn probe_root_update_end() -> Unit =
  #|(() => { const p = window.__documentLeadProbe; performance.mark("rabbita-root-update-end"); p.trace.push({ kind: "root-update-end", inDispatch: p.inDispatch, at: performance.now() }); })

///|
extern "js" fn probe_extract_start(mode : String, size : Int) -> Unit =
  #|((mode, size) => { const p = window.__documentLeadProbe; p.extractions++; if (mode === "pure") p.pureExtractions++; p.trace.push({ kind: "extract-start", mode, size, inDispatch: p.inDispatch, at: performance.now() }); performance.mark("document-lead-extract-start"); })

///|
extern "js" fn probe_extract_end(mode : String, size : Int) -> Unit =
  #|((mode, size) => { const p = window.__documentLeadProbe; performance.mark("document-lead-extract-end"); p.trace.push({ kind: "extract-end", mode, size, inDispatch: p.inDispatch, at: performance.now() }); })

///|
extern "js" fn probe_row_render(id : String, revision : Int) -> Unit =
  #|((id, revision) => { const p = window.__documentLeadProbe; p.trace.push({ kind: "row-render", id, revision, inDispatch: p.inDispatch, at: performance.now() }); })

///|
extern "js" fn probe_install() -> Unit =
  #|(() => { const p = window.__documentLeadProbe = { inputEvents: 0, quietAccepted: 0, immediateAccepted: 0, extractions: 0, pureExtractions: 0, inDispatch: false, trace: [], longtasks: [] }; if (PerformanceObserver.supportedEntryTypes?.includes("longtask")) new PerformanceObserver(list => list.getEntries().forEach(e => { const entry = { start: e.startTime, duration: e.duration }; p.longtasks.push(entry); p.trace.push({ kind: "longtask", ...entry, inDispatch: p.inDispatch }); })).observe({ entryTypes: ["longtask"] }); })

///|
extern "js" fn probe_accept(mode : String) -> Unit =
  #|((mode) => { const p = window.__documentLeadProbe; p[mode === "quiet" ? "quietAccepted" : "immediateAccepted"]++; })

///|
priv struct LeadSource {
  id : String
  revision : Int
  text : String
  status : String
} derive(Eq)

///|
priv struct LeadContent {
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
priv struct RecentInput {
  lead : Lead
  status : String
} derive(Eq)

///|
priv struct Model {
  visible : Bool
  sources : Vector[LeadSource]
  next_revision : Int
  refresh : Int
  input_text : String
  input_mode : String
  quiet_sequence : Int
} derive(Eq)

///|
priv enum Msg {
  Toggle
  ChangeA
  ChangeAStatus
  ChangeB
  DeleteB
  RestoreB
  Refresh
  Input(String)
  SetInputText(String)
  QuietElapsed(Int, String)
  SetMode(String)
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
) -> @rabbita.Val[RecentInput] {
  pure_branch_builds.val += 1
  record("build pure:\{id}")
  let anchor = instrumented_anchor(PureBranch, id)
  let content = source.map(source => {
    probe_extract_start("pure", source.text.length())
    let extracted = @document_lead.extract(
      source.text,
      limits=@document_lead.DocumentLeadLimits::try_new(
        primary=120,
        description=400,
      ).unwrap(),
    )
    probe_extract_end("pure", source.text.length())
    extraction_runs.val += 1
    record("extract pure \{source.id}@\{source.revision}")
    LeadContent::{
      id: source.id,
      revision: source.revision,
      text: extracted.primary(),
    }
  })
  let lead = content.map2(anchor, (content, _) => Lead::{
    id: content.id,
    revision: content.revision,
    text: content.text,
  })
  source.map2(lead, (source, lead) => { lead, status: source.status })
}

///|
fn row_component(
  id : String,
  input : @rabbita.Val[RecentInput],
) -> @rabbita.Val[@html.Html] {
  row_branch_builds.val += 1
  record("build row:\{id}")
  let anchor = instrumented_anchor(RowBranch, id)
  input.map2(anchor, (input, _) => {
    row_render_runs.val += 1
    record("render row \{input.lead.id}@\{input.lead.revision} \{input.status}")
    probe_row_render(input.lead.id, input.lead.revision)
    @html.li([
      @html.strong("\{input.lead.id}@\{input.lead.revision}"),
      @html.span(class="lead-text", input.lead.text),
      @html.span(class="lead-text", input.status),
    ])
  })
}

///|
fn visible_component(
  leads : @rabbita.Val[Vector[RecentInput]],
) -> @rabbita.Val[@html.Html] {
  visible_branch_builds.val += 1
  record("build visible")
  let anchor = instrumented_anchor(VisibleBranch, "recent-documents")
  let rows = leads.assoc_by(row_component, by=input => input.lead.id)
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
fn set_source_text(model : Model, id : String, text : String) -> Model {
  let revision = model.next_revision
  let sources = model.sources.map(source => {
    if source.id == id {
      { ..source, revision, text }
    } else {
      source
    }
  })
  { ..model, sources, next_revision: revision + 1, refresh: model.refresh + 1 }
}

///|
fn upsert_new_source(model : Model, text : String) -> Model {
  if model.sources.iter().any(source => source.id == "New") {
    set_source_text(model, "New", text)
  } else {
    let revision = model.next_revision
    {
      ..model,
      sources: model.sources.push({ id: "New", revision, text, status: "new" }),
      next_revision: revision + 1,
      refresh: model.refresh + 1,
    }
  }
}

///|
fn update_source(model : Model, id : String) -> Model {
  set_source_text(model, id, "\{id} changed at revision \{model.next_revision}")
}

///|
fn update(model : Model, msg : Msg) -> Model {
  match msg {
    Toggle => { ..model, visible: !model.visible, refresh: model.refresh + 1 }
    ChangeA => update_source(model, "A")
    ChangeAStatus => {
      let sources = model.sources.map(source => {
        if source.id == "A" {
          let status = if source.status == "saved" { "saving" } else { "saved" }
          { ..source, status, }
        } else {
          source
        }
      })
      { ..model, sources, refresh: model.refresh + 1 }
    }
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
            status: "saved",
          }),
          next_revision: revision + 1,
          refresh: model.refresh + 1,
        }
      }
    }
    Refresh => { ..model, refresh: model.refresh + 1 }
    Input(_) | SetInputText(_) | SetMode(_) => model
    QuietElapsed(sequence, text) =>
      if sequence != model.quiet_sequence {
        model
      } else {
        probe_root_update_start()
        let next = upsert_new_source(model, text)
        probe_root_update_end()
        probe_accept("quiet")
        next
      }
  }
}

///|
fn input_command(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    Input(text) => {
      probe_root_update_start()
      if model.input_mode == "quiet" {
        let sequence = model.quiet_sequence + 1
        probe_root_update_end()
        (
          { ..model, input_text: text, quiet_sequence: sequence },
          @cmd.delay(emit(QuietElapsed(sequence, text)), 250),
        )
      } else {
        let next = upsert_new_source(model, text)
        probe_accept("immediate")
        probe_root_update_end()
        ({ ..next, input_text: text }, @cmd.none)
      }
    }
    SetInputText(text) => ({ ..model, input_text: text }, @cmd.none)
    SetMode(mode) => ({ ..model, input_mode: mode }, @cmd.none)
    _ => (model, @cmd.none)
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
    @html.li("\{source.id}@\{source.revision} [\{source.status}]")
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
      @html.button(on_click=emit(SetMode("immediate")), "Immediate acceptance"),
      @html.button(on_click=emit(SetMode("quiet")), "Quiet 250ms simulation"),
      @html.button(
        on_click=emit(Input(model.input_text)),
        "Measure current input",
      ),
      @html.button(
        on_click=emit(
          SetInputText("# ordinary 10KB\\n\\n" + "ordinary ".repeat(1100)),
        ),
        "Ordinary 10KB",
      ),
      @html.button(
        on_click=emit(
          SetInputText("# heavy generated ~66KB\\n\\n" + "heavy ".repeat(11000)),
        ),
        "Heavy generated ~66KB",
      ),
      @html.textarea(
        id="document-lead-input",
        rows=8,
        value=model.input_text,
        placeholder="Type Markdown to measure the real extractor",
        on_input=value => {
          probe_event_start(model.input_mode)
          let command = emit(Input(value))
          probe_event_end(model.input_mode)
          command
        },
        @html.nothing,
      ),
      @html.button(
        on_click=emit(Toggle),
        if model.visible {
          "Hide"
        } else {
          "Show"
        },
      ),
      @html.button(on_click=emit(ChangeA), "Change A content"),
      @html.button(on_click=emit(ChangeAStatus), "Change A status only"),
      @html.button(on_click=emit(ChangeB), "Change B"),
      @html.button(on_click=emit(DeleteB), "Delete B"),
      @html.button(on_click=emit(RestoreB), "Restore B"),
      @html.button(on_click=emit(Refresh), "Refresh counters"),
    ]),
    @html.section(class="grid", [
      metric("pure branches built", pure_branch_builds.val),
      metric("pure extraction runs", extraction_runs.val),
      metric("row branches built", row_branch_builds.val),
      metric("row renders", row_render_runs.val),
      metric("visible branches built", visible_branch_builds.val),
      metric("pure branches disposed", pure_branch_disposals.val),
      metric("row branches disposed", row_branch_disposals.val),
      metric("visible branches disposed", visible_branch_disposals.val),
      metric("input bytes", model.input_text.length()),
      @html.p(
        "Mode: \{model.input_mode}; textarea updates New immediately only in immediate mode; quiet accepts latest input after 250ms.",
      ),
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
        { id: "A", revision: 1, text: "# Alpha", status: "saved" },
        { id: "B", revision: 2, text: "- [ ] Beta", status: "saved" },
      ]),
      next_revision: 3,
      refresh: 0,
      input_text: "# ordinary 10KB\\n\\n" + "ordinary ".repeat(1100),
      input_mode: "immediate",
      quiet_sequence: 0,
    },
    update=(model, msg, emit) => {
      let (next, command) = match msg {
        Input(_) => input_command(model, msg, emit)
        SetInputText(_) => (update(model, msg), @cmd.none)
        SetMode(_) => input_command(model, msg, emit)
        QuietElapsed(sequence, text) =>
          (update(model, QuietElapsed(sequence, text)), @cmd.none)
        _ => (update(model, msg), @cmd.none)
      }
      (next, command)
    },
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
  probe_install()
  @rabbita.new(app).mount("app")
}
