// Lambda editor diagnostics, AST export, sync export, and projection

///|
/// Get AST as DOT format with name resolution coloring
pub fn get_ast_dot_resolved(handle : Int) -> String {
  match lambda_handles.get(handle) {
    Some(h) => @lang_lambda.get_lambda_dot_resolved(h.editor)
    None => "digraph { }"
  }
}

///|
/// Get AST as pretty-printed string (expression + debug tree)
pub fn get_ast_pretty(handle : Int) -> String {
  match lambda_handles.get(handle) {
    Some(h) => @lang_lambda.get_lambda_ast_pretty(h.editor)
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
        let result = h.editor.parser_runtime().read(h.typecheck.output)
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
          @lang_lambda.EvalResult::Stuck(s) => {
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
