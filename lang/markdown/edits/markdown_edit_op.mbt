///| Edit operations for the Markdown block editor.

///|
using @core {
  type NodeId,
  type ProjNode,
  type SourceMap,
  type SpanEdit,
  type FocusHint,
}

///|
pub(all) enum MarkdownEditOp {
  CommitEdit(node_id~ : NodeId, new_text~ : String)
  ChangeHeadingLevel(node_id~ : NodeId, level~ : Int)
  ToggleListItem(node_id~ : NodeId)
  Delete(node_id~ : NodeId)
  InsertBlockAfter(node_id~ : NodeId)
  SplitBlock(node_id~ : NodeId, offset~ : Int)
  MergeWithPrevious(node_id~ : NodeId)
} derive(Show, Eq)
