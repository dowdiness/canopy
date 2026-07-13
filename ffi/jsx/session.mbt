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
  mut baseline : SessionBaseline
  mut mounted_ids : Array[Int]
  mut last_proj : @canopy_core.ProjNode[@jsx_ast.JsxNode]?
  mut dry_run_model : @jsx_proj.DryRunModel
}

///|
priv enum SourceProjectionRead {
  Available(@canopy_core.ProjNode[@jsx_ast.JsxNode])
  Unavailable
  Failed
}

///|
let session_registry : Map[Int, JsxSession] = {}

///|
let disposed_session_handles : Map[Int, Bool] = {}

///|
let next_session_handle : Ref[Int] = { val: 1 }

///|
priv struct JsxSessionErrorJson {
  code : String
  message : String
} derive(ToJson)

///|
priv struct JsxSessionResultJson {
  schema_version : Int
  success : Bool
  revision : Int
  mounted_ids : Array[String]
  diagnostics : Array[String]
  error : JsxSessionErrorJson?
}

///|
impl ToJson for JsxSessionResultJson with fn to_json(self) {
  let error_json = match self.error {
    Some(error) => error.to_json()
    None => Json::null()
  }
  Json::object({
    "schema_version": self.schema_version.to_json(),
    "success": self.success.to_json(),
    "revision": self.revision.to_json(),
    "mounted_ids": self.mounted_ids.to_json(),
    "diagnostics": self.diagnostics.to_json(),
    "error": error_json,
  })
}

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
    Some((code, message)) => Some(JsxSessionErrorJson::{ code, message })
    None => None
  }
  JsxSessionResultJson::{
    schema_version: 1,
    success,
    revision,
    mounted_ids: mounted_ids.map(id => id.to_string()),
    diagnostics,
    error: error_json,
  }
  .to_json()
  .stringify()
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
    baseline: SessionBaseline::initial(),
    mounted_ids: [],
    last_proj: None,
    dry_run_model: @jsx_proj.DryRunModel::empty(),
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
/// Return the parser to the last DOM-committed source after a rejected source
/// render. Mounted truth remains in `last_proj`, so projection failure preserves
/// the baseline's existing dirty state.
fn restore_committed_source(session : JsxSession) -> Unit {
  session.parser.set_source(session.committed_source)
}

///|
fn apply_session_baseline_effect(
  session : JsxSession,
  effect : SessionBaselineEffect,
) -> Unit {
  match effect {
    NoEffect => ()
    RestoreCommittedSource => restore_committed_source(session)
  }
}

///|
fn revision_exhausted_result(session : JsxSession) -> String {
  render_result_json(
    false,
    session.baseline.revision,
    session.mounted_ids,
    [],
    Some(("RevisionExhausted", "session revision is exhausted")),
  )
}

///|
fn finish_projection_failure(
  session : JsxSession,
  plan : RenderPlan,
  diagnostics : Array[String],
  code : String,
  message : String,
) -> String {
  let (baseline, effect) = finish_render(plan, ProjectionFail)
  session.baseline = baseline
  apply_session_baseline_effect(session, effect)
  render_result_json(
    false,
    session.baseline.revision,
    session.mounted_ids,
    diagnostics,
    Some((code, message)),
  )
}

///|
fn commit_projection(
  session : JsxSession,
  plan : RenderPlan,
  proj : @canopy_core.ProjNode[@jsx_ast.JsxNode],
  diagnostics : Array[String],
  source_to_commit : String?,
) -> String {
  let existing = if plan.must_remount { [] } else { session.mounted_ids.copy() }
  let (patches, next_mounted_ids) = @jsx_proj.reconcile(proj, existing)
  let dry_run_base = if plan.must_remount {
    @jsx_proj.DryRunModel::empty()
  } else {
    session.dry_run_model
  }
  match dry_run_base.apply(patches) {
    Err(message) => {
      let (baseline, effect) = finish_render(plan, DryRunFail)
      session.baseline = baseline
      apply_session_baseline_effect(session, effect)
      render_result_json(
        false,
        session.baseline.revision,
        session.mounted_ids,
        diagnostics,
        Some(("DryRunError", message)),
      )
    }
    Ok(dry_run_model) => {
      if plan.must_remount {
        clear_element_registry(session.registry)
      }
      match
        apply_patches_with_registry(
          @jsx_proj.dom_patches_to_json(patches),
          session.root_id,
          session.registry,
        ) {
        Ok(_) => {
          let (baseline, effect) = finish_render(plan, Success)
          session.baseline = baseline
          apply_session_baseline_effect(session, effect)
          session.mounted_ids = next_mounted_ids
          session.last_proj = Some(proj)
          session.dry_run_model = dry_run_model
          match source_to_commit {
            Some(source) => session.committed_source = source
            None => ()
          }
          render_result_json(
            true,
            session.baseline.revision,
            session.mounted_ids,
            diagnostics,
            None,
          )
        }
        Err(message) => {
          let (baseline, effect) = finish_render(plan, DomFail)
          session.baseline = baseline
          apply_session_baseline_effect(session, effect)
          render_result_json(
            false,
            session.baseline.revision,
            session.mounted_ids,
            diagnostics,
            Some(("DomApplyError", message)),
          )
        }
      }
    }
  }
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
fn read_source_projection(session : JsxSession) -> SourceProjectionRead {
  match session.proj_watch.read() {
    Ok(Some(proj)) => Available(proj)
    Ok(None) => Unavailable
    Err(_) => Failed
  }
}

///|
fn render_jsx_session_with_projection_read(
  session : JsxSession,
  source : String,
  update_source : Bool,
  projection_read_override? : SourceProjectionRead,
) -> String {
  match begin_render(session.baseline) {
    Err(RevisionExhausted) => revision_exhausted_result(session)
    Ok(permit) => {
      if update_source {
        session.parser.set_source(source)
      }
      let diagnostics = get_or_empty_errors(source)
      let projection_read = match projection_read_override {
        Some(value) => value
        None => read_source_projection(session)
      }
      match projection_read {
        Available(proj) => {
          let transition = match session.last_proj {
            Some(old) => has_mount_boundary_transition(old, proj)
            None => false
          }
          let plan = plan_render(permit, Source, transition)
          commit_projection(session, plan, proj, diagnostics, Some(source))
        }
        Unavailable =>
          finish_projection_failure(
            session,
            plan_render(permit, Source, false),
            diagnostics,
            "ProjectionUnavailable",
            "projection produced no root",
          )
        Failed =>
          finish_projection_failure(
            session,
            plan_render(permit, Source, false),
            diagnostics,
            "ProjectionError",
            "projection evaluation failed",
          )
      }
    }
  }
}

///|
fn render_jsx_session(
  session : JsxSession,
  source : String,
  update_source : Bool,
) -> String {
  render_jsx_session_with_projection_read(session, source, update_source)
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
      if session.baseline.revision != base_revision.to_int() {
        return render_result_json(
          false,
          session.baseline.revision,
          session.mounted_ids,
          [],
          Some(
            (
              "BaseRevisionMismatch", "candidate base revision does not match the session revision",
            ),
          ),
        )
      }
      match begin_render(session.baseline) {
        Err(RevisionExhausted) => revision_exhausted_result(session)
        Ok(permit) => {
          let projection = candidate_to_projection(candidate)
          let plan = plan_render(permit, Candidate, false)
          commit_projection(session, plan, projection, [], None)
        }
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
