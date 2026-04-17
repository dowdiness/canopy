// Lambda editor FFI — lifecycle, text, undo, projection, intent

// Handle-based editor registry (supports multiple concurrent editors)

///|
priv struct LambdaHandle {
  editor : @editor.SyncEditor[@ast.Term]
  companion : @lambda.LambdaCompanion
  typecheck : TypecheckBundle
}

///|
/// Standalone runtime that drives the typecheck pipeline incrementally
/// off the editor's text. Kept separate from the editor's runtime because
/// LambdaCompanion does not expose its runtime to FFI.
priv struct TypecheckBundle {
  rt : @cells.Runtime
  scope : @cells.Scope
  text_signal : @cells.Signal[String]
  output : @cells.Memo[@typecheck.ModuleTypeResult]
}

///|
fn new_typecheck_bundle() -> TypecheckBundle {
  let rt = @cells.Runtime::new()
  let scope = @cells.Scope::new(rt)
  let text_signal = scope.signal("", label="lambda-typecheck-text")
  let typed_term_memo : @cells.Memo[@typecheck.TypedTerm] = scope.memo(
    fn() {
      let text = text_signal.get()
      // parse_cst preserves `: Type` annotations on the CST. Parse
      // diagnostics (lex errors, recoverable syntax errors) are surfaced
      // separately via editor.get_errors() — get_diagnostics_json() only
      // reads this memo when parse errors are empty, so we drop the
      // diagnostics array here.
      let (cst, _) = @lambda_lang.parse_cst(text) catch {
        _ => return @typecheck.TypedTerm::Error("parse")
      }
      @typecheck.convert_from_cst(@seam.SyntaxNode::from_cst(cst))
    },
    label="lambda-typed-term",
  )
  let output = @typecheck.build_typecheck_pipeline(rt, scope, typed_term_memo)
  { rt, scope, text_signal, output }
}

///|
let lambda_handles : Map[Int, LambdaHandle] = Map::new()

///|
let next_handle : Ref[Int] = { val: 1 }

///|
let last_created_handle : Ref[Int?] = { val: None }

///|
/// Get the most recently created editor for legacy MoonBit consumers.
pub fn get_sync_editor() -> @editor.SyncEditor[@ast.Term]? {
  match last_created_handle.val {
    Some(handle) =>
      match lambda_handles.get(handle) {
        Some(h) => Some(h.editor)
        None => None
      }
    None => None
  }
}

///|
/// Get the companion for the most recently created lambda editor.
pub fn get_lambda_companion() -> @lambda.LambdaCompanion? {
  match last_created_handle.val {
    Some(handle) =>
      match lambda_handles.get(handle) {
        Some(h) => Some(h.companion)
        None => None
      }
    None => None
  }
}

///|
/// Create a new SyncEditor instance.
/// Returns a unique handle for this editor.
pub fn create_editor(agent_id : String) -> Int {
  let handle = next_handle.val
  next_handle.val = handle + 1
  let (editor, companion) = @lambda.new_lambda_editor(agent_id)
  lambda_handles[handle] = {
    editor,
    companion,
    typecheck: new_typecheck_bundle(),
  }
  last_created_handle.val = Some(handle)
  handle
}

///|
/// Destroy an editor instance and free its resources.
pub fn destroy_editor(handle : Int) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => h.typecheck.scope.dispose()
    None => ()
  }
  lambda_handles.remove(handle)
  view_states.remove(handle)
  pretty_view_states.remove(handle)
  if last_created_handle.val == Some(handle) {
    last_created_handle.val = None
  }
}

///|
/// Get current text content
pub fn get_text(handle : Int) -> String {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.get_text()
    None => ""
  }
}

///|
/// Set text content directly (replaces entire document)
pub fn set_text(handle : Int, new_text : String) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.set_text(new_text)
    None => ()
  }
}

