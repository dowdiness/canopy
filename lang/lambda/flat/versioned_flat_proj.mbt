// VersionedFlatProj: wraps FlatProj? with a revision stamp.
// Lives in lang/lambda/flat/ because it is lambda-specific (holds FlatProj).
// Extracted from editor/projection_memo.mbt to separate framework from language code.

///|
/// Wraps FlatProj? with a revision stamp. `changed_at` only advances when
/// the FlatProj content actually changes (proven in projection_memo.mbt
/// where `has_changes` gates `proj_changed_at_ref.val.next()` at
/// line 110-112). Custom `Eq` compares only `changed_at`, giving O(1)
/// equality semantics matched to `@incr.Derived[T : Eq]`.
pub(all) struct VersionedFlatProj {
  proj : @lambda_proj.FlatProj?
  changed_at : @incr.Revision
}

///|
pub impl Eq for VersionedFlatProj with fn equal(self, other) {
  self.changed_at == other.changed_at
}
