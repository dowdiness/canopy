///| V1 stateful JSX FFI sessions.

///|
/// A session owns all state that can affect projection identity or DOM
/// ownership. The process-global map is only a handle index; every value in
/// it is a complete, session-private ownership record.
priv struct JsxSession {
  parser : @loom.Parser[@jsx_ast.JsxNode]
  proj_memo : @incr.Derived[@canopy_core.ProjNode[@jsx_ast.JsxNode]?]
  registry_memo : @incr.Derived[
    Map[@canopy_core.NodeId, @canopy_core.ProjNode[@jsx_ast.JsxNode]],
  ]
  source_map_memo : @incr.Derived[@canopy_core.SourceMap]
  proj_watch : @incr.Watch[@canopy_core.ProjNode[@jsx_ast.JsxNode]?]
  registry : @js.Any
  root_id : String
  mut committed_source : String
  mut revision : Int
  mut mounted_ids : Array[Int]
  mut last_proj : @canopy_core.ProjNode[@jsx_ast.JsxNode]?
  mut dry_run_model : @jsx_proj.DryRunModel
  mut dirty : Bool
}

///|
let session_registry : Map[Int, JsxSession] = {}

///|
let disposed_session_handles : Map[Int, Bool] = {}

///|
let next_session_handle : Ref[Int] = { val: 1 }

///|
/// The result schema is deliberately JSON at the JS boundary. `mounted_ids`
/// are strings so JavaScript callers never depend on MoonBit's internal
/// integer representation for NodeId.
fn render_result_json(
  success : Bool,
  revision : Int,
  mounted_ids : Array[Int],
  diagnostics : Array[String],
  error : (String, String)?,
) -> String {
  let error_json = match error {
    Some((code, message)) =>
      Json::object({
        "code": Json::string(code),
        "message": Json::string(message),
      })
    None => Json::null()
  }
  Json::object({
    "schema_version": Json::number(1.0),
    "success": Json::boolean(success),
    "revision": Json::number(revision.to_double()),
    "mounted_ids": Json::array(
      mounted_ids.map(id => Json::string(id.to_string())),
    ),
    "diagnostics": Json::array(diagnostics.map(Json::string)),
    "error": error_json,
  }).stringify()
}

///|
fn session_envelope_json(handle : Int?, result_json : String) -> String {
  let result = @js.parse(result_json)
  let envelope = @js.object()
  envelope.set("schema_version", @js.any(1))
  envelope.set("success", result.get("success"))
  match handle {
    Some(value) => envelope.set("handle", @js.any(value.to_string()))
    None => envelope.set("handle", @js.null_())
  }
  envelope.set("result", result)
  envelope.stringify()
}

///|
fn new_jsx_session(source : String, root_id : String) -> JsxSession {
  let parser = @loom.new_parser(source, @jsx_ast.jsx_grammar)
  let (proj_memo, registry_memo, source_map_memo) = @jsx_proj.build_jsx_projection_memos(
    parser,
  )
  let proj_watch = proj_memo.watch()
  {
    parser,
    proj_memo,
    registry_memo,
    source_map_memo,
    proj_watch,
    registry: new_element_registry(),
    root_id,
    committed_source: source,
    revision: 0,
    mounted_ids: [],
    last_proj: None,
    dry_run_model: @jsx_proj.DryRunModel::empty(),
    dirty: false,
  }
}

///|
fn has_mount_boundary_transition(
  old : @canopy_core.ProjNode[@jsx_ast.JsxNode],
  new : @canopy_core.ProjNode[@jsx_ast.JsxNode],
) -> Bool {
  match (old.kind, new.kind) {
    (
      @jsx_ast.JsxNode::Element(tag=old_tag, ..),
      @jsx_ast.JsxNode::Element(tag=new_tag, ..),
    ) => if old_tag != new_tag { return true }
    _ => ()
  }
  let len = old.children.length().min(new.children.length())
  for i in 0..<len {
    if has_mount_boundary_transition(old.children[i], new.children[i]) {
      return true
    }
  }
  false
}

///|
/// Return the parser to the last DOM-committed source after a rejected
/// candidate. The memo may still retain internal speculative work, so the
/// session remains dirty and the next successful render must remount.
fn restore_committed_source(session : JsxSession) -> Unit {
  session.parser.set_source(session.committed_source)
}

///|
fn dispose_jsx_session(session : JsxSession) -> Unit {
  clear_session_registry(session.registry)
  // Dependents must go first. The parser-owned views are then collectable
  // after the session references disappear from the registry.
  session.source_map_memo.dispose()
  session.registry_memo.dispose()
  session.proj_watch.dispose()
  session.proj_memo.dispose()
  session.parser.runtime().gc()
}

