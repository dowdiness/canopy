///|
/// Re-export root canopy CRDT FFI functions so they appear in
/// the ideal-editor JS module exports. This eliminates the need
/// to load the separate @moonbit/canopy module (saves 7.6MB).

///|
pub fn create_editor_with_undo(
  agent_id : String,
  timeout_ms : Int32,
) -> Int32 raise {
  @ffi.create_editor_with_undo(agent_id, timeout_ms)
}

///|
pub fn try_destroy_editor(handle : Int32) -> Bool {
  @ffi.try_destroy_editor(handle)
}

///|
pub fn destroy_editor(handle : Int32) -> Unit {
  @ffi.destroy_editor(handle)
}

///|
pub fn get_text(handle : Int32) -> String raise Failure {
  @ffi.get_text(handle)
}

///|
pub fn set_text(handle : Int32, text : String) -> Unit raise {
  @ffi.set_text(handle, text)
}

///|
pub fn set_text_and_record(
  handle : Int32,
  text : String,
  timestamp_ms : Int32,
) -> Unit raise {
  @ffi.set_text_and_record(handle, text, timestamp_ms)
}

///|
pub fn get_proj_node_json(handle : Int32) -> String {
  @ffi.get_proj_node_json(handle)
}

///|
pub fn get_source_map_json(handle : Int32) -> String {
  @ffi.get_source_map_json(handle)
}

///|
pub fn get_errors_json(handle : Int32) -> String raise Failure {
  @ffi.get_errors_json(handle)
}

///|
pub fn get_version_json(handle : Int32) -> String raise {
  @ffi.get_version_json(handle)
}

///|
pub fn insert_at(
  handle : Int32,
  pos : Int32,
  ch : String,
  ts : Int32,
) -> Unit raise {
  @ffi.insert_at(handle, pos, ch, ts)
}

///|
pub fn delete_at(handle : Int32, pos : Int32, ts : Int32) -> Bool raise {
  @ffi.delete_at(handle, pos, ts)
}

///|
pub fn export_all_json(handle : Int32) -> String raise {
  @ffi.export_all_json(handle)
}

///|
pub fn export_since_json(handle : Int32, peer_version : String) -> String raise {
  @ffi.export_since_json(handle, peer_version)
}

///|
pub fn apply_sync_json(handle : Int32, sync_json : String) -> String {
  @ffi.apply_sync_json(handle, sync_json)
}

///|
pub fn undo_manager_undo(handle : Int32) -> Bool raise Failure {
  @ffi.undo_manager_undo(handle)
}

///|
pub fn undo_manager_redo(handle : Int32) -> Bool raise Failure {
  @ffi.undo_manager_redo(handle)
}

///|
pub fn undo_manager_can_undo(handle : Int32) -> Bool {
  @ffi.undo_manager_can_undo(handle)
}

///|
pub fn undo_manager_can_redo(handle : Int32) -> Bool {
  @ffi.undo_manager_can_redo(handle)
}

///|
pub fn ephemeral_encode_all(handle : Int32) -> Bytes {
  @ffi.ephemeral_encode_all(handle)
}

///|
pub fn ephemeral_apply(handle : Int32, data : Bytes) -> Unit {
  @ffi.ephemeral_apply(handle, data)
}

///|
pub fn ephemeral_set_presence(
  handle : Int32,
  name : String,
  color : String,
) -> Unit {
  @ffi.ephemeral_set_presence(handle, name, color)
}

///|
pub fn ephemeral_set_presence_with_selection(
  handle : Int32,
  name : String,
  color : String,
  sel_start : Int32,
  sel_end : Int32,
) -> Unit {
  @ffi.ephemeral_set_presence_with_selection(
    handle, name, color, sel_start, sel_end,
  )
}

///|
pub fn ephemeral_delete_presence(handle : Int32) -> Unit {
  @ffi.ephemeral_delete_presence(handle)
}

///|
pub fn ephemeral_get_peer_cursors_json(handle : Int32) -> String {
  @ffi.ephemeral_get_peer_cursors_json(handle)
}

///|
pub fn ephemeral_remove_outdated(handle : Int32) -> Unit {
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
  handle : Int32,
  from : Int32,
  deleted_len : Int32,
  insert : String,
  timestamp_ms : Int32,
) -> Unit raise {
  js_perf_begin("handleTextIntent")
  js_perf_begin("crdtMutation")
  errdefer {
    js_perf_end("crdtMutation")
    js_perf_end("handleTextIntent")
  }
  @ffi.handle_text_intent(handle, from, deleted_len, insert, timestamp_ms)
  js_perf_end("crdtMutation")
  js_perf_end("handleTextIntent")
}

///|
/// Bounds-checked variant of `handle_text_intent`. Returns false when the
/// requested splice would have been silently clamped by the editor seam,
/// leaving the CRDT untouched so the caller can resync without
/// broadcasting a clamped delta to peers. Retained as a forwarding
/// compatibility surface; Ideal's mounted Structure runtime does not use it.
pub fn handle_text_intent_checked(
  handle : Int32,
  from : Int32,
  deleted_len : Int32,
  insert : String,
  timestamp_ms : Int32,
) -> Bool raise {
  js_perf_begin("handleTextIntentChecked")
  js_perf_begin("crdtMutation")
  let accepted = {
    errdefer {
      js_perf_end("crdtMutation")
      js_perf_end("handleTextIntentChecked")
    }
    let result = @ffi.handle_text_intent_checked(
      handle, from, deleted_len, insert, timestamp_ms,
    )
    js_perf_end("crdtMutation")
    js_perf_end("handleTextIntentChecked")
    result
  }
  accepted
}

// ── File I/O ──────────────────────────────────────────────
// Re-export the file load/save FFI so the host can inject its FileHost and
// trigger picker/save through the ideal-editor module (see web/src/main.ts).

///|
/// Inject the JS host: `{ save(content, name), open(handle) }`.
pub fn register_file_host(host : @js.Any) -> Unit {
  @ffi.register_file_host(host)
}

///|
/// Trigger the host's file picker for `handle`. The host reads the file and
/// dispatches a "file-loaded" CustomEvent carrying the text.
pub fn load_file(handle : Int32) -> Unit {
  @ffi.load_file(handle)
}

///|
/// Ask the host to save `handle`'s current text to `suggested_name`.
pub fn save_file(handle : Int32, suggested_name : String) -> Unit raise Failure {
  @ffi.save_file(handle, suggested_name)
}
