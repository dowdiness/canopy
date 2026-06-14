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
/// Run `run` on a browser microtask. This is load-bearing for the
/// source-graph settle subscription: settle fires synchronously inside the
/// attachment mutation, before `SourceBackedGraph.source` has been updated, so
/// `SyncFromGraph` must run only after that mutation returns (see
/// `source_graph_change_sub`).
///
/// There is deliberately no `#cfg(not(target="js"))` fallback: the source demo
/// package is pinned to `supported_targets = "js"`, so widening that target set
/// must first provide a defer primitive with this post-mutation ordering.
#cfg(target="js")
extern "js" fn defer_sync(run : () -> Unit) -> Unit =
  #|((run) => { queueMicrotask(() => run()); })

///|
struct SourceDemoModel {
  handle : Int
  editor : String
  // `dirty` is true while the editor's current text is not graph-valid. The
  // source always tracks the editor buffer (see `apply_codemirror_changes`), so
  // `dirty` is purely a status/validity signal; it also gates `SyncFromGraph`
  // as a guard against pushing an out-of-band source over invalid typing.
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
/// is marked clean.
///
/// `dirty_on_reject` is the dirty flag to set when the operation is rejected.
/// `dirty` means "the editor's current text is not graph-valid". A rejected
/// Apply leaves the editor holding the invalid source it tried to apply, so it
/// passes `true`. Connect / Insert never touch the editor (and can be rejected
/// for an already-invalid current source, before any rollback), so they must
/// PRESERVE the prior `dirty` by passing `model.dirty` — not force it `false`,
/// which would wrongly clear dirtiness the editor still has.
fn source_demo_result_step(
  model : SourceDemoModel,
  result : SourceGraphOperationResultJson,
  status : String,
  status_tone : @status.Tone,
  dirty_on_reject~ : Bool,
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
    (
      source_demo_notify(model),
      { ..model, dirty: dirty_on_reject, status, status_tone },
    )
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
      // The editor is the source of truth for text. Lower the change
      // incrementally, passing the editor's post-change buffer (`model.editor`,
      // set by the preceding `EditorSynced`) as the authoritative target: the
      // adapter keeps its source equal to the editor and reconciles editor-wins
      // if an out-of-band graph mutation diverged them, so a transiently-invalid
      // edit recovers incrementally with stable node identity (no whole-source
      // churn). We never `set_doc` here — CodeMirror already holds the text; the
      // canvas keeps rendering the last-good graph while the source is invalid,
      // and `dirty` only records that validity.
      let result = apply_source_graph_codemirror_changes(
        model.handle,
        changes,
        model.editor,
      )
      let success_message = "Editor changes lowered into graph-dsl source."
      let failure_prefix = "Editor change rejected; canvas is rendering last-good graph"
      let (status, status_tone) = source_demo_status_from_result(
        result, success_message, failure_prefix,
      )
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
      // Apply lowers the editor's own text, so a rejection leaves the editor
      // holding invalid source → dirty.
      source_demo_result_step(
        model,
        result,
        status,
        status_tone,
        dirty_on_reject=true,
      )
    }
    ConnectSample => {
      let result = source_graph_connect_sample_result(model.handle)
      let success_message = "Connected meter.input to osc.out through graph-dsl source."
      let (status, status_tone) = source_demo_status_from_result(
        result, success_message, "Source operation rejected",
      )
      // A rejected connect never edits the editor, so its validity is unchanged.
      source_demo_result_step(
        model,
        result,
        status,
        status_tone,
        dirty_on_reject=model.dirty,
      )
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
      // A rejected insert never edits the editor, so its validity is unchanged.
      source_demo_result_step(
        model,
        result,
        status,
        status_tone,
        dirty_on_reject=model.dirty,
      )
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
      // `mounted` stays at its prior value (false): mount fires once via
      // `with_init`, so a failure can only arrive while `mounted` is still
      // false. No need to set it here.
      (
        @rabbita.none,
        {
          ..model,
          status: "CodeMirror failed to mount: " + message,
          status_tone: @status.Error,
        },
      )
  }
}

