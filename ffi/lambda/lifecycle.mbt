// Lambda editor FFI — lifecycle, text I/O, handle registry.
//
// All editor construction funnels through `assemble_lambda_handle` so the
// FFI ctors (`create_editor`, `create_editor_with_undo`) share one
// `@incr.Runtime`, one atomic registration boundary, and one destroy
// gateway. See docs/superpowers/specs/2026-05-24-p0b-phase1-skeleton-design.md
// §8 and docs/superpowers/plans/2026-05-24-p0b-phase1-implementation.md §PR4.

///|
priv struct LambdaHandle {
  editor : @editor.SyncEditor[@ast.Term]
  companion : @lang_lambda.LambdaCompanion
  typecheck : TypecheckBundle
  editor_id : @workspace.EditorId
  cells : LambdaProtectedCells
}

///|
/// Typecheck pipeline cells. `scope` disposal handles owned per-def cells;
/// rooting of `output` is the caller's responsibility — under §P0b Phase 1,
/// `LambdaProtectedCells` constructs the `Watch` via
/// `ProtectedCell::from_derived` (`protected_cells.mbt` `typecheck_output`).
priv struct TypecheckBundle {
  scope : @cells.Scope
  output : @cells.Derived[@typecheck.ModuleTypeResult]
}

///|
fn new_typecheck_bundle(
  rt : @cells.Runtime,
  syntax_tree : @cells.Derived[@seam.SyntaxNode],
) -> TypecheckBundle {
  let scope = @cells.Scope::new(rt)
  let typed_term_memo : @cells.Derived[@typecheck.TypedTerm] = scope.derived(
    fn() { @typecheck.convert_from_cst(syntax_tree.get_or_abort()) },
    label="lambda-typed-term",
  )
  let output = @typecheck.build_typecheck_pipeline(rt, scope, typed_term_memo)
  { scope, output }
}

///|
/// Process-global coordinator. Claimed once. Every FFI ctor goes through
/// `assemble_lambda_handle`, which uses this instance so all editors share
/// the same `@incr.Runtime` and the same atomic registration boundary.
let coordinator : @workspace.Coordinator = @workspace.Coordinator::new()

///|
let lambda_handles : Map[Int, LambdaHandle] = Map::default()

///|
let last_created_handle : Ref[Int?] = { val: None }

///|
/// Build a Lambda editor + companion + typecheck bundle on the shared
/// runtime, then atomically register them with the coordinator. Returns
/// the freshly-allocated `EditorId`. Aborting at any step leaves
/// `lambda_handles` untouched (atomic-boundary observation, spec §8.3).
fn assemble_lambda_handle(
  agent_id : String,
  capture_timeout_ms? : Int = 500,
) -> @workspace.EditorId {
  let (editor, companion) = @lang_lambda.new_lambda_editor(
    agent_id,
    capture_timeout_ms~,
    parent_runtime=coordinator.runtime(),
  )
  let typecheck = new_typecheck_bundle(
    editor.parser_runtime(),
    editor.parser_syntax_tree(),
  )
  let cells = LambdaProtectedCells::LambdaProtectedCells(
    editor, companion, typecheck,
  )
  let editor_id = coordinator.register_editor(
    agent_id,
    cells.to_protected_reads(),
  )
  lambda_handles[editor_id.0] = {
    editor,
    companion,
    typecheck,
    editor_id,
    cells,
  }
  last_created_handle.val = Some(editor_id.0)
  editor_id
}

///|
/// Get the most recently created editor for legacy MoonBit consumers.
pub fn get_sync_editor() -> @editor.SyncEditor[@ast.Term]? {
  match last_created_handle.val {
    Some(handle) =>
      match lambda_handles.get(handle) {
        Some(h) => Some(h.editor)
        None => None
      }
    None => None
  }
}

///|
/// Get the companion for the most recently created lambda editor.
pub fn get_lambda_companion() -> @lang_lambda.LambdaCompanion? {
  match last_created_handle.val {
    Some(handle) =>
      match lambda_handles.get(handle) {
        Some(h) => Some(h.companion)
        None => None
      }
    None => None
  }
}

///|
/// Create a new SyncEditor instance. Returns a unique handle.
pub fn create_editor(agent_id : String) -> Int {
  assemble_lambda_handle(agent_id).0
}

///|
/// Destroy an editor instance and free its resources. The coordinator
/// gateway refuses if workspace deps still reference the editor; in that
/// case the FFI-side bookkeeping (lambda_handles entry, typecheck scope)
/// is intentionally left intact so reads of cached state remain valid.
pub fn destroy_editor(handle : Int) -> Unit {
  let h = match lambda_handles.get(handle) {
    Some(v) => v
    None => return
  }
  match coordinator.destroy_editor(h.editor_id) {
    Ok(_) => ()
    Err(report) => {
      // Phase 1: log + skip teardown so dep references remain valid.
      // Phase 2 surfaces this to JS via a dedicated FFI error channel.
      println("destroy_editor refused: \{report}")
      return
    }
  }
  // Remove FFI-side bookkeeping BEFORE disposing the typecheck scope. If
  // scope.dispose ever raises (e.g., loom-side cleanup defect), the
  // externally-visible state still reflects reality: the handle is gone,
  // subsequent FFI calls on it return the empty/default fallback path. A
  // leaked scope is observable only via incr-level inspection; a leaked
  // lambda_handles entry would be observable as a phantom editor.
  lambda_handles.remove(handle)
  view_states.remove(handle)
  pretty_view_states.remove(handle)
  if last_created_handle.val == Some(handle) {
    last_created_handle.val = None
  }
  h.typecheck.scope.dispose()
}

///|
/// Get current text content
pub fn get_text(handle : Int) -> String {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.get_text()
    None => ""
  }
}

///|
/// Set text content directly (replaces entire document)
pub fn set_text(handle : Int, new_text : String) -> Unit {
  match lambda_handles.get(handle) {
    Some(h) => h.editor.set_text(new_text)
    None => ()
  }
}
