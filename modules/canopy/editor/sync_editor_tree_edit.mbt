// Generic Tier-2 structural edit methods and projection boundary for SyncEditor[T].
// All edits reduce to: span lookup → compute replacement text → apply_text_edit_internal.
// No language-specific projection side channel, no TreeEditOp, no lambda-specific logic.

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
  let _ = self.cached_proj_node.read_or_abort()
}

///|
/// Delete a node by replacing its source span with the node's placeholder text.
/// Uses T::placeholder(node.kind) so deletion leaves a parseable hole.
///
/// Example: deleting `(f x)` in lambda → leaves `?`
pub fn[T : Eq + @loom_core.Renderable] SyncEditor::delete_node(
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
  ignore(
    self.apply_text_edit_internal(
      range.start,
      delete_len,
      placeholder,
      timestamp_ms,
      true,
      false,
    ),
  )
  Ok(())
}

///|
/// Replace a node's source span with `new_text`.
/// The new text is inserted verbatim — the caller is responsible for
/// providing syntactically valid replacement text.
///
/// Example: committing an inline rename edit.
pub fn[T : Eq] SyncEditor::commit_edit(
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
  ignore(
    self.apply_text_edit_internal(
      range.start,
      delete_len,
      new_text,
      timestamp_ms,
      true,
      true,
    ),
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
///     Ok("((x) => " + src[s:e].to_string() + ")")
///   }, timestamp)
pub fn[T : Eq] SyncEditor::apply_text_transform(
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
  ignore(
    self.apply_text_edit_internal(
      range.start,
      delete_len,
      replacement,
      timestamp_ms,
      true,
      false,
    ),
  )
  Ok(())
}

///|
/// Move a node to a new position in the tree.
///
/// Thin application shell over the pure planner `@core.compute_move`: it
/// resolves source/target ranges, taints pending identity hints, applies the
/// planned span edits (undo-recorded, cursor per `FocusHint`), and maps
/// planner `EditError`s to the user-facing `TreeEditError`.
///
/// Text policies (placeholder, separator) are fixed to legacy behavior here;
/// language-specific policies go through the public `@core.compute_move`
/// (the SPI seam, see ADR 2026-08-07).
///
/// The shell taints pending transforms only after resolution succeeds;
/// unknown-id failures leave pending hints untouched.
pub fn[T : Eq + @loom_core.Renderable] SyncEditor::move_node(
  self : SyncEditor[T],
  source_id : @core.NodeId,
  target_id : @core.NodeId,
  position : @core.DropPosition,
  timestamp_ms : Int,
) -> Result[Array[@core.SpanEdit], TreeEditError] {
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
  // A drag-drop restructures the tree non-locally. Invalidate any pending
  // structural hints so reconcile degrades to LCS for this reparse.
  // (Move identity preservation deferred to Slice 5+ match_entities.)
  self.taint_pending_transforms()
  let (edits, focus_hint) = @core.compute_move(
    self.get_text(),
    source_id,
    src_range,
    target_id,
    tgt_range,
    position,
    @loom_core.Renderable::placeholder(src_node.kind),
    " ",
  ) catch {
    e => return Err(map_move_error(e))
  }
  self.apply_span_edits(edits, focus_hint, timestamp_ms)
  Ok(edits)
}

///|
/// Map the pure planner's `EditError` raises to the user-facing error type.
/// `compute_move` raises only `InvalidTarget`; the message carries the
/// legality detail ("Cannot drop onto self" / "Cannot drop into own
/// descendant").
fn map_move_error(e : @core.EditError) -> TreeEditError {
  TreeEditError::ProjectionEdit(detail=e.message())
}