///|
fn render_jsx_session(
  session : JsxSession,
  source : String,
  update_source : Bool,
) -> String {
  if update_source {
    session.parser.set_source(source)
  }
  let diagnostics = get_or_empty_errors(source)
  match session.proj_watch.read() {
    Ok(Some(proj)) => {
      let transition = match session.last_proj {
        Some(old) => has_mount_boundary_transition(old, proj)
        None => false
      }
      let remount = session.dirty || transition
      let existing = if remount { [] } else { session.mounted_ids.copy() }
      let (patches, next_mounted_ids) = @jsx_proj.reconcile(proj, existing)
      let dry_run_base = if remount {
        @jsx_proj.DryRunModel::empty()
      } else {
        session.dry_run_model
      }
      match dry_run_base.apply(patches) {
        Err(message) => {
          session.dirty = true
          restore_committed_source(session)
          render_result_json(
            false,
            session.revision,
            session.mounted_ids,
            diagnostics,
            Some(("DryRunError", message)),
          )
        }
        Ok(dry_run_model) => {
          if remount {
            // V1 has no Move/Reparent patch. The supported repair boundary is
            // the root container, which is also the smallest boundary we can
            // safely identify without a committed DOM parent graph.
            //
            // A rejected dry-run must leave the last DOM-committed tree
            // untouched, so clear the old registry only after validation.
            clear_element_registry(session.registry)
          }
          match
            apply_patches_with_registry(
              @jsx_proj.dom_patches_to_json(patches),
              session.root_id,
              session.registry,
            ) {
            Ok(_) => {
              session.revision += 1
              // Reconcile owns the complete reachable-ID set. The DOM shell's
              // result only contains IDs touched by this patch sequence and
              // must not become the next existing-ID baseline.
              session.mounted_ids = next_mounted_ids
              session.last_proj = Some(proj)
              session.dry_run_model = dry_run_model
              session.committed_source = source
              session.dirty = false
              render_result_json(
                true,
                session.revision,
                session.mounted_ids,
                diagnostics,
                None,
              )
            }
            Err(message) => {
              session.dirty = true
              restore_committed_source(session)
              render_result_json(
                false,
                session.revision,
                session.mounted_ids,
                diagnostics,
                Some(("DomApplyError", message)),
              )
            }
          }
        }
      }
    }
    Ok(None) => {
      restore_committed_source(session)
      render_result_json(
        false,
        session.revision,
        session.mounted_ids,
        diagnostics,
        Some(("ProjectionUnavailable", "projection produced no root")),
      )
    }
    Err(_) => {
      restore_committed_source(session)
      render_result_json(
        false,
        session.revision,
        session.mounted_ids,
        diagnostics,
        Some(("ProjectionError", "projection evaluation failed")),
      )
    }
  }
}

///|
fn allocate_session_handle() -> Int {
  let handle = next_session_handle.val
  next_session_handle.val += 1
  handle
}

///|
/// Create a session and perform its initial render. A failed initial render
/// never enters `session_registry` and its partially created DOM is cleaned
/// through the session-owned registry.
pub fn jsx_session_new(source : String, root_id : String) -> String {
  let session = new_jsx_session(source, root_id)
  let result = render_jsx_session(session, source, false)
  let result_value = @js.parse(result)
  if result_value.get("success").cast() {
    let handle = allocate_session_handle()
    session_registry.set(handle, session)
    session_envelope_json(Some(handle), result)
  } else {
    dispose_jsx_session(session)
    session_envelope_json(None, result)
  }
}

///|
/// Render a new source through one live session.
pub fn jsx_session_render(handle : Int, source : String) -> String {
  match session_registry.get(handle) {
    Some(session) => render_jsx_session(session, source, true)
    None => {
      let error = if disposed_session_handles.contains(handle) {
        ("DisposedSession", "session handle has been disposed")
      } else {
        ("InvalidSession", "unknown session handle")
      }
      render_result_json(false, 0, [], [], Some(error))
    }
  }
}

///|
/// Lower one validated candidate through the same dry-run and DOM commit
/// boundary as a regular JSX session render. The base revision is checked
/// before the parser or DOM is touched.
pub fn jsx_session_commit_candidate(
  handle : Int,
  base_revision : @cognition.GenerativeUiRevision,
  candidate : @cognition.GenerativeUiCandidate,
) -> String {
  match session_registry.get(handle) {
    Some(session) => {
      if session.revision != base_revision.to_int() {
        return render_result_json(
          false,
          session.revision,
          session.mounted_ids,
          [],
          Some(
            (
              "BaseRevisionMismatch", "candidate base revision does not match the session revision",
            ),
          ),
        )
      }
      match lower_generative_ui_candidate(candidate) {
        Ok(source) => render_jsx_session(session, source, true)
        Err(message) =>
          render_result_json(
            false,
            session.revision,
            session.mounted_ids,
            [],
            Some(("CandidateLoweringError", message)),
          )
      }
    }
    None => {
      let error = if disposed_session_handles.contains(handle) {
        ("DisposedSession", "session handle has been disposed")
      } else {
        ("InvalidSession", "unknown session handle")
      }
      render_result_json(false, 0, [], [], Some(error))
    }
  }
}

///|
/// Explicit, idempotent session disposal.
pub fn jsx_session_dispose(handle : Int) -> Unit {
  match session_registry.get(handle) {
    Some(session) => {
      dispose_jsx_session(session)
      session_registry.remove(handle)
      disposed_session_handles.set(handle, true)
    }
    None => ()
  }
}

///|
/// Compatibility reset: dispose all stateful sessions. Handles remain
/// monotonically invalidated rather than being recycled into new sessions.
fn reset_all_jsx_sessions() -> Unit {
  let handles = session_registry.keys().to_array()
  for handle in handles {
    jsx_session_dispose(handle)
  }
}
