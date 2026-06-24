// LanguageCapabilities: closure-based extension points for language-specific
// behavior in the generic view pipeline. Stored in SyncEditor[T].

///|
/// Language-specific callbacks injected into the generic SyncEditor view pipeline.
/// Closures capture language-specific state (e.g. eval memos) internally.
pub struct LanguageCapabilities[T] {
  priv get_annotations : (() -> Map[
    @core.NodeId,
    Array[@protocol.ViewAnnotation],
  ])?
  priv get_decorations : (() -> Array[@protocol.Decoration])?
  priv to_view_node : ((
    @core.ProjNode[T],
    @core.SourceMap,
    Map[@core.NodeId, Array[@protocol.ViewAnnotation]],
    String?,
  ) -> @protocol.ViewNode)?
  priv pretty_post_process : ((@pretty.Layout[@pretty.SyntaxCategory]) -> @pretty.Layout[
    @pretty.SyntaxCategory,
  ])?
  priv phantom : T?
}

///|
pub fn[T] LanguageCapabilities::new(
  get_annotations? : (() -> Map[@core.NodeId, Array[@protocol.ViewAnnotation]])? = None,
  get_decorations? : (() -> Array[@protocol.Decoration])? = None,
  pretty_post_process? : ((@pretty.Layout[@pretty.SyntaxCategory]) -> @pretty.Layout[
    @pretty.SyntaxCategory,
  ])? = None,
) -> LanguageCapabilities[T] {
  {
    get_annotations,
    get_decorations,
    to_view_node: None,
    pretty_post_process,
    phantom: None,
  }
}

///|
pub fn[T] LanguageCapabilities::with_to_view_node(
  self : LanguageCapabilities[T],
  to_view_node : (
    @core.ProjNode[T],
    @core.SourceMap,
    Map[@core.NodeId, Array[@protocol.ViewAnnotation]],
    String?,
  ) -> @protocol.ViewNode,
) -> LanguageCapabilities[T] {
  {
    get_annotations: self.get_annotations,
    get_decorations: self.get_decorations,
    to_view_node: Some(to_view_node),
    pretty_post_process: self.pretty_post_process,
    phantom: None,
  }
}

///|
/// Default capabilities with no language-specific behavior.
pub fn[T] LanguageCapabilities::default() -> LanguageCapabilities[T] {
  {
    get_annotations: None,
    get_decorations: None,
    to_view_node: None,
    pretty_post_process: None,
    phantom: None,
  }
}