///|
/// Get AST as DOT format with name resolution coloring
pub fn get_ast_dot_resolved(handle : Int) -> String {
  match lambda_handles.get(handle) {
    Some(h) => @lambda.get_lambda_dot_resolved(h.editor)
    None => "digraph { }"
  }
}

///|
/// Get AST as pretty-printed string (expression + debug tree)
pub fn get_ast_pretty(handle : Int) -> String {
  match lambda_handles.get(handle) {
    Some(h) => @lambda.get_lambda_ast_pretty(h.editor)
    None => ""
  }
}

///|
/// Get parse errors as JSON array
pub fn get_errors_json(handle : Int) -> String {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.get_errors().to_json().stringify()
    None => "[]"
  }
}

///|
/// Get all diagnostics (parse errors + type errors + eval warnings) as JSON array.
/// Each entry: `{"level": "error"|"warning", "message": "...", "def_name"?: "..."}`.
/// `def_name` is present only on type-check diagnostics that originate inside a
/// named binding (e.g. `let f = y` → `def_name: "f"`); consumers should group,
/// filter, or badge by this field rather than parsing the message string.
pub fn get_diagnostics_json(handle : Int) -> String {
  match lambda_handles.get(handle) {
    Some(h) => {
      let diags : Array[Json] = []
      let parse_errors = h.editor.get_errors()
      for msg in parse_errors {
        let m : Map[String, Json] = {}
        m["level"] = "error".to_json()
        m["message"] = msg.to_json()
        diags.push(Json::object(m))
      }
      // Type diagnostics — only meaningful if parsing succeeded; otherwise
      // the AST is incomplete and type errors would just be noise on top of
      // the parse error.
      if parse_errors.is_empty() {
        h.typecheck.text_signal.set(h.editor.get_text())
        let result = h.typecheck.rt.read(h.typecheck.output)
        for diag in result.all_diagnostics {
          let m : Map[String, Json] = {}
          m["level"] = "error".to_json()
          m["message"] = diag.message.to_json()
          match diag.def_name {
            Some(name) => m["def_name"] = name.to_json()
            None => ()
          }
          diags.push(Json::object(m))
        }
      }
      for result in h.companion.get_eval_results() {
        match result {
          @lambda.EvalResult::Stuck(s) => {
            let m : Map[String, Json] = {}
            m["level"] = "warning".to_json()
            m["message"] = s.to_json()
            diags.push(Json::object(m))
          }
          _ => continue
        }
      }
      Json::array(diags).stringify()
    }
    None => "[]"
  }
}

///|
/// Export all operations as a SyncMessage JSON string.
pub fn export_all_json(handle : Int) -> String {
  match lambda_handles.get(handle) {
    Some(h) =>
      h.editor.export_all().to_json_string() catch {
        _ => "{\"ops\":[],\"heads\":[]}"
      }
    None => "{\"ops\":[],\"heads\":[]}"
  }
}

///|
/// Export operations since a peer's version as a SyncMessage JSON string.
pub fn export_since_json(handle : Int, peer_version_json : String) -> String {
  match lambda_handles.get(handle) {
    Some(h) =>
      try {
        let ver = @text.Version::from_json_string(peer_version_json)
        h.editor.export_since(ver).to_json_string()
      } catch {
        _ => "{\"ops\":[],\"heads\":[]}"
      }
    None => "{\"ops\":[],\"heads\":[]}"
  }
}

///|
/// Apply a SyncMessage received from a peer.
pub fn apply_sync_json(handle : Int, sync_json : String) -> String {
  match lambda_handles.get(handle) {
    Some(h) =>
      try {
        let msg = @text.SyncMessage::from_json_string(sync_json)
        h.editor.apply_sync(msg)
        "ok"
      } catch {
        err => "{\"error\":\"\{err}\"}"
      }
    None => "{\"error\":\"invalid handle\"}"
  }
}

///|
/// Get the current version as a JSON string.
pub fn get_version_json(handle : Int) -> String {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.get_version().to_json_string()
    None => "\"\""
  }
}

// --- Undo ---

