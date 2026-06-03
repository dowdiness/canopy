///|
using @rabbita {type Cmd, type Emit, type Html}

///|
using @html {a, aside, button, div, h2, nothing, p, span, textarea, text}

///|
#cfg(target="js")
extern "js" fn js_source_mode_url(enabled : Bool) -> String =
  #|((enabled) => {
  #|  const url = new URL(window.location.href);
  #|  if (enabled) {
  #|    url.searchParams.set('source', '1');
  #|  } else {
  #|    url.searchParams.delete('source');
  #|  }
  #|  return url.toString();
  #|})

///|
#cfg(not(target="js"))
fn js_source_mode_url(enabled : Bool) -> String {
  if enabled {
    "?source=1"
  } else {
    "/"
  }
}

///|
struct SourceDemoModel {
  handle : Int
  editor : String
  dirty : Bool
  status : String
  tone : String
  on_change : () -> Unit
}

///|
enum SourceDemoMsg {
  EditorChanged(String)
  ApplySource
  ConnectSample
  InsertReverb
  SyncFromGraph
}

///|
fn source_toggle_view(enabled : Bool) -> Html {
  let next_enabled = !enabled
  a(
    id="source-mode-toggle",
    class="mode-toggle",
    href=js_source_mode_url(next_enabled),
    title=if enabled {
      "Reload the demo with the local canvas runtime adapter"
    } else {
      "Reload the demo with graph-dsl source as the backing store"
    },
    if enabled {
      "Return to canvas runtime"
    } else {
      "Open source-backed demo"
    },
  )
}

///|
fn source_demo_notify(model : SourceDemoModel) -> Cmd {
  @rabbita.effect(fn() { (model.on_change)() })
}

///|
fn source_demo_status_from_result(
  result : SourceGraphOperationResultJson,
  success_message : String,
) -> (String, String) {
  if result.applied {
    (success_message, "success")
  } else {
    let detail = match result.message {
      Some(message) => message
      None =>
        if result.diagnostics.is_empty() {
          "operation was rejected"
        } else {
          result.diagnostics.join("; ")
        }
    }
    ("Source operation rejected: " + detail, "error")
  }
}

///|
fn source_demo_update(
  _emit : Emit[SourceDemoMsg],
  msg : SourceDemoMsg,
  model : SourceDemoModel,
) -> (Cmd, SourceDemoModel) {
  match msg {
    EditorChanged(source) =>
      (@rabbita.none, { ..model, editor: source, dirty: true })
    ApplySource => {
      set_source_graph_source(model.handle, model.editor)
      (
        source_demo_notify(model),
        {
          ..model,
          editor: get_source_graph_source(model.handle),
          dirty: false,
          status: "Source applied; render state is reparsed from Loom GraphDoc.",
          tone: "success",
        },
      )
    }
    ConnectSample => {
      let result = source_graph_connect_sample_result(model.handle)
      let (status, tone) = source_demo_status_from_result(
        result, "Connected meter.input to osc.out through graph-dsl source.",
      )
      (
        source_demo_notify(model),
        { ..model, editor: result.source, dirty: false, status, tone },
      )
    }
    InsertReverb => {
      let result = source_graph_insert_unique_result(
        model.handle,
        "reverb",
        "plate",
      )
      let (status, tone) = source_demo_status_from_result(
        result, "Inserted reverb = plate() from canonical source.",
      )
      (
        source_demo_notify(model),
        { ..model, editor: result.source, dirty: false, status, tone },
      )
    }
    SyncFromGraph => {
      if model.dirty {
        return (@rabbita.none, model)
      }
      let source = get_source_graph_source(model.handle)
      if source == model.editor {
        (@rabbita.none, model)
      } else {
        (
          @rabbita.none,
          {
            ..model,
            editor: source,
            status: "Source synchronized from graph-dsl backing store.",
            tone: "success",
          },
        )
      }
    }
  }
}

///|
fn source_demo_subscriptions(
  emit : Emit[SourceDemoMsg],
  _model : SourceDemoModel,
) -> @sub.Sub {
  @sub.every(250, emit(SyncFromGraph))
}

///|
fn source_status_attrs(tone : String) -> @html.Attrs {
  @html.Attrs::build().data_set("tone", tone)
}

///|
fn source_textarea_attrs() -> @html.Attrs {
  @html.Attrs::build().spellcheck(false).aria_label("Graph DSL source")
}

///|
fn source_demo_view(
  emit : Emit[SourceDemoMsg],
  model : SourceDemoModel,
) -> Html {
  aside(
    id="source-panel",
    class="panel source-panel",
    attrs=@html.Attrs::build().aria_label("Graph DSL source"),
    [
      div(class="panel-title", [h2("Graph source"), span("Canonical DSL")]),
      textarea(
        id="source-editor",
        class="source-editor",
        value=model.editor,
        on_input=emit.map(source => EditorChanged(source)),
        attrs=source_textarea_attrs(),
        nothing,
      ),
      div(class="source-actions", [
        button(
          id="source-apply",
          type_="button",
          on_click=emit(ApplySource),
          "Apply source",
        ),
        button(
          id="source-connect",
          type_="button",
          on_click=emit(ConnectSample),
          "Connect osc → meter",
        ),
        button(
          id="source-insert",
          type_="button",
          on_click=emit(InsertReverb),
          "Insert reverb",
        ),
      ]),
      p(
        id="source-status",
        class="hint source-status",
        attrs=source_status_attrs(model.tone),
        style=["margin-top: 12px"],
        [text(model.status)],
      ),
    ],
  )
}

///|
#cfg(target="js")
pub fn mount_source_demo(
  handle : Int,
  enabled : Bool,
  on_change : () -> Unit,
) -> Unit {
  @rabbita.new(@rabbita.static_cell(source_toggle_view(enabled))).mount(
    "source-mode-root",
  )
  guard enabled else { return }
  let model = {
    handle,
    editor: get_source_graph_source(handle),
    dirty: false,
    status: "Source mode active: operations lower into graph-dsl text.",
    tone: "success",
    on_change,
  }
  @rabbita.new(
    @rabbita.cell(
      model~,
      update=source_demo_update,
      view=source_demo_view,
      subscriptions=source_demo_subscriptions,
    ),
  ).mount("source-panel-root")
}
