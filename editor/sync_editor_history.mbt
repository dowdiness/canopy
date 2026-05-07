///| History-view accessors on `SyncEditor`.
///
/// Surfaces the egw `CausalSnapshot` and a process-local construction
/// identity so callers can walk the document's causal DAG and memoize
/// derived views (e.g. the upcoming canopy "causal graph history" panel).

///|
/// Process-local counter for `SyncEditor` construction identities. Single
/// counter shared across all `T`. Single-threaded under the MoonBit
/// web/native runtime; if multi-thread editor construction is ever added,
/// this must be made atomic.
let editor_identity_counter : Ref[Int] = { val: 0 }

///|
/// Allocate the next construction identity. Called once per
/// `SyncEditor::new_generic`.
fn next_editor_identity() -> Int {
  let id = editor_identity_counter.val
  editor_identity_counter.val = id + 1
  id
}

///|
/// Read-only view of the document's causal DAG. The returned snapshot is a
/// live alias over the underlying egw `Document` — it reflects subsequent
/// edits made through this `SyncEditor`. See `@history.CausalSnapshot` for
/// the available accessors.
pub fn[T] SyncEditor::causal_snapshot(
  self : SyncEditor[T],
) -> @history.CausalSnapshot {
  self.doc.causal_snapshot()
}

///|
/// Process-local construction identity for this `SyncEditor`. Stable for
/// the lifetime of the instance; distinct across separately-constructed
/// instances. Suitable as part of a cache key for derived views (e.g.
/// `(editor.identity(), snapshot.op_count())` for an append-only history
/// memo).
pub fn[T] SyncEditor::identity(self : SyncEditor[T]) -> Int {
  self.identity
}