///|
/// Payload for the reactive source-graph change subscription. Carries the
/// graph handle (which graph to observe) and the tagger that turns a settle
/// ping into a `SyncFromGraph` message.
priv suberror SourceGraphSub {
  GraphChanged(Int, @rabbita.Emit[Unit])
}

///|
/// Reactive replacement for the former `@sub.every(250, SyncFromGraph)` poll:
/// bridges the `GraphAttachment` settle-observer (via `source_graph_subscribe`)
/// into an `Emit`. It pings on every settle regardless of origin; the
/// `SyncFromGraph` handler pulls the source and dedupes (`dirty` /
/// `source == editor` guards), so panel-origin echoes are no-ops.
///
/// The ping is delivered on a microtask (see `defer_sync` in the loader): the
/// settle fires synchronously inside the attachment mutation, before the
/// `SourceBackedGraph.source` wrapper finishes updating, so a same-tick pull
/// would read stale source. Deferring also means `scheduler.add` never runs
/// inside an in-progress drain, so there is no reentrancy to reason about.
fn source_graph_change_sub(
  handle : Int,
  tagger : @rabbita.Emit[Unit],
) -> @sub.Sub {
  // Key on the handle only (not the tagger identity) so re-renders rebind the
  // tagger via `update_tagger` rather than reinstalling the subscription.
  @sub.custom_sub(
    "source_graph.changed(handle=\{handle})",
    @sub.Scope::Local,
    GraphChanged(handle, tagger),
    @sub.SubLoader(source_graph_change_sub_loader),
  )
}

///|
fn source_graph_change_sub_loader(
  payload : Error,
  scheduler : &@cmd.Scheduler,
) -> @sub.RunningSub? {
  match payload {
    GraphChanged(handle, tagger) => {
      let mut current_tagger = tagger
      // Coalesce a burst of settle pings into a single sync. One CodeMirror
      // transaction can apply many per-delta loom edits (`apply_codemirror_changes`
      // settles once per delta), each firing this observer; but `SyncFromGraph`
      // only pulls the *final* source, so all but one ping per turn are redundant
      // TEA cycles. Hold `sync_pending` from the first ping until the deferred
      // sync actually runs, so a multi-range edit or large paste schedules just
      // one `SyncFromGraph` instead of one per delta.
      let mut sync_pending = false
      match
        source_graph_subscribe(handle, fn() {
          guard !sync_pending else { return }
          sync_pending = true
          // Deliver on a microtask: the settle ping fires *inside* the
          // attachment mutation, before `SourceBackedGraph.source` (what
          // `SyncFromGraph` pulls via `get_source_graph_source`) is updated for
          // a canvas-origin op. Deferring lets that synchronous mutation finish
          // so the sync reads the canonical post-mutation source — and keeps
          // `scheduler.add` out of any in-progress drain (no reentrancy).
          //
          // Clear `sync_pending` *before* `scheduler.add` so that if draining
          // the sync somehow provokes a fresh settle, it re-arms and is not
          // swallowed; settles that merely piled up before this microtask are
          // already coalesced into this one run.
          defer_sync(fn() {
            sync_pending = false
            scheduler.add(current_tagger(()))
          })
        }) {
        Some(subscription) =>
          Some({
            unload: fn(_) { subscription.unsubscribe() },
            update_tagger: fn(payload) {
              guard payload is GraphChanged(_, new_tagger) else { return }
              current_tagger = new_tagger
            },
          })
        None => None
      }
    }
    _ => None
  }
}

///|
fn source_demo_subscriptions(
  emit : Emit[SourceDemoMsg],
  model : SourceDemoModel,
) -> @sub.Sub {
  // Both subscriptions need the editor to exist: `listen` is a no-op until the
  // view is registered, and the graph -> editor sync has nothing to push into
  // (and would `set_doc` a not-yet-mounted editor). Gate the whole batch on
  // `mounted` so neither runs before the editor mounts.
  guard model.mounted else { return @sub.none }
  @sub.batch([
    source_graph_change_sub(model.handle, emit.map(_ => SyncFromGraph)),
    @codemirror.listen(
      SOURCE_CM_EDITOR_ID,
      doc=emit.map(source => EditorSynced(source)),
      on_change=emit.map(changes => SourceChanged(changes)),
    ),
  ])
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
