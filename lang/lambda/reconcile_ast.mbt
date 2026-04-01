// Backward-compat alias: delegates to generic reconcile in framework/core/.

///|
pub using @core {reconcile}

///|
/// Backward-compat alias: delegates to generic reconcile.
pub fn reconcile_ast(
  old : @core.ProjNode[@ast.Term],
  new : @core.ProjNode[@ast.Term],
  counter : Ref[Int],
) -> @core.ProjNode[@ast.Term] {
  @core.reconcile(old, new, counter)
}
