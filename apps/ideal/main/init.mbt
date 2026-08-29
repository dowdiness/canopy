///|
const ROOT_REVISION_MAX : Int = 2147483647

///|
/// Root-only reactive wrapper. `Model` owns mutable editor/FFI state and cannot
/// provide structural equality. A monotonically advancing generation keeps
/// adjacent root states unequal even when multiple updates are batched.
struct RootState(Model, Int)

///|
impl Eq for RootState with fn equal(self, other) {
  self.1 == other.1
}

///|
fn next_root_revision(revision : Int) -> Int {
  if revision == ROOT_REVISION_MAX {
    0
  } else {
    revision + 1
  }
}

///|
fn init_model() -> Model raise {
  // Read agent ID set by JS (main.ts) before module import.
  // Falls back to "local" if JS hasn't set it (e.g. test environment).
  let agent_id = js_get_agent_id()
  let agent_id = if agent_id == "" { "local" } else { agent_id }
  // Create the editor through the crdt module so it sets the singleton (editor.val).
  // JS (main.ts) reuses this handle instead of creating a second editor.
  // Under §P0b Phase 1 the coordinator allocates EditorIds from 0.
  let handle = @ffi.create_editor_with_undo(agent_id, 500)
  let editor = @ffi.get_sync_editor().unwrap()
  let companion = @ffi.get_lambda_companion().unwrap()
  // Attach the memo-event tap before any cell reads so initial-parse recomputes
  // are visible to the IncrGraph panel. `attach` only fails if incr's listener
  // slot is already claimed by an external caller — fatal here, propagate.
  let incr_tap = @visualizer.RecomputeTap::attach(editor.parser_runtime())
  let init_text = "fn id(x : Int) { x }\nfn apply(f : Int -> Int, x : Int) { f x }\napply id 42"
  editor.set_text(init_text)
  let outline_state : @proj.TreeEditorState[@ast.Term] = @proj.TreeEditorState::from_projection(
    editor.get_proj_node(),
    editor.get_source_map(),
  )
  {
    editor,
    handle,
    companion,
    outline_state,
    cm_id: "canopy-text-editor",
    mounted: false,
    mode: Text,
    workspace: initial_workspace_layout(),
    selected_node: None,
    diagnostics_open: false,
    next_timestamp: 1,
    bottom_tab: Problems,
    sync_status: Connecting,
    overlay: ActionOverlayHost::empty(),
    scope_map: build_scope_map_from_editor(editor),
    highlight_set: @immut/hashset.new(),
    nav_path: None,
    drag_source: None,
    drop_target_id: None,
    drop_position: None,
    intent_log: [],
    patch_log: [],
    incr_tap,
    incr_canvas: IncrCanvasState::empty(),
  }
}

///|
fn subscriptions(model : Model, emit : Emit[Msg]) -> Sub {
  let editor_events = editor_dom_event_subscriptions(emit)
  let cm_events = if model.mounted {
    @cm.listen(
      model.cm_id,
      selection=emit.map(range => CmSelectionChanged(range)),
      on_change_with_doc=emit.map(event => CmChanges(event)),
      source_version=() => Hash::hash(model.editor.get_version()).to_string(),
    )
  } else {
    @sub.none
  }
  let outline_resize = model.workspace.outline_resize.subscriptions(msg => {
    emit(OutlineResize(msg))
  })
  @sub.batch([editor_events, cm_events, outline_resize])
}

///|
fn root_init(emit : Emit[Msg]) -> (RootState, Cmd) {
  let model = init_model() catch {
    _ => abort("Ideal editor initialization failed")
  }
  let model = sync_incr_canvas(model)
  (RootState(model, 0), cm_mount_cmd(emit, model))
}

///|
fn root_update(
  state : RootState,
  msg : Msg,
  emit : Emit[Msg],
) -> (RootState, Cmd) {
  let (cmd, model) = update(emit, msg, state.0) catch {
    _ => (none, { ..state.0, sync_status: Error })
  }
  let model = sync_incr_canvas(model)
  (RootState(model, next_root_revision(state.1)), cmd)
}

///|
fn root_subscriptions(state : RootState, emit : Emit[Msg]) -> Sub {
  subscriptions(state.0, emit)
}

///|
fn render_view_fallback(model : Model) -> Html {
  let source = model.editor.get_text()
  @html.div(attrs=@html.Attrs::build().role("alert"), [
    @html.p([
      @html.text(
        "Derived views are unavailable. The current source is shown read-only.",
      ),
    ]),
    @html.node(
      "pre",
      @html.Attrs::build()
      .role("textbox")
      .aria_label("Current source, read-only")
      .aria_multiline("true")
      .aria_readonly("true"),
      [@html.text(source)],
    ),
  ])
}

///|
fn main {
  let app = @rabbita.new(() => {
    let (model, emit) = @rabbita.create_state_with_init(
      init=root_init,
      update=root_update,
      subscriptions=root_subscriptions,
    )
    model.map(state => {
      view(emit, state.0) catch {
        _ => render_view_fallback(state.0)
      }
    })
  })
  app.mount("app")
}
