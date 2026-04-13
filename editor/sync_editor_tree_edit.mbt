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
  // Legality: self-drop
  guard source_id != target_id else {
    return Err(TreeEditError::ProjectionEdit(detail="Cannot drop onto self"))
  }
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
  // Legality: descendant-drop (target inside source)
  guard !(tgt_range.start >= src_range.start && tgt_range.end <= src_range.end) else {
    return Err(
      TreeEditError::ProjectionEdit(detail="Cannot drop into own descendant"),
    )
  }
  let doc_text = self.get_text()
  let edits : Array[@core.SpanEdit] = match position {
    // Inside = exchange: swap the expression content, preserving leading whitespace
    Inside => {
      // Also reject source-inside-target for exchange
      guard !(src_range.start >= tgt_range.start &&
        src_range.end <= tgt_range.end) else {
        return Err(
          TreeEditError::ProjectionEdit(
            detail="Cannot drop into own descendant",
          ),
        )
      }
      // Strip leading whitespace from each span to find the expression-only range.
      // Source map ranges include leading separators; we keep those in place.
      fn skip_ws(text : String, start : Int, end : Int) -> Int {
        let mut i = start
        while i < end {
          match text[i] {
            ' ' | '\t' | '\n' | '\r' => i = i + 1
            _ => break
          }
        }
        i
      }
      let src_expr_start = skip_ws(doc_text, src_range.start, src_range.end)
      let tgt_expr_start = skip_ws(doc_text, tgt_range.start, tgt_range.end)
      let src_expr = doc_text[src_expr_start:src_range.end].to_string()
      let tgt_expr = doc_text[tgt_expr_start:tgt_range.end].to_string()
      [
        {
          start: src_expr_start,
          delete_len: src_range.end - src_expr_start,
          inserted: tgt_expr,
        },
        {
          start: tgt_expr_start,
          delete_len: tgt_range.end - tgt_expr_start,
          inserted: src_expr,
        },
      ]
    }
    // Before/After = move: remove source and insert at target position
    Before | After => {
      let src_text = @loom_core.Renderable::unparse(src_node.kind)
      let tgt_insert = match position {
        Before => tgt_range.start
        _ => tgt_range.end
      }
      [
        {
          start: src_range.start,
          delete_len: src_range.end - src_range.start,
          inserted: "",
        },
        { start: tgt_insert, delete_len: 0, inserted: src_text + " " },
      ]
    }
  }
  self.apply_span_edits(edits, @core.FocusHint::RestoreCursor, timestamp_ms)
  Ok(())
}
