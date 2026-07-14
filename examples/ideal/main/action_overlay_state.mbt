///|
fn open_action_overlay_from_event(
  _parent_emit : @rabbita.Emit[Msg],
  model : Model,
  node_id_str : String,
) -> (Cmd, Model) {
  open_action_overlay(model, node_id_str)
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
) -> (Cmd, Model) {
  if node_id_str == "" {
    return (none, model)
  }
  let nid = match parse_node_id(node_id_str) {
    Some(id) => id
    None => return (none, model)
  }
  let ctx = match @lambda.detect_action_context(model.editor, nid) {
    Some(c) => c
    None => return (none, model)
  }
  let proj_ctx = @lambda_edits.to_node_context(ctx)
  let actions = @lambda_edits.get_actions_for_node(ctx.kind, proj_ctx)
  if actions.is_empty() {
    return (none, model)
  }
  let (anchor_top, anchor_left) = parse_anchor_rect(rect_json)
  let initial_state = OverlayState::OverlayState(
    mode=MainMenu,
    actions~,
    kind=ctx.kind,
    error=None,
    anchor_top~,
    anchor_left~,
    menu=@menu.Model::new(
      id="ideal-action-overlay-menu",
      item_count=actions.length(),
    ),
  )
  js_set_overlay_open(true)
  (
    initial_state.menu_model().focus_cmd(),
    { ..model, overlay: model.overlay.mount(ctx, initial_state) },
  )
}

///|
/// Clear the active parent-owned overlay host. Parent-stamped queued
/// messages and effects from the prior token are rejected by token checks.
fn close_action_overlay(model : Model) -> (Cmd, Model) {
  js_set_overlay_open(false)
  (none, { ..model, overlay: model.overlay.close() })
}
