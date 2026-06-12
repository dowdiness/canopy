// S4 host-binding registry shared by ffi/{lambda,json,markdown}. Owns only
// generic per-handle bookkeeping: the handle map keyed by the exported
// integer handle, the per-handle ordinary view-update state, and the
// coordinator destroy gateway. Language-specific state (protected-cell
// bundles, companions, pretty view states, last-created tracking) stays in
// each ffi/<L> package. See docs/plans/2026-06-12-s4-ffi-host-extraction.md.

///|
/// Generic FFI handle registry: handle bookkeeping plus per-handle ordinary
/// view-update state, with the coordinator destroy gateway routed through
/// one shared implementation. Fields are private; mutation goes through
/// owning-package methods. Production teardown must use `destroy` (the
/// coordinator-gated path); `remove`/`clear` deliberately bypass the
/// gateway and exist for whitebox-test drains after a direct coordinator
/// destroy.
pub struct HostRegistry[H] {
  priv handles : Map[Int, H]
  priv view_states : Map[Int, @editor.ViewUpdateState]
}

///|
pub fn[H] HostRegistry::HostRegistry() -> HostRegistry[H] {
  { handles: Map::default(), view_states: Map::default() }
}

///|
/// Register a handle under its exported integer id.
pub fn[H] HostRegistry::insert(
  self : HostRegistry[H],
  id : Int,
  handle : H,
) -> Unit {
  self.handles[id] = handle
}

///|
pub fn[H] HostRegistry::get(self : HostRegistry[H], id : Int) -> H? {
  self.handles.get(id)
}

///|
pub fn[H] HostRegistry::contains(self : HostRegistry[H], id : Int) -> Bool {
  self.handles.contains(id)
}

///|
/// Number of registered handles.
pub fn[H] HostRegistry::size(self : HostRegistry[H]) -> Int {
  self.handles.length()
}

///|
/// Remove a handle's FFI bookkeeping (handle entry and its ordinary
/// view-update state). Does NOT consult the coordinator — use `destroy`
/// for the gated teardown path. Exists for whitebox test drains that
/// destroy through the coordinator directly.
pub fn[H] HostRegistry::remove(self : HostRegistry[H], id : Int) -> Unit {
  self.handles.remove(id)
  self.view_states.remove(id)
}

///|
/// Clear all bookkeeping. Test-reset helper for whitebox tests that need a
/// clean per-package registry between cases.
pub fn[H] HostRegistry::clear(self : HostRegistry[H]) -> Unit {
  self.handles.clear()
  self.view_states.clear()
}

///|
/// Get-or-create the ordinary view-update state for a handle. Callers are
/// expected to have validated the handle (`get`/`contains`) first; creating
/// a state for an unregistered id would leak until `clear`.
pub fn[H] HostRegistry::view_state(
  self : HostRegistry[H],
  id : Int,
) -> @editor.ViewUpdateState {
  self.view_states.get_or_init(id, () => {
    @editor.ViewUpdateState::ViewUpdateState()
  })
}

///|
/// Destroy gateway: route teardown through `Coordinator::destroy_editor`.
/// On refusal the FFI-side bookkeeping is intentionally left intact so
/// reads of cached state remain valid; on success the handle entry and its
/// ordinary view state are removed. The bookkeeping key is derived from
/// `editor_id.0` — every language package registers handles under that
/// integer, so taking it as a separate parameter would only invite a
/// mismatched pair. Returns true when teardown proceeded, so language
/// packages can remove their language-local extras afterwards.
pub fn[H] HostRegistry::destroy(
  self : HostRegistry[H],
  coordinator : @workspace.Coordinator,
  editor_id : @workspace.EditorId,
  label : String,
) -> Bool {
  match coordinator.destroy_editor(editor_id) {
    Ok(_) => {
      self.remove(editor_id.0)
      true
    }
    Err(report) => {
      println("\{label} refused: \{report}")
      false
    }
  }
}
