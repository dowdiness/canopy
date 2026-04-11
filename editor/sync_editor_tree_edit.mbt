// Generic Tier-2 structural edit methods and projection boundary for SyncEditor[T].
// All edits reduce to: span lookup → compute replacement text → apply_text_edit_internal.
// No FlatProj, no TreeEditOp, no lambda-specific logic.

///|
/// Returns true if any text edit has been applied since the last refresh().
/// Does not force memo evaluation.
pub fn[T] SyncEditor::is_dirty(self : SyncEditor[T]) -> Bool {
  self.projection_dirty
}

///|
/// Clears the dirty flag and eagerly evaluates the projection memo.
/// The dirty flag is advisory — get_proj_node() / get_source_map() etc.
/// still force recomputation on demand. refresh() is useful when callers
/// want to batch edits and trigger a single projection pass at a known
/// point (e.g., on animation frame) rather than paying the cost lazily
/// inside a getter.
pub fn[T] SyncEditor::refresh(self : SyncEditor[T]) -> Unit {
  self.projection_dirty = false
  let _ = self.cached_proj_node.get()
}

///|
/// Delete a node by replacing its source span with the node's placeholder text.
/// Uses T::placeholder(node.kind) so deletion leaves a parseable hole.
///
/// Example: deleting `(f x)` in lambda → leaves `?`
pub fn[T : @loom_core.Renderable] SyncEditor::delete_node(
  self : SyncEditor[T],
  node_id : @core.NodeId,
  timestamp_ms : Int,
) -> Result[Unit, TreeEditError] {
  let range = match self.get_node_range(node_id) {
    None =>
      return Err(
        TreeEditError::NodeNotInSourceMap(action="delete_node", node_id~),
      )
    Some(r) => r
  }
  let node = match self.get_node(node_id) {
    None =>
      return Err(
        TreeEditError::NodeNotInRegistry(action="delete_node", node_id~),
      )
    Some(n) => n
  }
  let placeholder = @loom_core.Renderable::placeholder(node.kind)
  let delete_len = range.end - range.start
  self.apply_text_edit_internal(
    range.start,
    delete_len,
    placeholder,
    timestamp_ms,
    true,
    false,
  )
  Ok(())
}

///|
/// Replace a node's source span with `new_text`.
/// The new text is inserted verbatim — the caller is responsible for
/// providing syntactically valid replacement text.
///
/// Example: committing an inline rename edit.
pub fn[T] SyncEditor::commit_edit(
  self : SyncEditor[T],
  node_id : @core.NodeId,
  new_text : String,
  timestamp_ms : Int,
) -> Result[Unit, TreeEditError] {
  let range = match self.get_node_range(node_id) {
    None =>
      return Err(
        TreeEditError::NodeNotInSourceMap(action="commit_edit", node_id~),
      )
    Some(r) => r
  }
  let delete_len = range.end - range.start
  self.apply_text_edit_internal(
    range.start,
    delete_len,
    new_text,
    timestamp_ms,
    true,
    true,
  )
  Ok(())
}

///|
/// Apply a language-provided text transform to a node's source span.
/// The closure receives (source_text, span_start, span_end) and returns
/// the replacement text. The framework handles span lookup → apply.
///
/// Example:
///   editor.apply_text_transform(node_id, fn(src, s, e) {
///     Ok("(λx. " + src[s:e].to_string() + ")")
///   }, timestamp)
pub fn[T] SyncEditor::apply_text_transform(
  self : SyncEditor[T],
  node_id : @core.NodeId,
  compute_replacement : (String, Int, Int) -> Result[String, String],
  timestamp_ms : Int,
) -> Result[Unit, TreeEditError] {
  let range = match self.get_node_range(node_id) {
    None =>
      return Err(
        TreeEditError::NodeNotInSourceMap(
          action="apply_text_transform",
          node_id~,
        ),
      )
    Some(r) => r
  }
  let source = self.get_text()
  let replacement = match compute_replacement(source, range.start, range.end) {
    Err(msg) => return Err(TreeEditError::TextTransformFailed(detail=msg))
    Ok(r) => r
  }
  let delete_len = range.end - range.start
  self.apply_text_edit_internal(
    range.start,
    delete_len,
    replacement,
    timestamp_ms,
    true,
    false,
  )
  Ok(())
}

///|
/// Move a node to a new position in the tree by:
///   1. Unparsing the source node via T::unparse
///   2. Deleting the source span (replace with placeholder)
///   3. Inserting the unparsed text adjacent to the target span
///
/// CAUTION: Insert position must be adjusted when source precedes target
/// in the document (deletion shifts subsequent offsets backward by
/// `source_len - placeholder_len`). This method handles the adjustment.
pub fn[T : @loom_core.Renderable] SyncEditor::move_node(
  self : SyncEditor[T],
  source_id : @core.NodeId,
  target_id : @core.NodeId,
  position : @core.DropPosition,
  timestamp_ms : Int,
) -> Result[Unit, TreeEditError] {
  // Resolve source
  let src_range = match self.get_node_range(source_id) {
    None =>
      return Err(
        TreeEditError::NodeNotInSourceMap(
          action="move_node: source",
          node_id=source_id,
        ),
      )
    Some(r) => r
  }
  let src_node = match self.get_node(source_id) {
    None =>
      return Err(
        TreeEditError::NodeNotInRegistry(
          action="move_node: source",
          node_id=source_id,
        ),
      )
    Some(n) => n
  }
  // Resolve target
  let tgt_range = match self.get_node_range(target_id) {
    None =>
      return Err(
        TreeEditError::NodeNotInSourceMap(
          action="move_node: target",
          node_id=target_id,
        ),
      )
    Some(r) => r
  }
  let src_text = @loom_core.Renderable::unparse(src_node.kind)
  let placeholder = @loom_core.Renderable::placeholder(src_node.kind)
  let src_len = src_range.end - src_range.start
  let shift = placeholder.length() - src_len // negative if placeholder is shorter

  // Step 1: delete source span (replace with placeholder)
  self.apply_text_edit_internal(
    src_range.start,
    src_len,
    placeholder,
    timestamp_ms,
    true,
    false,
  )

  // Step 2: compute insert position, adjusting for source deletion if source < target
  let tgt_insert = match position {
    Before => tgt_range.start
    After => tgt_range.end
    Inside => tgt_range.end // insert after opening — language-specific; best effort
  }
  let adjusted_insert = if src_range.start < tgt_insert {
    tgt_insert + shift
  } else {
    tgt_insert
  }

  // Step 3: insert src_text + separator at adjusted position
  // Separator is a space — language-specific grammars may need wrapping.
  // Use apply_text_transform with a custom closure for precise control.
  self.apply_text_edit_internal(
    adjusted_insert,
    0,
    src_text + " ",
    timestamp_ms,
    true,
    false,
  )
  Ok(())
}
