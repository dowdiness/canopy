// Lambda semantic overlay FFI.

///|
fn semantic_node_allows_rename(
  projection : @lambda_semantic.SemanticProjection,
  node_id : @core.NodeId,
) -> Bool {
  match projection.annotations.get(node_id) {
    Some(anns) =>
      anns
      .iter()
      .any(fn(ann) {
        (ann.kind == "semantic-ref" && ann.label.has_prefix("bound ")) ||
        ann.kind == "semantic-binder"
      })
    None => false
  }
}

///|
fn semantic_projection_json(
  projection : @lambda_semantic.SemanticProjection,
  diagnostics : Array[@protocol.Diagnostic],
) -> String {
  guard projection.to_json() is Json::Object(fields) else {
    abort("SemanticProjection must serialize to an object")
  }
  fields["diagnostics"] = Json::array(
    diagnostics.map(diagnostic => diagnostic.to_json()),
  )
  Json::object(fields).stringify()
}

///|
fn empty_semantic_projection_json() -> String {
  semantic_projection_json(@lambda_semantic.SemanticProjection::empty(), [])
}

///|
/// Get the read-only semantic projection as JSON.
/// Returns `{annotations, decorations, diagnostics}` and never mutates editor
/// state; semantic edits still lower through text/CRDT edit paths. Returns the
/// empty projection if any protected read fails.
pub fn get_semantic_projection_json(handle : Int) -> String {
  match lambda_registry.get(handle) {
    Some(h) => {
      let root = match
        coordinator.read_protected(h.editor_id, h.cells.cached_proj_node) {
        Ok(Some(root)) => root
        Ok(None) => return empty_semantic_projection_json()
        Err(report) => {
          println("get_semantic_projection_json proj read: \{report}")
          return empty_semantic_projection_json()
        }
      }
      let source_map = match
        coordinator.read_protected(h.editor_id, h.cells.source_map_memo) {
        Ok(sm) => sm
        Err(report) => {
          println("get_semantic_projection_json source_map read: \{report}")
          return empty_semantic_projection_json()
        }
      }
      let source = match
        coordinator.read_protected(h.editor_id, h.cells.parser_source) {
        Ok(source) => source
        Err(report) => {
          println("get_semantic_projection_json source read: \{report}")
          return empty_semantic_projection_json()
        }
      }
      let projection = @lambda_semantic.build_semantic_projection(
        root, source_map,
      )
      let diagnostics = @lambda_semantic.build_semantic_diagnostics(
        h.editor.parser_source_id(),
        source,
        root,
        source_map,
      ) catch {
        _ => @loom.DiagnosticSet::empty()
      }
      semantic_projection_json(
        projection,
        @editor.project_diagnostics_for_source(
          h.editor.parser_source_id(),
          diagnostics,
        ),
      )
    }
    None => empty_semantic_projection_json()
  }
}

///|
/// Rename a semantic binder/reference node through the normal text edit path.
/// This is a thin semantic-action prototype: the overlay gates the action, then
/// `TreeEditOp::Rename` computes and applies `SpanEdit`s to the text CRDT.
pub fn rename_semantic_node(
  handle : Int,
  node_id : Int,
  new_name : String,
  timestamp_ms : Int,
) -> String {
  match lambda_registry.get(handle) {
    Some(h) => {
      let id = @core.NodeId::from_int(node_id)
      let root = match
        coordinator.read_protected(h.editor_id, h.cells.cached_proj_node) {
        Ok(Some(root)) => root
        Ok(None) => return "error: no projection"
        Err(report) => {
          println("rename_semantic_node proj read: \{report}")
          return "error: editor unavailable"
        }
      }
      let source_map = match
        coordinator.read_protected(h.editor_id, h.cells.source_map_memo) {
        Ok(sm) => sm
        Err(report) => {
          println("rename_semantic_node source_map read: \{report}")
          return "error: editor unavailable"
        }
      }
      let projection = @lambda_semantic.build_semantic_projection(
        root, source_map,
      )
      if !semantic_node_allows_rename(projection, id) {
        return "error: node is not a semantic binder or reference"
      }
      match
        @lang_lambda.apply_lambda_tree_edit(
          h.editor,
          h.companion,
          @lang_lambda.TreeEditOp::Rename(node_id=id, new_name~),
          timestamp_ms,
        ) {
        Ok(_) => "ok"
        Err(err) => "error: " + map_edit_error(err).message()
      }
    }
    None => "error: no editor"
  }
}
