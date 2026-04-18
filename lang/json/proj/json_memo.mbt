// Memo builder for JSON projection pipeline.
// Returns 3 memos (no FlatProj) for SyncEditor::new_generic.

///|
pub fn build_json_projection_memos(
  parser : @loom.Parser[@json.JsonValue],
) -> (
  @incr.Memo[ProjNode[@json.JsonValue]?],
  @incr.Memo[Map[NodeId, ProjNode[@json.JsonValue]]],
  @incr.Memo[SourceMap],
) {
  @core.build_projection_memos(
    parser.runtime(),
    parser.syntax_tree(),
    syntax_to_proj_node,
    populate_token_spans,
    label="json",
  )
}
