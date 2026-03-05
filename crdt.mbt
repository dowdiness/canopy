// JavaScript bindings for CRDT Editor
// Exposes ParsedEditor API to JavaScript via FFI

// Global editor state (single editor for MVP)

///|
let editor : Ref[@editor.ParsedEditor?] = { val: None }

///|
/// Global UndoManager (paired with editor when undo is enabled)
let undo_mgr : Ref[@undo.UndoManager?] = { val: None }

///|
/// Create a new ParsedEditor instance
/// Returns handle 1 (MVP: single editor only)
pub fn create_editor(agent_id : String) -> Int {
  editor.val = Some(@editor.ParsedEditor::new(agent_id))
  1
}

///|
/// Insert text at cursor position
pub fn insert(_handle : Int, text : String) -> Unit {
  match editor.val {
    Some(editor) => try! editor.insert(text)
    None => ()
  }
}

///|
/// Delete character at cursor (forward delete)
pub fn delete_(_handle : Int) -> Bool {
  match editor.val {
    Some(editor) => editor.delete()
    None => false
  }
}

///|
/// Delete character before cursor (backspace)
pub fn backspace(_handle : Int) -> Bool {
  match editor.val {
    Some(editor) => editor.backspace()
    None => false
  }
}

///|
/// Get current text content
pub fn get_text(_handle : Int) -> String {
  match editor.val {
    Some(editor) => editor.get_text()
    None => ""
  }
}

///|
/// Set text content directly (replaces entire document)
/// This is more efficient than delete+insert for syncing from DOM
pub fn set_text(_handle : Int, new_text : String) -> Unit {
  match editor.val {
    Some(ed) => {
      let old_text = ed.get_text()
      if old_text == new_text {
        return // Already synced
      }

      // Clear the document
      let old_len = old_text.length()
      ed.move_cursor(0) // Move to start
      for _i = 0; _i < old_len; _i = _i + 1 {
        let _ = ed.delete()
        // Delete at position 0
      }

      // Insert new text
      if new_text.length() > 0 {
        try! ed.insert(new_text)
      }
    }
    None => ()
  }
}

///|
/// Get cursor position
pub fn get_cursor(_handle : Int) -> Int {
  match editor.val {
    Some(editor) => editor.get_cursor()
    None => 0
  }
}

///|
/// Set cursor position
pub fn set_cursor(_handle : Int, position : Int) -> Unit {
  match editor.val {
    Some(editor) => editor.move_cursor(position)
    None => ()
  }
}

///|
/// Get AST as JSON string
/// Uses incremental parser for efficient reparsing
pub fn get_ast_json(_handle : Int) -> String {
  match editor.val {
    Some(ed) =>
      // Use the incremental parser from ParsedEditor
      // This triggers lazy evaluation and incremental reparse if needed
      ed.get_ast().to_json().stringify()
    None => "{}"
  }
}

///|
/// Get AST as DOT format for graphviz visualization
/// Returns a DOT language string that can be rendered by graphviz
pub fn get_ast_dot(_handle : Int) -> String {
  match editor.val {
    Some(ed) => {
      let ast = ed.get_ast()
      @parser.term_to_dot(ast)
    }
    None => "digraph { }"
  }
}

///|
/// Get parse errors as JSON array
/// Uses cached errors from ParsedEditor (O(1) after parse)
pub fn get_errors_json(_handle : Int) -> String {
  match editor.val {
    Some(ed) =>
      // Get cached errors (triggers reparse if dirty, then returns cached errors)
      ed.get_errors().to_json().stringify()
    None => "[]"
  }
}

///|
/// Export all operations as a SyncMessage JSON string.
/// Use this for initial peer sync (send full history).
pub fn export_all_json(_handle : Int) -> String {
  match editor.val {
    Some(ed) =>
      ed.export_all().to_json_string() catch {
        _ => "{\"ops\":[],\"heads\":[]}"
      }
    None => "{\"ops\":[],\"heads\":[]}"
  }
}

///|
/// Export operations since a peer's version as a SyncMessage JSON string.
/// The peer_version_json is the JSON produced by `get_version_json`.
pub fn export_since_json(_handle : Int, peer_version_json : String) -> String {
  match editor.val {
    Some(ed) =>
      try {
        let ver = @text.Version::from_json_string(peer_version_json)
        ed.export_since(ver).to_json_string()
      } catch {
        _ => "{\"ops\":[],\"heads\":[]}"
      }
    None => "{\"ops\":[],\"heads\":[]}"
  }
}

///|
/// Apply a SyncMessage received from a peer.
/// The sync_json is produced by `export_all_json` or `export_since_json`.
pub fn apply_sync_json(_handle : Int, sync_json : String) -> Unit {
  match editor.val {
    Some(ed) =>
      try {
        let msg = @text.SyncMessage::from_json_string(sync_json)
        ed.apply_sync(msg)
      } catch {
        _ => ()
      }
    None => ()
  }
}

///|
/// Get the current version as a JSON string for use with `export_since_json`.
pub fn get_version_json(_handle : Int) -> String {
  match editor.val {
    Some(ed) => ed.get_version().to_json_string()
    None => "\"\""
  }
}

// ============================================================
// UndoManager-integrated API
// ============================================================

///|
/// Create a new ParsedEditor with an UndoManager
/// Returns handle 1 (MVP: single editor only)
pub fn create_editor_with_undo(
  agent_id : String,
  capture_timeout_ms : Int,
) -> Int {
  editor.val = Some(@editor.ParsedEditor::new(agent_id))
  undo_mgr.val = Some(@undo.UndoManager::new(agent_id, capture_timeout_ms~))
  1
}

