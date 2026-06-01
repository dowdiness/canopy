// VersionedModuleProjection: wraps ModuleProjection? with a revision stamp.
// Lives in lang/lambda/flat/ because it is lambda-specific (holds ModuleProjection).
// Extracted from editor/projection_memo.mbt to separate framework from language code.

///|
/// Wraps ModuleProjection? with a revision stamp. `changed_at` only advances when
/// the ModuleProjection content actually changes — the `has_changes` gate inside
/// `build_lambda_projection_memos` guards `proj_changed_at_ref.val.next()`.
/// Custom `Eq` compares only `changed_at`, giving O(1) equality semantics
/// matched to `@incr.Derived[T : Eq]`. See `versioned_module_projection_wbtest.mbt`
/// for the proof that `Eq` ignores the `proj` payload.
pub(all) struct VersionedModuleProjection {
  proj : @lambda_proj.ModuleProjection?
  changed_at : @incr.Revision
}

///|
pub impl Eq for VersionedModuleProjection with fn equal(self, other) {
  self.changed_at == other.changed_at
}
