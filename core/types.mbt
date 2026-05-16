// Active runtime types for projection editing.

///|
/// Unique identifier for AST nodes (persistent across edits).
/// Construct via `NodeId::from_int(n)`.
pub struct NodeId(Int) derive(Debug, Eq, Hash, Compare)

///|
pub impl Show for NodeId with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub fn NodeId::from_int(n : Int) -> NodeId {
  NodeId(n)
}

///|
/// Compact `#N` form used by `Show for ProjNode` / `Show for
/// InteractiveTreeNode` / `Show for GenericTreeOp` to render node IDs
/// without going through the longer `Show for NodeId` (which still emits
/// the `"NodeId(N)"` Debug form for production callers in the lambda edit
/// path). Package-private — does not expand the public API.
fn NodeId::short(self : NodeId) -> String {
  let NodeId(n) = self
  "#\{n}"
}

///|
pub impl ToJson for NodeId with to_json(self) {
  let NodeId(n) = self
  n.to_json()
}

///|
/// A text span replacement computed by an edit handler.
pub(all) struct SpanEdit {
  start : Int
  delete_len : Int
  inserted : String
} derive(Debug, Eq)

///|
/// Compact patch label for the Patch panel and debug traces:
/// `"@<start> -<delete_len> +«<escaped_inserted>»"`. The `inserted` string
/// is run through `escape_for_show` so control characters and the
/// guillemet delimiters don't break the single-line trace alignment.
/// See docs/plans/2026-05-16-show-unification.md.
pub impl Show for SpanEdit with output(self, logger) {
  logger.write_string(
    "@\{self.start} -\{self.delete_len} +«\{escape_for_show(self.inserted)}»",
  )
}

///|
/// Escape a string for inclusion between `«` and `»` delimiters in `Show`
/// output. Backslash-escapes:
/// - delimiters: `\`, `«`, `»`
/// - common whitespace controls: `\n`, `\r`, `\t`
/// - C0 controls (U+0000..U+001F) + DEL (U+007F): `\u{XX}`
/// - C1 controls (U+0080..U+009F, incl. NEL U+0085): `\u{XX}`
/// - line/paragraph separators (U+2028/U+2029): `\u{2028}` / `\u{2029}`
///
/// Other Unicode (BMP letters, emoji, non-BMP) passes through unchanged
/// — this is a display escape, not a wire-format escape.
fn escape_for_show(s : String) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    match ch {
      '\\' => buf.write_string("\\\\")
      '«' => buf.write_string("\\«")
      '»' => buf.write_string("\\»")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ => {
        let code = ch.to_int()
        match code {
          0..<0x20 | 0x7F | 0x80..<0xA0 | 0x2028 | 0x2029 => {
            buf.write_string("\\u{")
            let hex = code.to_string(radix=16)
            if hex.length() < 2 {
              buf.write_char('0')
            }
            buf.write_string(hex)
            buf.write_char('}')
          }
          _ => buf.write_char(ch)
        }
      }
    }
  }
  buf.to_string()
}

///|
/// Hint for where to place the cursor after a structural edit.
/// MoveCursor(position~) uses post-edit coordinates.
pub(all) enum FocusHint {
  RestoreCursor
  MoveCursor(position~ : Int)
} derive(Debug, Eq)

///|
pub impl Show for FocusHint with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
/// Drop position for drag-and-drop and move operations.
pub(all) enum DropPosition {
  /// Insert before the target
  Before
  /// Insert after the target
  After
  /// Insert as a child of the target
  Inside
} derive(Debug, Eq)

///|
/// UI-level tree operations that projection/TreeEditorState understands.
/// Language packages map their domain-specific ops to this type via to_generic().
pub(all) enum GenericTreeOp {
  // Selection
  Select(node_id~ : NodeId)
  SelectRange(start~ : NodeId, end~ : NodeId)

  // Inline editing
  StartEdit(node_id~ : NodeId)
  CommitEdit(node_id~ : NodeId, new_value~ : String)
  CancelEdit

  // Structural (generic)
  Delete(node_id~ : NodeId)
  StructuralEdit(node_id~ : NodeId)
  StructuralEditKeepSelected(node_id~ : NodeId)
  InsertChild(parent~ : NodeId, index~ : Int)

  // Drag and drop
  StartDrag(node_id~ : NodeId)
  DragOver(target~ : NodeId, position~ : DropPosition)
  Drop(source~ : NodeId, target~ : NodeId, position~ : DropPosition)

  // Navigation
  Collapse(node_id~ : NodeId)
  Expand(node_id~ : NodeId)
} derive(Debug)

///|
/// Verb-first label for the Intent panel and debug traces, e.g.
/// `"Drop(#11→#12 After)"`. Node IDs are rendered as `#N` directly
/// (not via `Show for NodeId`, which still emits `"NodeId(N)"`).
/// String payloads (`CommitEdit.new_value`) are escaped via
/// `escape_for_show`. See docs/plans/2026-05-16-show-unification.md.
pub impl Show for GenericTreeOp with output(self, logger) {
  let label = match self {
    Select(node_id~) => "Select(\{node_id.short()})"
    SelectRange(start~, end~) => "SelectRange(\{start.short()}..\{end.short()})"
    StartEdit(node_id~) => "StartEdit(\{node_id.short()})"
    CommitEdit(node_id~, new_value~) =>
      "CommitEdit(\{node_id.short()} «\{escape_for_show(new_value)}»)"
    CancelEdit => "CancelEdit"
    Delete(node_id~) => "Delete(\{node_id.short()})"
    StructuralEdit(node_id~) => "StructuralEdit(\{node_id.short()})"
    StructuralEditKeepSelected(node_id~) =>
      "StructuralEditKeepSelected(\{node_id.short()})"
    InsertChild(parent~, index~) => "InsertChild(\{parent.short()}, \{index})"
    StartDrag(node_id~) => "StartDrag(\{node_id.short()})"
    DragOver(target~, position~) =>
      "DragOver(\{target.short()}, \{drop_position_label(position)})"
    Drop(source~, target~, position~) =>
      "Drop(\{source.short()}→\{target.short()} \{drop_position_label(position)})"
    Collapse(node_id~) => "Collapse(\{node_id.short()})"
    Expand(node_id~) => "Expand(\{node_id.short()})"
  }
  logger.write_string(label)
}

///|
fn drop_position_label(p : DropPosition) -> String {
  match p {
    Before => "Before"
    After => "After"
    Inside => "Inside"
  }
}
