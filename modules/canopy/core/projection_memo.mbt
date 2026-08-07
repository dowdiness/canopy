///|
using @loomcore {trait TreeNode, trait Renderable}

///|
pub fn[T : TreeNode + Renderable + Eq] build_projection_memos(
  rt : @incr.Runtime,
  syntax_tree : @incr.Derived[@seam.SyntaxNode],
  syntax_to_proj : (@seam.SyntaxNode, Ref[Int]) -> ProjNode[T],
  populate_spans : (SourceMap, @seam.SyntaxNode, ProjNode[T]) -> Unit,
  reconcile_node? : (
    ProjNode[T],
    ProjNode[T],
    Ref[Int],
    Ref[Array[ReconcileTraceEvent]]?,
  ) -> ProjNode[T] = fn(o, n, c, tr) { reconcile(o, n, c, trace_ref=tr) },
  trace_ref? : Ref[Array[ReconcileTraceEvent]]? = None,
  label? : String = "generic",
) -> (
  @incr.Derived[ProjNode[T]?],
  @incr.Derived[Map[NodeId, ProjNode[T]]],
  @incr.Derived[SourceMap],
) {
  let prev_proj_ref : Ref[ProjNode[T]?] = Ref(None)
  let counter : Ref[Int] = Ref(0)

  let proj_memo : @incr.Derived[ProjNode[T]?] = @incr.Derived::Derived(
    rt,
    fn() -> ProjNode[T]? {
      let syntax_root = syntax_tree.get_or_abort()
      let new_proj = syntax_to_proj(syntax_root, counter)
      match trace_ref {
        Some(r) => r.val = []
        None => ()
      }
      let result = match prev_proj_ref.val {
        Some(old) => reconcile_node(old, new_proj, counter, trace_ref)
        None => new_proj
      }
      prev_proj_ref.val = Some(result)
      Some(result)
    },
    label=label + "_proj",
  )

  let registry_memo : @incr.Derived[Map[NodeId, ProjNode[T]]] = @incr.Derived::Derived(
    rt,
    fn() -> Map[NodeId, ProjNode[T]] {
      let reg : Map[NodeId, ProjNode[T]] = Map([])
      match proj_memo.get_or_abort() {
        Some(root) => collect_registry(root, reg)
        None => ()
      }
      reg
    },
    label=label + "_registry",
  )

  let source_map_memo : @incr.Derived[SourceMap] = @incr.Derived::Derived(
    rt,
    fn() -> SourceMap {
      match proj_memo.get_or_abort() {
        Some(root) => {
          let syntax_root = syntax_tree.get_or_abort()
          let sm = SourceMap::from_ast(root)
          populate_spans(sm, syntax_root, root)
          sm
        }
        None => SourceMap::new()
      }
    },
    label=label + "_source_map",
  )

  (proj_memo, registry_memo, source_map_memo)
}

///|
/// Build the standard projection memo stack while consuming framework-owned
/// identity hints at the reconcile boundary.
///
/// This wrapper keeps `IdentityHintConsumer::take_pending` inside `core` and
/// passes an owned hint batch to the language's pure reconcile policy. The
/// existing `build_projection_memos` remains the shallow path for languages
/// and isolated callers that do not use structural identity hints.
pub fn[T : TreeNode + Renderable + Eq] build_projection_memos_with_identity_hints(
  rt : @incr.Runtime,
  syntax_tree : @incr.Derived[@seam.SyntaxNode],
  syntax_to_proj : (@seam.SyntaxNode, Ref[Int]) -> ProjNode[T],
  populate_spans : (SourceMap, @seam.SyntaxNode, ProjNode[T]) -> Unit,
  reconcile_node : (
    ProjNode[T],
    ProjNode[T],
    Ref[Int],
    Array[IdentityTransform],
    Ref[Array[ReconcileTraceEvent]]?,
  ) -> ProjNode[T],
  identity_hints? : IdentityHintConsumer,
  trace_ref? : Ref[Array[ReconcileTraceEvent]]? = None,
  label? : String = "generic",
) -> (
  @incr.Derived[ProjNode[T]?],
  @incr.Derived[Map[NodeId, ProjNode[T]]],
  @incr.Derived[SourceMap],
) {
  build_projection_memos(
    rt,
    syntax_tree,
    syntax_to_proj,
    populate_spans,
    reconcile_node=(old, new_, counter, reconcile_trace) => {
      let hints = match identity_hints {
        Some(consumer) => consumer.take_pending()
        None => []
      }
      reconcile_node(old, new_, counter, hints, reconcile_trace)
    },
    trace_ref~,
    label~,
  )
}
