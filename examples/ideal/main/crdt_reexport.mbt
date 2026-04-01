///|
/// Re-export root canopy CRDT FFI functions so they appear in
/// the ideal-editor JS module exports. This eliminates the need
/// to load the separate @moonbit/canopy module (saves 7.6MB).

///|
pub fn create_editor_with_undo(agent_id : String, timeout_ms : Int) -> Int {
  @ffi.create_editor_with_undo(agent_id, timeout_ms)
}

///|
pub fn get_text(handle : Int) -> String {
  @ffi.get_text(handle)
}

///|
pub fn set_text(handle : Int, text : String) -> Unit {
  @ffi.set_text(handle, text)
}

///|
pub fn set_text_and_record(
  handle : Int,
  text : String,
  timestamp_ms : Int,
) -> Unit {
  @ffi.set_text_and_record(handle, text, timestamp_ms)
}

///|
pub fn get_proj_node_json(handle : Int) -> String {
  @ffi.get_proj_node_json(handle)
}

///|
pub fn get_source_map_json(handle : Int) -> String {
  @ffi.get_source_map_json(handle)
}

///|
pub fn get_errors_json(handle : Int) -> String {
  @ffi.get_errors_json(handle)
}

///|
pub fn get_version_json(handle : Int) -> String {
  @ffi.get_version_json(handle)
}

///|
pub fn insert_at(handle : Int, pos : Int, ch : String, ts : Int) -> Unit {
  @ffi.insert_at(handle, pos, ch, ts)
}

///|
pub fn delete_at(handle : Int, pos : Int, ts : Int) -> Bool {
  @ffi.delete_at(handle, pos, ts)
}

///|
pub fn export_all_json(handle : Int) -> String {
  @ffi.export_all_json(handle)
}

///|
pub fn export_since_json(handle : Int, peer_version : String) -> String {
  @ffi.export_since_json(handle, peer_version)
}

///|
pub fn apply_sync_json(handle : Int, sync_json : String) -> String {
  @ffi.apply_sync_json(handle, sync_json)
}

///|
pub fn apply_tree_edit_json(handle : Int, op_json : String, ts : Int) -> String {
  @ffi.apply_tree_edit_json(handle, op_json, ts)
}

///|
pub fn undo_manager_undo(handle : Int) -> Bool {
  @ffi.undo_manager_undo(handle)
}

///|
pub fn undo_manager_redo(handle : Int) -> Bool {
  @ffi.undo_manager_redo(handle)
}

///|
pub fn undo_manager_can_undo(handle : Int) -> Bool {
  @ffi.undo_manager_can_undo(handle)
}

///|
pub fn undo_manager_can_redo(handle : Int) -> Bool {
  @ffi.undo_manager_can_redo(handle)
}

///|
pub fn ephemeral_encode_all(handle : Int) -> Bytes {
  @ffi.ephemeral_encode_all(handle)
}

///|
pub fn ephemeral_apply(handle : Int, data : Bytes) -> Unit {
  @ffi.ephemeral_apply(handle, data)
}

///|
pub fn ephemeral_set_presence(
  handle : Int,
  name : String,
  color : String,
) -> Unit {
  @ffi.ephemeral_set_presence(handle, name, color)
}

///|
pub fn ephemeral_set_presence_with_selection(
  handle : Int,
  name : String,
  color : String,
  sel_start : Int,
  sel_end : Int,
) -> Unit {
  @ffi.ephemeral_set_presence_with_selection(
    handle, name, color, sel_start, sel_end,
  )
}

///|
pub fn ephemeral_delete_presence(handle : Int) -> Unit {
  @ffi.ephemeral_delete_presence(handle)
}

///|
pub fn ephemeral_get_peer_cursors_json(handle : Int) -> String {
  @ffi.ephemeral_get_peer_cursors_json(handle)
}

///|
pub fn ephemeral_remove_outdated(handle : Int) -> Unit {
  @ffi.ephemeral_remove_outdated(handle)
}

// ── Protocol-based intent handlers ────────────────────────
// These replace the global-state bridge for Phase 4.
// TS calls these directly instead of setting globals + clicking hidden buttons.

///|
/// Apply a text edit intent. Called from CM6 updateListener.
/// Applies the edit to the CRDT with undo recording.
/// Returns the current text after the edit (for sync verification).
pub fn handle_text_intent(
  handle : Int,
  from : Int,
  deleted_len : Int,
  insert : String,
  timestamp_ms : Int,
) -> Unit {
  @ffi.handle_text_intent(handle, from, deleted_len, insert, timestamp_ms)
}

///|
/// Undo on the MoonBit editor directly and return whether it succeeded.
pub fn handle_undo(handle : Int) -> Bool {
  @ffi.handle_undo(handle)
}

///|
/// Redo on the MoonBit editor directly and return whether it succeeded.
pub fn handle_redo(handle : Int) -> Bool {
  @ffi.handle_redo(handle)
}

///|
/// Apply a structural edit intent. Returns "ok" on success, error message on failure.
pub fn handle_structural_intent(
  handle : Int,
  op : String,
  node_id : String,
  timestamp_ms : Int,
  params_json : String,
) -> String {
  @ffi.handle_structural_intent(handle, op, node_id, timestamp_ms, params_json)
}
