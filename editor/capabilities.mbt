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
  { get_annotations, get_decorations, pretty_post_process, phantom: None }
}

///|
/// Default capabilities with no language-specific behavior.
pub fn[T] LanguageCapabilities::default() -> LanguageCapabilities[T] {
  {
    get_annotations: None,
    get_decorations: None,
    pretty_post_process: None,
    phantom: None,
  }
}
