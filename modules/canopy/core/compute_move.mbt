// Pure move-planning core for expression-level structural moves.
//
// Extracted from `SyncEditor::move_node` (editor/sync_editor_tree_edit.mbt)
// so the span arithmetic and legality checks are language-neutral and
// testable without an editor. The application shell (range resolution,
// hint taint, `apply_span_edits`, undo recording) stays in the editor.
//
// See docs/decisions/2026-08-07-generic-language-spi-deepening.md: moves are
// edit-port computation; `compute_move` is the shared expression-level helper
// that languages opt into (Markdown keeps its own block-level move logic).

///|
/// Compute the span edits for a structural move.
///
/// - **Inside** (exchange): swaps the expression content of source and
///   target, preserving leading whitespace/separators.
/// - **Before/After**: replaces the source expression with `placeholder`
///   (keeping leading whitespace and the syntax parseable) and inserts the
///   source expression followed by `separator` at the target position.
///
/// `placeholder` and `separator` are language text policies — for Lambda,
/// `Renderable::placeholder(kind)` and `" "` respectively.
///
/// CAUTION: Insert positions assume the caller applies edits in reverse
/// document order (as `apply_span_edits` does) so deletion shifts do not
/// disturb later offsets.
///
/// Raises `InvalidTarget` on self-drop or descendant-drop (both directions).
pub fn compute_move(
  text : String,
  source_id : NodeId,
  source_range : @loomcore.Range,
  target_id : NodeId,
  target_range : @loomcore.Range,
  position : DropPosition,
  placeholder : String,
  separator : String,
) -> (Array[SpanEdit], FocusHint) raise EditError {
  // Legality: self-drop. Id-based: two distinct nodes may share an empty
  // range, so ranges alone cannot express this check.
  guard source_id != target_id else {
    raise InvalidTarget(detail="Cannot drop onto self")
  }
  // Legality: descendant-drop (target inside source)
  guard !(target_range.start >= source_range.start &&
    target_range.end <= source_range.end) else {
    raise InvalidTarget(detail="Cannot drop into own descendant")
  }
  let edits : Array[SpanEdit] = match position {
    // Inside = exchange: swap the expression content, preserving leading
    // whitespace.
    Inside => {
      // Also reject source-inside-target for exchange
      guard !(source_range.start >= target_range.start &&
        source_range.end <= target_range.end) else {
        raise InvalidTarget(detail="Cannot drop into own descendant")
      }
      let src_expr_start = skip_ws(text, source_range.start, source_range.end)
      let tgt_expr_start = skip_ws(text, target_range.start, target_range.end)
      let src_expr = text[src_expr_start:source_range.end].to_owned()
      let tgt_expr = text[tgt_expr_start:target_range.end].to_owned()
      [
        {
          start: src_expr_start,
          delete_len: source_range.end - src_expr_start,
          inserted: tgt_expr,
        },
        {
          start: tgt_expr_start,
          delete_len: target_range.end - tgt_expr_start,
          inserted: src_expr,
        },
      ]
    }
    // Before/After = move: replace source with placeholder, insert at target.
    Before | After => {
      let src_expr_start = skip_ws(text, source_range.start, source_range.end)
      let src_expr = text[src_expr_start:source_range.end].to_owned()
      let tgt_insert = match position {
        Before => target_range.start
        _ => target_range.end
      }
      [
        {
          start: src_expr_start,
          delete_len: source_range.end - src_expr_start,
          inserted: placeholder,
        },
        { start: tgt_insert, delete_len: 0, inserted: src_expr + separator },
      ]
    }
  }
  (edits, FocusHint::RestoreCursor)
}

///|
/// Strip leading whitespace from a span to find the expression-only start.
/// Source map ranges include leading separators; callers keep those in place.
///
/// Reuse check: MoonBit core has no `String::skip_whitespace`-style helper,
/// and `@loomcore.Range` exposes no range-in-range containment method
/// (`contains` takes a position; `overlaps` is intersection, not
/// containment), so the manual loop and range arithmetic are the
/// minimal-coupling choices.
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
