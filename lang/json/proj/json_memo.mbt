// Memo builder for JSON projection pipeline.
// Returns 3 memos (no FlatProj) for SyncEditor::new_generic.

///|
pub fn build_json_projection_memos(
  rt : @incr.Runtime,
  _source_text : @incr.Signal[String],
  syntax_tree : @incr.Signal[@seam.SyntaxNode?],
  _parser : @loom.ImperativeParser[@json.JsonValue],
) -> (
  @incr.Memo[ProjNode[@json.JsonValue]?],
  @incr.Memo[Map[NodeId, ProjNode[@json.JsonValue]]],
  @incr.Memo[SourceMap],
) {
  let prev_proj_ref : Ref[ProjNode[@json.JsonValue]?] = Ref::new(None)
  let counter = Ref::new(0)

  let proj_memo : @incr.Memo[ProjNode[@json.JsonValue]?] = @incr.Memo::new_no_backdate(
    rt,
    fn() -> ProjNode[@json.JsonValue]? {
      match syntax_tree.get() {
        None => {
          prev_proj_ref.val = None
          None
        }
        Some(syntax_root) => {
          let new_proj = syntax_to_proj_node(syntax_root, counter)
          let result = match prev_proj_ref.val {
            Some(old) => @core.reconcile(old, new_proj, counter)
            None => new_proj
          }
          prev_proj_ref.val = Some(result)
          Some(result)
        }
      }
    },
    label="json_proj",
  )

  let registry_memo : @incr.Memo[Map[NodeId, ProjNode[@json.JsonValue]]] = @incr.Memo::new_no_backdate(
    rt,
    fn() -> Map[NodeId, ProjNode[@json.JsonValue]] {
      let reg : Map[NodeId, ProjNode[@json.JsonValue]] = {}
      match proj_memo.get() {
        Some(root) => @core.collect_registry(root, reg)
        None => ()
      }
      reg
    },
    label="json_registry",
  )

  let source_map_memo : @incr.Memo[SourceMap] = @incr.Memo::new_no_backdate(
    rt,
    fn() -> SourceMap {
      match (proj_memo.get(), syntax_tree.get()) {
        (Some(root), Some(syntax_root)) => {
          let sm = SourceMap::from_ast(root)
          populate_token_spans(sm, syntax_root, root)
          sm
        }
        _ => SourceMap::new()
      }
    },
    label="json_source_map",
  )

  (proj_memo, registry_memo, source_map_memo)
}
