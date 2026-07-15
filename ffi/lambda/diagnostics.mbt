// Lambda editor diagnostics, AST export, sync export, and projection

///|
/// Get AST as DOT format with name resolution coloring
pub fn get_ast_dot_resolved(handle : Int) -> String {
  match lambda_registry.get(handle) {
    Some(h) => @lang_lambda.get_lambda_dot_resolved(h.editor)
    None => "digraph { }"
  }
}

///|
/// Get AST as pretty-printed string (expression + debug tree)
pub fn get_ast_pretty(handle : Int) -> String {
  match lambda_registry.get(handle) {
    Some(h) => @lang_lambda.get_lambda_ast_pretty(h.editor)
    None => ""
  }
}

///|
/// Get parse errors as JSON array
pub fn get_errors_json(handle : Int) -> String {
  match lambda_registry.get(handle) {
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
  match lambda_registry.get(handle) {
    Some(h) => {
      // Read every protected cell this accessor depends on up front; any
      // Err collapses the whole accessor to "[]". Partial diagnostics from a
      // coordinator-destroyed editor would be worse than empty, and
      // CellNotInProtectedSurface / CycleDetected are structural defects we
      // do not want to render as authoritative output.
      //
      // Empty-source guard: mirrors the suppression that lived in
      // `SyncEditor::get_errors` (editor/sync_editor_parser.mbt:108-110)
      // before this migration replaced that call. Reading
      // `parser_diagnostics.format()` directly on an empty doc could
      // surface spurious parser output that consumers (JS panel rendering)
      // were never previously exposed to.
      let parse_errors : Array[String] = if h.editor.get_text() == "" {
        []
      } else {
        match
          coordinator.read_protected(h.editor_id, h.cells.parser_diagnostics) {
          Ok(d) => d.format()
          Err(report) => {
            println("get_diagnostics_json parser read: \{report}")
            return "[]"
          }
        }
      }
      // Typecheck only meaningful if parsing succeeded; otherwise the AST
      // is incomplete and type errors would just be noise on top of the
      // parse error.
      let typecheck_diags = if parse_errors.is_empty() {
        match
          coordinator.read_protected(h.editor_id, h.cells.typecheck_output) {
          Ok(result) => result.all_diagnostics
          Err(report) => {
            println("get_diagnostics_json typecheck read: \{report}")
            return "[]"
          }
        }
      } else {
        []
      }
      let eval_results = match
        coordinator.read_protected(h.editor_id, h.cells.escalation_memo) {
        Ok(r) => r
        Err(report) => {
          println("get_diagnostics_json eval read: \{report}")
          return "[]"
        }
      }
      let diags : Array[Json] = []
      for msg in parse_errors {
        let m : Map[String, Json] = Map([])
        m["level"] = "error".to_json()
        m["message"] = msg.to_json()
        diags.push(Json::object(m))
      }
      for diag in typecheck_diags {
        let m : Map[String, Json] = Map([])
        m["level"] = "error".to_json()
        m["message"] = diag.message.to_json()
        match diag.def_name {
          Some(name) => m["def_name"] = name.to_json()
          None => ()
        }
        diags.push(Json::object(m))
      }
      for result in eval_results {
        match result {
          @lang_lambda.EvalResult::Stuck(s) => {
            let m : Map[String, Json] = Map([])
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
  match lambda_registry.get(handle) {
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
  match lambda_registry.get(handle) {
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
  match lambda_registry.get(handle) {
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
  match lambda_registry.get(handle) {
    Some(h) => h.editor.get_version().to_json_string()
    None => "\"\""
  }
}

///|
/// Get the ProjNode tree as JSON string.
/// Returns "null" if no projection is available or the protected read fails.
pub fn get_proj_node_json(handle : Int) -> String {
  match lambda_registry.get(handle) {
    Some(h) =>
      match coordinator.read_protected(h.editor_id, h.cells.cached_proj_node) {
        Ok(Some(proj)) => proj.to_json().stringify()
        Ok(None) => "null"
        Err(report) => {
          println("get_proj_node_json: \{report}")
          "null"
        }
      }
    None => "null"
  }
}

///|
/// Get the SourceMap as JSON string.
/// Returns an array of {node_id, start, end} entries, or "[]" if the
/// protected read fails.
pub fn get_source_map_json(handle : Int) -> String {
  match lambda_registry.get(handle) {
    Some(h) =>
      match coordinator.read_protected(h.editor_id, h.cells.source_map_memo) {
        Ok(sm) => sm.to_json().stringify()
        Err(report) => {
          println("get_source_map_json: \{report}")
          "[]"
        }
      }
    None => "[]"
  }
}
