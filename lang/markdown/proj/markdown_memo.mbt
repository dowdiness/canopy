///| Reactive memo wrapper for Markdown projection.

///|
pub fn build_markdown_projection_memos(
  parser : @loom.Parser[@markdown.Block],
) -> (
  @incr.Memo[@core.ProjNode[@markdown.Block]?],
  @incr.Memo[Map[@core.NodeId, @core.ProjNode[@markdown.Block]]],
  @incr.Memo[@core.SourceMap],
) {
  @core.build_projection_memos(
    parser.runtime(),
    parser.syntax_tree(),
    syntax_to_proj_node,
    populate_token_spans,
    label="markdown",
  )
}
