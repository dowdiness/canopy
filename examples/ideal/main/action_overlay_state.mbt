///|
/// True when the overlay is showing any of its open modes.
fn OverlayState::is_open(self : OverlayState) -> Bool {
  match self.mode {
    Closed => false
    MainMenu | Submenu(_) | NamePrompt(_) => true
  }
}

///|
fn open_action_overlay_from_event(
  model : Model,
  node_id_str : String,
) -> (Cmd, Model) {
  let new_model = open_action_overlay(model, node_id_str)
  if new_model.overlay.is_open() {
    (new_model.overlay.menu.focus_cmd(), new_model)
  } else {
    (none, new_model)
  }
}

///|
fn closed_overlay() -> OverlayState {
  {
    mode: Closed,
    actions: [],
    node_context: None,
    name_value: "",
    name_error: "",
    anchor_top: 0,
    anchor_left: 0,
    menu: @menu.Model::new(id="ideal-action-overlay-menu", item_count=0),
  }
}

///|
/// Current viewport size in pixels, falling back to conservative defaults
/// (1024x768) if the browser value can't be read.
fn viewport_size() -> (Int, Int) {
  let json = @json.parse(js_get_viewport_size()) catch {
    _ => return (1024, 768)
  }
  match json {
    Json::Object(m) => {
      let vw = match m.get("width") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 1024
      }
      let vh = match m.get("height") {
        Some(Json::Number(n, ..)) => n.to_int()
        _ => 768
      }
      (vw, vh)
    }
    _ => (1024, 768)
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
  // Viewport size (conservative defaults if it can't be read), so the clamp
  // below always runs and never leaves the overlay off-screen.
  let (vw, vh) = viewport_size()
  // Clamp to [8, viewport - panel - 8] on both ends so a node scrolled
  // above/left of the viewport (negative rect) doesn't push the overlay
  // off-screen, while still preventing right/bottom overflow. Estimated panel
  // size: 320px wide, 300px tall (conservative).
  let panel_w = 320
  let panel_h = 300
  let max_left = (vw - panel_w - 8).max(8)
  let max_top = (vh - panel_h - 8).max(8)
  let clamped_left = raw_left.max(8).min(max_left)
  let clamped_top = raw_top.max(8).min(max_top)
  (clamped_top, clamped_left)
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
      mode: MainMenu,
      actions,
      node_context: Some(ctx),
      name_value: "",
      name_error: "",
      anchor_top,
      anchor_left,
      menu: model.overlay.menu.reset(item_count=actions.length()),
    },
  }
}

///|
fn close_action_overlay(model : Model) -> (Cmd, Model) {
  js_set_overlay_open(false)
  (none, { ..model, overlay: closed_overlay() })
}
