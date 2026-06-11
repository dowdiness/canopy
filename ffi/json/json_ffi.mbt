// FFI surface for the JSON editor: lifecycle, text I/O, diagnostics, and
// view patches. Editor construction funnels through `assemble_json_handle`
// so the FFI ctor shares one `@incr.Runtime`, one atomic registration
// boundary, and one destroy gateway with the workspace coordinator. See
// docs/superpowers/specs/2026-05-25-p0b-phase1b-ws2-design.md §5.
// Structural edits live in edit.mbt.

///|
priv struct JsonHandle {
  editor : @editor.SyncEditor[@djson.JsonValue]
  editor_id : @workspace.EditorId
  cells : JsonProtectedCells
}

///|
/// Process-global coordinator for the JSON FFI bundle. Per-language (not
/// shared with Lambda/Markdown) — see spec §4 for the JS-bundle empirical
/// justification.
let coordinator : @workspace.Coordinator = @workspace.Coordinator::new()

///|
/// Generic handle/view-state bookkeeping shared with the other language FFI
/// packages via `ffi/host`. Keyed by the exported integer handle.
let json_registry : @host.HostRegistry[JsonHandle] = @host.HostRegistry::HostRegistry()

// ── Lifecycle ────────────────────────────────────────────────────────────

///|
/// Build a JSON editor on the shared runtime, then atomically register its
/// protected cells with the coordinator. Returns the freshly-allocated
/// `EditorId`. Aborting at any step leaves `json_registry` untouched
/// (atomic-boundary observation, spec §3.6).
fn assemble_json_handle(agent_id : String) -> @workspace.EditorId {
  let editor = @json_companion.new_json_editor(
    agent_id,
    parent_runtime=coordinator.runtime(),
  )
  let cells = JsonProtectedCells::JsonProtectedCells(editor)
  let editor_id = coordinator.register_editor(
    agent_id,
    cells.to_protected_reads(),
  )
  json_registry.insert(editor_id.0, { editor, editor_id, cells })
  editor_id
}

///|
/// Create a new JSON SyncEditor instance. Returns a unique handle.
pub fn create_json_editor(agent_id : String) -> Int {
  assemble_json_handle(agent_id).0
}

///|
/// Destroy a JSON editor and free its resources. The coordinator gateway
/// refuses if workspace deps still reference the editor; in that case the
/// FFI-side bookkeeping (registry handle entry, view-state entry) is
/// intentionally left intact so reads of cached state remain valid.
pub fn destroy_json_editor(handle : Int) -> Unit {
  let h = match json_registry.get(handle) {
    Some(v) => v
    None => return
  }
  let _ = json_registry.destroy(
    coordinator,
    handle,
    h.editor_id,
    "destroy_json_editor",
  )

}

///|
/// Get current text content of the JSON editor.
pub fn json_get_text(handle : Int) -> String {
  match json_registry.get(handle) {
    Some(h) => h.editor.get_text()
    None => ""
  }
}

///|
/// Set text content directly (replaces entire JSON document).
pub fn json_set_text(handle : Int, new_text : String) -> Unit {
  match json_registry.get(handle) {
    Some(h) => h.editor.set_text(new_text)
    None => ()
  }
}

// ── Diagnostics ──────────────────────────────────────────────────────────

///|
/// Get parse errors as JSON array of strings. Reads
/// `parser_diagnostics` through the coordinator's protected surface; on
/// Err collapses to "[]". Mirrors `SyncEditor::get_errors` empty-doc
/// short-circuit (`editor/sync_editor_parser.mbt:107-110`) at the FFI
/// boundary — pre-migration, that suppression lived inside the unmigrated
/// `ed.get_errors()` call. Without this guard the migration would surface
/// spurious empty-doc parser diagnostics that consumers were never
/// previously exposed to (Codex round-2 #1).
pub fn json_get_errors(handle : Int) -> String {
  let h = match json_registry.get(handle) {
    Some(v) => v
    None => return "[]"
  }
  if h.editor.get_text() == "" {
    return "[]"
  }
  match coordinator.read_protected(h.editor_id, h.cells.parser_diagnostics) {
    Ok(d) => d.format().to_json().stringify()
    Err(report) => {
      println("json_get_errors parser read: \{report}")
      "[]"
    }
  }
}

