///|
using @overlay {type OverlayMode, format_overlay_error}

// Whitebox tests for update helpers.

///|
fn test_actions() -> Array[@lambda_edits.Action] {
  @lambda_edits.get_actions_for_node(
    @ast.Term::Unit,
    @lambda_edits.NodeContext::new(),
  )
}

///|
fn test_action_by_id(id : String) -> @lambda_edits.Action {
  test_actions().iter().find_first(fn(action) { action.id == id }).unwrap()
}

///|
fn test_overlay_context() -> @lambda_edits.ActionContext {
  {
    node_id: @canopy_core.NodeId::from_int(1),
    kind: @ast.Term::Unit,
    is_let_binding: false,
    binding_node_id: None,
    binding_def_index: None,
    module_node_id: None,
  }
}

///|
fn test_overlay_state(mode : OverlayMode) -> OverlayState {
  let actions = test_actions()
  OverlayState::OverlayState(
    mode~,
    actions~,
    kind=@ast.Term::Unit,
    error=None,
    anchor_top=0,
    anchor_left=0,
    menu=@menu.Model::new(
      id="ideal-action-overlay-menu-test",
      item_count=actions.length(),
    ),
  )
}

///|
fn test_parent_emit() -> @rabbita.Emit[Msg] {
  _ => @rabbita.none
}

///|
test "overlay update dispatches main menu mnemonic action" {
  let delete_action = test_action_by_id("delete")
  let result = test_overlay_state(MainMenu).update(KeyPressed("d"))
  match result.effect {
    ExecuteAction(action, choice~, name~) => {
      inspect(action.id, content="delete")
      inspect(choice, content="")
      inspect(name, content="")
    }
    _ => inspect("unexpected", content="ExecuteAction")
  }
  match result.state.overlay_mode() {
    MainMenu => inspect("main", content="main")
    _ => inspect("unexpected", content="MainMenu")
  }
  inspect(delete_action.id, content="delete")
}

///|
test "overlay update dispatches valid submenu numbered choice" {
  let wrap_bop_action = test_action_by_id("wrap_bop")
  let result = test_overlay_state(Submenu(wrap_bop_action)).update(
    Menu(@menu.Activate(0)),
  )
  match result.effect {
    ExecuteAction(action, choice~, name~) => {
      inspect(action.id, content="wrap_bop")
      inspect(choice, content="Plus")
      inspect(name, content="")
    }
    _ => inspect("unexpected", content="ExecuteAction")
  }
}

///|
test "overlay update recovers invalid submenu key to focused main menu" {
  let wrap_bop_action = test_action_by_id("wrap_bop")
  let result = test_overlay_state(Submenu(wrap_bop_action)).update(
    KeyPressed("z"),
  )
  match result.state.overlay_mode() {
    MainMenu => inspect("main", content="main")
    _ => inspect("unexpected", content="MainMenu")
  }
  match result.effect {
    FocusMenu => inspect("focus", content="focus")
    _ => inspect("unexpected", content="FocusMenu")
  }
  inspect(result.state.overlay_error() is None, content="true")
}

///|
test "overlay public key event preserves submenu invalid-key recovery" {
  let wrap_bop_action = test_action_by_id("wrap_bop")
  let result = test_overlay_state(Submenu(wrap_bop_action)).update(
    OverlayKeyPressed("z").to_overlay_msg(),
  )
  match result.state.overlay_mode() {
    MainMenu => inspect("main", content="main")
    _ => inspect("unexpected", content="MainMenu")
  }
  match result.effect {
    FocusMenu => inspect("focus", content="focus")
    _ => inspect("unexpected", content="FocusMenu")
  }
}

///|
test "overlay update keeps empty name submit in prompt with error" {
  let wrap_lambda_action = test_action_by_id("wrap_lambda")
  let state = test_overlay_state(NamePrompt(wrap_lambda_action, value="stale"))
  let input_result = state.update(NameInput(""))
  let result = input_result.state.update(NameSubmit)
  match result.effect {
    NoOverlayEffect => inspect("none", content="none")
    _ => inspect("unexpected", content="NoOverlayEffect")
  }
  match result.state.overlay_mode() {
    NamePrompt(action, value~) => {
      inspect(action.id, content="wrap_lambda")
      inspect(value, content="")
    }
    _ => inspect("unexpected", content="NamePrompt")
  }
  inspect(result.state.overlay_error() is Some(EmptyName), content="true")
}

