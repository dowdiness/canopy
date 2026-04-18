///|
using @loomcore {trait TreeNode}

///|
pub fn[T : TreeNode] build_projection_memos(
  rt : @incr.Runtime,
  syntax_tree : @incr.Memo[@seam.SyntaxNode?],
  syntax_to_proj : (@seam.SyntaxNode, Ref[Int]) -> ProjNode[T],
  populate_spans : (SourceMap, @seam.SyntaxNode, ProjNode[T]) -> Unit,
  label? : String = "generic",
) -> (
  @incr.Memo[ProjNode[T]?],
  @incr.Memo[Map[NodeId, ProjNode[T]]],
  @incr.Memo[SourceMap],
) {
  let prev_proj_ref : Ref[ProjNode[T]?] = Ref::new(None)
  let counter : Ref[Int] = Ref::new(0)

  let proj_memo : @incr.Memo[ProjNode[T]?] = @incr.Memo::new_no_backdate(
    rt,
    fn() -> ProjNode[T]? {
      match syntax_tree.get() {
        None => {
          prev_proj_ref.val = None
          None
        }
        Some(syntax_root) => {
          let new_proj = syntax_to_proj(syntax_root, counter)
          let result = match prev_proj_ref.val {
            Some(old) => reconcile(old, new_proj, counter)
            None => new_proj
          }
          prev_proj_ref.val = Some(result)
          Some(result)
        }
      }
    },
    label=label + "_proj",
  )

  let registry_memo : @incr.Memo[Map[NodeId, ProjNode[T]]] = @incr.Memo::new_no_backdate(
    rt,
    fn() -> Map[NodeId, ProjNode[T]] {
      let reg : Map[NodeId, ProjNode[T]] = {}
      match proj_memo.get() {
        Some(root) => collect_registry(root, reg)
        None => ()
      }
      reg
    },
    label=label + "_registry",
  )

  let source_map_memo : @incr.Memo[SourceMap] = @incr.Memo::new_no_backdate(
    rt,
    fn() -> SourceMap {
      match (proj_memo.get(), syntax_tree.get()) {
        (Some(root), Some(syntax_root)) => {
          let sm = SourceMap::from_ast(root)
          populate_spans(sm, syntax_root, root)
          sm
        }
        _ => SourceMap::new()
      }
    },
    label=label + "_source_map",
  )

  (proj_memo, registry_memo, source_map_memo)
}