///|
/// Get the ProjNode tree as JSON string.
/// Returns "null" if no projection is available or the protected read fails.
pub fn json_get_proj_node_json(handle : Int) -> String {
  match json_registry.get(handle) {
    Some(h) =>
      match coordinator.read_protected(h.editor_id, h.cells.cached_proj_node) {
        Ok(Some(proj)) => proj.to_json().stringify()
        Ok(None) => "null"
        Err(report) => {
          println("json_get_proj_node_json proj read: \{report}")
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
pub fn json_get_source_map_json(handle : Int) -> String {
  match json_registry.get(handle) {
    Some(h) =>
      match coordinator.read_protected(h.editor_id, h.cells.source_map_memo) {
        Ok(sm) => sm.to_json().stringify()
        Err(report) => {
          println("json_get_source_map_json source_map read: \{report}")
          "[]"
        }
      }
    None => "[]"
  }
}

// ── View patches ─────────────────────────────────────────────────────────

///|
/// Get the ViewNode tree as JSON for a JSON editor.
/// Returns "null" if no projection is available or any protected read fails.
pub fn json_get_view_tree_json(handle : Int) -> String {
  match json_registry.get(handle) {
    Some(h) => {
      let _ = match
        coordinator.read_protected(h.editor_id, h.cells.cached_proj_node) {
        Ok(v) => v
        Err(report) => {
          println("json_get_view_tree_json proj read: \{report}")
          return "null"
        }
      }
      let _ = match
        coordinator.read_protected(h.editor_id, h.cells.source_map_memo) {
        Ok(v) => v
        Err(report) => {
          println("json_get_view_tree_json source_map read: \{report}")
          return "null"
        }
      }
      let _ = match
        coordinator.read_protected(h.editor_id, h.cells.parser_source) {
        Ok(v) => v
        Err(report) => {
          println("json_get_view_tree_json source read: \{report}")
          return "null"
        }
      }
      match h.editor.get_view_tree() {
        Some(view_node) => view_node.to_json().stringify()
        None => "null"
      }
    }
    None => "null"
  }
}

///|
/// Compute incremental view patches for a JSON editor.
/// Returns a JSON array of ViewPatch objects, or "[]" if any protected read
/// fails.
pub fn json_compute_view_patches_json(handle : Int) -> String {
  match json_registry.get(handle) {
    Some(h) => {
      let _ = match
        coordinator.read_protected(h.editor_id, h.cells.cached_proj_node) {
        Ok(v) => v
        Err(report) => {
          println("json_compute_view_patches_json proj read: \{report}")
          return "[]"
        }
      }
      let _ = match
        coordinator.read_protected(h.editor_id, h.cells.source_map_memo) {
        Ok(v) => v
        Err(report) => {
          println("json_compute_view_patches_json source_map read: \{report}")
          return "[]"
        }
      }
      let _ = match
        coordinator.read_protected(h.editor_id, h.cells.parser_source) {
        Ok(v) => v
        Err(report) => {
          println("json_compute_view_patches_json source read: \{report}")
          return "[]"
        }
      }
      let _ = match
        coordinator.read_protected(h.editor_id, h.cells.parser_diagnostics) {
        Ok(v) => v
        Err(report) => {
          println("json_compute_view_patches_json diagnostics read: \{report}")
          return "[]"
        }
      }
      let state = json_registry.view_state(handle)
      let patches = @editor.compute_view_patches(state, h.editor)
      Json::array(patches.map(fn(p) { p.to_json() })).stringify()
    }
    None => "[]"
  }
}
