// Workspace coordinator types — §P0b Phase 1 skeleton.
// See docs/superpowers/specs/2026-05-24-p0b-phase1-skeleton-design.md §6.

///|
pub(all) struct EditorId(Int) derive(Eq, Hash, @debug.Debug)

///|
pub impl Show for EditorId with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub(all) enum AbortKind {
  EditorDestroyed
  DestroyWhileDependedUpon
  CellNotInProtectedSurface
  CycleDetected
  ProtectedCellDisposed
} derive(Eq, @debug.Debug)

///|
pub impl Show for AbortKind with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub(all) struct AbortReport {
  kind : AbortKind
  editor_id : EditorId
  agent_id : String
  cell_id : @incr.CellId?
  cell_label : String?
  domain_tag : String?
} derive(@debug.Debug)

///|
pub impl Show for AbortReport with fn output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
fn AbortReport::AbortReport(
  kind~ : AbortKind,
  editor_id~ : EditorId,
  agent_id~ : String,
  cell_id? : @incr.CellId,
  cell_label? : String,
  domain_tag? : String,
) -> AbortReport {
  { kind, editor_id, agent_id, cell_id, cell_label, domain_tag }
}

///|
pub struct ProtectedRead {
  cell_id : @incr.CellId
  label : String
  is_disposed : () -> Bool
  dispose : () -> Unit
}

///|
fn ProtectedRead::ProtectedRead(
  cell_id~ : @incr.CellId,
  label~ : String,
  is_disposed~ : () -> Bool,
  dispose~ : () -> Unit,
) -> ProtectedRead {
  { cell_id, label, is_disposed, dispose }
}

///|
pub struct ProtectedCell[T] {
  cell_id : @incr.CellId
  label : String
  read : () -> Result[T, @incr.CycleError]
  is_disposed : () -> Bool
  dispose : () -> Unit
}

///|
fn[T] ProtectedCell::ProtectedCell(
  cell_id~ : @incr.CellId,
  label~ : String,
  read~ : () -> Result[T, @incr.CycleError],
  is_disposed~ : () -> Bool,
  dispose~ : () -> Unit,
) -> ProtectedCell[T] {
  { cell_id, label, read, is_disposed, dispose }
}

///|
/// Build a `ProtectedCell` from a `Derived[T]`. Creates a long-lived `Watch`
/// (the GC root) and primes it once so `gc_dependencies` is populated before
/// any `Runtime::gc()` can sweep upstream cells. See spec §6.6.
pub fn[T] ProtectedCell::from_derived(
  label : String,
  d : @incr.Derived[T],
) -> ProtectedCell[T] {
  let watch = d.watch()
  let _ = watch.read()
  ProtectedCell(
    cell_id=d.id(),
    label~,
    read=fn() { watch.read() },
    is_disposed=fn() { watch.is_disposed() },
    dispose=fn() { watch.dispose() },
  )
}

///|
/// Erase the typed read closure, producing a registration-ready record.
pub fn[T] ProtectedCell::erase(self : ProtectedCell[T]) -> ProtectedRead {
  let c = self
  ProtectedRead(
    cell_id=c.cell_id,
    label=c.label,
    is_disposed=c.is_disposed,
    dispose=c.dispose,
  )
}

///|
/// `protected_reads` rather than `protected` — the latter is a reserved
/// MoonBit keyword and rejected by the parser.
priv struct EditorRegistration {
  agent_id : String
  protected_reads : Array[ProtectedRead]
  alive : Ref[Bool]
}

///|
pub struct Coordinator {
  priv runtime : @incr.Runtime
  priv editors : @hashmap.HashMap[Int, EditorRegistration]
  priv deps : @hashmap.HashMap[@incr.CellId, Array[(EditorId, @incr.CellId)]]
  priv next_id : Ref[Int]
}

///|
fn Coordinator::Coordinator(runtime~ : @incr.Runtime) -> Coordinator {
  {
    runtime,
    editors: @hashmap.HashMap([]),
    deps: @hashmap.HashMap([]),
    next_id: Ref(0),
  }
}