///|
/// Insert text at cursor position and record for undo
pub fn insert_and_record(
  _handle : Int,
  text : String,
  timestamp_ms : Int,
) -> Unit {
  match (editor.val, undo_mgr.val) {
    (Some(ed), Some(mgr)) => {
      let pos = ed.editor.get_cursor()
      try! ed.editor.doc.insert_and_record(
        @text.Pos::at(pos),
        text,
        mgr,
        timestamp_ms~,
      )
      ed.editor.move_cursor(pos + text.length())
      ed.mark_dirty()
    }
    _ => ()
  }
}

///|
/// Delete character at cursor (forward delete) and record for undo
pub fn delete_and_record(_handle : Int, timestamp_ms : Int) -> Bool {
  match (editor.val, undo_mgr.val) {
    (Some(ed), Some(mgr)) => {
      let pos = ed.editor.get_cursor()
      try {
        ed.editor.doc.delete_and_record(@text.Pos::at(pos), mgr, timestamp_ms~)
        ed.mark_dirty()
        true
      } catch {
        _ => false
      }
    }
    _ => false
  }
}

///|
/// Delete character before cursor (backspace) and record for undo
pub fn backspace_and_record(_handle : Int, timestamp_ms : Int) -> Bool {
  match (editor.val, undo_mgr.val) {
    (Some(ed), Some(mgr)) => {
      let pos = ed.editor.get_cursor()
      if pos > 0 {
        let new_pos = pos - 1
        try {
          ed.editor.doc.delete_and_record(
            @text.Pos::at(new_pos),
            mgr,
            timestamp_ms~,
          )
          ed.editor.move_cursor(new_pos)
          ed.mark_dirty()
          true
        } catch {
          _ => false
        }
      } else {
        false
      }
    }
    _ => false
  }
}

///|
/// Set text content directly and record changes for undo
/// Computes diff between old and new text, applies as individual ops
pub fn set_text_and_record(
  _handle : Int,
  new_text : String,
  timestamp_ms : Int,
) -> Unit {
  match (editor.val, undo_mgr.val) {
    (Some(ed), Some(mgr)) => {
      let old_text = ed.editor.get_text()
      if old_text == new_text {
        return
      }
      // Simple diff: find common prefix/suffix
      let old_len = old_text.length()
      let new_len = new_text.length()
      let mut prefix = 0
      while prefix < old_len &&
            prefix < new_len &&
            old_text[prefix] == new_text[prefix] {
        prefix = prefix + 1
      }
      let mut suffix = 0
      while suffix < old_len - prefix &&
            suffix < new_len - prefix &&
            old_text[old_len - 1 - suffix] == new_text[new_len - 1 - suffix] {
        suffix = suffix + 1
      }
      let del_count = old_len - prefix - suffix
      let ins_len = new_len - prefix - suffix
      // Delete changed region (delete from prefix position, del_count times)
      for _i = 0; _i < del_count; _i = _i + 1 {
        ed.editor.doc.delete_and_record(
          @text.Pos::at(prefix),
          mgr,
          timestamp_ms~,
        ) catch {
          _ => ()
        }
      }
      // Insert new text at prefix position
      if ins_len > 0 {
        let inserted = new_text[prefix:prefix + ins_len].to_string() catch {
          _ => ""
        }
        if inserted.length() > 0 {
          ed.editor.doc.insert_and_record(
            @text.Pos::at(prefix),
            inserted,
            mgr,
            timestamp_ms~,
          ) catch {
            _ => ()
          }
        }
      }
      ed.mark_dirty()
    }
    _ => ()
  }
}

///|
/// Undo the last operation group.
/// Returns true if undo was performed, false if nothing to undo.
/// Use export_all_json after undo to sync the result to peers.
pub fn undo_manager_undo(_handle : Int) -> Bool {
  match (editor.val, undo_mgr.val) {
    (Some(ed), Some(mgr)) =>
      try {
        mgr.undo(ed.editor.doc)
        ed.mark_dirty()
        true
      } catch {
        _ => false
      }
    _ => false
  }
}

///|
/// Redo the last undone operation group.
/// Returns true if redo was performed, false if nothing to redo.
/// Use export_all_json after redo to sync the result to peers.
pub fn undo_manager_redo(_handle : Int) -> Bool {
  match (editor.val, undo_mgr.val) {
    (Some(ed), Some(mgr)) =>
      try {
        mgr.redo(ed.editor.doc)
        ed.mark_dirty()
        true
      } catch {
        _ => false
      }
    _ => false
  }
}

///|
/// Check if undo is possible
pub fn undo_manager_can_undo(_handle : Int) -> Bool {
  match undo_mgr.val {
    Some(mgr) => mgr.can_undo()
    None => false
  }
}

///|
/// Check if redo is possible
pub fn undo_manager_can_redo(_handle : Int) -> Bool {
  match undo_mgr.val {
    Some(mgr) => mgr.can_redo()
    None => false
  }
}

///|
/// Enable or disable undo tracking (use false during remote op application)
pub fn undo_manager_set_tracking(_handle : Int, enabled : Bool) -> Unit {
  match undo_mgr.val {
    Some(mgr) => mgr.set_tracking(enabled)
    None => ()
  }
}

///|
/// Clear both undo and redo stacks
pub fn undo_manager_clear(_handle : Int) -> Unit {
  match undo_mgr.val {
    Some(mgr) => mgr.clear()
    None => ()
  }
}
