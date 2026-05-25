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
/// Split an action ID on the first ':' into (base_id, choice).
/// Returns (action_id, "") when there is no colon.
fn split_action_id(action_id : String) -> (String, String) {
  match action_id.find(":") {
    Some(i) => (action_id[0:i].to_owned(), action_id[i + 1:].to_owned())
    None => (action_id, "")
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
  let _handle = @ffi.create_editor_with_undo(agent_id, 500)
  let editor = @ffi.get_sync_editor().unwrap()
  let companion = @ffi.get_lambda_companion().unwrap()
  // Attach the memo-event tap before any cell reads so initial-parse recomputes
  // are visible to the IncrGraph panel. `attach` only fails if incr's listener
  // slot is already claimed by an external caller — fatal here, propagate.
  let incr_tap = @visualizer.IncrMemoEventTap::attach(editor.parser_runtime())
  let init_text = "let id = \\x. { x }\nlet apply = \\f. \\x. { f x }\napply id 42"
  editor.set_text(init_text)
  let outline_state : @proj.TreeEditorState[@ast.Term] = @proj.TreeEditorState::from_projection(
    editor.get_proj_node(),
    editor.get_source_map(),
  )
  {
    editor,
    companion,
    outline_state,
    cm_id: "canopy-text-editor",
    mounted: false,
    mode: Text,
    workspace: {
      outline_visible: true,
      inspector_visible: true,
      bottom_visible: false,
    },
    selected_node: None,
    diagnostics_open: false,
    next_timestamp: 1,
    bottom_tab: Problems,
    sync_status: Connecting,
    overlay: closed_overlay(),
    scope_map: build_scope_map(editor),
    highlight_set: @immut/hashset.new(),
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
  @sub.batch([editor_events, cm_events])
}

///|
fn open_action_overlay_from_event(
  model : Model,
  node_id_str : String,
) -> (Cmd, Model) {
  let new_model = open_action_overlay(model, node_id_str)
  if new_model.overlay.visible {
    // Focus the overlay panel after Rabbita renders it
    let focus_cmd = @rabbita_cmd.custom_cmd(
      fn(_) { js_focus_overlay_panel() },
      kind=@rabbita_cmd.after_render,
    )
    (focus_cmd, new_model)
  } else {
    (none, new_model)
  }
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
  let snapshot : Array[@canopy_core.SpanEdit] = edits.map(fn(e) {
    // Truncate by iterating codepoints, not UTF-16 code units. Slicing
    // `e.inserted[:N]` would abort uncatchably if index N landed mid
    // surrogate pair (e.g. user pastes 199 BMP code units then an emoji).
    // `String::length` is the cheap upper-bound check; the loop produces a
    // codepoint-bounded copy when truncation is warranted.
    let inserted = if e.inserted.length() > MAX_PATCH_INSERTED_CHARS {
      let buf = StringBuilder::new(size_hint=MAX_PATCH_INSERTED_CHARS)
      let mut count = 0
      for ch in e.inserted {
        if count >= MAX_PATCH_INSERTED_CHARS {
          break
        }
        buf.write_char(ch)
        count = count + 1
      }
      buf.write_char('…')
      buf.to_string()
    } else {
      e.inserted
    }
    { start: e.start, delete_len: e.delete_len, inserted }
  })
  model.patch_log.push({
    op_label: op.to_generic().to_string(),
    edits: snapshot,
  })
  while model.patch_log.length() > MAX_PATCH_LOG {
    model.patch_log.remove(0) |> ignore
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
  let scope_map = build_scope_map(model.editor)
  js_perf_end("buildScopeMap")
  // Recompute highlight_set if a node is selected
  js_perf_begin("computeHighlightSet")
  let highlight_set = match model.selected_node {
    Some(nid_str) =>
      match parse_node_id(nid_str) {
        Some(nid) => compute_highlight_set(nid, scope_map)
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
  ("Basics", "let double = \\x. {\n  x + x\n}\nlet result = double 5\nresult"),
  (
    "Composition", "let inc = \\n. { n + 1 }\nlet twice = \\f. \\x. {\n  f (f x)\n}\nlet result = twice inc 0\nresult",
  ),
  (
    "Currying", "let add = \\x. \\y. { x + y }\nlet add5 = add 5\nlet sum = add5 10\nsum",
  ),
  (
    "Conditional", "let choose = \\x. if x then {\n  x + 1\n} else {\n  42\n}\nlet a = choose 0\nlet b = choose 5\na + b",
  ),
  (
    "Pipeline", "let compose = \\f. \\g. \\x. {\n  f (g x)\n}\nlet double = \\x. { x + x }\nlet inc = \\x. { x + 1 }\nlet f = compose inc double\nf 5",
  ),
]

///|
fn view_toolbar(dispatch : Emit[Msg], model : Model) -> Html {
  let example_buttons : Array[Html] = examples.map(fn(pair) {
    let (label, code) = pair
    button(
      class="toolbar-btn example-btn",
      on_click=dispatch(LoadExample(code)),
      [text(label)],
    )
  })
  let toolbar_items : Array[Html] = [
    span(class="toolbar-title", [text("Canopy Editor")]),
    div(class="toolbar-spacer", [text("")]),
    button(
      class=if model.mode == Text { "tab active" } else { "tab" },
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
      class=if model.mode == Structure { "tab active" } else { "tab" },
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
    div(class="toolbar-spacer", [text("")]),
    button(class="toolbar-btn", on_click=dispatch(Undo), [text("Undo")]),
    button(class="toolbar-btn", on_click=dispatch(Redo), [text("Redo")]),
    div(class="toolbar-spacer", [text("")]),
    button(
      class=if model.workspace.outline_visible {
        "panel-toggle active"
      } else {
        "panel-toggle"
      },
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
      class=if model.workspace.inspector_visible {
        "panel-toggle active"
      } else {
        "panel-toggle"
      },
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
      class=if model.workspace.bottom_visible {
        "panel-toggle active"
      } else {
        "panel-toggle"
      },
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
    div(class="toolbar-spacer", [text("")]),
  ]
  example_buttons.each(fn(b) { toolbar_items.push(b) })
  div(class="toolbar", toolbar_items)
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
/// Map a standard structural-edit op string to a typed `TreeEditOp`. Used
/// on both the direct-apply path (`apply_structural_edit_request`, from
/// Inspector / Web Component `STRUCTURAL_EDIT_REQUEST`) and the FFI-applied
/// path (`StructureStructuralEdit`, from `STRUCTURAL_EDIT_APPLIED`) so the
/// Op Log row shape matches in both. Must stay in sync with the dispatch
/// sites in `view_inspector.mbt` and `web/src/keymap.ts`. Returns `None`
/// for ops outside the standard set — notably `"Drop"`, whose `source` /
/// `position` payload is not recoverable from `(op, node_id)` alone.
fn structural_edit_op_to_tree_edit(
  op : String,
  node_id : @canopy_core.NodeId,
) -> @lambda_edits.TreeEditOp? {
  match op {
    "WrapInLambda" => Some(@lambda_edits.WrapInLambda(node_id~, var_name="x"))
    "Delete" => Some(@lambda_edits.Delete(node_id~))
    _ => None
  }
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
  let tree_op = match structural_edit_op_to_tree_edit(op, nid) {
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
fn closed_overlay() -> OverlayState {
  {
    visible: false,
    actions: [],
    node_context: None,
    submenu: None,
    pending_action: None,
    name_value: "",
    name_error: "",
    anchor_top: 0,
    anchor_left: 0,
  }
}

///|
/// Parse the bounding rect JSON from js_get_selected_node_rect into (top, left).
fn parse_anchor_rect(json_str : String) -> (Int, Int) {
  let json = @json.parse(json_str) catch { _ => return (0, 0) }
  let (raw_top, raw_left) = match json {
    Json::Object(m) => {
      let top = match m.get("bottom") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 0
      }
      let left = match m.get("left") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 0
      }
      (top, left)
    }
    _ => (0, 0)
  }
  // Clamp to viewport so the overlay doesn't extend offscreen.
  // Estimated panel size: 320px wide, 300px tall (conservative).
  let viewport_json = js_get_viewport_size()
  let vp = @json.parse(viewport_json) catch { _ => return (raw_top, raw_left) }
  match vp {
    Json::Object(m) => {
      let vw = match m.get("width") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 1024
      }
      let vh = match m.get("height") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 768
      }
      let panel_w = 320
      let panel_h = 300
      let clamped_left = if raw_left + panel_w > vw {
        (vw - panel_w - 8).max(8)
      } else {
        raw_left
      }
      let clamped_top = if raw_top + panel_h > vh {
        (vh - panel_h - 8).max(8)
      } else {
        raw_top
      }
      (clamped_top, clamped_left)
    }
    _ => (raw_top, raw_left)
  }
}

///|
/// Open the action overlay for the given node ID string.
fn open_action_overlay(
  model : Model,
  node_id_str : String,
  rect_json? : String = js_get_selected_node_rect(),
) -> Model {
  if node_id_str == "" {
    return model
  }
  let ctx = match
    detect_action_context(model.editor, model.companion, node_id_str) {
    Some(c) => c
    None => return model
  }
  let proj_ctx = to_proj_context(ctx)
  let actions = @lambda_edits.get_actions_for_node(ctx.kind, proj_ctx)
  if actions.is_empty() {
    return model
  }
  let (anchor_top, anchor_left) = parse_anchor_rect(rect_json)
  js_set_overlay_open(true)
  {
    ..model,
    overlay: {
      visible: true,
      actions,
      node_context: Some(ctx),
      submenu: None,
      pending_action: None,
      name_value: "",
      name_error: "",
      anchor_top,
      anchor_left,
    },
  }
}

///|
/// Execute an action: build the tree edit op and apply it.
/// Returns (Cmd, Model) after execution.
fn execute_action(
  model : Model,
  action : @lambda_edits.Action,
  choice : String,
  name : String,
) -> (Cmd, Model) {
  let ctx = match model.overlay.node_context {
    Some(c) => c
    None => return (none, model)
  }
  match build_tree_edit_op(action.id, ctx, choice, name) {
    Ok(Some(op)) =>
      match
        @lambda.apply_lambda_tree_edit(
          model.editor,
          model.companion,
          op,
          js_now_ms(),
        ) {
        Ok(edits) => {
          push_intent(model, op)
          push_patch(model, op, edits)
          js_set_overlay_open(false)
          let new_model = refresh({
            ..model,
            next_timestamp: model.next_timestamp + 1,
            overlay: closed_overlay(),
          })
          let text = new_model.editor.get_text()
          let cmd = sync_after_local_model_change(new_model, text)
          (cmd, new_model)
        }
        Err(err) => {
          let overlay = { ..model.overlay, name_error: err.message() }
          (none, { ..model, overlay, })
        }
      }
    Ok(None) => {
      // Action needs a name prompt
      let overlay = {
        ..model.overlay,
        pending_action: Some(action),
        name_value: "",
        name_error: "",
      }
      (none, { ..model, overlay, })
    }
    Err(msg) => {
      let overlay = { ..model.overlay, name_error: msg }
      (none, { ..model, overlay, })
    }
  }
}

///|
/// Dispatch an action immediately, open a submenu for choice-based actions,
/// or open the name prompt for input-requiring actions.
fn dispatch_or_prompt(
  model : Model,
  action : @lambda_edits.Action,
) -> (Cmd, Model) {
  if action.needs_input {
    let overlay = {
      ..model.overlay,
      pending_action: Some(action),
      name_value: "",
      name_error: "",
    }
    (none, { ..model, overlay, })
  } else {
    // Check if this action needs a choice submenu
    let ctx_kind = match model.overlay.node_context {
      Some(ctx) => ctx.kind
      None => @ast.Term::Unit
    }
    let choices = get_submenu_choices(action.id, ctx_kind)
    if choices.length() > 0 {
      let overlay = { ..model.overlay, submenu: Some(action) }
      (none, { ..model, overlay, })
    } else {
      execute_action(model, action, "", "")
    }
  }
}

///|
fn update(_dispatch : Emit[Msg], msg : Msg, model : Model) -> (Cmd, Model) {
  match msg {
    SetMode(mode) => {
      let mode_str : String = match mode {
        Text => "text"
        Structure => "structure"
      }
      let cmd = @rabbita.effect(fn() { js_set_editor_mode(mode_str) })
      (cmd, { ..model, mode, })
    }
    TogglePanel(panel) => {
      let ws = model.workspace
      let workspace = match panel {
        Outline => { ..ws, outline_visible: !ws.outline_visible }
        Inspector => { ..ws, inspector_visible: !ws.inspector_visible }
        Bottom => { ..ws, bottom_visible: !ws.bottom_visible }
      }
      let new_model = { ..model, workspace, }
      // Bottom-panel HTML is now mounted through rabbita's vdom (see
      // `view_bottom_content`), so opening/closing the panel re-renders
      // it from scratch — no separate refresh command needed.
      (none, new_model)
    }
    DismissPanels => {
      let ws = model.workspace
      let workspace = { ..ws, outline_visible: false, inspector_visible: false }
      (none, { ..model, workspace, })
    }
    SelectBottomTab(tab) => {
      let new_model = { ..model, bottom_tab: tab }
      (bottom_tab_focus_cmd(tab), new_model)
    }
    StructuralEditRequested(op~, node_id~) =>
      if op == "" || node_id == "" {
        (none, model)
      } else {
        apply_structural_edit_request(model, op, node_id)
      }
    TreeEdited(op) =>
      match op {
        @lambda_edits.Expand(node_id~) => {
          let hydrate_after_expand = can_hydrate_tree_node(model, node_id)
          let outline_state = if hydrate_after_expand {
            model.outline_state.expand_node(
              node_id,
              model.editor.get_proj_node(),
              model.editor.get_source_map(),
            )
          } else {
            model.outline_state.apply_edit(op.to_generic())
          }
          return (none, { ..model, outline_state, })
        }
        @lambda_edits.Collapse(..)
        | @lambda_edits.Select(..)
        | @lambda_edits.SelectRange(..) => {
          let outline_state = model.outline_state.apply_edit(op.to_generic())
          return (none, { ..model, outline_state, })
        }
        _ => (none, model)
      }
    Undo => {
      let did_undo = model.editor.undo()
      if did_undo {
        let new_model = refresh(model)
        let text = new_model.editor.get_text()
        let cmd = sync_after_local_model_change(new_model, text)
        (cmd, new_model)
      } else {
        (none, model)
      }
    }
    Redo => {
      let did_redo = model.editor.redo()
      if did_redo {
        let new_model = refresh(model)
        let text = new_model.editor.get_text()
        let cmd = sync_after_local_model_change(new_model, text)
        (cmd, new_model)
      } else {
        (none, model)
      }
    }
    LoadExample(example_text) => {
      model.editor.set_text_and_record(example_text, js_now_ms())
      let new_model = refresh({
        ..model,
        next_timestamp: model.next_timestamp + 1,
      })
      let text = new_model.editor.get_text()
      let cmd = sync_after_local_model_change(new_model, text)
      (cmd, new_model)
    }
    OutlineNodeClicked(node_id) => {
      // Highlight in the active editor, then re-focus tree rows.
      let cmd = select_editor_node_cmd(model, node_id)
      let highlight_set = match parse_node_id(node_id) {
        Some(nid) => compute_highlight_set(nid, model.scope_map)
        None => @immut/hashset.new()
      }
      (cmd, { ..model, selected_node: Some(node_id), highlight_set })
    }
    OutlineNavigate(node_id_str) => {
      // Update selection without touching editor focus — outline keeps keyboard focus
      let new_selected : String? = if node_id_str == "" {
        None
      } else {
        Some(node_id_str)
      }
      let outline_state = match new_selected {
        Some(s) =>
          match parse_node_id(s) {
            Some(nid) =>
              model.outline_state.apply_edit(
                @canopy_core.GenericTreeOp::Select(node_id=nid),
              )
            None => return (none, model)
          }
        None => model.outline_state
      }
      let cmd = match new_selected {
        Some(s) =>
          @rabbita.batch([
            select_editor_node_cmd(model, s),
            scroll_selector_after_render(".outline-panel .tree-row.selected"),
          ])
        None => none
      }
      let highlight_set = match new_selected {
        Some(s) =>
          match parse_node_id(s) {
            Some(nid) => compute_highlight_set(nid, model.scope_map)
            None => @immut/hashset.new()
          }
        None => @immut/hashset.new()
      }
      (
        cmd,
        { ..model, selected_node: new_selected, outline_state, highlight_set },
      )
    }
    OutlineStructuralEdit(tree_op) =>
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
          // Relocate selection to where FocusHint placed the text cursor
          let (new_selected, outline_state) = match
            new_model.editor
            .get_source_map()
            .innermost_node_at(new_model.editor.get_cursor()) {
            Some(nid) => {
              let os = new_model.outline_state.apply_edit(
                @canopy_core.GenericTreeOp::Select(node_id=nid),
              )
              (Some(node_id_to_string(nid)), os)
            }
            None => (None, new_model.outline_state)
          }
          let highlight_set = match new_selected {
            Some(s) =>
              match parse_node_id(s) {
                Some(nid) => compute_highlight_set(nid, new_model.scope_map)
                None => @immut/hashset.new()
              }
            None => @immut/hashset.new()
          }
          let text = new_model.editor.get_text()
          let cmd = sync_after_local_model_change(new_model, text)
          (
            cmd,
            {
              ..new_model,
              selected_node: new_selected,
              outline_state,
              highlight_set,
            },
          )
        }
        Err(_) => (none, model)
      }
    OpenActionOverlayFromOutline => {
      let node_id_str = match model.selected_node {
        Some(s) => s
        None => return (none, model)
      }
      let rect_json = js_get_outline_selected_rect()
      let new_model = open_action_overlay(model, node_id_str, rect_json~)
      if new_model.overlay.visible {
        (focus_selector_after_render(".action-overlay-panel"), new_model)
      } else {
        (none, new_model)
      }
    }
    SyncStatusChanged(status) => {
      let sync_status : SyncStatus = match status {
        "connected" => Connected
        "connecting" => Connecting
        "disconnected" => Offline
        "error" => Error
        _ => model.sync_status
      }
      (none, { ..model, sync_status, })
    }
    OpenActionOverlayForNode(node_id_str)
    | LongPressTriggeredForNode(node_id_str) =>
      open_action_overlay_from_event(model, node_id_str)
    CloseActionOverlay => {
      js_set_overlay_open(false)
      (none, { ..model, overlay: closed_overlay() })
    }
    ActionKeyPressed(key) => {
      if key == "" {
        return (none, model)
      }
      // Escape always closes
      if key == "Escape" {
        js_set_overlay_open(false)
        return (none, { ..model, overlay: closed_overlay() })
      }
      // If in submenu mode, match numeric keys to choices
      match model.overlay.submenu {
        Some(sub_action) => {
          let ctx_kind = match model.overlay.node_context {
            Some(ctx) => ctx.kind
            None => @ast.Term::Unit
          }
          let choices = get_submenu_choices(sub_action.id, ctx_kind)
          let idx = @string.parse_int(key) catch { _ => -1 }
          let idx = idx - 1 // "1" → 0, "2" → 1, etc.
          if idx >= 0 && idx < choices.length() {
            let (_, value) = choices[idx]
            execute_action(model, sub_action, value, "")
          } else {
            // Invalid key — close submenu
            (none, { ..model, overlay: { ..model.overlay, submenu: None } })
          }
        }
        None =>
          // If in name prompt mode, let the view handle input
          if model.overlay.pending_action is Some(_) {
            (none, model)
          } else {
            // Match mnemonic: find the action whose mnemonic matches the key
            let matched = model.overlay.actions
              .iter()
              .find_first(fn(a) { a.mnemonic == key })
            match matched {
              Some(action) => dispatch_or_prompt(model, action)
              None => (none, model)
            }
          }
      }
    }
    ActionTapped(action_id) => {
      // Submenu choices encode as "base_id:choice_value" for single-tap dispatch
      let (base_id, choice) = split_action_id(action_id)
      let matched = model.overlay.actions
        .iter()
        .find_first(fn(a) { a.id == base_id })
      match (matched, choice) {
        (Some(action), "") => dispatch_or_prompt(model, action)
        (Some(action), _) => execute_action(model, action, choice, "")
        (None, _) => (none, model)
      }
    }
    NamePromptInput(value) => {
      let overlay = { ..model.overlay, name_value: value, name_error: "" }
      (none, { ..model, overlay, })
    }
    NamePromptSubmit => {
      let name = model.overlay.name_value.trim().to_owned()
      if name == "" {
        let overlay = {
          ..model.overlay,
          name_error: "Enter a name to continue",
        }
        return (none, { ..model, overlay, })
      }
      let overlay = { ..model.overlay, name_value: name }
      let model = { ..model, overlay, }
      match model.overlay.pending_action {
        Some(action) => execute_action(model, action, "", name)
        None => (none, model)
      }
    }
    NamePromptCancel => {
      js_set_overlay_open(false)
      (none, { ..model, overlay: closed_overlay() })
    }
    // ── Outline drag-and-drop ──────
    OutlineDragStart(node_id) => (none, { ..model, drag_source: Some(node_id) })
    OutlineDragOver(target_id, position) =>
      (
        none,
        {
          ..model,
          drop_target_id: Some(target_id),
          drop_position: Some(position),
        },
      )
    OutlineDragLeave =>
      (none, { ..model, drop_target_id: None, drop_position: None })
    OutlineDragEnd =>
      (
        none,
        {
          ..model,
          drag_source: None,
          drop_target_id: None,
          drop_position: None,
        },
      )
    OutlineDrop(target_id, position) => {
      let source = model.drag_source
      let model = {
        ..model,
        drag_source: None,
        drop_target_id: None,
        drop_position: None,
      }
      match source {
        None => (none, model)
        Some(source_id) => {
          let tree_op = @lambda_edits.TreeEditOp::Drop(
            source=source_id,
            target=target_id,
            position~,
          )
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
      }
    }
    // ── Structure-mode Web Component communication ──────
    StructureNodeSelected(node_id) =>
      if node_id == "" {
        (none, model)
      } else {
        let highlight_set = match parse_node_id(node_id) {
          Some(nid) => compute_highlight_set(nid, model.scope_map)
          None => @immut/hashset.new()
        }
        (none, { ..model, selected_node: Some(node_id), highlight_set })
      }
    StructureStructuralEdit(op~, node_id~) =>
      if op == "" || node_id == "" {
        (none, model)
      } else {
        // The edit was already applied by TS calling handle_structural_intent FFI.
        // For ops the helper can rebuild (`WrapInLambda`, `Delete`), route
        // through `push_intent` so the Op Log row shape matches direct-apply
        // paths. Fall back to a raw label for ops whose payload can't be
        // reconstructed from `(op, node_id)` (e.g. `"Drop"`).
        let rebuilt = parse_node_id(node_id).bind(nid => {
          structural_edit_op_to_tree_edit(op, nid)
        })
        match rebuilt {
          Some(tree_op) => push_intent(model, tree_op)
          None => push_intent_label(model, "\{op}(node=\{node_id})")
        }
        let new_model = refresh({
          ..model,
          next_timestamp: model.next_timestamp + 1,
        })
        (sync_after_external_crdt_change(new_model), new_model)
      }
    ExternalCrdtChanged => {
      let new_model = refresh(model)
      (sync_after_external_crdt_change(new_model), new_model)
    }
    CmMounted => {
      let new_model = { ..model, mounted: true }
      (sync_after_external_crdt_change(new_model), new_model)
    }
    CmDocChanged(text) => {
      // Binding listen sends the full document; use the recording variant so undo keeps working.
      model.editor.set_text_and_record(text, js_now_ms())
      let new_model = refresh({
        ..model,
        next_timestamp: model.next_timestamp + 1,
      })
      let actual_text = new_model.editor.get_text()
      let sync_cmd = if actual_text != text {
        @cm.set_doc(model.cm_id, actual_text)
      } else {
        none
      }
      let cmd = @rabbita.batch([
        sync_cmd,
        @rabbita.effect(fn() { js_after_local_text_edit() }),
      ])
      (cmd, new_model)
    }
    CmSelectionChanged(range) => {
      js_after_cm_selection_changed(range.from, range.to)
      (none, model)
    }
    CmFocusChanged(_) => (none, model)
  }
}

///|
fn view_peer_status(model : Model) -> Html {
  let (dot_class, label) : (String, String) = match model.sync_status {
    Connected => ("peer-dot connected", "You (connected)")
    Connecting => ("peer-dot connecting", "Connecting\u{2026}")
    Offline => ("peer-dot offline", "Offline \u{2014} reconnecting\u{2026}")
    Error => ("peer-dot error", "Connection error")
  }
  div(class="peer-item", [
    div(class=dot_class, attrs=@html.Attrs::build().aria_hidden("true"), [
      text(""),
    ]),
    span(class="peer-label", [text(label)]),
  ])
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
  let outline_attrs = @html.Attrs::build()
    .role("navigation")
    .aria_label("AST outline")
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
        div(class="panel-header", [span(class="panel-label", [text("OUTLINE")])]),
        view_outline_content(dispatch, model),
        div(class="panel-section", [
          span(class="panel-label", [text("PEERS")]),
          view_peer_status(model),
        ]),
      ]),
      view_editor(dispatch, model),
      div(class=inspector_class, attrs=inspector_attrs, [
        view_inspector_content(dispatch, model),
      ]),
    ]),
    div(class=bottom_class, [view_bottom_content(dispatch, model)]),
    view_action_overlay(dispatch, model),
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