///|
/// Create a new SyncEditor with undo support.
/// Returns a unique handle for this editor.
pub fn create_editor_with_undo(
  agent_id : String,
  capture_timeout_ms : Int,
) -> Int {
  let handle = next_handle.val
  next_handle.val = handle + 1
  let (editor, companion) = @lambda.new_lambda_editor(
    agent_id,
    capture_timeout_ms~,
  )
  lambda_handles[handle] = {
    editor,
    companion,
    typecheck: new_typecheck_bundle(),
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
/// Insert text at a specific position without moving the cursor.
/// Records the operation for undo. Used by ProseMirror bridge.
pub fn insert_at(
  handle : Int,
  position : Int,
  text : String,
  timestamp_ms : Int,
) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.insert_at(position, text, timestamp_ms)
    None => ()
  }
}

///|
/// Delete the character at a specific position without moving the cursor.
/// Records the operation for undo. Returns false if position is out of bounds.
/// Used by ProseMirror bridge.
pub fn delete_at(handle : Int, position : Int, timestamp_ms : Int) -> Bool {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.delete_at(position, timestamp_ms)
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

// --- Projection ---

///|
/// Get the ProjNode tree as JSON string.
/// Returns "null" if no projection is available.
pub fn get_proj_node_json(handle : Int) -> String {
  match lambda_handles.get(handle) {
    Some(h) =>
      match h.editor.get_proj_node() {
        Some(proj) => proj.to_json().stringify()
        None => "null"
      }
    None => "null"
  }
}

///|
/// Get the SourceMap as JSON string.
/// Returns an array of {node_id, start, end} entries.
pub fn get_source_map_json(handle : Int) -> String {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.get_source_map().to_json().stringify()
    None => "[]"
  }
}

///|
/// Apply a structural tree edit from a JSON-encoded TreeEditOp.
/// Returns "ok" on success, or "error: <message>" on failure.
pub fn apply_tree_edit_json(
  handle : Int,
  op_json : String,
  timestamp_ms : Int,
) -> String {
  match lambda_handles.get(handle) {
    Some(h) => {
      let json = @json.parse(op_json) catch {
        _ => return "error: invalid JSON"
      }
      let op = try? @lambda.parse_tree_edit_op(json)
      match op {
        Ok(op) =>
          match
            @lambda.apply_lambda_tree_edit(
              h.editor,
              h.companion,
              op,
              timestamp_ms,
            ) {
            Ok(_) => "ok"
            Err(err) => "error: " + err.message()
          }
        Err(err) => "error: " + err.message()
      }
    }
    None => "error: no editor"
  }
}

// --- Intent ---

///|
pub fn handle_text_intent(
  handle : Int,
  from : Int,
  deleted_len : Int,
  insert : String,
  timestamp_ms : Int,
) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.apply_text_edit(from, deleted_len, insert, timestamp_ms)
    None => ()
  }
}

///|
pub fn handle_undo(handle : Int) -> Bool {
  undo_manager_undo(handle)
}

///|
pub fn handle_redo(handle : Int) -> Bool {
  undo_manager_redo(handle)
}

///|
/// Apply a structural edit intent with optional params.
/// params_json is a JSON object string like '{"var_name":"x"}' or ''.
pub fn handle_structural_intent(
  handle : Int,
  op : String,
  node_id_str : String,
  timestamp_ms : Int,
  params_json : String,
) -> String {
  let m : Map[String, Json] = {}
  m["type"] = op.to_json()
  let node_id_int = @string.parse_int(node_id_str) catch {
    _ => return "error: invalid node_id"
  }
  m["node_id"] = node_id_int.to_json()
  // Merge extra params (var_name, new_name, op, etc.)
  if params_json != "" {
    try {
      match @json.parse(params_json) {
        Json::Object(pm) =>
          for k, v in pm {
            m[k] = v
          }
        _ => ()
      }
    } catch {
      _ => ()
    }
  }
  apply_tree_edit_json(handle, Json::object(m).stringify(), timestamp_ms)
}
