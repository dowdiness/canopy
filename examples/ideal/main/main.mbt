///|
using @html {button, div, p, span, text}

///|
using @rabbita {type Cmd, type Emit, type Html, none}

///|
using @sub {type Sub}

///|
/// Parse a node ID string into a NodeId, returning None on invalid input.
fn parse_node_id(s : String) -> @canopy_core.NodeId? {
  let n = @string.parse_int(s) catch { _ => return None }
  Some(@canopy_core.NodeId::from_int(n))
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
  }
}

///|
fn cm_mount_cmd(emit : Emit[Msg], model : Model) -> Cmd {
  @cm.mount(
    model.cm_id,
    "canopy-text-editor",
    init_doc=model.editor.get_text(),
    source="global:__canopy_codemirror",
    initial_line_wrapping=true,
    on_mounted=emit(CmMounted),
    failed=emit.map(message => {
      ignore(message)
      SyncStatusChanged("error")
    }),
    initial_extension=Some(js_make_ideal_cm_extension),
  )
}

///|
fn sync_after_local_model_change(model : Model, text : String) -> Cmd {
  @rabbita.batch([
    @cm.set_doc(model.cm_id, text),
    @rabbita.effect(fn() { js_after_local_text_edit() }),
  ])
}

///|
fn sync_after_external_crdt_change(model : Model) -> Cmd {
  @cm.set_doc(model.cm_id, model.editor.get_text())
}

///|
fn select_text_node_cmd(model : Model, node_id : String) -> Cmd {
  match parse_node_id(node_id) {
    None => none
    Some(nid) =>
      match model.editor.get_source_map().get_range(nid) {
        None => none
        Some(range) =>
          @rabbita.batch([
            @cm.set_selection(
              model.cm_id,
              @cm.SelRange::new(range.start, range.end),
              scroll_into_view=true,
            ),
            @rabbita.effect(fn() {
              js_after_cm_selection_changed(range.start, range.end)
            }),
          ])
      }
  }
}

///|
fn select_editor_node_cmd(model : Model, node_id : String) -> Cmd {
  let focus_outline = @rabbita.effect(fn() { js_focus_tree_rows() })
  if model.mode == Text {
    @rabbita.batch([select_text_node_cmd(model, node_id), focus_outline])
  } else {
    @rabbita.effect(fn() {
      js_set_editor_selected_node(node_id)
      js_focus_tree_rows()
    })
  }
}

