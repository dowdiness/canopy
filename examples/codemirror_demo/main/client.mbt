///|
using @cmd {type Cmd}

///|
using @html {button, code, div, h1, h2, nothing, p, span}

///|
using @rabbita {type Emit, type Html}

///|
using @sub {type Sub}

///|
let initial_text =
  #|Canopy CodeMirror binding demo
  #|
  #|Type here to exercise listen(doc=...).

///|
enum Msg {
  Mounted
  MountFailed(String)
  DocChangedA(String)
  DocChangedB(String)
  SetDocClicked
  ToggleReadonly
  UnmountClicked
  MountClicked
  SwapTagger
}

///|
struct Model {
  cm_id : String
  mounted : Bool
  read_only : Bool
  last_doc : String
  last_variant : String
  use_variant_b : Bool
  status_log : Array[String]
}

///|
fn capped_prepend(
  xs : Array[String],
  value : String,
  limit : Int,
) -> Array[String] {
  let next = xs.copy()
  next.insert(0, value)
  if next.length() > limit {
    ignore(next.remove(next.length() - 1))
  }
  next
}

///|
fn with_status(model : Model, line : String) -> Model {
  { ..model, status_log: capped_prepend(model.status_log, line, 8) }
}

///|
fn readonly_label(value : Bool) -> String {
  if value {
    "readonly"
  } else {
    "editable"
  }
}

///|
fn mounted_label(value : Bool) -> String {
  if value {
    "mounted"
  } else {
    "unmounted"
  }
}

///|
fn active_variant(model : Model) -> String {
  if model.use_variant_b {
    "B"
  } else {
    "A"
  }
}

///|
fn mount_cmd(emit : Emit[Msg], model : Model) -> Cmd {
  @cm.mount(
    model.cm_id,
    "cm-demo-host",
    init_doc=initial_text,
    initial_theme=Some(@theme.Theme::custom(@js_ffi.js_extension_combine([]))),
    initial_readonly=model.read_only,
    on_mounted=emit(Mounted),
    failed=emit.map(message => MountFailed(message)),
  )
}

///|
fn update(emit : Emit[Msg], msg : Msg, model : Model) -> (Cmd, Model) {
  match msg {
    Mounted =>
      (@rabbita.none, with_status({ ..model, mounted: true }, "mounted editor"))
    MountFailed(message) =>
      (
        @rabbita.none,
        with_status({ ..model, mounted: false }, "failed: \{message}"),
      )
    DocChangedA(text) =>
      (
        @rabbita.none,
        with_status(
          { ..model, last_doc: text, last_variant: "A" },
          "doc changed through A",
        ),
      )
    DocChangedB(text) =>
      (
        @rabbita.none,
        with_status(
          { ..model, last_doc: text, last_variant: "B" },
          "doc changed through B",
        ),
      )
    SetDocClicked =>
      (
        @cm.set_doc(model.cm_id, "fresh text from the demo"),
        with_status(
          { ..model, last_doc: "fresh text from the demo" },
          "set_doc requested",
        ),
      )
    ToggleReadonly => {
      let next_readonly = !model.read_only
      (
        @cm.set_readonly(model.cm_id, next_readonly),
        with_status(
          { ..model, read_only: next_readonly },
          "readonly -> \{readonly_label(next_readonly)}",
        ),
      )
    }
    UnmountClicked =>
      (
        @cm.unmount(model.cm_id),
        with_status({ ..model, mounted: false }, "unmount requested"),
      )
    MountClicked =>
      (
        mount_cmd(emit, model),
        with_status({ ..model, mounted: false }, "mount requested"),
      )
    SwapTagger => {
      let next_use_variant_b = !model.use_variant_b
      let next_variant = if next_use_variant_b { "B" } else { "A" }
      (
        @rabbita.none,
        with_status(
          { ..model, use_variant_b: next_use_variant_b },
          "listen tagger -> \{next_variant}",
        ),
      )
    }
  }
}

///|
fn subscriptions(emit : Emit[Msg], model : Model) -> Sub {
  guard model.mounted else { return @sub.none }
  let doc_tagger : Emit[String] = if model.use_variant_b {
    emit.map(text => DocChangedB(text))
  } else {
    emit.map(text => DocChangedA(text))
  }
  @cm.listen(model.cm_id, doc=doc_tagger)
}

///|
fn metric(label : String, value : String) -> Html {
  div(class="metric") <| [
    p(class="metric-label", label),
    code(class="metric-value", value),
  ]
}

///|
fn status_class(model : Model) -> String {
  if model.mounted {
    "status is-mounted"
  } else {
    "status is-unmounted"
  }
}

///|
fn view(emit : Emit[Msg], model : Model) -> Html {
  div(class="page") <| [
    div(class="topbar") <| [
      div(class="title-block") <| [
        h1(class="title", "CodeMirror Rabbita demo"),
        p(class="subtitle", "P2.4 public API smoke"),
      ],
      div(class=status_class(model), mounted_label(model.mounted)),
    ],
    div(class="workbench") <| [
      div(class="editor-column") <| [
        div(id="cm-demo-host", class="editor-host", nothing),
      ],
      div(class="control-column") <| [
        div(class="panel") <| [
          h2(class="panel-title", "Controls"),
          div(class="actions") <| [
            button(
              class="primary",
              disabled=model.mounted,
              on_click=emit(MountClicked),
              "Mount",
            ),
            button(
              class="secondary",
              disabled=!model.mounted,
              on_click=emit(UnmountClicked),
              "Unmount",
            ),
            button(
              class="secondary",
              disabled=!model.mounted,
              on_click=emit(SetDocClicked),
              "Set doc",
            ),
            button(
              class="secondary",
              disabled=!model.mounted,
              on_click=emit(ToggleReadonly),
              "Toggle readonly",
            ),
            button(
              class="secondary",
              disabled=!model.mounted,
              on_click=emit(SwapTagger),
              "Swap tagger",
            ),
          ],
        ],
        div(class="panel") <| [
          h2(class="panel-title", "Readout"),
          div(class="metrics") <| [
            metric("mode", readonly_label(model.read_only)),
            metric("next tagger", active_variant(model)),
            metric("last doc", "\{model.last_variant}: \{model.last_doc}"),
          ],
        ],
        div(class="panel") <| [
          h2(class="panel-title", "Log"),
          if model.status_log.is_empty() {
            p(class="empty", "-")
          } else {
            div(class="log-list") <| model.status_log.map(line => {
              div(class="log-line") <| [
                span(class="log-dot", ""),
                code(line),
              ]
            })
          },
        ],
      ],
    ],
  ]
}

///|
let initial_model : Model = {
  cm_id: "codemirror-demo",
  mounted: false,
  read_only: false,
  last_doc: initial_text,
  last_variant: "A",
  use_variant_b: false,
  status_log: [],
}

///|
#warnings("-alert_unstable")
#cfg(target="js")
fn main {
  let (emit, app) = @rabbita.cell_with_emit(
    model=initial_model,
    update~,
    view~,
    subscriptions~,
  )
  @rabbita.new(app)..with_init(mount_cmd(emit, initial_model)).mount("app")
}