///|
test "overlay update whitespace input does not clear error" {
  let wrap_lambda_action = test_action_by_id("wrap_lambda")
  let state_with_error = test_overlay_state(
      NamePrompt(wrap_lambda_action, value=""),
    ).update(NameSubmit).state
  inspect(state_with_error.overlay_error() is Some(EmptyName), content="true")
  let result = state_with_error.update(NameInput(" "))
  inspect(result.state.overlay_error() is Some(EmptyName), content="true")
}

///|
test "overlay update non-empty input clears error" {
  let wrap_lambda_action = test_action_by_id("wrap_lambda")
  let state_with_error = test_overlay_state(
      NamePrompt(wrap_lambda_action, value=""),
    ).update(NameSubmit).state
  let result = state_with_error.update(NameInput("x"))
  inspect(result.state.overlay_error() is None, content="true")
}

///|
test "overlay update name cancel closes overlay" {
  let wrap_lambda_action = test_action_by_id("wrap_lambda")
  let result = test_overlay_state(NamePrompt(wrap_lambda_action, value="x")).update(
    NameCancel,
  )
  match result.effect {
    CloseOverlay => inspect("close", content="close")
    _ => inspect("unexpected", content="CloseOverlay")
  }
}

///|
test "overlay outputs only match their originating parent token" {
  let host = ActionOverlayHost::empty().mount(
    test_overlay_context(),
    test_overlay_state(MainMenu),
  )
  inspect(host.active_for_token(1) is Some(_), content="true")
  inspect(host.active_for_token(2) is None, content="true")
}

///|
test "overlay close effects use the active parent token" {
  let host = ActionOverlayHost::empty().mount(
    test_overlay_context(),
    test_overlay_state(MainMenu),
  )
  inspect(host.active_for_token(1) is Some(_), content="true")
  inspect(host.active_for_token(2) is None, content="true")
}

///|
test "mount sets context and state on host" {
  let ctx = test_overlay_context()
  let host = ActionOverlayHost::empty().mount(ctx, test_overlay_state(MainMenu))
  inspect(host.active is Some(_), content="true")
}

///|
test "root init starts with closed overlay and first runtime token" {
  let model = init_model()
  inspect(model.overlay.active is None, content="true")
  inspect(model.overlay.next_token, content="1")
  inspect(model.mounted, content="false")
  inspect(model.cm_id, content="canopy-text-editor")
  inspect(model.mode is Text, content="true")
  inspect(model.sync_status is Connecting, content="true")
}

///|
test "root reactive wrapper distinguishes adjacent updates" {
  let model = init_model()
  let state = RootState(model, 0)
  inspect(state == state, content="true")
  let (next, _) = root_update(
    test_parent_emit(),
    OutlineNavigate("not-a-node-id"),
    state,
  )
  inspect(state == next, content="false")
  inspect(next.1, content="1")
}

///|
test "root revision advances and wraps explicitly" {
  inspect(next_root_revision(0), content="1")
  inspect(next_root_revision(ROOT_REVISION_MAX), content="0")
}

///|
test "overlay host close clears active runtime without advancing token" {
  let host = ActionOverlayHost::empty().mount(
    test_overlay_context(),
    test_overlay_state(MainMenu),
  )
  inspect(host.active is Some(_), content="true")
  inspect(host.next_token, content="2")
  let closed = host.close()
  inspect(closed.active is None, content="true")
  inspect(closed.next_token, content="2")
}

///|
test "parent close output closes only the active overlay runtime" {
  let model = init_model()
  let model = {
    ..model,
    overlay: model.overlay.mount(
      test_overlay_context(),
      test_overlay_state(MainMenu),
    ),
  }
  let (_, changed) = handle_overlay_output(
    model,
    1,
    OverlayOutput::CloseOverlay,
  )
  inspect(changed.overlay.active is None, content="true")
  inspect(changed.overlay.next_token, content="2")
}

