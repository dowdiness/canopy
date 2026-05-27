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
/// Get the read-only semantic projection as JSON.
/// Returns `{annotations, decorations, diagnostics}` and never mutates editor
/// state; semantic edits still lower through text/CRDT edit paths.
pub fn get_semantic_projection_json(handle : Int) -> String {
  match lambda_handles.get(handle) {
    Some(h) =>
      match h.editor.get_proj_node() {
        Some(root) =>
          @lambda_semantic.build_semantic_projection_with_flat_proj(
            root,
            h.editor.get_source_map(),
            h.companion.get_flat_proj(),
          )
          .to_json()
          .stringify()
        None =>
          @lambda_semantic.SemanticProjection::empty().to_json().stringify()
      }
    None => @lambda_semantic.SemanticProjection::empty().to_json().stringify()
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
  match lambda_handles.get(handle) {
    Some(h) => {
      let id = @core.NodeId::from_int(node_id)
      let root = match h.editor.get_proj_node() {
        Some(root) => root
        None => return "error: no projection"
      }
      let projection = @lambda_semantic.build_semantic_projection_with_flat_proj(
        root,
        h.editor.get_source_map(),
        h.companion.get_flat_proj(),
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
        Err(err) => "error: " + err.message()
      }
    }
    None => "error: no editor"
  }
}
