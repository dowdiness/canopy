///|
using @rabbita {type Cmd, type Emit, type Html}

///|
using @html {a, aside, button, div, h2, nothing, p, span, text}

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
  // `dirty` is true while the CodeMirror buffer diverges from the graph's
  // canonical source — i.e. the user has typed edits that have not (or could
  // not) be lowered. It gates `SyncFromGraph` so the periodic graph→editor
  // push never clobbers in-progress (possibly transiently-invalid) typing.
  dirty : Bool
  mounted : Bool
  status : String
  status_tone : @status.Tone
  on_change : () -> Unit
}

///|
/// Element id of the source-panel CodeMirror editor. It serves as both the
/// host DOM element id (the `view` renders an empty `div` with this id) and the
/// binding's logical editor id, so `mount` and `listen` address the same view.
const SOURCE_CM_EDITOR_ID = "source-editor-cm"

///|
enum SourceDemoMsg {
  // Full post-change CodeMirror document; tracks the editor's text so `Apply`
  // and `SyncFromGraph` reason against what the user actually sees, even when
  // a change was rolled back by the graph.
  EditorSynced(String)
  // Ordered per-change deltas of one CodeMirror transaction; lowered into the
  // graph-dsl source through `apply_edit`.
  SourceChanged(Array[@codemirror.ChangeDelta])
  ApplySource
  ConnectSample
  InsertReverb
  SyncFromGraph
  Mounted
  MountFailed(String)
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
/// Mount the source-panel CodeMirror editor into the `SOURCE_CM_EDITOR_ID`
/// host and report readiness through `Mounted`. The per-change `listen`
/// subscription only attaches once `mounted` is true, because the binding's
/// sub loader is a no-op until the editor exists in its registry.
fn mount_source_cm_cmd(
  emit : Emit[SourceDemoMsg],
  model : SourceDemoModel,
) -> Cmd {
  @codemirror.mount(
    SOURCE_CM_EDITOR_ID,
    SOURCE_CM_EDITOR_ID,
    init_doc=model.editor,
    source="global:__canopy_codemirror",
    on_mounted=emit(Mounted),
    failed=emit.map(message => MountFailed(message)),
  )
}

///|
fn source_demo_status_from_result(
  result : SourceGraphOperationResultJson,
  success_message : String,
  failure_prefix : String,
) -> (String, @status.Tone) {
  if result.applied {
    (success_message, @status.Success)
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
    (failure_prefix + ": " + detail, @status.Error)
  }
}

///|
/// Fold a graph-side operation result (Connect / Insert / Apply) into the next
/// command and model. On success the canonical `result.source` is pushed back
/// into CodeMirror via `set_doc` (echo-suppressed, skip-equal) and the editor
/// is marked clean; on rejection the editor keeps the user's text and stays
/// dirty so the canvas continues rendering the last-good graph.
fn source_demo_result_step(
  model : SourceDemoModel,
  result : SourceGraphOperationResultJson,
  status : String,
  status_tone : @status.Tone,
) -> (Cmd, SourceDemoModel) {
  if result.applied {
    (
      @rabbita.batch([
        source_demo_notify(model),
        @codemirror.set_doc(SOURCE_CM_EDITOR_ID, result.source),
      ]),
      { ..model, editor: result.source, dirty: false, status, status_tone },
    )
  } else {
    (source_demo_notify(model), { ..model, dirty: true, status, status_tone })
  }
}

///|
fn source_demo_update(
  _emit : Emit[SourceDemoMsg],
  msg : SourceDemoMsg,
  model : SourceDemoModel,
) -> (Cmd, SourceDemoModel) {
  match msg {
    EditorSynced(source) => (@rabbita.none, { ..model, editor: source })
    SourceChanged(changes) => {
      // Incremental lowering rebases each CodeMirror delta onto the graph's
      // current source, which only matches the editor while they agree. Once
      // `dirty` (a prior edit was rejected and rolled back to last-good), the
      // deltas are expressed against the diverged editor buffer, so replaying
      // them onto last-good would splice into the wrong coordinates and corrupt
      // the source. While dirty, recover by reparsing the whole buffer instead
      // (`EditorSynced`, delivered before this message, has `editor` current);
      // identity-preserving incremental lowering resumes once the editor and
      // graph are back in sync.
      let result = if model.dirty {
        set_source_graph_source_checked(model.handle, model.editor)
      } else {
        apply_source_graph_codemirror_changes(model.handle, changes)
      }
      let success_message = "Editor changes lowered into graph-dsl source."
      let failure_prefix = "Editor change rejected; canvas is rendering last-good graph"
      let (status, status_tone) = source_demo_status_from_result(
        result, success_message, failure_prefix,
      )
      // The edit originates in CodeMirror, which already holds the user's text,
      // so never push it back here (a transiently-invalid keystroke rolled back
      // to last-good would otherwise revert in-progress typing). `EditorSynced`
      // keeps `editor` current; we only record validity through `dirty`.
      (
        source_demo_notify(model),
        { ..model, dirty: !result.applied, status, status_tone },
      )
    }
    ApplySource => {
      let result = set_source_graph_source_checked(model.handle, model.editor)
      let success_message = "Source applied; render state is reparsed from Loom GraphDoc."
      let failure_prefix = "Current source is invalid; canvas is rendering last-good graph"
      let (status, status_tone) = source_demo_status_from_result(
        result, success_message, failure_prefix,
      )
      source_demo_result_step(model, result, status, status_tone)
    }
    ConnectSample => {
      let result = source_graph_connect_sample_result(model.handle)
      let success_message = "Connected meter.input to osc.out through graph-dsl source."
      let (status, status_tone) = source_demo_status_from_result(
        result, success_message, "Source operation rejected",
      )
      source_demo_result_step(model, result, status, status_tone)
    }
    InsertReverb => {
      let result = source_graph_insert_unique_result(
        model.handle,
        "reverb",
        "plate",
      )
      let success_message = "Inserted reverb = plate() from canonical source."
      let (status, status_tone) = source_demo_status_from_result(
        result, success_message, "Source operation rejected",
      )
      source_demo_result_step(model, result, status, status_tone)
    }
    SyncFromGraph => {
      // Keep out of the way while the editor holds unapplied edits, so the
      // periodic poll never overwrites in-progress typing.
      if model.dirty {
        return (@rabbita.none, model)
      }
      let source = get_source_graph_source(model.handle)
      if source == model.editor {
        (@rabbita.none, model)
      } else {
        (
          @codemirror.set_doc(SOURCE_CM_EDITOR_ID, source),
          {
            ..model,
            editor: source,
            status: "Source synchronized from graph-dsl backing store.",
            status_tone: @status.Success,
          },
        )
      }
    }
    Mounted => (@rabbita.none, { ..model, mounted: true })
    MountFailed(message) =>
      (
        @rabbita.none,
        {
          ..model,
          mounted: false,
          status: "CodeMirror failed to mount: " + message,
          status_tone: @status.Error,
        },
      )
  }
}

///|
fn source_demo_subscriptions(
  emit : Emit[SourceDemoMsg],
  model : SourceDemoModel,
) -> @sub.Sub {
  let cm_listen = if model.mounted {
    @codemirror.listen(
      SOURCE_CM_EDITOR_ID,
      doc=emit.map(source => EditorSynced(source)),
      on_change=emit.map(changes => SourceChanged(changes)),
    )
  } else {
    @sub.none
  }
  @sub.batch([@sub.every(250, emit(SyncFromGraph)), cm_listen])
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
      // CodeMirror mounts into this host imperatively; the `nothing` child
      // keeps rabbita's vdom from reconciling (and clearing) the editor DOM.
      div(
        id=SOURCE_CM_EDITOR_ID,
        class="source-editor source-editor-cm",
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
        attrs=model.status_tone.attrs(),
        style=["margin-top: 12px"],
        [text(model.status)],
      ),
    ],
  )
}

///|
#warnings("-alert_unstable")
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
    mounted: false,
    status: "Source mode active: operations lower into graph-dsl text.",
    status_tone: @status.Info,
    on_change,
  }
  let (emit, cell) = @rabbita.cell_with_emit(
    model~,
    update=source_demo_update,
    view=source_demo_view,
    subscriptions=source_demo_subscriptions,
  )
  @rabbita.new(cell)
  ..with_init(mount_source_cm_cmd(emit, model))
  .mount("source-panel-root")
}