///|
test "parent rejects stale output after close and reopen" {
  let model = init_model()
  let reopened = {
    ..model,
    overlay: ActionOverlayHost::empty()
    .mount(test_overlay_context(), test_overlay_state(MainMenu))
    .close()
    .mount(test_overlay_context(), test_overlay_state(MainMenu)),
  }
  let (_, stale_closed) = handle_overlay_output(
    reopened,
    1,
    OverlayOutput::CloseOverlay,
  )
  inspect(stale_closed.overlay.active is Some(_), content="true")
  inspect(stale_closed.overlay.next_token, content="3")
  let (_, current_closed) = handle_overlay_output(
    stale_closed,
    2,
    OverlayOutput::CloseOverlay,
  )
  inspect(current_closed.overlay.active is None, content="true")
  inspect(current_closed.overlay.next_token, content="3")
}

///|
test "parent rejects stale overlay message after close and reopen" {
  let model = init_model()
  let reopened = {
    ..model,
    overlay: ActionOverlayHost::empty()
    .mount(test_overlay_context(), test_overlay_state(MainMenu))
    .close()
    .mount(test_overlay_context(), test_overlay_state(MainMenu)),
  }
  let (_, changed) = handle_overlay_msg(
    test_parent_emit(),
    1,
    SetError(ApplyActionFailed("stale")),
    reopened,
  )
  match changed.overlay.active {
    Some((_, state, token)) => {
      inspect(token, content="2")
      inspect(state.overlay_error() is None, content="true")
    }
    None => inspect("closed", content="active")
  }
}

///|
test "parse_node_id valid" {
  inspect(parse_node_id("42") is Some(_), content="true")
}

///|
test "parse_node_id invalid returns None" {
  inspect(parse_node_id("abc") is None, content="true")
  inspect(parse_node_id("") is None, content="true")
}

///|
test "graphviz parse errors escape HTML details" {
  let dot = "digraph { a -> b } extra"
  match @gv_parser.parse_dot(dot) {
    Err(error) =>
      @debug.assert_eq(
        render_dot_to_svg(dot),
        render_graphviz_parse_error(error.position, error.message),
      )
    Ok(_) => fail("expected malformed Graphviz input")
  }
  @debug.assert_eq(
    render_graphviz_parse_error(3, "<script>&\""),
    "<span class=\"problem-text\">Parse error at 3: &lt;script&gt;&amp;&quot;</span>",
  )
}

///|
test "event_detail_node_id extracts nodeId from object detail" {
  inspect(event_detail_node_id("{\"nodeId\":\"42\"}"), content="42")
}

///|
test "event_detail_node_id accepts string detail fallback" {
  inspect(event_detail_node_id("42"), content="42")
}

///|
test "event_detail_node_id rejects unrelated detail" {
  inspect(event_detail_node_id("{\"other\":\"42\"}"), content="")
}

///|
test "event_detail_status extracts status from object detail" {
  inspect(
    event_detail_status("{\"status\":\"connected\"}"),
    content="connected",
  )
}

///|
test "event_detail_status accepts string detail fallback" {
  inspect(event_detail_status("error"), content="error")
}

///|
test "event_detail_status rejects unrelated detail" {
  inspect(event_detail_status("{\"other\":\"connected\"}"), content="")
}

///|
test "event_detail_structural_edit extracts op and nodeId" {
  let (op, node_id) = event_detail_structural_edit(
    "{\"op\":\"Drop\",\"nodeId\":\"7\"}",
  )
  inspect(op, content="Drop")
  inspect(node_id, content="7")
}

///|
test "event_detail_structural_edit rejects incomplete detail" {
  let (op, node_id) = event_detail_structural_edit("{\"op\":\"Drop\"}")
  inspect(op, content="Drop")
  inspect(node_id, content="")
}

///|
test "event_detail_structural_edit rejects non-object detail" {
  let (op, node_id) = event_detail_structural_edit("Drop")
  inspect(op, content="")
  inspect(node_id, content="")
}

///|
test "event target selector is centralized" {
  inspect(EditorHost.selector(), content="#canopy-editor")
  inspect(TextEditor.selector(), content="#canopy-text-editor")
}

