///|
pub struct BenchmarkSession {
  priv mut model : Model
}

///|
fn benchmark_dispatch(_msg : Msg) -> @rabbita.Cmd {
  @rabbita.none
}

///|
fn benchmark_model(source : String) -> Model {
  let editor = @editor.SyncEditor::new_lambda("bench")
  editor.set_text(source)
  {
    editor,
    tree_state: @proj.TreeEditorState::from_projection(
      editor.get_proj_node(),
      editor.get_source_map(),
    ),
    text_view: source,
    workspace_mode: Split,
    diagnostics_open: false,
    peers: [],
    next_timestamp: 1,
    projection_dirty: false,
    refresh_scheduled: false,
  }
}

///|
pub fn BenchmarkSession::new(source : String) -> BenchmarkSession {
  { model: benchmark_model(source) }
}

///|
pub fn BenchmarkSession::legacy_set_text_refresh(
  self : BenchmarkSession,
  new_text : String,
) -> Unit {
  self.model.editor.set_text(new_text)
  self.model = refresh({
    ..self.model,
    text_view: new_text,
    next_timestamp: self.model.next_timestamp + 1,
  })
}

///|
pub fn BenchmarkSession::incremental_eager_refresh(
  self : BenchmarkSession,
  new_text : String,
) -> Unit {
  let splice = @text_change.compute_text_change(
    self.model.editor.get_text(),
    new_text,
  )
  self.model.editor.apply_text_edit(
    splice.start,
    splice.delete_len,
    splice.inserted,
    self.model.next_timestamp,
  )
  self.model = refresh({
    ..self.model,
    text_view: new_text,
    next_timestamp: self.model.next_timestamp + 1,
    projection_dirty: true,
  })
}

///|
pub fn BenchmarkSession::deferred_text_input(
  self : BenchmarkSession,
  new_text : String,
) -> Unit {
  let (_, updated) = update(benchmark_dispatch, TextInput(new_text), self.model)
  self.model = updated
}

///|
pub fn BenchmarkSession::refresh_projection(self : BenchmarkSession) -> Unit {
  let (_, updated) = update(benchmark_dispatch, RefreshProjection, self.model)
  self.model = updated
}

///|
pub fn BenchmarkSession::deferred_full_cycle(
  self : BenchmarkSession,
  new_text : String,
) -> Unit {
  self.deferred_text_input(new_text)
  self.refresh_projection()
}

///|
pub fn BenchmarkSession::has_tree(self : BenchmarkSession) -> Bool {
  self.model.tree_state.tree is Some(_)
}

///|
pub fn BenchmarkSession::projection_dirty(self : BenchmarkSession) -> Bool {
  self.model.projection_dirty
}

///|
pub extern "js" fn now_ms() -> Int =
  #|() => {
  #|  const clock = globalThis.performance?.now?.bind(globalThis.performance);
  #|  return Math.round(clock ? clock() : Date.now());
  #|}

///|
pub(all) struct BenchmarkMeasurement {
  total_ms : Int
  phases : Array[(String, Int)]
}

///|
pub fn BenchmarkSession::deferred_full_cycle_timed(
  self : BenchmarkSession,
  new_text : String,
) -> BenchmarkMeasurement {
  // Phase 1: text input (apply_text_edit via Rabbita update)
  let t0 = now_ms()
  self.deferred_text_input(new_text)
  let t1 = now_ms()
  if not(self.model.projection_dirty) {
    // Match RefreshProjection's no-op behavior when the edit did not dirty
    // the projection, such as identical text input.
    self.refresh_projection()
    let t2 = now_ms()
    return {
      total_ms: t2 - t0,
      phases: [
        ("text_input_ms", t1 - t0),
        ("get_proj_node_ms", 0),
        ("get_source_map_ms", 0),
        ("tree_refresh_ms", 0),
      ],
    }
  }
  // Phase 2: get_proj_node (triggers reactive parse + projection memo)
  let proj_node = self.model.editor.get_proj_node()
  let t2 = now_ms()
  // Phase 3: get_source_map
  let source_map = self.model.editor.get_source_map()
  let t3 = now_ms()
  // Phase 4: tree_refresh
  let text_view = self.model.editor.get_text()
  let tree_state = self.model.tree_state.refresh(proj_node, source_map)
  let t4 = now_ms()
  // Update model (equivalent to refresh() helper)
  self.model = {
    ..self.model,
    text_view,
    tree_state,
    projection_dirty: false,
    refresh_scheduled: false,
  }
  {
    total_ms: t4 - t0,
    phases: [
      ("text_input_ms", t1 - t0),
      ("get_proj_node_ms", t2 - t1),
      ("get_source_map_ms", t3 - t2),
      ("tree_refresh_ms", t4 - t3),
    ],
  }
}
