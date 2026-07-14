///|
using @html {button, div, p, span, text}

///|
using @rabbita {type Cmd, type Emit, type Html, none}

///|
using @sub {type Sub}

///|
/// Parse a node ID string into a NodeId, returning None on invalid input.
fn parse_node_id(s : String) -> @canopy_core.NodeId? {
  let n = @string.parse_int(s) catch { _ => return None }
  Some(@canopy_core.NodeId::from_int(n))
}

///|
fn cm_mount_cmd(emit : Emit[Msg], model : Model) -> Cmd {
  @cm.mount(
    model.cm_id,
    "canopy-text-editor",
    init_doc=model.editor.get_text(),
    source="global:__canopy_codemirror",
    initial_line_wrapping=true,
    on_mounted=emit(CmMounted),
    failed=emit.map(message => {
      ignore(message)
      SyncStatusChanged("error")
    }),
    initial_extension=Some(js_make_ideal_cm_extension),
  )
}

///|
fn sync_after_local_model_change(model : Model, text : String) -> Cmd {
  @rabbita.batch([
    @cm.set_doc(model.cm_id, text),
    @rabbita.effect(fn() { js_after_local_text_edit() }),
  ])
}

///|
fn sync_after_external_crdt_change(model : Model) -> Cmd {
  @cm.set_doc(model.cm_id, model.editor.get_text())
}

///|
fn apply_text_edit(model : Model, text : String) -> (String, Model) {
  model.editor.set_text_and_record(text, js_now_ms())
  let changed = refresh({ ..model, next_timestamp: model.next_timestamp + 1 })
  (changed.editor.get_text(), changed)
}

///|
fn load_text(model : Model, text : String) -> (Cmd, Model) {
  let (actual_text, changed) = apply_text_edit(model, text)
  (sync_after_local_model_change(changed, actual_text), changed)
}

///|
fn select_text_node_cmd(model : Model, node_id : String) -> Cmd {
  match parse_node_id(node_id) {
    None => none
    Some(nid) =>
      match model.editor.get_source_map().get_range(nid) {
        None => none
        Some(range) =>
          @rabbita.batch([
            @cm.set_selection(
              model.cm_id,
              @cm.SelRange::new(range.start, range.end),
              scroll_into_view=true,
            ),
            @rabbita.effect(fn() {
              js_after_cm_selection_changed(range.start, range.end)
            }),
          ])
      }
  }
}

///|
fn select_editor_node_cmd(model : Model, node_id : String) -> Cmd {
  let focus_outline = @rabbita.effect(fn() { js_focus_tree_rows() })
  if model.mode == Text {
    @rabbita.batch([select_text_node_cmd(model, node_id), focus_outline])
  } else {
    @rabbita.effect(fn() {
      js_set_editor_selected_node(node_id)
      js_focus_tree_rows()
    })
  }
}

///|
/// Build scope_map from an editor. Thin wrapper over the pure
/// @scope.build_scope_map that extracts projection data from SyncEditor.
fn build_scope_map_from_editor(
  editor : @editor.SyncEditor[@ast.Term],
) -> Map[@canopy_core.NodeId, @scope.ScopeAnnotation] {
  match editor.get_proj_node() {
    Some(proj_root) =>
      @scope.build_scope_map(
        proj_root,
        editor.get_registry(),
        editor.get_source_map(),
      )
    None => {}
  }
}

///|
fn refresh(model : Model) -> Model {
  js_perf_begin("refreshTotal")
  js_perf_begin("getProjNode")
  let proj_node = model.editor.get_proj_node()
  js_perf_end("getProjNode")
  js_perf_begin("getSourceMap")
  let source_map = model.editor.get_source_map()
  js_perf_end("getSourceMap")
  js_perf_begin("treeEditorRefresh")
  let outline_state = model.outline_state.refresh(proj_node, source_map)
  js_perf_end("treeEditorRefresh")
  // Build scope_map from current projection
  js_perf_begin("buildScopeMap")
  let scope_map = build_scope_map_from_editor(model.editor)
  js_perf_end("buildScopeMap")
  // Recompute highlight_set if a node is selected
  js_perf_begin("computeHighlightSet")
  let highlight_set = highlight_set_for(model.selected_node, scope_map)
  js_perf_end("computeHighlightSet")
  js_perf_end("refreshTotal")
  { ..model, outline_state, scope_map, highlight_set }
}

///|
fn highlight_set_for(
  node_id : String?,
  scope_map : Map[@canopy_core.NodeId, @scope.ScopeAnnotation],
) -> @immut/hashset.HashSet[@canopy_core.NodeId] {
  match node_id {
    Some(value) =>
      match parse_node_id(value) {
        Some(nid) => @scope.compute_highlight_set(nid, scope_map)
        None => @immut/hashset.new()
      }
    None => @immut/hashset.new()
  }
}

///|
fn select_with_highlight(
  model : Model,
  selected_node : String?,
  reset_nav : Bool,
) -> Model {
  let highlight_set = highlight_set_for(selected_node, model.scope_map)
  if reset_nav {
    { ..model, selected_node, highlight_set, nav_path: None }
  } else {
    { ..model, selected_node, highlight_set }
  }
}

///|
/// Check if a tree node has elided children in the outline state.
fn tree_node_is_elided(
  state : @proj.TreeEditorState[@ast.Term],
  node_id : @canopy_core.NodeId,
) -> Bool {
  match state.get_loaded_node(node_id) {
    Some(node) =>
      match node.children {
        @proj.Elided(_) => true
        @proj.Loaded(_) => false
      }
    None => false
  }
}

///|
/// Check if expanding a node should hydrate its elided subtree.
/// Hydration is always allowed since the projection is refreshed
/// immediately on every text change (no stale state possible).
fn can_hydrate_tree_node(model : Model, node_id : @canopy_core.NodeId) -> Bool {
  tree_node_is_elided(model.outline_state, node_id)
}

///|
fn commit_tree_edit(
  model : Model,
  tree_op : @lambda_edits.TreeEditOp,
) -> Result[(Cmd, Model), @editor.TreeEditError] {
  match
    @lambda.apply_lambda_tree_edit(
      model.editor,
      model.companion,
      tree_op,
      js_now_ms(),
    ) {
    Ok(edits) => {
      push_intent(model, tree_op)
      push_patch(model, tree_op, edits)
      let changed = refresh({
        ..model,
        next_timestamp: model.next_timestamp + 1,
      })
      let cmd = sync_after_local_model_change(
        changed,
        changed.editor.get_text(),
      )
      Ok((cmd, changed))
    }
    Err(err) => Err(err)
  }
}