///|
test "event names are centralized" {
  inspect(ActionOverlayOpen.event_type(), content="action-overlay-open")
  inspect(ActionKey.event_type(), content="action-key")
  inspect(ExternalCrdtChange.event_type(), content="external-crdt-changed")
  inspect(LongPress.event_type(), content="long-press")
  inspect(NodeSelected.event_type(), content="node-selected")
  inspect(RequestUndo.event_type(), content="request-undo")
  inspect(RequestRedo.event_type(), content="request-redo")
  inspect(StructuralEditApplied.event_type(), content="structural-edit-applied")
  inspect(SyncStatus.event_type(), content="sync-status")
}

///|
test "dom event subscription error message includes context" {
  inspect(
    dom_event_subscription_error_message(
      EditorHost,
      ActionKey,
      "document is unavailable",
    ),
    content="[canopy] failed to install DOM event subscription target=editor-host event=action-key: document is unavailable",
  )
}

// ── OverlayError typed-error tests ───────────────────────────────────────────

///|
test "overlay error: SetError(BuildActionFailed) stores typed variant" {
  let result = test_overlay_state(MainMenu).update(
    SetError(BuildActionFailed("bad op")),
  )
  inspect(
    result.state.overlay_error() is Some(BuildActionFailed("bad op")),
    content="true",
  )
  match result.effect {
    NoOverlayEffect => ()
    _ => inspect("unexpected", content="NoOverlayEffect")
  }
}

///|
test "overlay error: SetError(ApplyActionFailed) stores typed variant" {
  let result = test_overlay_state(MainMenu).update(
    SetError(ApplyActionFailed("apply failed")),
  )
  inspect(
    result.state.overlay_error() is Some(ApplyActionFailed("apply failed")),
    content="true",
  )
}

///|
test "overlay error: cleared on name prompt open" {
  let wrap_lambda_action = test_action_by_id("wrap_lambda")
  let state_with_error = test_overlay_state(MainMenu).update(
      SetError(EmptyName),
    ).state
  let result = state_with_error.update(ShowNamePrompt(wrap_lambda_action))
  inspect(result.state.overlay_error() is None, content="true")
  inspect(result.state.overlay_mode() is NamePrompt(_, ..), content="true")
  match result.effect {
    FocusNamePrompt => inspect("focus", content="focus")
    _ => inspect("unexpected", content="FocusNamePrompt")
  }
}

///|
test "overlay error: cleared on submenu open" {
  let wrap_bop_action = test_action_by_id("wrap_bop")
  let state_with_error = test_overlay_state(MainMenu).update(
      SetError(EmptyName),
    ).state
  let choices = state_with_error.submenu_choices(wrap_bop_action)
  let result = state_with_error.open_submenu(wrap_bop_action, choices.length())
  inspect(result.state.overlay_error() is None, content="true")
  inspect(result.state.overlay_mode() is Submenu(_), content="true")
}

///|
test "overlay error: cleared on main menu reset (close_submenu)" {
  let wrap_bop_action = test_action_by_id("wrap_bop")
  let state_with_error = test_overlay_state(Submenu(wrap_bop_action)).update(
      SetError(ApplyActionFailed("stale")),
    ).state
  let result = state_with_error.close_submenu()
  inspect(result.state.overlay_error() is None, content="true")
  inspect(result.state.overlay_mode() is MainMenu, content="true")
}

///|
test "format_overlay_error: EmptyName" {
  inspect(format_overlay_error(EmptyName), content="Enter a name to continue")
}

///|
test "format_overlay_error: BuildActionFailed carries message" {
  inspect(
    format_overlay_error(BuildActionFailed("bad op")),
    content="Build failed: bad op",
  )
}

///|
test "format_overlay_error: ApplyActionFailed carries message" {
  inspect(
    format_overlay_error(ApplyActionFailed("apply failed")),
    content="Apply failed: apply failed",
  )
}

///|
fn selected_test_model() -> (Model, String) raise {
  let model = init_model()
  let node_id = model.scope_map
    .keys()
    .to_array()
    .iter()
    .find_first(nid => {
      !@scope.compute_highlight_set(nid, model.scope_map).is_empty()
    })
    .unwrap()
  let range = model.editor.get_source_map().get_range(node_id).unwrap()
  model.editor.move_cursor(range.start)
  (model, node_id_to_string(node_id))
}

