// JavaScript bindings for CRDT Editor
// Exposes SyncEditor API to JavaScript via FFI

// Global editor state (single editor for MVP)

///|
let editor : Ref[@editor.SyncEditor?] = { val: None }

///|
/// Create a new SyncEditor instance
/// Returns handle 1 (MVP: single editor only)
pub fn create_editor(agent_id : String) -> Int {
  editor.val = Some(@editor.SyncEditor::new(agent_id))
  1
}

///|
/// Insert text at cursor position
pub fn insert(_handle : Int, text : String) -> Unit {
  match editor.val {
    Some(ed) => try! ed.insert(text)
    None => ()
  }
}

///|
/// Delete character at cursor (forward delete)
pub fn delete_(_handle : Int) -> Bool {
  match editor.val {
    Some(ed) => ed.delete()
    None => false
  }
}

///|
/// Delete character before cursor (backspace)
pub fn backspace(_handle : Int) -> Bool {
  match editor.val {
    Some(ed) => ed.backspace()
    None => false
  }
}

///|
/// Get current text content
pub fn get_text(_handle : Int) -> String {
  match editor.val {
    Some(ed) => ed.get_text()
    None => ""
  }
}

///|
/// Set text content directly (replaces entire document)
pub fn set_text(_handle : Int, new_text : String) -> Unit {
  match editor.val {
    Some(ed) => {
      let old_text = ed.get_text()
      if old_text == new_text {
        return
      }
      let old_len = old_text.length()
      ed.move_cursor(0)
      for _i = 0; _i < old_len; _i = _i + 1 {
        let _ = ed.delete()
      }
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
    Some(ed) => ed.get_cursor()
    None => 0
  }
}

///|
/// Set cursor position
pub fn set_cursor(_handle : Int, position : Int) -> Unit {
  match editor.val {
    Some(ed) => ed.move_cursor(position)
    None => ()
  }
}

///|
/// Get AST as JSON string
pub fn get_ast_json(_handle : Int) -> String {
  match editor.val {
    Some(ed) => ed.get_ast().to_json().stringify()
    None => "{}"
  }
}

///|
/// Get AST as DOT format for graphviz visualization
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
pub fn get_errors_json(_handle : Int) -> String {
  match editor.val {
    Some(ed) => ed.get_errors().to_json().stringify()
    None => "[]"
  }
}

///|
/// Export all operations as a SyncMessage JSON string.
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
/// Get the current version as a JSON string.
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
/// Create a new SyncEditor with undo support
/// Returns handle 1 (MVP: single editor only)
pub fn create_editor_with_undo(
  agent_id : String,
  capture_timeout_ms : Int,
) -> Int {
  editor.val = Some(@editor.SyncEditor::new(agent_id, capture_timeout_ms~))
  1
}

///|
/// Insert text at cursor position and record for undo
pub fn insert_and_record(
  _handle : Int,
  text : String,
  timestamp_ms : Int,
) -> Unit {
  match editor.val {
    Some(ed) => try! ed.insert_and_record(text, timestamp_ms)
    None => ()
  }
}

///|
/// Delete character at cursor (forward delete) and record for undo
pub fn delete_and_record(_handle : Int, timestamp_ms : Int) -> Bool {
  match editor.val {
    Some(ed) => ed.delete_and_record(timestamp_ms)
    None => false
  }
}

///|
/// Delete character before cursor (backspace) and record for undo
pub fn backspace_and_record(_handle : Int, timestamp_ms : Int) -> Bool {
  match editor.val {
    Some(ed) => ed.backspace_and_record(timestamp_ms)
    None => false
  }
}

///|
/// Set text content directly and record changes for undo
pub fn set_text_and_record(
  _handle : Int,
  new_text : String,
  timestamp_ms : Int,
) -> Unit {
  match editor.val {
    Some(ed) => {
      let old_text = ed.get_text()
      if old_text == new_text {
        return
      }
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
      for _i = 0; _i < del_count; _i = _i + 1 {
        ed.doc.delete_and_record(
          @text.Pos::at(prefix),
          ed.undo,
          timestamp_ms~,
        ) catch {
          _ => ()
        }
      }
      if ins_len > 0 {
        let inserted = new_text[prefix:prefix + ins_len].to_string() catch {
          _ => ""
        }
        if inserted.length() > 0 {
          ed.doc.insert_and_record(
            @text.Pos::at(prefix),
            inserted,
            ed.undo,
            timestamp_ms~,
          ) catch {
            _ => ()
          }
        }
      }
      ed.mark_dirty()
    }
    None => ()
  }
}

///|
/// Undo the last operation group.
pub fn undo_manager_undo(_handle : Int) -> Bool {
  match editor.val {
    Some(ed) => ed.undo()
    None => false
  }
}

///|
/// Redo the last undone operation group.
pub fn undo_manager_redo(_handle : Int) -> Bool {
  match editor.val {
    Some(ed) => ed.redo()
    None => false
  }
}

///|
/// Check if undo is possible
pub fn undo_manager_can_undo(_handle : Int) -> Bool {
  match editor.val {
    Some(ed) => ed.can_undo()
    None => false
  }
}

///|
/// Check if redo is possible
pub fn undo_manager_can_redo(_handle : Int) -> Bool {
  match editor.val {
    Some(ed) => ed.can_redo()
    None => false
  }
}

///|
/// Enable or disable undo tracking
pub fn undo_manager_set_tracking(_handle : Int, enabled : Bool) -> Unit {
  match editor.val {
    Some(ed) => ed.set_tracking(enabled)
    None => ()
  }
}

///|
/// Clear both undo and redo stacks
pub fn undo_manager_clear(_handle : Int) -> Unit {
  match editor.val {
    Some(ed) => ed.clear_undo()
    None => ()
  }
}
