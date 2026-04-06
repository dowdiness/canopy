///|
using @html {button, div, p, span, text}

///|
using @rabbita {type Cmd, type Dispatch, type Html, none}
// delay removed — outline refreshes immediately on EditorTextChanged

///|
fn init_model() -> Model {
  // Read agent ID set by JS (main.ts) before module import.
  // Falls back to "local" if JS hasn't set it (e.g. test environment).
  let agent_id = js_get_agent_id()
  let agent_id = if agent_id == "" { "local" } else { agent_id }
  // Create the editor through the crdt module so it sets the singleton (editor.val).
  // JS (main.ts) will reuse handle=1 instead of creating a second editor.
  let _handle = @ffi.create_editor_with_undo(agent_id, 500)
  let editor = @ffi.get_sync_editor().unwrap()
  let init_text = "let id = \\x. { x }\nlet apply = \\f. \\x. { f x }\napply id 42"
  editor.set_text(init_text)
  let outline_state : @proj.TreeEditorState[@ast.Term] = @proj.TreeEditorState::from_projection(
    editor.get_proj_node(),
    editor.get_source_map(),
  )
  {
    editor,
    outline_state,
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
    highlight_set: @immut/hashset.HashSet::new(),
  }
}

///|
fn refresh(model : Model) -> Model {
  let outline_state = model.outline_state.refresh(
    model.editor.get_proj_node(),
    model.editor.get_source_map(),
  )
  // Build scope_map from current projection
  let scope_map = build_scope_map(model.editor)
  // Recompute highlight_set if a node is selected
  let highlight_set = match model.selected_node {
    Some(nid_str) => {
      let n = @string.parse_int(nid_str) catch { _ => 0 }
      compute_highlight_set(@proj.NodeId::from_int(n), scope_map)
    }
    None => @immut/hashset.HashSet::new()
  }
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
fn view_toolbar(dispatch : Dispatch[Msg], model : Model) -> Html {
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
  node_id : @proj.NodeId,
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
fn can_hydrate_tree_node(model : Model, node_id : @proj.NodeId) -> Bool {
  tree_node_is_elided(model.outline_state, node_id)
}

///|
fn apply_structural_edit_request(
  model : Model,
  op : String,
  node_id : String,
) -> (Cmd, Model) {
  let node_id_int = @string.parse_int(node_id) catch {
    _ => return (none, model)
  }
  let nid = @proj.NodeId::from_int(node_id_int)
  let tree_op : @lambda_edits.TreeEditOp = match op {
    "WrapInLambda" => @lambda_edits.WrapInLambda(node_id=nid, var_name="x")
    "Delete" => @lambda_edits.Delete(node_id=nid)
    _ => return (none, model)
  }
  match model.editor.apply_tree_edit(tree_op, model.next_timestamp) {
    Ok(_) => {
      let new_model = refresh({
        ..model,
        next_timestamp: model.next_timestamp + 1,
      })
      let text = new_model.editor.get_text()
      let cmd = @rabbita.effect(fn() { js_reconcile_editor_with_text(text) })
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
        let a = 8
        let b = vw - panel_w - 8
        if a > b {
          a
        } else {
          b
        }
      } else {
        raw_left
      }
      let clamped_top = if raw_top + panel_h > vh {
        let a = 8
        let b = vh - panel_h - 8
        if a > b {
          a
        } else {
          b
        }
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
  let ctx = match detect_action_context(model.editor, node_id_str) {
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
      match model.editor.apply_tree_edit(op, model.next_timestamp) {
        Ok(_) => {
          js_set_overlay_open(false)
          let cmd = @rabbita.effect(fn() { js_reconcile_after_tree_edit() })
          let new_model = refresh({
            ..model,
            next_timestamp: model.next_timestamp + 1,
            overlay: closed_overlay(),
          })
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
fn update(_dispatch : Dispatch[Msg], msg : Msg, model : Model) -> (Cmd, Model) {
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
      (none, { ..model, workspace, })
    }
    DismissPanels => {
      let ws = model.workspace
      let workspace = { ..ws, outline_visible: false, inspector_visible: false }
      (none, { ..model, workspace, })
    }
    SelectBottomTab(tab) => {
      let new_model = { ..model, bottom_tab: tab }
      (graphviz_render_cmd(new_model), new_model)
    }
    StructuralEditRequested(op~, node_id~) => {
      let resolved_op = if op == "" { js_take_structural_edit_op() } else { op }
      let resolved_node_id = if node_id == "" {
        js_take_structural_edit_node_id()
      } else {
        node_id
      }
      if resolved_op == "" || resolved_node_id == "" {
        (none, model)
      } else {
        apply_structural_edit_request(model, resolved_op, resolved_node_id)
      }
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
            model.outline_state.apply_edit(op)
          }
          return (none, { ..model, outline_state, })
        }
        @lambda_edits.Collapse(..)
        | @lambda_edits.Select(..)
        | @lambda_edits.SelectRange(..) => {
          let outline_state = model.outline_state.apply_edit(op)
          return (none, { ..model, outline_state, })
        }
        _ => (none, model)
      }
    Undo => {
      let did_undo = model.editor.undo()
      if did_undo {
        let new_model = refresh(model)
        let text = new_model.editor.get_text()
        let cmd = @rabbita.batch([
          @rabbita.effect(fn() { js_sync_and_broadcast(text) }),
          graphviz_render_cmd(new_model),
        ])
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
        let cmd = @rabbita.batch([
          @rabbita.effect(fn() { js_sync_and_broadcast(text) }),
          graphviz_render_cmd(new_model),
        ])
        (cmd, new_model)
      } else {
        (none, model)
      }
    }
    LoadExample(example_text) => {
      model.editor.set_text(example_text)
      let new_model = refresh(model)
      let text = new_model.editor.get_text()
      let cmd = @rabbita.batch([
        @rabbita.effect(fn() { js_reconcile_editor_with_text(text) }),
        graphviz_render_cmd(new_model),
      ])
      (cmd, new_model)
    }
    OutlineNodeClicked(node_id) => {
      // Highlight in CM6, then re-focus tree-rows (overrides cmView.focus())
      let cmd = @rabbita.effect(fn() {
        js_set_editor_selected_node(node_id)
        js_focus_tree_rows()
      })
      let n = @string.parse_int(node_id) catch { _ => 0 }
      let nid = @proj.NodeId::from_int(n)
      let highlight_set = compute_highlight_set(nid, model.scope_map)
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
        Some(s) => {
          let nid_int = @string.parse_int(s) catch { _ => return (none, model) }
          let nid = @proj.NodeId::from_int(nid_int)
          model.outline_state.apply_edit(@lambda_edits.Select(node_id=nid))
        }
        None => model.outline_state
      }
      let cmd = match new_selected {
        Some(s) =>
          @rabbita.batch([
            // Use same path as click: set selection in CM6, then re-focus tree
            @rabbita.effect(fn() {
              js_set_editor_selected_node(s)
              js_focus_tree_rows()
            }),
            @rabbita_cmd.raw_effect(
              fn(_) { js_scroll_outline_to_selected() },
              kind=@rabbita_cmd.after_render,
            ),
          ])
        None => none
      }
      // Compute highlight_set for binder coloring
      let highlight_set = match new_selected {
        Some(s) => {
          let n = @string.parse_int(s) catch { _ => 0 }
          compute_highlight_set(@proj.NodeId::from_int(n), model.scope_map)
        }
        None => @immut/hashset.HashSet::new()
      }
      (
        cmd,
        { ..model, selected_node: new_selected, outline_state, highlight_set },
      )
    }
    OutlineStructuralEdit(tree_op) =>
      match model.editor.apply_tree_edit(tree_op, model.next_timestamp) {
        Ok(_) => {
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
                @lambda_edits.Select(node_id=nid),
              )
              (Some(node_id_to_string(nid)), os)
            }
            None => (None, new_model.outline_state)
          }
          let highlight_set = match new_selected {
            Some(s) => {
              let n = @string.parse_int(s) catch { _ => 0 }
              compute_highlight_set(
                @proj.NodeId::from_int(n),
                new_model.scope_map,
              )
            }
            None => @immut/hashset.HashSet::new()
          }
          let text = new_model.editor.get_text()
          let cmd = @rabbita.effect(fn() { js_reconcile_editor_with_text(text) })
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
        let focus_cmd = @rabbita_cmd.raw_effect(
          fn(_) { js_focus_outline_overlay() },
          kind=@rabbita_cmd.after_render,
        )
        (focus_cmd, new_model)
      } else {
        (none, new_model)
      }
    }
    SyncStatusChanged(status) => {
      let resolved = if status == "" { js_take_sync_status() } else { status }
      let sync_status : SyncStatus = match resolved {
        "connected" => Connected
        "connecting" => Connecting
        "disconnected" => Offline
        "error" => Error
        _ => model.sync_status
      }
      (none, { ..model, sync_status, })
    }
    OpenActionOverlay | LongPressTriggered => {
      let node_id_str = js_take_action_overlay_node()
      let new_model = open_action_overlay(model, node_id_str)
      if new_model.overlay.visible {
        // Focus the overlay panel after Rabbita renders it
        let focus_cmd = @rabbita_cmd.raw_effect(
          fn(_) { js_focus_overlay_panel() },
          kind=@rabbita_cmd.after_render,
        )
        (focus_cmd, new_model)
      } else {
        (none, new_model)
      }
    }
    CloseActionOverlay => {
      js_set_overlay_open(false)
      (none, { ..model, overlay: closed_overlay() })
    }
    ActionKeyPressed(key_arg) => {
      let key = if key_arg != "" { key_arg } else { js_take_action_key() }
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
          if !(model.overlay.pending_action is None) {
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
    ActionTapped(action_id) =>
      // Check for submenu choice format: "action_id:value"
      if action_id.contains(":") {
        // Split on first ':'
        let mut base_id = ""
        let mut choice = ""
        let mut found_colon = false
        action_id
        .iter()
        .each(fn(ch) {
          if !found_colon && ch == ':' {
            found_colon = true
          } else if found_colon {
            choice = choice + ch.to_string()
          } else {
            base_id = base_id + ch.to_string()
          }
        })
        let matched = model.overlay.actions
          .iter()
          .find_first(fn(a) { a.id == base_id })
        match matched {
          Some(action) => execute_action(model, action, choice, "")
          None => (none, model)
        }
      } else {
        let matched = model.overlay.actions
          .iter()
          .find_first(fn(a) { a.id == action_id })
        match matched {
          Some(action) => dispatch_or_prompt(model, action)
          None => (none, model)
        }
      }
    NamePromptInput(value) => {
      let overlay = { ..model.overlay, name_value: value, name_error: "" }
      (none, { ..model, overlay, })
    }
    NamePromptSubmit => {
      let name = model.overlay.name_value.trim().to_string()
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
    // ── Protocol-based editor communication (Phase 4) ──────
    EditorTextChanged => {
      // Text was already applied by TS calling handle_text_intent FFI.
      // Just refresh the outline.
      let new_model = refresh(model)
      (graphviz_render_cmd(new_model), new_model)
    }
    EditorNodeSelected(node_id) => {
      let resolved_node_id = if node_id == "" {
        js_take_selected_node_id()
      } else {
        node_id
      }
      if resolved_node_id == "" {
        (none, model)
      } else {
        let n = @string.parse_int(resolved_node_id) catch { _ => 0 }
        let highlight_set = compute_highlight_set(
          @proj.NodeId::from_int(n),
          model.scope_map,
        )
        (
          none,
          { ..model, selected_node: Some(resolved_node_id), highlight_set },
        )
      }
    }
    EditorStructuralEdit(op~, node_id~) => {
      let resolved_op = if op == "" { js_take_structural_edit_op() } else { op }
      let resolved_node_id = if node_id == "" {
        js_take_structural_edit_node_id()
      } else {
        node_id
      }
      if resolved_op == "" || resolved_node_id == "" {
        (none, model)
      } else {
        // The edit was already applied by TS calling handle_structural_intent FFI.
        let new_model = refresh({
          ..model,
          next_timestamp: model.next_timestamp + 1,
        })
        (graphviz_render_cmd(new_model), new_model)
      }
    }
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
fn view(dispatch : Dispatch[Msg], model : Model) -> Html {
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
fn main {
  let app = @rabbita.cell(model=init_model(), update~, view~)
  @rabbita.new(app).mount("app")
}