///|
test "select_with_highlight obeys its explicit reset_nav policy" {
  let (model, node_id) = selected_test_model()
  model.nav_path = Some([0])
  let preserved = select_with_highlight(model, Some(node_id), false)
  inspect(preserved.highlight_set.is_empty(), content="false")
  @debug.assert_eq(preserved.nav_path, Some([0]))
  let reset = select_with_highlight(model, Some(node_id), true)
  inspect(reset.nav_path is None, content="true")
}

///|
test "load_text records text and advances the edit timestamp" {
  let model = init_model()
  let before = model.next_timestamp
  let (_, changed) = load_text(model, "fn loaded() { 42 }")
  inspect(changed.editor.get_text(), content="fn loaded() { 42 }")
  inspect(changed.next_timestamp, content="\{before + 1}")
}

///|
test "commit_tree_edit returns the committed model" {
  let (model, node_id) = selected_test_model()
  let op = @lambda_edits.TreeEditOp::Select(
    node_id=parse_node_id(node_id).unwrap(),
  )
  match commit_tree_edit(model, op) {
    Ok((_, changed)) =>
      inspect(changed.next_timestamp, content="\{model.next_timestamp + 1}")
    Err(err) => abort(err.message())
  }
}

///|
test "selection characterization: refresh recomputes selected highlight" {
  let (model, node_id) = selected_test_model()
  let refreshed = refresh({ ..model, selected_node: Some(node_id) })
  inspect(refreshed.highlight_set.is_empty(), content="false")
}

///|
test "selection characterization: outline click selects highlights and clears nav" {
  let (model, node_id) = selected_test_model()
  model.nav_path = Some([0])
  match handle_outline(test_parent_emit(), OutlineNodeClicked(node_id), model) {
    Some((_, changed)) => {
      inspect(changed.selected_node == Some(node_id), content="true")
      inspect(changed.highlight_set.is_empty(), content="false")
      inspect(changed.nav_path is None, content="true")
    }
    None => abort("OutlineNodeClicked was not handled")
  }
}

///|
test "selection characterization: outline navigation preserves nav cache" {
  let (model, node_id) = selected_test_model()
  model.nav_path = Some([0])
  match handle_outline(test_parent_emit(), OutlineNavigate(node_id), model) {
    Some((_, changed)) => {
      inspect(changed.selected_node == Some(node_id), content="true")
      inspect(changed.highlight_set.is_empty(), content="false")
      @debug.assert_eq(changed.nav_path, Some([0]))
    }
    None => abort("OutlineNavigate was not handled")
  }
}

///|
test "outline navigation with an invalid id is a handled no-op" {
  let model = init_model()
  match
    handle_outline(test_parent_emit(), OutlineNavigate("not-a-node-id"), model) {
    Some((_, changed)) => @debug.assert_eq(changed.selected_node, None)
    None => abort("invalid OutlineNavigate fell through to the top-level abort")
  }
}

///|
test "selection characterization: outline structural edit refreshes selection" {
  let (model, node_id) = selected_test_model()
  model.nav_path = Some([0])
  let nid = parse_node_id(node_id).unwrap()
  match
    handle_structural(
      test_parent_emit(),
      OutlineStructuralEdit(@lambda_edits.TreeEditOp::Select(node_id=nid)),
      model,
    ) {
    Some((_, changed)) => {
      inspect(changed.highlight_set.is_empty(), content="false")
      inspect(changed.nav_path is None, content="true")
    }
    None => abort("OutlineStructuralEdit was not handled")
  }
}

///|
test "selection characterization: structure selection highlights and clears nav" {
  let (model, node_id) = selected_test_model()
  model.nav_path = Some([0])
  match
    handle_structure_mode(
      test_parent_emit(),
      StructureNodeSelected(node_id),
      model,
    ) {
    Some((_, changed)) => {
      inspect(changed.selected_node == Some(node_id), content="true")
      inspect(changed.highlight_set.is_empty(), content="false")
      inspect(changed.nav_path is None, content="true")
    }
    None => abort("StructureNodeSelected was not handled")
  }
}