///|
fn subscriptions(emit : Emit[Msg], model : Model) -> Sub {
  let editor_events = editor_dom_event_subscriptions(emit)
  let cm_events = if model.mounted {
    @cm.listen(
      model.cm_id,
      doc=emit.map(text => CmDocChanged(text)),
      selection=emit.map(range => CmSelectionChanged(range)),
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
const MAX_INTENT_LOG = 50

///|
const MAX_PATCH_LOG = 50

///|
/// Per-SpanEdit cap on the retained `inserted` text. The full text is still
/// applied to the CRDT; only the patch_log copy is truncated to keep
/// patch_log memory proportional to MAX_PATCH_LOG, not to user paste size.
const MAX_PATCH_INSERTED_CHARS = 200

///|
fn push_intent(model : Model, op : @lambda_edits.TreeEditOp) -> Unit {
  push_intent_label(model, op.to_generic().to_string())
}

///|
/// Fallback for structural intents arriving via the FFI path when the op
/// cannot be rebuilt as a typed `TreeEditOp` from `(op, node_id)` alone —
/// e.g. `"Drop"`, whose `source`/`position` payload is not recoverable.
/// Ops in `structural_edit_op_to_tree_edit`'s domain go through
/// `push_intent` instead so the Op Log row shape matches direct-apply paths.
fn push_intent_label(model : Model, label : String) -> Unit {
  model.intent_log.push(label)
  while model.intent_log.length() > MAX_INTENT_LOG {
    model.intent_log.remove(0) |> ignore
  }
}

///|
/// Record an applied (op, SpanEdits) pair for the Patch panel. The op label
/// mirrors the Op Log entry shape (`TreeEditOp.to_generic().to_string()`),
/// so a Patch row reads as a back-reference to the producing Op Log entry.
/// Skipped if `edits` is empty — those rows would be visually noisy and
/// duplicate the corresponding Op Log entry without adding patch detail.
///
/// Each retained `SpanEdit` is decoupled from the editor-owned array:
/// (a) the outer array is rebuilt, so post-apply mutation upstream can't
/// corrupt logged rows; (b) `inserted` is capped at
/// `MAX_PATCH_INSERTED_CHARS` so a 1MB paste doesn't anchor 1MB in the log.
fn push_patch(
  model : Model,
  op : @lambda_edits.TreeEditOp,
  edits : Array[@canopy_core.SpanEdit],
) -> Unit {
  if edits.is_empty() {
    return
  }
  let snapshot = @lambda.snapshot_span_edits(edits, MAX_PATCH_INSERTED_CHARS)
  model.patch_log.push({
    op_label: op.to_generic().to_string(),
    edits: snapshot,
  })
  while model.patch_log.length() > MAX_PATCH_LOG {
    model.patch_log.remove(0) |> ignore
  }
}

///|
/// Build scope_map from an editor. Thin wrapper over the pure
/// @scope.build_scope_map that extracts projection data from SyncEditor.
fn build_scope_map_from_editor(
  editor : @editor.SyncEditor[@ast.Term],
) -> Map[@canopy_core.NodeId, @scope.ScopeAnnotation] {
  match editor.get_proj_node() {
    Some(proj_root) =>
      @scope.build_scope_map(
        proj_root,
        editor.get_registry(),
        editor.get_source_map(),
      )
    None => {}
  }
}

///|
fn refresh(model : Model) -> Model {
  js_perf_begin("refreshTotal")
  js_perf_begin("getProjNode")
  let proj_node = model.editor.get_proj_node()
  js_perf_end("getProjNode")
  js_perf_begin("getSourceMap")
  let source_map = model.editor.get_source_map()
  js_perf_end("getSourceMap")
  js_perf_begin("treeEditorRefresh")
  let outline_state = model.outline_state.refresh(proj_node, source_map)
  js_perf_end("treeEditorRefresh")
  // Build scope_map from current projection
  js_perf_begin("buildScopeMap")
  let scope_map = build_scope_map_from_editor(model.editor)
  js_perf_end("buildScopeMap")
  // Recompute highlight_set if a node is selected
  js_perf_begin("computeHighlightSet")
  let highlight_set = match model.selected_node {
    Some(nid_str) =>
      match parse_node_id(nid_str) {
        Some(nid) => @scope.compute_highlight_set(nid, scope_map)
        None => @immut/hashset.new()
      }
    None => @immut/hashset.new()
  }
  js_perf_end("computeHighlightSet")
  js_perf_end("refreshTotal")
  { ..model, outline_state, scope_map, highlight_set }
}

///|
let examples : Array[(String, String)] = [
  ("Basics", "fn double(x : Int) {\n  x + x\n}\nlet result = double 5\nresult"),
  (
    "Composition", "fn inc(n : Int) { n + 1 }\nfn twice(f : Int -> Int, x : Int) {\n  f (f x)\n}\nlet result = twice inc 0\nresult",
  ),
  (
    "Currying", "fn add(x : Int, y : Int) { x + y }\nlet add5 = add 5\nlet sum = add5 10\nsum",
  ),
  (
    "Conditional", "fn choose(x : Int) { if x then {\n  x + 1\n} else {\n  42\n} }\nlet a = choose 0\nlet b = choose 5\na + b",
  ),
  (
    "Pipeline", "fn compose(f : Int -> Int, g : Int -> Int, x : Int) {\n  f (g x)\n}\nfn double(x : Int) { x + x }\nfn inc(x : Int) { x + 1 }\nlet f = compose inc double\nf 5",
  ),
]

///|
fn view_toolbar(dispatch : Emit[Msg], model : Model) -> Html {
  let example_buttons : Array[Html] = examples.map(fn(pair) {
    let (label, code) = pair
    button(
      class=@ui.toolbar_example_button_class(),
      on_click=dispatch(LoadExample(code)),
      [text(label)],
    )
  })
  let toolbar_items : Array[Html] = [
    span(class=toolbar_title_class, [text("Canopy Editor")]),
    div(class=toolbar_spacer_class, [text("")]),
    button(
      class=@ui.toolbar_tab_class(model.mode == Text),
      on_click=dispatch(SetMode(Text)),
      attrs=@html.Attrs::build().aria_pressed(
        if model.mode == Text {
          "true"
        } else {
          "false"
        },
      ),
      [text("Text")],
    ),
    button(
      class=@ui.toolbar_tab_class(model.mode == Structure),
      on_click=dispatch(SetMode(Structure)),
      attrs=@html.Attrs::build().aria_pressed(
        if model.mode == Structure {
          "true"
        } else {
          "false"
        },
      ),
      [text("Structure")],
    ),
    div(class=toolbar_spacer_class, [text("")]),
    button(class=@ui.toolbar_button_class(), on_click=dispatch(Undo), [
      text("Undo"),
    ]),
    button(class=@ui.toolbar_button_class(), on_click=dispatch(Redo), [
      text("Redo"),
    ]),
    div(class=toolbar_spacer_class, [text("")]),
    button(class=@ui.toolbar_button_class(), on_click=dispatch(OpenFile), [
      text("Open"),
    ]),
    button(class=@ui.toolbar_button_class(), on_click=dispatch(SaveFile), [
      text("Save"),
    ]),
    div(class=toolbar_spacer_class, [text("")]),
    button(
      class=@ui.toolbar_panel_toggle_class(model.workspace.outline_visible),
      on_click=dispatch(TogglePanel(Outline)),
      attrs=@html.Attrs::build().aria_pressed(
        if model.workspace.outline_visible {
          "true"
        } else {
          "false"
        },
      ),
      [text("Outline")],
    ),
    button(
      class=@ui.toolbar_panel_toggle_class(model.workspace.inspector_visible),
      on_click=dispatch(TogglePanel(Inspector)),
      attrs=@html.Attrs::build().aria_pressed(
        if model.workspace.inspector_visible {
          "true"
        } else {
          "false"
        },
      ),
      [text("Inspector")],
    ),
    button(
      class=@ui.toolbar_panel_toggle_class(model.workspace.bottom_visible),
      on_click=dispatch(TogglePanel(Bottom)),
      attrs=@html.Attrs::build().aria_pressed(
        if model.workspace.bottom_visible {
          "true"
        } else {
          "false"
        },
      ),
      [text("Panels")],
    ),
    div(class=toolbar_spacer_class, [text("")]),
  ]
  example_buttons.each(fn(b) { toolbar_items.push(b) })
  div(class=toolbar_class, toolbar_items)
}

///|
/// Check if a tree node has elided children in the outline state.
fn tree_node_is_elided(
  state : @proj.TreeEditorState[@ast.Term],
  node_id : @canopy_core.NodeId,
) -> Bool {
  match state.get_loaded_node(node_id) {
    Some(node) =>
      match node.children {
        @proj.Elided(_) => true
        @proj.Loaded(_) => false
      }
    None => false
  }
}

///|
/// Check if expanding a node should hydrate its elided subtree.
/// Hydration is always allowed since the projection is refreshed
/// immediately on every text change (no stale state possible).
fn can_hydrate_tree_node(model : Model, node_id : @canopy_core.NodeId) -> Bool {
  tree_node_is_elided(model.outline_state, node_id)
}

///|
fn apply_structural_edit_request(
  model : Model,
  op : String,
  node_id : String,
) -> (Cmd, Model) {
  let nid = match parse_node_id(node_id) {
    Some(id) => id
    None => return (none, model)
  }
  let tree_op = match @lambda.structural_edit_op_to_tree_edit(op, nid) {
    Some(tree_op) => tree_op
    None => return (none, model)
  }
  match
    @lambda.apply_lambda_tree_edit(
      model.editor,
      model.companion,
      tree_op,
      js_now_ms(),
    ) {
    Ok(edits) => {
      push_intent(model, tree_op)
      push_patch(model, tree_op, edits)
      let new_model = refresh({
        ..model,
        next_timestamp: model.next_timestamp + 1,
      })
      let text = new_model.editor.get_text()
      let cmd = sync_after_local_model_change(new_model, text)
      (cmd, new_model)
    }
    Err(_) => (none, model)
  }
}

///|
fn update(emit : Emit[Msg], msg : Msg, model : Model) -> (Cmd, Model) {
  match handle_workspace(emit, msg, model) {
    Some(r) => return r
    None => ()
  }
  match handle_structural(emit, msg, model) {
    Some(r) => return r
    None => ()
  }
  match handle_outline(emit, msg, model) {
    Some(r) => return r
    None => ()
  }
  match handle_overlay(emit, msg, model) {
    Some(r) => return r
    None => ()
  }
  match handle_file_io(emit, msg, model) {
    Some(r) => return r
    None => ()
  }
  match handle_structure_mode(emit, msg, model) {
    Some(r) => return r
    None => ()
  }
  match handle_codemirror(emit, msg, model) {
    Some(r) => return r
    None => ()
  }
  abort("unhandled message")
}

///|
fn view_peer_status(model : Model) -> Html {
  let (label, tone) : (String, @status.Tone) = match model.sync_status {
    Connected => ("You (connected)", @status.Success)
    Connecting => ("Connecting\u{2026}", @status.Info)
    Offline => ("Offline \u{2014} reconnecting\u{2026}", @status.Info)
    Error => ("Connection error", @status.Error)
  }
  div(class=peer_item_class, attrs=tone.attrs(), [
    div(
      class=peer_dot_class(model.sync_status),
      attrs=@html.Attrs::build().aria_hidden("true"),
      [text("")],
    ),
    span(class="peer-label", [text(label)]),
  ])
}

///|
fn outline_panel_attrs(workspace : WorkspaceLayout) -> @html.Attrs {
  let attrs = @html.Attrs::build()
    .role("navigation")
    .aria_label("AST outline")
    .style("--outline-panel-width", workspace.outline_width_px())
  if workspace.outline_resize.is_resizing() {
    attrs.style("user-select", "none")
  } else {
    attrs
  }
}

///|
fn view_outline_resize_handle(
  dispatch : Emit[Msg],
  workspace : WorkspaceLayout,
) -> Html {
  div(
    class=outline_resize_handle_class,
    attrs=workspace.outline_resize.handle_attrs(@resizable.Edge::East, msg => {
      dispatch(OutlineResize(msg))
    }),
    [text("")],
  )
}

///|
fn view(dispatch : Emit[Msg], model : Model) -> Html {
  // Always render panels — toggle visibility via CSS class
  // so CSS transitions work for both enter and exit.
  let outline_class = if model.workspace.outline_visible {
    "outline-panel panel-visible"
  } else {
    "outline-panel panel-hidden"
  }
  let inspector_class = if model.workspace.inspector_visible {
    "inspector-panel panel-visible"
  } else {
    "inspector-panel panel-hidden"
  }
  let bottom_class = if model.workspace.bottom_visible {
    "bottom-panel panel-visible"
  } else {
    "bottom-panel panel-hidden"
  }
  let outline_attrs = outline_panel_attrs(model.workspace)
  let inspector_attrs = @html.Attrs::build()
    .role("complementary")
    .aria_label("Node inspector")
  // Scrim visible when either side panel is open (used on mobile as drawer backdrop)
  let scrim_class = if model.workspace.outline_visible ||
    model.workspace.inspector_visible {
    "panel-scrim"
  } else {
    "panel-scrim scrim-hidden"
  }
  div(class="app-shell", [
    view_toolbar(dispatch, model),
    div(class="workspace", [
      div(
        class=scrim_class,
        on_click=dispatch(DismissPanels),
        attrs=@html.Attrs::build().aria_hidden("true"),
        [text("")],
      ),
      div(class=outline_class, attrs=outline_attrs, [
        div(class=panel_header_class(), [
          span(class=@ui.panel_label_class(), [text("OUTLINE")]),
        ]),
        view_outline_content(dispatch, model),
        div(class=@ui.panel_section_class(), [
          span(class=@ui.panel_label_class(), [text("PEERS")]),
          view_peer_status(model),
        ]),
        view_outline_resize_handle(dispatch, model.workspace),
      ]),
      view_editor(dispatch, model),
      div(class=inspector_class, attrs=inspector_attrs, [
        view_inspector_content(dispatch, model),
      ]),
    ]),
    div(class=bottom_class, [view_bottom_content(dispatch, model)]),
    match model.overlay.active {
      Some((_, runtime)) => runtime.view()
      None => @html.nothing
    },
  ])
}

///|
#warnings("-alert_unstable")
fn main {
  // init_model attaches the incr memo-event tap, which raises if incr's
  // listener slot is already claimed. fn main can't propagate, so collapse
  // the error to an abort at the boundary.
  let initial_model = try! init_model()
  let (emit, app) = @rabbita.cell_with_emit(
    model=initial_model,
    update~,
    view~,
    subscriptions~,
  )
  let app = @rabbita.new(app)
  app..with_init(cm_mount_cmd(emit, initial_model)).mount("app")
}
