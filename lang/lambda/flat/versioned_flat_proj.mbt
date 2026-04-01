// VersionedFlatProj: wraps FlatProj? with a revision stamp for BackdateEq.
// Lives in lang/lambda/flat/ because it is lambda-specific (holds FlatProj).
// Extracted from editor/projection_memo.mbt to separate framework from language code.

///|
/// Wraps FlatProj? with a revision stamp for O(1) BackdateEq.
/// changed_at only advances when the FlatProj content actually changes.
/// Sequential keystrokes with no AST change leave changed_at stable,
/// causing proj_memo to backdate and skipping cached_proj_node,
/// registry_memo, and source_map_memo recomputation entirely.
///
/// Measured: whitespace-only keystrokes (trivia edits) are ~5–10% faster
/// than content-changing keystrokes at 1000 defs. The remaining cost is
/// dominated by the incremental parse + O(N) to_flat_proj_incremental scan,
/// not the downstream memos. The win grows when heavier downstream
/// consumers (type checking, rendering) are added.
pub(all) struct VersionedFlatProj {
  proj : @lambda_proj.FlatProj?
  changed_at : @incr.Revision
}

///|
pub impl @incr.HasChangedAt for VersionedFlatProj with changed_at(self) -> @incr.Revision {
  self.changed_at
}

///|
pub impl @incr.BackdateEq for VersionedFlatProj
