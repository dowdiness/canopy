// Coordinator method bodies — §P0b Phase 1.
// See docs/superpowers/specs/2026-05-24-p0b-phase1-skeleton-design.md §7.

///|
/// Allocates a fresh runtime, claims the single-occupancy `set_on_change`
/// slot (spec §6.1), and constructs an empty registry.
pub fn Coordinator::new() -> Coordinator {
  let runtime = @incr.Runtime::new(on_change=fn() {
    // Phase 1 stub. Pre-populates the §6.1 single-occupancy slot at
    // construction so the runtime always has *some* listener. Callers
    // can still overwrite via `Runtime::set_on_change` — Phase 2 will
    // close that hole by routing all listener registration through a
    // coordinator-owned multiplexer (spec §13 follow-up).

  })
  Coordinator(runtime~)
}

///|
pub fn Coordinator::runtime(self : Coordinator) -> @incr.Runtime {
  self.runtime
}

///|
/// Registers an editor and returns a fresh `EditorId`. Factories must have
/// already created the `Watch` (the GC root) and primed it once.
pub fn Coordinator::register_editor(
  self : Coordinator,
  agent_id : String,
  protected_reads : Array[ProtectedRead],
) -> EditorId {
  // Mode-1 fail-fast: factories MUST call `Derived::watch()` before erasure,
  // which adds a GC root. Reaching this guard means a factory bypass or a
  // `watch.dispose()` ran before registration — a contract violation, not a
  // runtime condition. Spec §13 D4 = ON.
  for p in protected_reads {
    let n = self.runtime.gc_root_count(p.cell_id)
    guard n > 0 else {
      abort(
        "Coordinator::register_editor: protected cell '\{p.label}' has no GC root — factory must call .watch() before erasure",
      )
    }
  }
  let id = self.next_id.val
  self.next_id.val = id + 1
  self.editors.set(id, { agent_id, protected_reads, alive: Ref(true) })
  EditorId(id)
}

///|
/// Idempotently records a `workspace_memo → editor_cell` dep edge owned by
/// `editor_id`. `destroy_editor` refuses while any such edge points at the
/// editor. Phase 1 callers: tests for the destroy gateway. Phase 1b+ callers:
/// workspace memos releasing their own deps on dispose.
pub fn Coordinator::register_dep(
  self : Coordinator,
  workspace_memo : @incr.CellId,
  editor_id : EditorId,
  editor_cell : @incr.CellId,
) -> Unit {
  let entry = match self.deps.get(workspace_memo) {
    Some(arr) => arr
    None => {
      let arr : Array[(EditorId, @incr.CellId)] = []
      self.deps.set(workspace_memo, arr)
      arr
    }
  }
  let edge = (editor_id, editor_cell)
  if !entry.contains(edge) {
    entry.push(edge)
  }
}

///|
/// Idempotent. Removes the edge if present; no-op if absent.
pub fn Coordinator::unregister_dep(
  self : Coordinator,
  workspace_memo : @incr.CellId,
  editor_id : EditorId,
  editor_cell : @incr.CellId,
) -> Unit {
  let entry = match self.deps.get(workspace_memo) {
    Some(e) => e
    None => return
  }
  let edge = (editor_id, editor_cell)
  // `Array::remove` is positional, not by-value; rebuild via filter and
  // write back. Phase 1 dep-counts per workspace memo are small (<10 in
  // any plausible scenario); profile in Phase 2 if this becomes hot.
  let new_entry = entry.filter(fn(e) { e != edge })
  if new_entry.is_empty() {
    self.deps.remove(workspace_memo)
  } else {
    self.deps.set(workspace_memo, new_entry)
  }
}

///|
/// Refuses while workspace deps reference the editor (spec §7, Decision A).
/// On success: flips `alive=false` BEFORE disposing watches so a re-entrant
/// read can never see `alive=true` with disposed watches. Keeps the
/// registration in the map so a stray `read_protected` after destroy still
/// surfaces a full `AbortReport` with `agent_id`.
pub fn Coordinator::destroy_editor(
  self : Coordinator,
  editor_id : EditorId,
) -> Result[Unit, AbortReport] {
  let reg = match self.editors.get(editor_id.0) {
    Some(r) => r
    None =>
      return Err(
        AbortReport(kind=EditorDestroyed, editor_id~, agent_id="<unknown>"),
      )
  }
  guard reg.alive.val else {
    return Err(
      AbortReport(kind=EditorDestroyed, editor_id~, agent_id=reg.agent_id),
    )
  }
  let referring : Array[@incr.CellId] = []
  for ws_memo, edges in self.deps {
    for edge in edges {
      if edge.0 == editor_id {
        referring.push(ws_memo)
      }
    }
  }
  if referring.length() > 0 {
    return Err(
      AbortReport(
        kind=DestroyWhileDependedUpon,
        editor_id~,
        agent_id=reg.agent_id,
        cell_id=referring[0],
      ),
    )
  }
  reg.alive.val = false
  for p in reg.protected_reads {
    (p.dispose)()
  }
  Ok(())
}

///|
/// Validates editor liveness + cell membership + watch liveness, then reads.
/// This is the required gate for exported FFI accessors that consult protected
/// editor state. Direct editor reads are only appropriate where the editor owns
/// the lifecycle invariant or in whitebox tests that intentionally inspect
/// internals; boundary code should use this method and collapse `Err` into that
/// API's existing fail-closed response.
///
/// Cycles propagate to `AbortKind::CycleDetected` with `domain_tag` carrying
/// `CycleError::format_path()`.
pub fn[T] Coordinator::read_protected(
  self : Coordinator,
  editor_id : EditorId,
  cell : ProtectedCell[T],
) -> Result[T, AbortReport] {
  let reg = match self.editors.get(editor_id.0) {
    Some(r) => r
    None =>
      return Err(
        AbortReport(
          kind=EditorDestroyed,
          editor_id~,
          agent_id="<unknown>",
          cell_id=cell.cell_id,
          cell_label=cell.label,
        ),
      )
  }
  guard reg.alive.val else {
    return Err(
      AbortReport(
        kind=EditorDestroyed,
        editor_id~,
        agent_id=reg.agent_id,
        cell_id=cell.cell_id,
        cell_label=cell.label,
      ),
    )
  }
  guard reg.protected_reads.any(fn(p) { p.cell_id == cell.cell_id }) else {
    return Err(
      AbortReport(
        kind=CellNotInProtectedSurface,
        editor_id~,
        agent_id=reg.agent_id,
        cell_id=cell.cell_id,
        cell_label=cell.label,
      ),
    )
  }
  // Defense-in-depth against out-of-band Watch::dispose. Under normal flow,
  // alive=true ⟹ no destroy ran ⟹ no watch disposed. Surfaces a typed
  // AbortReport instead of the underlying Watch::read abort.
  guard !(cell.is_disposed)() else {
    return Err(
      AbortReport(
        kind=ProtectedCellDisposed,
        editor_id~,
        agent_id=reg.agent_id,
        cell_id=cell.cell_id,
        cell_label=cell.label,
      ),
    )
  }
  match (cell.read)() {
    Ok(value) => Ok(value)
    Err(cycle) =>
      Err(
        AbortReport(
          kind=CycleDetected,
          editor_id~,
          agent_id=reg.agent_id,
          cell_id=cell.cell_id,
          cell_label=cell.label,
          domain_tag=cycle.format_path(),
        ),
      )
  }
}
