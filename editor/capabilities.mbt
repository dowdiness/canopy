// LanguageCapabilities: closure-based extension points for language-specific
// behavior in the generic view pipeline. Stored in SyncEditor[T].

///|
/// Language-specific callbacks injected into the generic SyncEditor view pipeline.
/// Closures capture language-specific state (e.g. eval memos) internally.
pub struct LanguageCapabilities[T] {
  /// Returns annotations (eval results, type info) keyed by NodeId.
  /// Called by get_view_tree() to overlay semantic data on the structural view.
  get_annotations : (() -> Map[@proj.NodeId, Array[@protocol.ViewAnnotation]])?
  /// Post-processes the pretty-printer layout (e.g. inject eval result suffixes).
  /// Called by get_pretty_view() after the initial layout is built.
  pretty_post_process : ((@pretty.Layout[@pretty.SyntaxCategory]) -> @pretty.Layout[
    @pretty.SyntaxCategory,
  ])?
}

///|
pub fn[T] LanguageCapabilities::new(
  get_annotations? : (() -> Map[@proj.NodeId, Array[@protocol.ViewAnnotation]])? = None,
  pretty_post_process? : ((@pretty.Layout[@pretty.SyntaxCategory]) -> @pretty.Layout[
    @pretty.SyntaxCategory,
  ])? = None,
) -> LanguageCapabilities[T] {
  { get_annotations, pretty_post_process }
}

///|
/// Default capabilities with no language-specific behavior.
pub fn[T] LanguageCapabilities::default() -> LanguageCapabilities[T] {
  { get_annotations: None, pretty_post_process: None }
}
