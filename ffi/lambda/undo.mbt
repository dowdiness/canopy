// Lambda editor undo support — editor creation with undo, text mutation with undo recording,
// undo manager lifecycle.

///|
/// Create a new SyncEditor with undo support.
/// Returns a unique handle for this editor.
pub fn create_editor_with_undo(
  agent_id : String,
  capture_timeout_ms : Int,
) -> Int {
  let handle = next_handle.val
  next_handle.val = handle + 1
  let (editor, companion) = @lang_lambda.new_lambda_editor(
    agent_id,
    capture_timeout_ms~,
  )
  lambda_handles[handle] = {
    editor,
    companion,
    typecheck: new_typecheck_bundle(
      editor.parser_runtime(),
      editor.parser_syntax_tree(),
    ),
  }
  last_created_handle.val = Some(handle)
  handle
}

///|
/// Insert text at cursor position and record for undo
pub fn insert_and_record(
  handle : Int,
  text : String,
  timestamp_ms : Int,
) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => try! h.editor.insert_and_record(text, timestamp_ms)
    None => ()
  }
}

///|
/// Delete character at cursor (forward delete) and record for undo
pub fn delete_and_record(handle : Int, timestamp_ms : Int) -> Bool {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.delete_and_record(timestamp_ms)
    None => false
  }
}

///|
/// Delete character before cursor (backspace) and record for undo
pub fn backspace_and_record(handle : Int, timestamp_ms : Int) -> Bool {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.backspace_and_record(timestamp_ms)
    None => false
  }
}

///|
/// Set text content directly and record changes for undo
pub fn set_text_and_record(
  handle : Int,
  new_text : String,
  timestamp_ms : Int,
) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.set_text_and_record(new_text, timestamp_ms)
    None => ()
  }
}

///|
/// Undo the last operation group.
pub fn undo_manager_undo(handle : Int) -> Bool {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.undo()
    None => false
  }
}

///|
/// Redo the last undone operation group.
pub fn undo_manager_redo(handle : Int) -> Bool {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.redo()
    None => false
  }
}

///|
/// Undo and return sync ops as JSON for peer broadcast.
/// Returns empty string if undo stack is empty.
pub fn undo_and_export_json(handle : Int) -> String {
  match lambda_handles.get(handle) {
    Some(h) =>
      match h.editor.undo_and_export() {
        Some(msg) => msg.to_json_string()
        None => ""
      }
    None => ""
  }
}

///|
/// Redo and return sync ops as JSON for peer broadcast.
/// Returns empty string if redo stack is empty.
pub fn redo_and_export_json(handle : Int) -> String {
  match lambda_handles.get(handle) {
    Some(h) =>
      match h.editor.redo_and_export() {
        Some(msg) => msg.to_json_string()
        None => ""
      }
    None => ""
  }
}

///|
/// Check if undo is possible
pub fn undo_manager_can_undo(handle : Int) -> Bool {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.can_undo()
    None => false
  }
}

///|
/// Check if redo is possible
pub fn undo_manager_can_redo(handle : Int) -> Bool {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.can_redo()
    None => false
  }
}

///|
/// Enable or disable undo tracking
pub fn undo_manager_set_tracking(handle : Int, enabled : Bool) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.set_tracking(enabled)
    None => ()
  }
}

///|
/// Clear both undo and redo stacks
pub fn undo_manager_clear(handle : Int) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.clear_undo()
    None => ()
  }
}
