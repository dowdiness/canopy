// SyncEditor: Unified facade composing TextDoc + UndoManager + incremental parser.
// Parsing stays edit-aware via ImperativeParser; projection views are memo-derived.

///|
pub struct SyncEditor {
  priv doc : @text.TextDoc
  priv undo : @undo.UndoManager
  priv parser : @loom.ImperativeParser[@parser.SyntaxNode]
  priv parser_rt : @incr.Runtime
  priv source_text : @incr.Signal[String]
  priv syntax_tree : @incr.Signal[@seam.SyntaxNode?]
  priv mut cursor : Int
  priv prev_proj_node : Ref[@proj.ProjNode?]
  priv proj_memo : @incr.Memo[@proj.ProjNode?]
  priv registry_memo : @incr.Memo[Map[@proj.NodeId, @proj.ProjNode]]
  priv source_map_memo : @incr.Memo[@proj.SourceMap]
  priv next_node_id : Ref[Int]
}

///|
pub fn SyncEditor::new(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
) -> SyncEditor {
  let parser = @loom.new_imperative_parser("", @parser.lambda_grammar)
  let parser_rt = @incr.Runtime::new()
  let source_text = @incr.Signal::new(parser_rt, "", label="editor_source_text")
  let syntax_tree = @incr.Signal::new(
    parser_rt,
    None,
    label="editor_syntax_tree",
  )
  let prev_proj_node : Ref[@proj.ProjNode?] = Ref::new(None)
  let next_node_id : Ref[Int] = Ref::new(0)
  let (proj_memo, registry_memo, source_map_memo) = build_projection_memos(
    parser_rt, source_text, syntax_tree, prev_proj_node, next_node_id,
  )
  {
    doc: @text.TextDoc::new(agent_id),
    undo: @undo.UndoManager::new(agent_id, capture_timeout_ms~),
    parser,
    parser_rt,
    source_text,
    syntax_tree,
    cursor: 0,
    prev_proj_node,
    proj_memo,
    registry_memo,
    source_map_memo,
    next_node_id,
  }
}
