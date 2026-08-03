///|
fn handle_overlay(emit : Emit[Msg], msg : Msg, model : Model) -> (Cmd, Model)? {
  match msg {
    OpenActionOverlayFromOutline => {
      let node_id_str = match model.selected_node {
        Some(s) => s
        None => return Some((none, model))
      }
      let rect_json = js_get_outline_selected_rect()
      Some(open_action_overlay(model, node_id_str, rect_json~))
    }
    OpenActionOverlayForNode(node_id_str)
    | LongPressTriggeredForNode(node_id_str) =>
      Some(open_action_overlay_from_event(emit, model, node_id_str))
    ActionOverlay(overlay_event) =>
      Some(handle_overlay_event(emit, model, overlay_event))
    ActionOverlayMsg(token~, overlay_msg) =>
      Some(handle_overlay_msg(emit, token, overlay_msg, model))
    ActionOverlayEffect(token~, output) =>
      Some(handle_overlay_output(model, token, output))
    _ => None
  }
}
